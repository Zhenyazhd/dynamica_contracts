// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {MockToken, IERC20Mock} from "./MockToken.sol";
import {MockToken} from "./MockToken.sol";
import {Dynamica} from "../src/Dynamica.sol";
import {IDynamica} from "../src/interfaces/IDynamica.sol";
import {DynamicaFactory} from "../src/DynamicaFactory.sol";
import {MarketResolutionManager} from "../src/Oracles/MarketResolutionManager.sol";
import {ChainlinkResolutionModule} from "../src/Oracles/Hedera/ChainlinkResolutionModule.sol";
import {OracleSetUP} from "./MockOracles/OracleSetUP.t.sol";
import {IMarketResolutionModule} from "../src/interfaces/Oracles/IMarketResolutionModule.sol";
import {LMSRMath} from "../src/LMSRMath.sol";

import {console} from "forge-std/src/console.sol";

/**
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
contract LMSRMarketMakerSimpleTest is OracleSetUP {
    // ============ State Variables ============

    address public constant OWNER = address(0xABCD);

    uint8 constant DECIMALS = 10;
    uint8 constant DECIMALS_COLLATERAL = 10;
    uint256 constant INITIAL_SUPPLY = 500 * (10 ** DECIMALS);
    uint256 constant START_FUNDING = 1000 * 10 ** uint256(DECIMALS_COLLATERAL);


    /// @notice Dynamica implementation contract
    Dynamica public implementation;

    /// @notice LMSR math contract
    LMSRMath public lmsrMathExternal;

    /// @notice Deployed market maker instance
    Dynamica public marketMaker;

    /// @notice Factory contract for creating markets
    DynamicaFactory public factory;

    /// @notice Mock token for testing
    address public mockToken;

    /// @notice Market resolution manager
    MarketResolutionManager public marketResolutionManager;

    /// @notice Chainlink resolution module implementation address
    address public implementationResolutionModuleChainlink;


    // ============ Constants ============

    /// @notice Unit decimal for calculations (1e18)
    int256 public constant UNIT_DEC = 1e18;

    /// @notice Alpha parameter for LMSR (3%)
    int256 public constant ALPHA = 3 * UNIT_DEC / 100;

    // ============ Test Addresses ============

    /// @notice Oracle address for testing
    address oracle = address(0x1234);

    /// @notice Test trader addresses
    address trader0 = address(1);
    address trader1 = address(2);
    address trader2 = address(3);
    address trader3 = address(4);

    address[] outcomeTokenAddresses;

    address[] testT;
    // ============ Setup Function ============

    function createToken(string memory name1, string memory symbol2)
        public
        payable
    {
        mockToken = address(new MockToken(DECIMALS_COLLATERAL));   
    }

    /**
     * @notice Sets up the test environment
     * @dev Initializes contracts, mints tokens, and creates a test market
     */
    function setUp() public override {
        vm.startPrank(OWNER);
        vm.deal(OWNER, 1000 ether);

        super.setUp();

        _setupMockToken();
        _deployImplementations();
        _setupFactory();
        _setupMarketResolutionManager();
        _createTestMarket();
        _mintTokensToTraders();

        vm.stopPrank();
    }

    // ============ Test Functions ============


    function testSetupMarketMaker() public view {
        assertEq(marketMaker.currentEpochNumber(), 1);
        assertEq(marketMaker.currentPeriodNumber(), 1);
        assertEq(marketMaker.balanceOf(address(marketMaker), marketMaker.shareId(1, 1, 0)), uint256(uint64(INITIAL_SUPPLY)));
        assertEq(marketMaker.balanceOf(address(marketMaker), marketMaker.shareId(1, 1, 1)), uint256(uint64(INITIAL_SUPPLY)));
        assertEq(IERC20Mock(mockToken).balanceOf(address(marketMaker)), START_FUNDING);
    }

    function testEpoch() public {
        vm.startPrank(OWNER);
        uint256 start = block.timestamp;
        vm.warp(start + 1 days);

        marketMaker.updateEpochAndPeriod();
        assertEq(marketMaker.currentEpochNumber(), 1);
        assertEq(marketMaker.currentPeriodNumber(), 2);

        vm.warp(block.timestamp + 4 days);
        marketMaker.updateEpochAndPeriod();
        assertEq(marketMaker.currentEpochNumber(), 1);
        assertEq(marketMaker.currentPeriodNumber(), 6);

        vm.warp(block.timestamp + 5 days);
        vm.expectRevert(abi.encodeWithSelector(IDynamica.EpochFinishedButNotResolvedYet.selector, 1));
        marketMaker.updateEpochAndPeriod();

        marketResolutionManager.resolveMarket(keccak256(bytes("eth/btc")));
        marketMaker.updateEpochAndPeriod();
        assertEq(marketMaker.currentEpochNumber(), 2);
        assertEq(marketMaker.currentPeriodNumber(), 1);
    }

    /**
     * @notice Tests the complete market lifecycle
     * @dev Tests market creation, multiple trades, resolution, and payout distribution
     */
    function testMarketCicle() public {
        uint256[] memory startBalances = _getInitialBalances();

        _executeTradingSequence();

        startBalances[4] = IERC20Mock(mockToken).balanceOf(address(marketMaker));

        vm.warp(block.timestamp + 8 days + 1);
        console.log('currentEpochNumber', marketMaker.currentEpochNumber());

        vm.prank(OWNER);
        marketResolutionManager.resolveMarket(keccak256(bytes("eth/btc")));
        
        _redeemPayoutsForTraders(1); 
        _redeemPayoutsForTraders(2); 

        _displayBalanceComparison(startBalances);
    }

    

    // ============ Private Setup Functions ============

    /**
     * @notice Sets up the mock token for testing
     */
    function _setupMockToken() private {
        this.createToken("Token1", "T1");
        IERC20Mock(mockToken).mint(OWNER, 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
    }

    /**
     * @notice Deploys implementation contracts
     */
    function _deployImplementations() private {
        implementation = new Dynamica();
        implementationResolutionModuleChainlink = address(new ChainlinkResolutionModule());
        lmsrMathExternal = new LMSRMath();
    }

    /**
     * @notice Sets up the factory contract
     */
    function _setupFactory() private {
        factory = new DynamicaFactory(
            address(implementation),
            implementationResolutionModuleChainlink,
            OWNER,
            address(lmsrMathExternal)
        );
        factory.addAllowedCollateralToken(address(mockToken));
    }

    /**
     * @notice Sets up the market resolution manager
     */
    function _setupMarketResolutionManager() private {
        marketResolutionManager = new MarketResolutionManager(OWNER, address(factory));
        factory.setOracleCoordinator(address(marketResolutionManager));
        IERC20Mock(mockToken).approve(address(factory), 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
    }

    /**
     * @notice Creates the test market with Chainlink configuration
     */
    function _createTestMarket() private {
        ChainlinkResolutionModule.ChainlinkConfig memory chainlinkConfig = _prepareChainlinkConfig();
        factory.createMarketMaker(
            IDynamica.Config({
                owner: OWNER,
                collateralToken: address(mockToken),
                oracle: oracle,
                question: "eth/btc",
                outcomeSlotCount: 2,
                startFunding: START_FUNDING,
                outcomeTokenAmounts: INITIAL_SUPPLY,
                fee: 0,
                alpha: 3,
                expLimit: 12750,
                decimals: DECIMALS,
                expirationEpoch: 2,
                gamma: 9000,
                epochDuration: 10 days,
                periodDuration: 1 days
            }),
            IMarketResolutionModule.MarketResolutionConfig({
                marketMaker: address(0),
                outcomeSlotCount: 5,
                resolutionModule: address(0),
                resolutionData: abi.encode(chainlinkConfig),
                isResolved: false,
                resolutionModuleType: IMarketResolutionModule.ResolutionModule.CHAINLINK
            })
        );
        marketMaker = Dynamica(payable(factory.marketMakers(0)));
        vm.deal(address(marketMaker), 1000 ether);
    }

    /**
     * @notice Prepares Chainlink configuration for the test market
     * @return config The Chainlink configuration
     */
    function _prepareChainlinkConfig() private view returns (ChainlinkResolutionModule.ChainlinkConfig memory config) {
        address[] memory priceFeedAddresses = new address[](2);
        uint256[] memory staleness = new uint256[](2);
        uint8[] memory decimals = new uint8[](2);

        priceFeedAddresses[0] = address(ethUsdAggregator);
        priceFeedAddresses[1] = address(btcUsdAggregator);

        staleness[0] = 3600;
        staleness[1] = 3600;

        decimals[0] = ethUsdAggregator.decimals();
        decimals[1] = btcUsdAggregator.decimals();

        config = ChainlinkResolutionModule.ChainlinkConfig({priceFeedAddresses: priceFeedAddresses, staleness: staleness, decimals: decimals});
    }

    /**
     * @notice Mints tokens to test traders
     */
    function _mintTokensToTraders() private {
        IERC20Mock(mockToken).mint(trader0, 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
        IERC20Mock(mockToken).mint(trader1, 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
        IERC20Mock(mockToken).mint(trader2, 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
        IERC20Mock(mockToken).mint(trader3, 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
    }

    // ============ Private Test Functions ============

    /**
     * @notice Gets initial balances for all participants
     * @return startBalances Array of initial balances
     */
    function _getInitialBalances() private view returns (uint256[] memory startBalances) {
        startBalances = new uint256[](5);
        startBalances[0] = IERC20Mock(mockToken).balanceOf(trader0);
        startBalances[1] = IERC20Mock(mockToken).balanceOf(trader1);
        startBalances[2] = IERC20Mock(mockToken).balanceOf(trader2);
        startBalances[3] = IERC20Mock(mockToken).balanceOf(trader3);
    }

    /**
     * @notice Executes the trading sequence with predefined trades
     */
    function _executeTradingSequence() private {
        address[] memory traders = _getTraderSequence();
        int256[][] memory amounts = _getTradeAmounts();
        uint t = 0;
        uint256[] memory periods = new uint256[](5);
        periods[0] = 2 days;
        periods[1] = 4 days;
        periods[2] = 10 days;
        periods[3] = 2 days;
        periods[4] = 6 days;

        for (uint256 i = 0; i < traders.length; i++) {
            uint256[] memory balances = new uint256[](amounts[i].length);
            if(i == 6 || i == 10 || i == 12 || i == 16 || i == 19){
                vm.warp(block.timestamp + periods[t]);
                t++;
            }
            if(marketMaker.checkEpoch()){
                vm.prank(OWNER);
                marketResolutionManager.resolveMarket(keccak256(bytes("eth/btc")));
            }
            for (uint256 j = 0; j < amounts[i].length; j++) {
                balances[j] = marketMaker.balanceOf(traders[i], marketMaker.shareId(marketMaker.currentEpochNumber(), marketMaker.currentPeriodNumber(), j));
            }
            vm.startPrank(traders[i]);
            int256 mockBalance = int256(IERC20Mock(mockToken).balanceOf(traders[i]));
            marketMaker.setApprovalForAll(address(marketMaker), true);
            IERC20Mock(mockToken).approve(address(marketMaker), 1_000 * 10 ** uint256(uint64(DECIMALS_COLLATERAL)));
            marketMaker.makePrediction(amounts[i], false);
            for (uint256 j = 0; j < amounts[i].length; j++) {
            }
            console.log('_________________________________________________');
            console.log('trader', traders[i]);
            console.log('epoch', marketMaker.currentEpochNumber());
            console.log('period', marketMaker.currentPeriodNumber());
            console.log('amounts_0', amounts[i][0]);
            console.log('amounts_1', amounts[i][1]);
            console.log('balance', mockBalance - int256(IERC20Mock(mockToken).balanceOf(traders[i])));
            console.log('_________________________________________________');
            vm.stopPrank();
        }
        console.log('Current epoch', marketMaker.currentEpochNumber());
        console.log('Current period', marketMaker.currentPeriodNumber());
    }

    /**
     * @notice Gets the sequence of traders for the test
     * @return traders Array of trader addresses in execution order
     */
    function _getTraderSequence() private pure returns (address[] memory traders) {
        traders = new address[](20);
        traders[0] = address(1); // trader_0
        traders[1] = address(2); // trader_1
        traders[2] = address(3); // trader_2
        traders[3] = address(4); // trader_3
        traders[4] = address(1); // trader_0
        traders[5] = address(2); // trader_1
        traders[6] = address(4); // trader_3
        traders[7] = address(4); // trader_3
        traders[8] = address(4); // trader_3
        traders[9] = address(3); // trader_2
        traders[10] = address(3); // trader_2
        traders[11] = address(3); // trader_2
        traders[12] = address(3); // trader_0
        traders[13] = address(1); // trader_0
        traders[14] = address(1); // trader_0
        traders[15] = address(3); // trader_2
        traders[16] = address(4); // trader_3
        traders[17] = address(2); // trader_1
        traders[18] = address(2); // trader_1
        traders[19] = address(1); // trader_0
    }

    /**
     * @notice Gets the predefined trade amounts for testing
     * @return amounts Array of trade amounts for each trader
     */
    function _getTradeAmounts() private pure returns (int256[][] memory amounts) {
        amounts = new int256[][](20);

        amounts[0] = new int256[](2);
        amounts[0][0] = 67 * int256(10 ** DECIMALS);
        amounts[0][1] = 18 * int256(10 ** DECIMALS);

        amounts[1] = new int256[](2);
        amounts[1][0] = 40 * int256(10 ** DECIMALS);
        amounts[1][1] = 99 * int256(10 ** DECIMALS);

        amounts[2] = new int256[](2);
        amounts[2][0] = 77 * int256(10 ** DECIMALS);
        amounts[2][1] = 93 * int256(10 ** DECIMALS);

        amounts[3] = new int256[](2);
        amounts[3][0] = 64 * int256(10 ** DECIMALS);
        amounts[3][1] = 83 * int256(10 ** DECIMALS);

        amounts[4] = new int256[](2);
        amounts[4][0] = -39 * int256(10 ** DECIMALS);
        amounts[4][1] = 4 * int256(10 ** DECIMALS);

        amounts[5] = new int256[](2);
        amounts[5][0] = -37 * int256(10 ** DECIMALS);
        amounts[5][1] = 21 * int256(10 ** DECIMALS);

        amounts[6] = new int256[](2);
        amounts[6][0] = 70 * int256(10 ** DECIMALS);
        amounts[6][1] = 89 * int256(10 ** DECIMALS);

        amounts[7] = new int256[](2);
        amounts[7][0] = -17 * int256(10 ** DECIMALS);
        amounts[7][1] = 38 * int256(10 ** DECIMALS);

        amounts[8] = new int256[](2);
        amounts[8][0] = -22 * int256(10 ** DECIMALS);
        amounts[8][1] = 60 * int256(10 ** DECIMALS);

        amounts[9] = new int256[](2);
        amounts[9][0] = 20 * int256(10 ** DECIMALS);
        amounts[9][1] = 77 * int256(10 ** DECIMALS);

        amounts[10] = new int256[](2);
        amounts[10][0] = 34 * int256(10 ** DECIMALS);
        amounts[10][1] = 67 * int256(10 ** DECIMALS);

        amounts[11] = new int256[](2);
        amounts[11][0] = 96 * int256(10 ** DECIMALS);
        amounts[11][1] = -31 * int256(10 ** DECIMALS);

        amounts[12] = new int256[](2);
        amounts[12][0] = 56 * int256(10 ** DECIMALS);
        amounts[12][1] = 32 * int256(10 ** DECIMALS);

        amounts[13] = new int256[](2);
        amounts[13][0] = 93 * int256(10 ** DECIMALS);
        amounts[13][1] = 18 * int256(10 ** DECIMALS);

        amounts[14] = new int256[](2);
        amounts[14][0] = -44 * int256(10 ** DECIMALS);
        amounts[14][1] = 79 * int256(10 ** DECIMALS);

        amounts[15] = new int256[](2);
        amounts[15][0] = 49 * int256(10 ** DECIMALS);
        amounts[15][1] = -1 * int256(10 ** DECIMALS);

        amounts[16] = new int256[](2);
        amounts[16][0] = 35 * int256(10 ** DECIMALS);
        amounts[16][1] = 28 * int256(10 ** DECIMALS);

        amounts[17] = new int256[](2);
        amounts[17][0] = 83 * int256(10 ** DECIMALS);
        amounts[17][1] = 7 * int256(10 ** DECIMALS);

        amounts[18] = new int256[](2);
        amounts[18][0] = -9 * int256(10 ** DECIMALS);
        amounts[18][1] = -4 * int256(10 ** DECIMALS);

        amounts[19] = new int256[](2);
        amounts[19][0] = 39 * int256(10 ** DECIMALS);
        amounts[19][1] = 79 * int256(10 ** DECIMALS);
    }

    /**
     * @notice Redeems payouts for all traders
     */
    function _redeemPayoutsForTraders(uint32 epoch) private {
        address[] memory traders = new address[](4);
        traders[0] = trader0;
        traders[1] = trader1;
        traders[2] = trader2;
        traders[3] = trader3;

        for (uint256 i = 0; i < 4; i++) {
            console.log("redeeming", i);
            vm.prank(traders[i]);
            marketMaker.redeemPayout(epoch);
        }
    }

    /**
     * @notice Displays balance comparison between start and end states
     * @param startBalances Array of initial balances
     */
    function _displayBalanceComparison(uint256[] memory startBalances) private view {
        uint256[] memory endBalances = new uint256[](5);
        endBalances[0] = IERC20Mock(mockToken).balanceOf(trader0);
        endBalances[1] = IERC20Mock(mockToken).balanceOf(trader1);
        endBalances[2] = IERC20Mock(mockToken).balanceOf(trader2);
        endBalances[3] = IERC20Mock(mockToken).balanceOf(trader3);
        endBalances[4] = IERC20Mock(mockToken).balanceOf(address(marketMaker));

        for (uint256 i = 0; i < 4; i++) {
            console.log('_________________________________________________');
            console.log("startBalances", startBalances[i]);
            console.log("endBalances", endBalances[i]);
            console.log('difference', int256(endBalances[i]) - int256(startBalances[i]));
            console.log('_________________________________________________');

        }

        console.log("startBalances", startBalances[4]);
        console.log("endBalances", endBalances[4]);
    }
}