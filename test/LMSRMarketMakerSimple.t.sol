// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {MockToken} from "./MockToken.sol";
import {Dynamica} from "../src/Dynamica.sol";
import {IDynamica} from "../src/interfaces/IDynamica.sol";
import {DynamicaFactory} from "../src/MarketMakerFactory.sol";
import {MarketResolutionManager} from "../src/Oracles/MarketResolutionManager.sol";
import {ChainlinkResolutionModule, ChainlinkConfig} from "../src/Oracles/Hedera/ChainlinkResolutionModule.sol";
import {FTSOResolutionModule} from "../src/Oracles/Flare/FTSOResolutionModule.sol";
import {OracleSetUP} from "./MockOracles/OracleSetUP.t.sol";
import {IMarketResolutionModule} from "../src/interfaces/IMarketResolutionModule.sol";
import {SD59x18, sd, exp, ln} from "@prb-math/src/SD59x18.sol";
import {console} from "forge-std/src/console.sol";
import {Test} from "forge-std/src/Test.sol";
import {HederaTokenService} from
    "@hashgraph/hedera-token-service/system-contracts/hedera-token-service/HederaTokenService.sol";
import {IHederaTokenService} from
    "@hashgraph/hedera-token-service/system-contracts/hedera-token-service/IHederaTokenService.sol";
import {ExpiryHelper} from "@hashgraph/hedera-token-service/system-contracts/hedera-token-service/ExpiryHelper.sol";
import {KeyHelper} from "@hashgraph/hedera-token-service/system-contracts/hedera-token-service/KeyHelper.sol";
import {htsSetup} from "hedera-forking/contracts/htsSetup.sol";

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
    int64 constant INITIAL_SUPPLY = 1_000_000e8;

    int64 constant DECIMALS = 10;

    /// @notice Dynamica implementation contract
    Dynamica public implementation;

    /// @notice Deployed market maker instance
    Dynamica public marketMaker;

    /// @notice Factory contract for creating markets
    DynamicaFactory public factory;

    /// @notice Mock ERC20 token for testing
    MockToken public mockToken;

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
    // ============ Setup Function ============

    function createToken(string memory name1, string memory symbol1, string memory name2, string memory symbol2)
        public
        payable
    {
        testT = new address[](2);
        IHederaTokenService.HederaToken memory token;
        for (uint256 i = 0; i < 2; i++) {
            token.name = i == 0 ? name1 : name2;
            token.symbol = i == 0 ? symbol1 : symbol2;
            token.treasury = OWNER;
            token.expiry.autoRenewAccount = OWNER;
            token.expiry.autoRenewPeriod = 5184000;
            token.tokenKeys = new IHederaTokenService.TokenKey[](1);
            IHederaTokenService.TokenKey memory supplyKey = IHederaTokenService.TokenKey({
                keyType: 16,
                key: IHederaTokenService.KeyValue({
                    inheritAccountKey: false,
                    contractId: OWNER,
                    ed25519: "",
                    ECDSA_secp256k1: "",
                    delegatableContractId: address(0)
                })
            });
            token.tokenKeys[0] = supplyKey;
            int256 responseCode;
            address tokenAddress;
            (responseCode, tokenAddress) = createFungibleToken(token, int64(100000000), 8);
            testT[i] = tokenAddress;
        }
    }

    function mintToken() public payable {
        for (uint256 i = 0; i < 2; i++) {
            bytes[] memory serialNumbersBytes;
            int256 responseCode;
            int64 newTotalSupply;
            int64[] memory serialNumbers;
            (responseCode, newTotalSupply, serialNumbers) = mintToken(testT[i], int64(100000000), serialNumbersBytes);
            console.log("responseCode", responseCode);
            console.log("newTotalSupply", newTotalSupply);
        }
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
        this.createToken{value: 2 ether}("Token1", "T1", "Token2", "T2");
        mintToken();
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

        // Record market balance before resolution
        startBalances[4] = mockToken.balanceOf(address(marketMaker));

        // Resolve the market
        vm.prank(OWNER);
        marketResolutionManager.resolveMarket(keccak256(bytes("eth/usdc")));

        // Redeem payouts for all traders
        _redeemPayoutsForTraders();

        // Display final balance comparison
        _displayBalanceComparison(startBalances);
    }

    // ============ Private Setup Functions ============

    /**
     * @notice Sets up the mock token for testing
     */
    function _setupMockToken() private {
        mockToken = new MockToken();
        mockToken.mint(OWNER, 1_000_000 * 10 ** uint256(uint64(DECIMALS)));
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
        assertNotEq(outcomeTokenAddresses[0], address(0));
        assertNotEq(outcomeTokenAddresses[1], address(0));
        assertEq(marketMaker.outcomeTokenAmounts(0), uint256(uint64(INITIAL_SUPPLY)));
        assertEq(marketMaker.outcomeTokenAmounts(1), uint256(uint64(INITIAL_SUPPLY)));
        assertEq(IERC20(outcomeTokenAddresses[0]).balanceOf(address(marketMaker)), uint256(uint64(INITIAL_SUPPLY)));
        assertEq(IERC20(outcomeTokenAddresses[1]).balanceOf(address(marketMaker)), uint256(uint64(INITIAL_SUPPLY)));
    }

    function testMintBurnToken() public {
        vm.startPrank(trader_0);
        mockToken.approve(address(marketMaker), 1_000 * 10 ** uint256(uint64(DECIMALS)));

        int256[] memory amounts = new int256[](2);
        amounts[0] = 546 * int256(10 ** uint256(uint64(DECIMALS)));
        amounts[1] = 514 * int256(10 ** uint256(uint64(DECIMALS)));
        console.log("amount_before", IERC20(outcomeTokenAddresses[0]).balanceOf(trader_0));
        marketMaker.makePrediction(amounts);
        console.log("amount_after", IERC20(outcomeTokenAddresses[0]).balanceOf(trader_0));

        amounts[0] = -500 * int256(10 ** uint256(uint64(DECIMALS)));
        amounts[1] = 4 * int256(10 ** uint256(uint64(DECIMALS)));
        console.log("amount_before", IERC20(outcomeTokenAddresses[0]).balanceOf(trader_0));
        int256 responseCode = approve(
            outcomeTokenAddresses[0], address(marketMaker), uint256(500 * int256(10 ** uint256(uint64(DECIMALS))))
        );
        console.log("responseCode", responseCode);
        marketMaker.makePrediction(amounts);
        console.log("amount_after", IERC20(outcomeTokenAddresses[0]).balanceOf(trader_0));

        vm.stopPrank();

        //assertEq(IERC20(outcomeTokenAddresses[0]).balanceOf(address(marketMaker)), uint256(uint64(INITIAL_SUPPLY)));
        //assertEq(IERC20(outcomeTokenAddresses[1]).balanceOf(address(marketMaker)), uint256(uint64(INITIAL_SUPPLY)));
    }

    /**
     * @notice Sets up the market resolution manager
     */
    function _setupMarketResolutionManager() private {
        marketResolutionManager = new MarketResolutionManager(OWNER, address(factory));
        factory.setOracleCoordinator(address(marketResolutionManager));
        mockToken.approve(address(factory), 1_000_000 * 10 ** uint256(uint64(DECIMALS)));
    }

    /**
     * @notice Creates the test market with Chainlink configuration
     */
    function _createTestMarket() private {
        // Prepare Chainlink configuration
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
                collateralToken: address(mockToken),
                oracle: ORACLE,
                question: "eth/usdc",
                outcomeSlotCount: 2,
                startFunding: 10 * 10 ** uint256(uint64(DECIMALS)),
                outcomeTokenAmounts: uint256(uint64(INITIAL_SUPPLY)),
                fee: 0,
                alpha: 3,
                expLimit: 12750
            }),
            IMarketResolutionModule.MarketResolutionConfig({
                marketMaker: address(0),
                outcomeSlotCount: 5,
                resolutionModule: address(0),
                resolutionData: abi.encode(chainlinkConfig),
                isResolved: false,
                resolutionModuleType: IMarketResolutionModule.ResolutionModule.CHAINLINK
            }),
            tokens
        );

        // Get the deployed market maker
        marketMaker = Dynamica(payable(factory.marketMakers(0)));

        outcomeTokenAddresses = new address[](2);
        outcomeTokenAddresses[0] = marketMaker.outcomeTokenAddresses(0);
        outcomeTokenAddresses[1] = marketMaker.outcomeTokenAddresses(1);
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
        mockToken.mint(trader_0, 1_000_000 * 10 ** uint256(uint64(DECIMALS)));
        mockToken.mint(trader_1, 1_000_000 * 10 ** uint256(uint64(DECIMALS)));
        mockToken.mint(trader_2, 1_000_000 * 10 ** uint256(uint64(DECIMALS)));
        mockToken.mint(trader_3, 1_000_000 * 10 ** uint256(uint64(DECIMALS)));
    }

    // ============ Private Test Functions ============

    /**
     * @notice Gets initial balances for all participants
     * @return startBalances Array of initial balances
     */
    function _getInitialBalances() private view returns (uint256[] memory startBalances) {
        startBalances = new uint256[](5);
        startBalances[0] = mockToken.balanceOf(trader_0);
        startBalances[1] = mockToken.balanceOf(trader_1);
        startBalances[2] = mockToken.balanceOf(trader_2);
        startBalances[3] = mockToken.balanceOf(trader_3);
    }

    /**
     * @notice Executes the trading sequence with predefined trades
     */
    function _executeTradingSequence() private {
        address[] memory traders = _getTraderSequence();
        int256[][] memory amounts = _getTradeAmounts();

        for (uint256 i = 0; i < traders.length; i++) {
            vm.startPrank(traders[i]);
            int256 responseCode = approve(
                outcomeTokenAddresses[0], address(marketMaker), uint256(1_000 * int256(10 ** uint256(uint64(DECIMALS))))
            );
            responseCode = approve(
                outcomeTokenAddresses[1], address(marketMaker), uint256(1_000 * int256(10 ** uint256(uint64(DECIMALS))))
            );
            mockToken.approve(address(marketMaker), 1_000 * 10 ** uint256(uint64(DECIMALS)));
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

    /**
     * @notice Gets the predefined trade amounts for testing
     * @return amounts Array of trade amounts for each trader
     */
    function _getTradeAmounts() private pure returns (int256[][] memory amounts) {
        amounts = new int256[][](11);

        // Trade 1: trader_0 buys both outcomes
        amounts[0] = new int256[](2);
        amounts[0][0] = 546 * int256(10 ** uint256(uint64(DECIMALS)));
        amounts[0][1] = 514 * int256(10 ** uint256(uint64(DECIMALS)));

        // Trade 2: trader_1 buys both outcomes
        amounts[1] = new int256[](2);
        amounts[1][0] = 527 * int256(10 ** uint256(uint64(DECIMALS)));
        amounts[1][1] = 496 * int256(10 ** uint256(uint64(DECIMALS)));

        // Trade 3: trader_2 buys both outcomes
        amounts[2] = new int256[](2);
        amounts[2][0] = 299 * int256(10 ** uint256(uint64(DECIMALS)));
        amounts[2][1] = 136 * int256(10 ** uint256(uint64(DECIMALS)));

        // Trade 4: trader_3 buys both outcomes
        amounts[3] = new int256[](2);
        amounts[3][0] = 263 * int256(10 ** uint256(uint64(DECIMALS)));
        amounts[3][1] = 136 * int256(10 ** uint256(uint64(DECIMALS)));

        // Trade 5: trader_0 buys outcome 0, sells outcome 1
        amounts[4] = new int256[](2);
        amounts[4][0] = 143 * int256(10 ** uint256(uint64(DECIMALS)));
        amounts[4][1] = -136 * int256(10 ** uint256(uint64(DECIMALS)));

        // Trade 6: trader_1 buys both outcomes
        amounts[5] = new int256[](2);
        amounts[5][0] = 92 * int256(10 ** uint256(uint64(DECIMALS)));
        amounts[5][1] = 122 * int256(10 ** uint256(uint64(DECIMALS)));

        // Trade 7: trader_2 buys both outcomes
        amounts[6] = new int256[](2);
        amounts[6][0] = 53 * int256(10 ** uint256(uint64(DECIMALS)));
        amounts[6][1] = 88 * int256(10 ** uint256(uint64(DECIMALS)));

        // Trade 8: trader_3 sells both outcomes
        amounts[7] = new int256[](2);
        amounts[7][0] = -53 * int256(10 ** uint256(uint64(DECIMALS)));
        amounts[7][1] = -62 * int256(10 ** uint256(uint64(DECIMALS)));

        // Trade 9: trader_2 only buys outcome 1
        amounts[8] = new int256[](2);
        amounts[8][0] = 0;
        amounts[8][1] = 11 * int256(10 ** uint256(uint64(DECIMALS)));

        // Trade 10: trader_3 only sells outcome 1
        amounts[9] = new int256[](2);
        amounts[9][0] = 0;
        amounts[9][1] = -10 * int256(10 ** uint256(uint64(DECIMALS)));

        // Trade 11: trader_1 only buys outcome 1
        amounts[10] = new int256[](2);
        amounts[10][0] = 0;
        amounts[10][1] = 2 * int256(10 ** uint256(uint64(DECIMALS)));
    }

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
        endBalances[0] = mockToken.balanceOf(trader_0);
        endBalances[1] = mockToken.balanceOf(trader_1);
        endBalances[2] = mockToken.balanceOf(trader_2);
        endBalances[3] = mockToken.balanceOf(trader_3);
        endBalances[4] = mockToken.balanceOf(address(marketMaker));

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

/*
  netCost 555908056241143224484
  netCost 536530914472432726532
  netCost 283260834088902418767
  netCost 260836127244916577738
  netCost 141529220288594265563
  netCost 92091957708025698591
  netCost 53151154512030819909
  netCost -53088765766026265983
  netCost 32937849213664532
  netCost -30121114583731157
  netCost 5736803886458836
  redeeming 0
  redeeming 1
  redeeming 2
  redeeming 3
  startBalances 1000000000000000000000000
  endBalances 999700000223470262509953
  startBalances 1000000000000000000000000
  endBalances 999991308891015655116041
  startBalances 1000000000000000000000000
  endBalances 999905867573549853096792
  startBalances 1000000000000000000000000
  endBalances 999865407759635693419402
  startBalances 1880228052328535857812           
  endBalances 0







  Logs:
  netCost 55204421254
  minting token 0x0000000000000000000000000000000000000408
  minting amount 54600000000
  minting token 0x0000000000000000000000000000000000000409
  minting amount 51400000000
  netCost 53277881491
  minting token 0x0000000000000000000000000000000000000408
  minting amount 52700000000
  minting token 0x0000000000000000000000000000000000000409
  minting amount 49600000000
  netCost 22664358503
  minting token 0x0000000000000000000000000000000000000408
  minting amount 29900000000
  minting token 0x0000000000000000000000000000000000000409
  minting amount 13600000000
  netCost 20794992091
  minting token 0x0000000000000000000000000000000000000408
  minting amount 26300000000
  minting token 0x0000000000000000000000000000000000000409
  minting amount 13600000000
  netCost 421725197
  minting token 0x0000000000000000000000000000000000000408
  minting amount 14300000000
  netCost 11137291262
  minting token 0x0000000000000000000000000000000000000408
  minting amount 9200000000
  minting token 0x0000000000000000000000000000000000000409
  minting amount 12200000000
  netCost 7334686012
  minting token 0x0000000000000000000000000000000000000408
  minting amount 5300000000
  minting token 0x0000000000000000000000000000000000000409
  minting amount 8800000000
  netCost -5986992214
  netCost 570262850
  minting token 0x0000000000000000000000000000000000000409
  minting amount 1100000000
  netCost -518422854
  netCost 103681240
  minting token 0x0000000000000000000000000000000000000409
  minting amount 200000000
  redeeming 0
  redeeming 1
  redeeming 2
  redeeming 3
  startBalances 100000000000000
  endBalances 99984117603549
  startBalances 100000000000000
  endBalances 99997474896007
  startBalances 100000000000000
  endBalances 99993661942635
  startBalances 100000000000000
  endBalances 99993022922977
  startBalances 166003884832
  endBalances 0
*/
