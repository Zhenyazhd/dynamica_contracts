// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {MockToken, IERC20Mock} from "./MockToken.sol";
import {Dynamica} from "../src/Dynamica.sol";
import {IDynamica} from "../src/interfaces/IDynamica.sol";
import {DynamicaFactory} from "../src/DynamicaFactory.sol";
import {MarketResolutionManager} from "../src/Oracles/MarketResolutionManager.sol";
import {ChainlinkResolutionModule} from "../src/Oracles/Hedera/ChainlinkResolutionModule.sol";
import {OracleSetUP} from "./MockOracles/OracleSetUP.t.sol";
import {IMarketResolutionModule} from "../src/interfaces/Oracles/IMarketResolutionModule.sol";
import {LMSRMath} from "../src/LMSRMath.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Test} from "forge-std/src/Test.sol";

/**
 * @title DynamicaV2
 * @dev Test version of Dynamica with version = 2 for upgrade testing
 * @notice This contract adds an upgrade function that can be called after beacon upgrade
 */
contract DynamicaV2 is Dynamica {
    /**
     * @notice Upgrades the contract to version 2
     * @dev This function should be called after the beacon is upgraded to this implementation
     * @notice Only callable once per market
     */
    function upgradeToV2() external {
        require(version == 1, "Already upgraded or wrong version");
        version = 2;
    }

    /**
     * @notice Returns true if this is V2 implementation
     * @dev Used to verify upgrade
     */
    function isV2() external pure returns (bool) {
        return true;
    }
}

/**
 * @title TestUpgrade
 * @dev Test contract for upgrading Dynamica markets via UpgradeableBeacon
 * @notice Tests the upgrade mechanism for markets created through DynamicaFactory
 */
contract TestUpgrade is OracleSetUP {
    // ============ State Variables ============

    address public constant OWNER = address(0xABCD);

    uint8 constant DECIMALS = 10;
    uint8 constant DECIMALS_COLLATERAL = 10;
    uint256 constant INITIAL_SUPPLY = 500 * (10 ** DECIMALS);
    uint256 constant START_FUNDING = 1000 * 10 ** uint256(DECIMALS_COLLATERAL);

    /// @notice Dynamica v1 implementation contract
    Dynamica public implementationV1;

    /// @notice Dynamica v2 implementation contract
    DynamicaV2 public implementationV2;

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

    /// @notice Beacon contract from factory
    UpgradeableBeacon public beacon;

    // ============ Setup Function ============

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

        vm.stopPrank();
    }

    // ============ Test Functions ============

    /**
     * @notice Tests that the market is created with version 1
     */
    function testInitialVersion() public view {
        assertEq(marketMaker.version(), 1, "Initial version should be 1");
    }

    /**
     * @notice Tests upgrading the market to version 2
     * @dev This test verifies that:
     *      1. Market starts with version 1
     *      2. Data is preserved after upgrade
     *      3. Market functionality still works after upgrade
     *      4. Version is updated to 2
     */
    function testUpgradeMarket() public {
        // Record initial state
        uint256 initialEpoch = marketMaker.currentEpochNumber();
        uint256 initialPeriod = marketMaker.currentPeriodNumber();
        address initialOwner = marketMaker.owner();
        address initialCollateralToken = marketMaker.collateralToken();
        string memory initialQuestion = marketMaker.question();
        IDynamica.EpochData memory initialEpochData = marketMaker.getEpochData(1);
        uint32 initialEpochStart = initialEpochData.epochStart;
        uint256 initialBalance = IERC20Mock(mockToken).balanceOf(address(marketMaker));

        // Verify initial version
        assertEq(marketMaker.version(), 1, "Initial version should be 1");

        // Upgrade beacon to v2 implementation
        vm.prank(OWNER);
        beacon.upgradeTo(address(implementationV2));

        // Call upgrade function to set version to 2
        DynamicaV2(address(marketMaker)).upgradeToV2();

        // Verify version is now 2
        assertEq(marketMaker.version(), 2, "Version should be 2 after upgrade");
        
        // Verify this is V2 implementation
        assertTrue(DynamicaV2(address(marketMaker)).isV2(), "Should be V2 implementation");

        // Verify all data is preserved
        assertEq(marketMaker.currentEpochNumber(), initialEpoch, "Epoch should be preserved");
        assertEq(marketMaker.currentPeriodNumber(), initialPeriod, "Period should be preserved");
        assertEq(marketMaker.owner(), initialOwner, "Owner should be preserved");
        assertEq(marketMaker.collateralToken(), initialCollateralToken, "Collateral token should be preserved");
        assertEq(keccak256(bytes(marketMaker.question())), keccak256(bytes(initialQuestion)), "Question should be preserved");
        assertEq(IERC20Mock(mockToken).balanceOf(address(marketMaker)), initialBalance, "Balance should be preserved");
        
        // Verify epoch data is accessible (structure is preserved)
        uint32 epochStartAfter = marketMaker.getEpochData(1).epochStart;
        assertEq(epochStartAfter, initialEpochStart, "Epoch start should be preserved");
    }

    /**
     * @notice Tests that market functionality works after upgrade
     */
    function testMarketFunctionalityAfterUpgrade() public {
        // Upgrade to v2
        vm.prank(OWNER);
        beacon.upgradeTo(address(implementationV2));

        // Call upgrade function to set version to 2
        DynamicaV2(address(marketMaker)).upgradeToV2();

        // Verify version is 2
        assertEq(marketMaker.version(), 2, "Version should be 2");

        // Test that basic functions still work
        assertEq(marketMaker.currentEpochNumber(), 1, "Epoch should be accessible");
        assertEq(marketMaker.currentPeriodNumber(), 1, "Period should be accessible");
        assertTrue(marketMaker.owner() != address(0), "Owner should be accessible");
        assertTrue(marketMaker.collateralToken() != address(0), "Collateral token should be accessible");

        // Test that checkEpoch works
        bool shouldResolve = marketMaker.checkEpoch();
        assertFalse(shouldResolve, "Epoch should not be ready to resolve initially");

        // Test that outcomeTokenSupplies works
        uint256 supply0 = marketMaker.outcomeTokenSupplies(1, 1, 0);
        uint256 supply1 = marketMaker.outcomeTokenSupplies(1, 1, 1);
        assertEq(supply0, INITIAL_SUPPLY, "Supply for outcome 0 should be correct");
        assertEq(supply1, INITIAL_SUPPLY, "Supply for outcome 1 should be correct");
    }

    /**
     * @notice Tests that multiple markets can be upgraded simultaneously
     */
    function testUpgradeMultipleMarkets() public {
        // Create second market
        address market2 = _createSecondMarket();

        // Verify both markets have version 1
        assertEq(marketMaker.version(), 1, "Market 1 should have version 1");
        assertEq(Dynamica(market2).version(), 1, "Market 2 should have version 1");

        // Upgrade beacon
        vm.prank(OWNER);
        beacon.upgradeTo(address(implementationV2));

        // Call upgrade function for both markets
        DynamicaV2(address(marketMaker)).upgradeToV2();
        DynamicaV2(market2).upgradeToV2();

        // Verify both markets are upgraded
        assertEq(marketMaker.version(), 2, "Market 1 should have version 2");
        assertEq(Dynamica(market2).version(), 2, "Market 2 should have version 2");
    }

    /**
     * @notice Tests that only owner can upgrade
     */
    function testOnlyOwnerCanUpgrade() public {
        address nonOwner = address(0x1234);

        vm.prank(nonOwner);
        vm.expectRevert();
        beacon.upgradeTo(address(implementationV2));
    }

    // ============ Private Setup Functions ============

    /**
     * @notice Sets up the mock token for testing
     */
    function _setupMockToken() private {
        mockToken = address(new MockToken(DECIMALS_COLLATERAL));
        IERC20Mock(mockToken).mint(OWNER, 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
    }

    /**
     * @notice Deploys implementation contracts
     */
    function _deployImplementations() private {
        implementationV1 = new Dynamica();
        implementationV2 = new DynamicaV2();
        implementationResolutionModuleChainlink = address(new ChainlinkResolutionModule());
        lmsrMathExternal = new LMSRMath();
    }

    /**
     * @notice Sets up the factory contract
     */
    function _setupFactory() private {
        factory = new DynamicaFactory(
            address(implementationV1),
            implementationResolutionModuleChainlink,
            OWNER,
            address(lmsrMathExternal)
        );
        factory.addAllowedCollateralToken(address(mockToken));
        beacon = factory.BEACON();
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
                oracle: address(marketResolutionManager),
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
                outcomeSlotCount: 2,
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
     * @notice Creates a second market for testing multiple upgrades
     */
    function _createSecondMarket() private returns (address) {
        ChainlinkResolutionModule.ChainlinkConfig memory chainlinkConfig = _prepareChainlinkConfig();
        
        vm.prank(OWNER);
        factory.createMarketMaker(
            IDynamica.Config({
                owner: OWNER,
                collateralToken: address(mockToken),
                oracle: address(marketResolutionManager),
                question: "eth/btc-v2",
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
                outcomeSlotCount: 2,
                resolutionModule: address(0),
                resolutionData: abi.encode(chainlinkConfig),
                isResolved: false,
                resolutionModuleType: IMarketResolutionModule.ResolutionModule.CHAINLINK
            })
        );
        return factory.marketMakers(1);
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

        config = ChainlinkResolutionModule.ChainlinkConfig({
            priceFeedAddresses: priceFeedAddresses,
            staleness: staleness,
            decimals: decimals
        });
    }
}

