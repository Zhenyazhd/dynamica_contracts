// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import { MockToken } from "./MockToken.sol";
import { Dynamica } from "../src/Dynamica.sol";
import { IDynamica } from "../src/interfaces/IDynamica.sol";
import { DynamicaFactory } from "../src/MarketMakerFactory.sol";
import { MarketResolutionManager } from "../src/Oracles/MarketResolutionManager.sol";
import { ChainlinkResolutionModule, ChainlinkConfig } from "../src/Oracles/Hedera/ChainlinkResolutionModule.sol";
import { FTSOResolutionModule } from "../src/Oracles/Flare/FTSOResolutionModule.sol";
import { OracleSetUP } from "./MockOracles/OracleSetUP.t.sol";
import { IMarketResolutionModule } from "../src/interfaces/IMarketResolutionModule.sol";
import { SD59x18, sd, exp, ln } from "@prb-math/src/SD59x18.sol";
import { console } from "forge-std/src/console.sol";
import { Test } from "forge-std/src/Test.sol";

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
    int constant public UNIT_DEC = 1e18;
    
    /// @notice Alpha parameter for LMSR (3%)
    int constant public alha = 3 * UNIT_DEC / 100;
    
    /// @notice Natural logarithm of 2
    int ln_2 = ln(sd(2 * UNIT_DEC)).unwrap();

    // ============ Test Addresses ============
    
    /// @notice Oracle address for testing
    address ORACLE = address(0x1234);
    
    /// @notice Test trader addresses
    address trader_0 = address(1);
    address trader_1 = address(2);
    address trader_2 = address(3);
    address trader_3 = address(4);

    // ============ Setup Function ============
    
    /**
     * @notice Sets up the test environment
     * @dev Initializes contracts, mints tokens, and creates a test market
     */
    function setUp() public override {
        vm.startPrank(OWNER);
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
        mockToken.mint(OWNER, 1_000_000 * 10**18);
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
        mockToken.approve(address(factory), 1_000_000 * 10**18);
    }

    /**
     * @notice Creates the test market with Chainlink configuration
     */
    function _createTestMarket() private {
        // Prepare Chainlink configuration
        ChainlinkConfig memory chainlinkConfig = _prepareChainlinkConfig();
        
        // Create market through factory
        factory.createMarketMaker(
            IDynamica.Config({
                owner: OWNER,
                collateralToken: address(mockToken),
                oracle: ORACLE,
                question: "eth/usdc",
                outcomeSlotCount: 2,
                startFunding: 10 * 10**18,
                outcomeTokenAmounts: 1_000e18,
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
            })
        );
        
        // Get the deployed market maker
        marketMaker = Dynamica(factory.marketMakers(0));
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
        
        config = ChainlinkConfig({
            priceFeedAddresses: priceFeedAddresses,
            staleness: staleness,
            decimals: decimals
        });
    }

    /**
     * @notice Mints tokens to test traders
     */
    function _mintTokensToTraders() private {
        mockToken.mint(trader_0, 1_000_000 * 10**18);
        mockToken.mint(trader_1, 1_000_000 * 10**18);
        mockToken.mint(trader_2, 1_000_000 * 10**18);
        mockToken.mint(trader_3, 1_000_000 * 10**18);
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

        for (uint i = 0; i < traders.length; i++) {
            vm.startPrank(traders[i]);
            mockToken.approve(address(marketMaker), 1_000e18);
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
        amounts[0][0] = 546e18;
        amounts[0][1] = 514e18;
        
        // Trade 2: trader_1 buys both outcomes
        amounts[1] = new int256[](2);
        amounts[1][0] = 527e18;
        amounts[1][1] = 496e18;
        
        // Trade 3: trader_2 buys both outcomes
        amounts[2] = new int256[](2);
        amounts[2][0] = 299e18;
        amounts[2][1] = 136e18;
        
        // Trade 4: trader_3 buys both outcomes
        amounts[3] = new int256[](2);
        amounts[3][0] = 263e18;
        amounts[3][1] = 136e18;
        
        // Trade 5: trader_0 buys outcome 0, sells outcome 1
        amounts[4] = new int256[](2);
        amounts[4][0] = 143e18;
        amounts[4][1] = -136e18;
        
        // Trade 6: trader_1 buys both outcomes
        amounts[5] = new int256[](2);
        amounts[5][0] = 92e18;
        amounts[5][1] = 122e18;
        
        // Trade 7: trader_2 buys both outcomes
        amounts[6] = new int256[](2);
        amounts[6][0] = 53e18;
        amounts[6][1] = 88e18;
        
        // Trade 8: trader_3 sells both outcomes
        amounts[7] = new int256[](2);
        amounts[7][0] = -53e18;
        amounts[7][1] = -62e18;
        
        // Trade 9: trader_2 only buys outcome 1
        amounts[8] = new int256[](2);
        amounts[8][0] = 0;
        amounts[8][1] = 11e18;
        
        // Trade 10: trader_3 only sells outcome 1
        amounts[9] = new int256[](2);
        amounts[9][0] = 0;
        amounts[9][1] = -10e18;
        
        // Trade 11: trader_1 only buys outcome 1
        amounts[10] = new int256[](2);
        amounts[10][0] = 0;
        amounts[10][1] = 2e18;
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

        for (uint i = 0; i < 4; i++) {
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
        for (uint i = 0; i < 4; i++) {
            console.log("startBalances", startBalances[i]);
            console.log("endBalances", endBalances[i]);
        }
        
        // Display market maker balance
        console.log("startBalances", startBalances[4]);
        console.log("endBalances", endBalances[4]);
    }
}