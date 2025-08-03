// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

//import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {MockToken} from "./MockToken.sol";
import {Dynamica} from "../src/Dynamica.sol";
import {IDynamica} from "../src/interfaces/IDynamica.sol";
import {DynamicaFactory} from "../src/MarketMakerFactory.sol";
import {MarketResolutionManager} from "../src/Oracles/MarketResolutionManager.sol";
import {ChainlinkResolutionModule, ChainlinkConfig} from "../../src/Oracles/Hedera/ChainlinkResolutionModule.sol";
import {FTSOResolutionModule} from "../src/Oracles/Flare/FTSOResolutionModule.sol";
import {OracleSetUP} from "./MockOracles/OracleSetUP.t.sol";
import {IMarketResolutionModule} from "../src/interfaces/IMarketResolutionModule.sol";
import {SD59x18, sd, exp, ln} from "@prb-math/src/SD59x18.sol";
import {console} from "forge-std/src/console.sol";
import {Test} from "forge-std/src/Test.sol";

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

    uint8 constant DECIMALS = 10;
    uint8 constant DECIMALS_COLLATERAL = 10;
    uint256 constant INITIAL_SUPPLY = 500 * (10 ** DECIMALS);
    uint256 constant START_FUNDING = 1000 * 10 ** uint256(DECIMALS_COLLATERAL);


    /// @notice Dynamica implementation contract
    Dynamica public implementation;

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

    // ============ Test Functions ============


    function testSetupMarketMaker() public view {
        assertEq(marketMaker.currentEpochNumber(), 1);
        assertEq(marketMaker.currentPeriodNumber(), 1);
        assertEq(marketMaker.balanceOf(address(marketMaker), marketMaker.shareId(1, 1, 0)), uint256(uint64(INITIAL_SUPPLY)));
        assertEq(marketMaker.balanceOf(address(marketMaker), marketMaker.shareId(1, 1, 1)), uint256(uint64(INITIAL_SUPPLY)));
        assertEq(IERC20(mockToken).balanceOf(address(marketMaker)), START_FUNDING);
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
        // Track initial balances
        uint256[] memory startBalances = _getInitialBalances();

        // Execute trading sequence
        _executeTradingSequence();

        // Record market balance before resolution
        startBalances[4] = IERC20(mockToken).balanceOf(address(marketMaker));

        // Resolve the market
        vm.warp(block.timestamp + 8 days + 1);
        console.log('currentEpochNumber', marketMaker.currentEpochNumber());

        vm.prank(OWNER);
        marketResolutionManager.resolveMarket(keccak256(bytes("eth/btc")));
        //console.log('basePrice_0', marketMaker.basePrice(0));
        //console.log('basePrice_1', marketMaker.basePrice(1));
        // Redeem payouts for all traders 
        _redeemPayoutsForTraders(1); 
        _redeemPayoutsForTraders(2); 


        //vm.prank(OWNER);
       // marketResolutionManager.resolveMarket(keccak256(bytes("eth/btc")));


        // Display final balance comparison
        _displayBalanceComparison(startBalances);
    }

    

    // ============ Private Setup Functions ============

    /**
     * @notice Sets up the mock token for testing
     */
    function _setupMockToken() private {
        this.createToken("Token1", "T1");
        IERC20(mockToken).mint(OWNER, 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
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

    /**
     * @notice Sets up the market resolution manager
     */
    function _setupMarketResolutionManager() private {
        marketResolutionManager = new MarketResolutionManager(OWNER, address(factory));
        factory.setOracleCoordinator(address(marketResolutionManager));
        IERC20(mockToken).approve(address(factory), 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
    }

    /**
     * @notice Creates the test market with Chainlink configuration
     */
    function _createTestMarket() private {
        ChainlinkConfig memory chainlinkConfig = _prepareChainlinkConfig();
        // Create market through factory
        factory.createMarketMaker(
            IDynamica.Config({
                owner: OWNER,
                collateralToken: address(mockToken),
                oracle: ORACLE,
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
        IERC20(mockToken).mint(trader_0, 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
        IERC20(mockToken).mint(trader_1, 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
        IERC20(mockToken).mint(trader_2, 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
        IERC20(mockToken).mint(trader_3, 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
    }

    // ============ Private Test Functions ============

    /**
     * @notice Gets initial balances for all participants
     * @return startBalances Array of initial balances
     */
    function _getInitialBalances() private view returns (uint256[] memory startBalances) {
        startBalances = new uint256[](5);
        startBalances[0] = IERC20(mockToken).balanceOf(trader_0);
        startBalances[1] = IERC20(mockToken).balanceOf(trader_1);
        startBalances[2] = IERC20(mockToken).balanceOf(trader_2);
        startBalances[3] = IERC20(mockToken).balanceOf(trader_3);
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
            int256 mockBalance = int256(IERC20(mockToken).balanceOf(traders[i]));
            marketMaker.setApprovalForAll(address(marketMaker), true);
            IERC20(mockToken).approve(address(marketMaker), 1_000 * 10 ** uint256(uint64(DECIMALS_COLLATERAL)));
            marketMaker.makePrediction(amounts[i]);
            for (uint256 j = 0; j < amounts[i].length; j++) {
                //assertEq(int256(marketMaker.balanceOf(traders[i], marketMaker.shareId(marketMaker.currentEpochNumber(), marketMaker.currentPeriodNumber(), j))), int256(balances[j]) + amounts[i][j]);
            }
            console.log('_________________________________________________');
            console.log('trader', traders[i]);
            console.log('epoch', marketMaker.currentEpochNumber());
            console.log('period', marketMaker.currentPeriodNumber());
            console.log('amounts_0', amounts[i][0]);
            console.log('amounts_1', amounts[i][1]);
            console.log('balance', mockBalance - int256(IERC20(mockToken).balanceOf(traders[i])));
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
        traders[0] = trader_0;
        traders[1] = trader_1;
        traders[2] = trader_2;
        traders[3] = trader_3;

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
        endBalances[0] = IERC20(mockToken).balanceOf(trader_0);
        endBalances[1] = IERC20(mockToken).balanceOf(trader_1);
        endBalances[2] = IERC20(mockToken).balanceOf(trader_2);
        endBalances[3] = IERC20(mockToken).balanceOf(trader_3);
        endBalances[4] = IERC20(mockToken).balanceOf(address(marketMaker));

        // Display balance changes for each participant
        for (uint256 i = 0; i < 4; i++) {
            console.log('_________________________________________________');
            console.log("startBalances", startBalances[i]);
            console.log("endBalances", endBalances[i]);
            console.log('difference', int256(endBalances[i]) - int256(startBalances[i]));
            console.log('_________________________________________________');

        }

        // Display market maker balance
        console.log("startBalances", startBalances[4]);
        console.log("endBalances", endBalances[4]);
    }
}

/*
  netCost 555908056241143224484 (555,)
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
  netCost 55204421254 (552,)
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




Encountered 2 failing tests in test/LMSRMarketMakerSimple.t.sol:LMSRMarketMakerSimpleTest
[FAIL: EVM error; database error: failed to get storage for 0x000000000000000000000000000000000000040B at 50942633119752846454219349998365661925608737367104304655302372697895582664657: HTTP error 502 with body: <!DOCTYPE html>
<!--[if lt IE 7]> <html class="no-js ie6 oldie" lang="en-US"> <![endif]-->
<!--[if IE 7]>    <html class="no-js ie7 oldie" lang="en-US"> <![endif]-->
<!--[if IE 8]>    <html class="no-js ie8 oldie" lang="en-US"> <![endif]-->
<!--[if gt IE 8]><!--> <html class="no-js" lang="en-US"> <!--<![endif]-->
<head>


<title>testnet.hashio.io | 502: Bad gateway</title>
<meta charset="UTF-8" />
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
<meta http-equiv="X-UA-Compatible" content="IE=Edge" />
<meta name="robots" content="noindex, nofollow" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<link rel="stylesheet" id="cf_styles-css" href="/cdn-cgi/styles/main.css" />


</head>
<body>
<div id="cf-wrapper">
    <div id="cf-error-details" class="p-0">
        <header class="mx-auto pt-10 lg:pt-6 lg:px-8 w-240 lg:w-full mb-8">
            <h1 class="inline-block sm:block sm:mb-2 font-light text-60 lg:text-4xl text-black-dark leading-tight mr-2">
              <span class="inline-block">Bad gateway</span>
              <span class="code-label">Error code 502</span>
            </h1>
            <div>
               Visit <a href="https://www.cloudflare.com/5xx-error-landing?utm_source=errorcode_502&utm_campaign=testnet.hashio.io" target="_blank" rel="noopener noreferrer">cloudflare.com</a> for more information.
            </div>
            <div class="mt-3">2025-07-23 16:09:26 UTC</div>
        </header>
        <div class="my-8 bg-gradient-gray">
            <div class="w-240 lg:w-full mx-auto">
                <div class="clearfix md:px-8">
                  
<div id="cf-browser-status" class=" relative w-1/3 md:w-full py-15 md:p-0 md:py-8 md:text-left md:border-solid md:border-0 md:border-b md:border-gray-400 overflow-hidden float-left md:float-none text-center">
  <div class="relative mb-10 md:m-0">
    
    <span class="cf-icon-browser block md:hidden h-20 bg-center bg-no-repeat"></span>
    <span class="cf-icon-ok w-12 h-12 absolute left-1/2 md:left-auto md:right-0 md:top-0 -ml-6 -bottom-4"></span>
    
  </div>
  <span class="md:block w-full truncate">You</span>
  <h3 class="md:inline-block mt-3 md:mt-0 text-2xl text-gray-600 font-light leading-1.3">
    
    Browser
    
  </h3>
  <span class="leading-1.3 text-2xl text-green-success">Working</span>
</div>

<div id="cf-cloudflare-status" class=" relative w-1/3 md:w-full py-15 md:p-0 md:py-8 md:text-left md:border-solid md:border-0 md:border-b md:border-gray-400 overflow-hidden float-left md:float-none text-center">
  <div class="relative mb-10 md:m-0">
    <a href="https://www.cloudflare.com/5xx-error-landing?utm_source=errorcode_502&utm_campaign=testnet.hashio.io" target="_blank" rel="noopener noreferrer">
    <span class="cf-icon-cloud block md:hidden h-20 bg-center bg-no-repeat"></span>
    <span class="cf-icon-ok w-12 h-12 absolute left-1/2 md:left-auto md:right-0 md:top-0 -ml-6 -bottom-4"></span>
    </a>
  </div>
  <span class="md:block w-full truncate">Marseille</span>
  <h3 class="md:inline-block mt-3 md:mt-0 text-2xl text-gray-600 font-light leading-1.3">
    <a href="https://www.cloudflare.com/5xx-error-landing?utm_source=errorcode_502&utm_campaign=testnet.hashio.io" target="_blank" rel="noopener noreferrer">
    Cloudflare
    </a>
  </h3>
  <span class="leading-1.3 text-2xl text-green-success">Working</span>
</div>

<div id="cf-host-status" class="cf-error-source relative w-1/3 md:w-full py-15 md:p-0 md:py-8 md:text-left md:border-solid md:border-0 md:border-b md:border-gray-400 overflow-hidden float-left md:float-none text-center">
  <div class="relative mb-10 md:m-0">
    
    <span class="cf-icon-server block md:hidden h-20 bg-center bg-no-repeat"></span>
    <span class="cf-icon-error w-12 h-12 absolute left-1/2 md:left-auto md:right-0 md:top-0 -ml-6 -bottom-4"></span>
    
  </div>
  <span class="md:block w-full truncate">testnet.hashio.io</span>
  <h3 class="md:inline-block mt-3 md:mt-0 text-2xl text-gray-600 font-light leading-1.3">
    
    Host
    
  </h3>
  <span class="leading-1.3 text-2xl text-red-error">Error</span>
</div>

                </div>
            </div>
        </div>

        <div class="w-240 lg:w-full mx-auto mb-8 lg:px-8">
            <div class="clearfix">
                <div class="w-1/2 md:w-full float-left pr-6 md:pb-10 md:pr-0 leading-relaxed">
                    <h2 class="text-3xl font-normal leading-1.3 mb-4">What happened?</h2>
                    <p>The web server reported a bad gateway error.</p>
                </div>
                <div class="w-1/2 md:w-full float-left leading-relaxed">
                    <h2 class="text-3xl font-normal leading-1.3 mb-4">What can I do?</h2>
                    <p class="mb-6">Please try again in a few minutes.</p>
                </div>
            </div>
        </div>

        <div class="cf-error-footer cf-wrapper w-240 lg:w-full py-10 sm:py-4 sm:px-8 mx-auto text-center sm:text-left border-solid border-0 border-t border-gray-300">
  <p class="text-13">
    <span class="cf-footer-item sm:block sm:mb-1">Cloudflare Ray ID: <strong class="font-semibold">963c71353b9f129f</strong></span>
    <span class="cf-footer-separator sm:hidden">&bull;</span>
    <span id="cf-footer-item-ip" class="cf-footer-item hidden sm:block sm:mb-1">
      Your IP:
      <button type="button" id="cf-footer-ip-reveal" class="cf-footer-ip-reveal-btn">Click to reveal</button>
      <span class="hidden" id="cf-footer-ip">2a02:842a:a542:6901:b0c3:78c6:de72:62b1</span>
      <span class="cf-footer-separator sm:hidden">&bull;</span>
    </span>
    <span class="cf-footer-item sm:block sm:mb-1"><span>Performance &amp; security by</span> <a rel="noopener noreferrer" href="https://www.cloudflare.com/5xx-error-landing?utm_source=errorcode_502&utm_campaign=testnet.hashio.io" id="brand_link" target="_blank">Cloudflare</a></span>
    
  </p>
  <script>(function(){function d(){var b=a.getElementById("cf-footer-item-ip"),c=a.getElementById("cf-footer-ip-reveal");b&&"classList"in b&&(b.classList.remove("hidden"),c.addEventListener("click",function(){c.classList.add("hidden");a.getElementById("cf-footer-ip").classList.remove("hidden")}))}var a=document;document.addEventListener&&a.addEventListener("DOMContentLoaded",d)})();</script>
</div><!-- /.error-footer -->


    </div>
</div>
</body>
</html>] testCreateToken() (gas: 0)
[FAIL: Market not expired] testMarketCicle() (gas: 5857920)
*/