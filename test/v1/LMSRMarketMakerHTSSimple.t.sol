// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

//import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {MockToken} from "./../MockToken.sol";
import {Dynamica} from "../../src/v1/Dynamica.sol";
import {IDynamica} from "../../src/interfaces/IDynamica.sol";
import {DynamicaFactory} from "../../src/v1/MarketMakerFactory.sol";
import {MarketResolutionManager} from "../../src/Oracles/MarketResolutionManager.sol";
import {ChainlinkResolutionModule, ChainlinkConfig} from "../../src/Oracles/Hedera/ChainlinkResolutionModule.sol";
import {FTSOResolutionModule} from "../../src/Oracles/Flare/FTSOResolutionModule.sol";
import {OracleSetUP} from "../MockOracles/OracleSetUP.t.sol";
import {IMarketResolutionModule} from "../../src/interfaces/IMarketResolutionModule.sol";
import {SD59x18, sd, exp, ln} from "@prb-math/src/SD59x18.sol";
import {console} from "forge-std/src/console.sol";
import {Test} from "forge-std/src/Test.sol";
import {HederaTokenService} from
    "@hashgraph/hedera-smart-contracts/contracts/system-contracts/hedera-token-service/HederaTokenService.sol";
import {IHederaTokenService} from
    "@hashgraph/hedera-smart-contracts/contracts/system-contracts/hedera-token-service/IHederaTokenService.sol";
import {ExpiryHelper} from "@hashgraph/hedera-smart-contracts/contracts/system-contracts/hedera-token-service/ExpiryHelper.sol";
import {KeyHelper} from "@hashgraph/hedera-smart-contracts/contracts/system-contracts/hedera-token-service/KeyHelper.sol";
import {htsSetup} from "hashgraph-hedera-forking/contracts/htsSetup.sol";

/**
 * forge test --fork-url https://mainnet.hashio.io/api -vv
 * @title LMSRMarketMakerSimpleTest
 * @dev Test contract for the LMSR (Logarithmic Market Scoring Rule) market maker
 * @notice Tests the complete market lifecycle including market creation, trading, and resolution
 *
 * This test suite covers:
 * - Market setup with Chainlink oracle integration
 * - Multiple trader interactions with the market
 * - Market resolution and payout distribution
 * - Balance tracking throughout the market lifecycle
 */
contract LMSRMarketMakerSimpleTest is OracleSetUP, ExpiryHelper, KeyHelper, HederaTokenService {
    // ============ State Variables ============
    address constant HTS_PRECOMPILE = address(0x167);

    int64 constant DECIMALS = 10;
    uint8 constant DECIMALS_COLLATERAL = 10;
    uint256 constant INITIAL_SUPPLY = 1_000 * (10 ** uint64(DECIMALS));

    /// @notice Dynamica implementation contract
    Dynamica public implementation;

    /// @notice Deployed market maker instance
    Dynamica public marketMaker;

    /// @notice Factory contract for creating markets
    DynamicaFactory public factory;

    /// @notice Mock HTS token for testing
    address public mockTokenHTS;

    /// @notice Market resolution manager
    MarketResolutionManager public marketResolutionManager;

    /// @notice Chainlink resolution module implementation address
    address public implementationResolutionModuleChainlink;

    /// @notice FTSO resolution module implementation address
    address public implementationResolutionModuleFTSO;

    // ============ Constants ============

    /// @notice Unit decimal for calculations (1e18)
    int256 public constant UNIT_DEC = 1e18;

    /// @notice Alpha parameter for LMSR (3%)
    int256 public constant alha = 3 * UNIT_DEC / 100;

    /// @notice Natural logarithm of 2
    int256 ln_2 = ln(sd(2 * UNIT_DEC)).unwrap();

    // ============ Test Addresses ============

    /// @notice Oracle address for testing
    address ORACLE = address(0x1234);

    /// @notice Test trader addresses
    address trader_0 = address(1);
    address trader_1 = address(2);
    address trader_2 = address(3);
    address trader_3 = address(4);

    address[] outcomeTokenAddresses;

    address[] testT;


    function createToken(string memory name1, string memory symbol2)
        public
        payable
    {

        mockTokenHTS = address(new MockToken(DECIMALS_COLLATERAL));
        
    }

    /**
     * @notice Sets up the test environment
     * @dev Initializes contracts, mints tokens, and creates a test market
     */
    function setUp() public override {
        htsSetup();
        vm.startPrank(OWNER);
        vm.deal(OWNER, 1000 ether);

        super.setUp();

        // Deploy and configure mock token
        _setupMockToken();

        // Deploy implementation contracts
        _deployImplementations();

        // Deploy and configure factory
        _setupFactory();

        // Deploy market resolution manager
        _setupMarketResolutionManager();

        // Create test market
        _createTestMarket();

        // Mint tokens to test traders
        _mintTokensToTraders();

        vm.stopPrank();
    }

    function testCreateToken() public {
        vm.startPrank(OWNER);
        createToken("Token1", "T1");
        vm.stopPrank();
    }

    // ============ Test Functions ============

    /**
     * @notice Tests the complete market lifecycle
     * @dev Tests market creation, multiple trades, resolution, and payout distribution
     */
    function testMarketCicle() public {
        
        // Track initial balances
        uint256[] memory startBalances = _getInitialBalances();

        // Execute trading sequence
        _executeTradingSequence();

        // Record market balance before resolution 1000000  1000253
        startBalances[4] = IERC20(mockTokenHTS).balanceOf(address(marketMaker));

        // Resolve the market
        vm.warp(block.timestamp + 8 days + 1);
        marketMaker._updateEpoch();
        vm.startPrank(OWNER);

        //IERC20(mockTokenHTS).mint(OWNER, 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
        ///console.log("responseCode", responseCode);
        IERC20(mockTokenHTS).transfer(address(marketMaker), 1000 * 10 ** uint256(DECIMALS_COLLATERAL));
        marketResolutionManager.resolveMarket(keccak256(bytes("eth/usdc_hts_collateral")));
        vm.stopPrank();

        //Redeem payouts for all traders
        _redeemPayoutsForTraders();

        // Display final balance comparison
        //_displayBalanceComparison(startBalances);
    }

    function testMarginalPrice() public {
        _executeTradingSequence();

        int256 marginalPrice0 = marketMaker.calcMarginalPrice(0);
        int256 marginalPrice1 = marketMaker.calcMarginalPrice(1);
        console.log("marginalPrice0", marginalPrice0);
        console.log("marginalPrice1", marginalPrice1);
        console.log("marginalPrice0", marginalPrice0 + marginalPrice1);
    }

    // ============ Private Setup Functions ============

    /**
     * @notice Sets up the mock token for testing
     */
    function _setupMockToken() private {
        createToken("Token1", "T1");
        IERC20(mockTokenHTS).mint(OWNER, 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
    }

    /**
     * @notice Deploys implementation contracts
     */
    function _deployImplementations() private {
        implementation = new Dynamica();
        implementationResolutionModuleChainlink = address(new ChainlinkResolutionModule());
        implementationResolutionModuleFTSO = address(new FTSOResolutionModule());
    }

    /**
     * @notice Sets up the factory contract
     */
    function _setupFactory() private {
        factory = new DynamicaFactory(
            address(implementation),
            implementationResolutionModuleChainlink,
            implementationResolutionModuleFTSO,
            address(ftsoV2),
            OWNER
        );
    }

    function testSetupMarketMaker() public {
        assertEq(marketMaker.balanceOf(address(marketMaker), marketMaker.shareId(1, 0)), uint256(uint64(INITIAL_SUPPLY)));
        assertEq(marketMaker.balanceOf(address(marketMaker), marketMaker.shareId(1, 1)), uint256(uint64(INITIAL_SUPPLY)));
    }

    /**
     * @notice Sets up the market resolution manager
     */
    function _setupMarketResolutionManager() private {
        marketResolutionManager = new MarketResolutionManager(OWNER, address(factory));
        factory.setOracleCoordinator(address(marketResolutionManager));
        IERC20(mockTokenHTS).approve(address(factory), 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
    }

    /**
     * @notice Creates the test market with Chainlink configuration
     */
    function _createTestMarket() private {
        ChainlinkConfig memory chainlinkConfig = _prepareChainlinkConfig();
        IHederaTokenService.HederaToken[] memory tokens = new IHederaTokenService.HederaToken[](2);
        tokens[0].name = "Token1";
        tokens[0].symbol = "T1";
        tokens[0].treasury = OWNER;
        tokens[0].expiry.autoRenewAccount = OWNER;
        tokens[0].expiry.autoRenewPeriod = 5184000;
        tokens[1].name = "Token2";
        tokens[1].symbol = "T2";
        tokens[1].treasury = OWNER;
        tokens[1].expiry.autoRenewAccount = OWNER;
        tokens[1].expiry.autoRenewPeriod = 5184000;

        // Create market through factory
        factory.createMarketMaker{value: 2 ether}(
            IDynamica.Config({
                owner: OWNER,
                collateralToken: address(mockTokenHTS),
                oracle: ORACLE,
                question: "eth/usdc_hts_collateral",
                outcomeSlotCount: 2,
                startFunding: 1000 * 10 ** uint256(DECIMALS_COLLATERAL),
                outcomeTokenAmounts: INITIAL_SUPPLY,
                fee: 0,
                alpha: 3,
                expLimit: 12750,
                decimals: int32(DECIMALS), 
                expirationTime: uint32(block.timestamp + 8 days),
                gamma: 9000
            }),
            IMarketResolutionModule.MarketResolutionConfig({
                marketMaker: address(0),
                outcomeSlotCount: 5,
                resolutionModule: address(0),
                resolutionData: abi.encode(chainlinkConfig),
                isResolved: false,
                expirationTime: uint32(block.timestamp + 8 days),
                resolutionModuleType: IMarketResolutionModule.ResolutionModule.CHAINLINK
            })
        );

        // Get the deployed market maker
        marketMaker = Dynamica(payable(factory.marketMakers(0)));
        vm.deal(address(marketMaker), 1000 ether);
    }

    /**
     * @notice Prepares Chainlink configuration for the test market
     * @return config The Chainlink configuration
     */
    function _prepareChainlinkConfig() private view returns (ChainlinkConfig memory config) {
        address[] memory priceFeedAddresses = new address[](2);
        uint256[] memory staleness = new uint256[](2);
        uint8[] memory decimals = new uint8[](2);

        // Set price feed addresses
        priceFeedAddresses[0] = address(ethUsdAggregator);
        priceFeedAddresses[1] = address(btcUsdAggregator);

        // Set staleness periods (1 hour)
        staleness[0] = 3600;
        staleness[1] = 3600;

        // Set decimal places
        decimals[0] = ethUsdAggregator.decimals();
        decimals[1] = btcUsdAggregator.decimals();

        config = ChainlinkConfig({priceFeedAddresses: priceFeedAddresses, staleness: staleness, decimals: decimals});
    }

    /**
     * @notice Mints tokens to test traders
     */
    function _mintTokensToTraders() private {
        IERC20(mockTokenHTS).mint(trader_0, 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
        IERC20(mockTokenHTS).mint(trader_1, 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
        IERC20(mockTokenHTS).mint(trader_2, 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
        IERC20(mockTokenHTS).mint(trader_3, 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
    }

    // ============ Private Test Functions ============

    /**
     * @notice Gets initial balances for all participants
     * @return startBalances Array of initial balances
     */
    function _getInitialBalances() private view returns (uint256[] memory startBalances) {
        startBalances = new uint256[](5);
        startBalances[0] = IERC20(mockTokenHTS).balanceOf(trader_0);
        startBalances[1] = IERC20(mockTokenHTS).balanceOf(trader_1);
        startBalances[2] = IERC20(mockTokenHTS).balanceOf(trader_2);
        startBalances[3] = IERC20(mockTokenHTS).balanceOf(trader_3);
    }

    /**
     * @notice Executes the trading sequence with predefined trades
     */
    function _executeTradingSequence() private {
        address[] memory traders = _getTraderSequence();
        int256[][] memory amounts = _getTradeAmounts();

        for (uint256 i = 0; i < traders.length; i++) {
            if(i == 3 || i == 5 || i == 9){
                vm.warp(block.timestamp + 1 days);
            }
            vm.startPrank(traders[i]);
            IERC20(mockTokenHTS).approve(address(marketMaker), 1_000_000 * 10 ** uint256(uint64(DECIMALS_COLLATERAL)));
            marketMaker.makePrediction(amounts[i]);
            vm.stopPrank();
        }
    }

    /**
     * @notice Gets the sequence of traders for the test
     * @return traders Array of trader addresses in execution order
     */
    function _getTraderSequence() private pure returns (address[] memory traders) {
        traders = new address[](11);
        traders[0] = address(1); // trader_0
        traders[1] = address(2); // trader_1
        traders[2] = address(3); // trader_2
        traders[3] = address(4); // trader_3
        traders[4] = address(1); // trader_0
        traders[5] = address(2); // trader_1
        traders[6] = address(3); // trader_2
        traders[7] = address(4); // trader_3
        traders[8] = address(3); // trader_2
        traders[9] = address(4); // trader_3
        traders[10] = address(2); // trader_1
    }

    function _getTradeAmounts() private pure returns (int256[][] memory amounts) {
        amounts = new int256[][](11);

        // Trade 1: trader_0 buys both outcomes
        amounts[0] = new int256[](2);
        amounts[0][0] = int256(300) * int256(10 ** uint64(DECIMALS));
        amounts[0][1] = int256(4500) * int256(10 ** uint64(DECIMALS));

        // Trade 2: trader_1 buys both outcomes
        amounts[1] = new int256[](2);
        amounts[1][0] = int256(527) * int256(10 ** uint64(DECIMALS));
        amounts[1][1] = int256(496) * int256(10 ** uint64(DECIMALS));

        // Trade 3: trader_2 buys both outcomes
        amounts[2] = new int256[](2);
        amounts[2][0] = int256(299) * int256(10 ** uint64(DECIMALS));
        amounts[2][1] = int256(136) * int256(10 ** uint64(DECIMALS));

        // Trade 4: trader_3 buys both outcomes
        amounts[3] = new int256[](2);
        amounts[3][0] = int256(263) * int256(10 ** uint64(DECIMALS));
        amounts[3][1] = int256(136) * int256(10 ** uint64(DECIMALS));

        // Trade 5: trader_0 buys outcome 0, sells outcome 1
        amounts[4] = new int256[](2);
        amounts[4][0] = int256(1) * int256(10 ** uint64(DECIMALS));
        amounts[4][1] = int256(0) * int256(10 ** uint64(DECIMALS));

        // Trade 6: trader_1 buys both outcomes
        amounts[5] = new int256[](2);
        amounts[5][0] = int256(92) * int256(10 ** uint64(DECIMALS));
        amounts[5][1] = int256(122) * int256(10 ** uint64(DECIMALS));

        // Trade 7: trader_2 buys both outcomes
        amounts[6] = new int256[](2);
        amounts[6][0] = int256(53) * int256(10 ** uint64(DECIMALS));
        amounts[6][1] = int256(88) * int256(10 ** uint64(DECIMALS));

        // Trade 8: trader_3 sells both outcomes
        amounts[7] = new int256[](2);
        amounts[7][0] = int256(53) * int256(10 ** uint64(DECIMALS));
        amounts[7][1] = int256(62) * int256(10 ** uint64(DECIMALS));

        // Trade 9: trader_2 only buys outcome 1
        amounts[8] = new int256[](2);
        amounts[8][0] = 0;
        amounts[8][1] = int256(11) * int256(10 ** uint64(DECIMALS));

        // Trade 10: trader_3 only sells outcome 1
        amounts[9] = new int256[](2);
        amounts[9][0] = 0;
        amounts[9][1] = int256(10) * int256(10 ** uint64(DECIMALS));

        // Trade 11: trader_1 only buys outcome 1
        amounts[10] = new int256[](2);
        amounts[10][0] = 0;
        amounts[10][1] = int256(2) * int256(10 ** uint64(DECIMALS));
    }

    /**
     * @notice Gets the predefined trade amounts for testing
     * @return amounts Array of trade amounts for each trader
     */
    /*function _getTradeAmounts() private pure returns (int64[][] memory amounts) {
        amounts = new int64[][](11);

        // Trade 1: trader_0 buys both outcomes
        amounts[0] = new int64[](2);
        amounts[0][0] = 546 * int64(uint64(10) ** uint64(DECIMALS));
        amounts[0][1] = 514 * int64(uint64(10) ** uint64(DECIMALS));

        // Trade 2: trader_1 buys both outcomes
        amounts[1] = new int64[](2);
        amounts[1][0] = 527 * int64(uint64(10) ** uint64(DECIMALS));
        amounts[1][1] = 496 * int64(uint64(10) ** uint64(DECIMALS));

        // Trade 3: trader_2 buys both outcomes
        amounts[2] = new int64[](2);
        amounts[2][0] = 299 * int64(uint64(10) ** uint64(DECIMALS));
        amounts[2][1] = 136 * int64(uint64(10) ** uint64(DECIMALS));

        // Trade 4: trader_3 buys both outcomes
        amounts[3] = new int64[](2);
        amounts[3][0] = 263 * int64(uint64(10) ** uint64(DECIMALS));
        amounts[3][1] = 136 * int64(uint64(10) ** uint64(DECIMALS));

        // Trade 5: trader_0 buys outcome 0, sells outcome 1
        amounts[4] = new int64[](2);
        amounts[4][0] = 143 * int64(uint64(10) ** uint64(DECIMALS));
        amounts[4][1] = -136 * int64(uint64(10) ** uint64(DECIMALS));

        // Trade 6: trader_1 buys both outcomes
        amounts[5] = new int64[](2);
        amounts[5][0] = 92 * int64(uint64(10) ** uint64(DECIMALS));
        amounts[5][1] = 122 * int64(uint64(10) ** uint64(DECIMALS));

        // Trade 7: trader_2 buys both outcomes
        amounts[6] = new int64[](2);
        amounts[6][0] = 53 * int64(uint64(10) ** uint64(DECIMALS));
        amounts[6][1] = 88 * int64(uint64(10) ** uint64(DECIMALS));

        // Trade 8: trader_3 sells both outcomes
        amounts[7] = new int64[](2);
        amounts[7][0] = -53 * int64(uint64(10) ** uint64(DECIMALS));
        amounts[7][1] = -62 * int64(uint64(10) ** uint64(DECIMALS));

        // Trade 9: trader_2 only buys outcome 1
        amounts[8] = new int64[](2);
        amounts[8][0] = 0;
        amounts[8][1] = 11 * int64(uint64(10) ** uint64(DECIMALS));

        // Trade 10: trader_3 only sells outcome 1
        amounts[9] = new int64[](2);
        amounts[9][0] = 0;
        amounts[9][1] = -10 * int64(uint64(10) ** uint64(DECIMALS));

        // Trade 11: trader_1 only buys outcome 1
        amounts[10] = new int64[](2);
        amounts[10][0] = 0;
        amounts[10][1] = 2 * int64(uint64(10) ** uint64(DECIMALS));
    }*/

    /**
     * @notice Redeems payouts for all traders
     */
    function _redeemPayoutsForTraders() private {
        address[] memory traders = new address[](4);
        traders[0] = trader_0;
        traders[1] = trader_1;
        traders[2] = trader_2;
        traders[3] = trader_3;

        for (uint256 i = 0; i < 4; i++) {
            console.log("redeeming", i);
            vm.prank(traders[i]);
            marketMaker.redeemPayout();
        }
    }

    /**
     * @notice Displays balance comparison between start and end states
     * @param startBalances Array of initial balances
     */
    function _displayBalanceComparison(uint256[] memory startBalances) private view {
        uint256[] memory endBalances = new uint256[](5);
        endBalances[0] = IERC20(mockTokenHTS).balanceOf(trader_0);
        endBalances[1] = IERC20(mockTokenHTS).balanceOf(trader_1);
        endBalances[2] = IERC20(mockTokenHTS).balanceOf(trader_2);
        endBalances[3] = IERC20(mockTokenHTS).balanceOf(trader_3);
        endBalances[4] = IERC20(mockTokenHTS).balanceOf(address(marketMaker));

        // Display balance changes for each participant
        for (uint256 i = 0; i < 4; i++) {
            console.log("startBalances", startBalances[i]);
            console.log("endBalances", endBalances[i]);
        }

        // Display market maker balance
        console.log("startBalances", startBalances[4]);
        console.log("endBalances", endBalances[4]);
    }

}