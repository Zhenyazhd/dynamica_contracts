// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "../src/interfaces/IERC20.sol";
import {MockToken} from "./MockToken.sol";
import {Dynamica} from "../src/Dynamica.sol";
import {IDynamica} from "../src/interfaces/IDynamica.sol";
import {DynamicaFactory} from "../src/MarketMakerFactory.sol";
import {MarketResolutionManager} from "../src/Oracles/MarketResolutionManager.sol";
import {ChainlinkResolutionModule} from "../src/Oracles/Hedera/ChainlinkResolutionModule.sol";
import {FTSOResolutionModule} from "../src/Oracles/Flare/FTSOResolutionModule.sol";
import {OracleSetUP} from "./MockOracles/OracleSetUP.t.sol";
import {IMarketResolutionModule} from "../src/interfaces/IMarketResolutionModule.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";
/**
 * @title DynamicaRevertTests
 * @dev Comprehensive test suite for all revert and require conditions in Dynamica contracts
 * @notice Tests all error conditions, access controls, and validation checks
 */
contract DynamicaRevertTests is OracleSetUP {
    // ============ State Variables ============

    address public constant OWNER = address(0xABCD);


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
    address public implementationResolutionModuleFtso; 

    // ============ Test Addresses ============

    /// @notice Oracle address for testing
    address oracle = address(0x1234);

    /// @notice Test trader addresses
    address trader0 = address(1);
    address trader1 = address(2);
    address trader2 = address(3);
    address trader3 = address(4);

    // ============ Setup Function ============

    function createToken(string memory name1, string memory symbol2) public payable {
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

    // ============ Factory Revert Tests ============

    function testFactoryConstructorReverts() public {
        // Test invalid implementation addresses
        vm.expectRevert("Invalid implementation");
        new DynamicaFactory(
            address(0), // Invalid market maker implementation
            implementationResolutionModuleChainlink,
            implementationResolutionModuleFtso,
            address(ftsoV2),
            OWNER
        );

        vm.expectRevert("Invalid implementation resolution module chainlink");
        new DynamicaFactory(
            address(implementation),
            address(0), // Invalid Chainlink implementation
            implementationResolutionModuleFtso,
            address(ftsoV2),
            OWNER
        );

        vm.expectRevert("Invalid implementation resolution module ftso");
        new DynamicaFactory(
            address(implementation),
            implementationResolutionModuleChainlink,
            address(0), // Invalid FTSO implementation
            address(ftsoV2),
            OWNER
        );

        vm.expectRevert("Invalid FTSO V2 address");
        new DynamicaFactory(
            address(implementation),
            implementationResolutionModuleChainlink,
            implementationResolutionModuleFtso,
            address(0), // Invalid FTSO V2 address
            OWNER
        );
    }

    function testFactorySetOracleCoordinatorReverts() public {
        vm.startPrank(OWNER);
        vm.expectRevert("Invalid oracle coordinator");
        factory.setOracleCoordinator(address(0));
        vm.stopPrank();

        vm.startPrank(trader0);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, trader0));
        factory.setOracleCoordinator(address(0));
        vm.stopPrank();
    }

    function testFactoryCreateMarketMakerReverts() public {
        vm.startPrank(OWNER);

        ChainlinkResolutionModule.ChainlinkConfig memory chainlinkConfig = _prepareChainlinkConfig();

        // Test invalid collateral token
        vm.expectRevert("Invalid collateral token");
        factory.createMarketMaker(
            IDynamica.Config({
                owner: OWNER,
                collateralToken: address(0),
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
                resolutionModuleType: IMarketResolutionModule.ResolutionModule.CHAINLINK,
                minPrice: 0,
                maxPrice: 0
            })
        );

        // Test invalid owner
        vm.expectRevert("Invalid owner");
        factory.createMarketMaker(
            IDynamica.Config({
                owner: address(0),
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
                resolutionModuleType: IMarketResolutionModule.ResolutionModule.CHAINLINK,
                minPrice: 0,
                maxPrice: 0
            })
        );

        // Test fee too high
        vm.expectRevert("Fee too high");
        factory.createMarketMaker(
            IDynamica.Config({
                owner: OWNER,
                collateralToken: address(mockToken),
                oracle: oracle,
                question: "eth/btc",
                outcomeSlotCount: 2,
                startFunding: START_FUNDING,
                outcomeTokenAmounts: INITIAL_SUPPLY,
                fee: 10001, // Higher than FEE_RANGE (10000)
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
                resolutionModuleType: IMarketResolutionModule.ResolutionModule.CHAINLINK,
                minPrice: 0,
                maxPrice: 0
            })
        );

        // Test zero funding
        vm.expectRevert("Funding must be positive");
        factory.createMarketMaker(
            IDynamica.Config({
                owner: OWNER,
                collateralToken: address(mockToken),
                oracle: oracle,
                question: "eth/btc",
                outcomeSlotCount: 2,
                startFunding: 0,
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
                resolutionModuleType: IMarketResolutionModule.ResolutionModule.CHAINLINK,
                minPrice: 0,
                maxPrice: 0
            })
        );

        // Test single outcome
        vm.expectRevert("Must have more than one outcome");
        factory.createMarketMaker(
            IDynamica.Config({
                owner: OWNER,
                collateralToken: address(mockToken),
                oracle: oracle,
                question: "eth/btc",
                outcomeSlotCount: 1,
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
                resolutionModuleType: IMarketResolutionModule.ResolutionModule.CHAINLINK,
                minPrice: 0,
                maxPrice: 0
            })
        );

        // Test zero outcome token amounts
        vm.expectRevert("Outcome token amounts must be positive");
        factory.createMarketMaker(
            IDynamica.Config({
                owner: OWNER,
                collateralToken: address(mockToken),
                oracle: oracle,
                question: "eth/btc",
                outcomeSlotCount: 2,
                startFunding: START_FUNDING,
                outcomeTokenAmounts: 0,
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
                resolutionModuleType: IMarketResolutionModule.ResolutionModule.CHAINLINK,
                minPrice: 0,
                maxPrice: 0
            })
        );

        // Test empty question
        vm.expectRevert("Question cannot be empty");
        factory.createMarketMaker(
            IDynamica.Config({
                owner: OWNER,
                collateralToken: address(mockToken),
                oracle: oracle,
                question: "",
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
                resolutionModuleType: IMarketResolutionModule.ResolutionModule.CHAINLINK,
                minPrice: 0,
                maxPrice: 0
            })
        );

        // Test zero alpha
        vm.expectRevert("Alpha must be positive");
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
                alpha: 0,
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
                resolutionModuleType: IMarketResolutionModule.ResolutionModule.CHAINLINK,
                minPrice: 0,
                maxPrice: 0
            })
        );

        // Test zero exp limit
        vm.expectRevert("Exp limit must be positive");
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
                expLimit: 0,
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
                resolutionModuleType: IMarketResolutionModule.ResolutionModule.CHAINLINK,
                minPrice: 0,
                maxPrice: 0
            })
        );

        // Test decimals too low
        vm.expectRevert("Decimals must be at least 8");
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
                decimals: 7,
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
                resolutionModuleType: IMarketResolutionModule.ResolutionModule.CHAINLINK,
                minPrice: 0,
                maxPrice: 0
            })
        );

        // Test invalid gamma
        vm.expectRevert("Invalid gamma value");
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
                gamma: 0,
                epochDuration: 10 days,
                periodDuration: 1 days
            }),
            IMarketResolutionModule.MarketResolutionConfig({
                marketMaker: address(0),
                outcomeSlotCount: 5,
                resolutionModule: address(0),
                resolutionData: abi.encode(chainlinkConfig),
                isResolved: false,
                resolutionModuleType: IMarketResolutionModule.ResolutionModule.CHAINLINK,
                minPrice: 0,
                maxPrice: 0
            })
        );

        // Test epoch duration <= period duration
        vm.expectRevert("Epoch duration must be greater than period duration");
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
                epochDuration: 1 days,
                periodDuration: 10 days
            }),
            IMarketResolutionModule.MarketResolutionConfig({
                marketMaker: address(0),
                outcomeSlotCount: 5,
                resolutionModule: address(0),
                resolutionData: abi.encode(chainlinkConfig),
                isResolved: false,
                resolutionModuleType: IMarketResolutionModule.ResolutionModule.CHAINLINK,
                minPrice: 0,
                maxPrice: 0
            })
        );

        // Test zero period duration
        vm.expectRevert("Period duration must be greater than 0");
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
                periodDuration: 0
            }),
            IMarketResolutionModule.MarketResolutionConfig({
                marketMaker: address(0),
                outcomeSlotCount: 5,
                resolutionModule: address(0),
                resolutionData: abi.encode(chainlinkConfig),
                isResolved: false,
                resolutionModuleType: IMarketResolutionModule.ResolutionModule.CHAINLINK,
                minPrice: 0,
                maxPrice: 0
            })
        );
        vm.stopPrank();


        vm.startPrank(trader0);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, trader0));
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
                periodDuration: 0
            }),
            IMarketResolutionModule.MarketResolutionConfig({
                marketMaker: address(0),
                outcomeSlotCount: 5,
                resolutionModule: address(0),
                resolutionData: abi.encode(chainlinkConfig),
                isResolved: false,
                resolutionModuleType: IMarketResolutionModule.ResolutionModule.CHAINLINK,
                minPrice: 0,
                maxPrice: 0
            })
        );
        vm.stopPrank();
    }

    // ============ Dynamica Revert Tests ============

    function testDynamicaCalcMarginalPriceReverts() public {
        // Test invalid outcome index
        vm.expectRevert(abi.encodeWithSelector(IDynamica.InvalidOutcomeIndex.selector, 2, 2));
        marketMaker.calcMarginalPrice(2);
    }

    function testDynamicaCalcNetCostReverts() public {
        // Test invalid delta outcome amounts length
        int256[] memory invalidAmounts = new int256[](3);
        vm.expectRevert(abi.encodeWithSelector(IDynamica.InvalidDeltaOutcomeAmountsLength.selector, 3, 2));
        marketMaker.calcNetCost(invalidAmounts);
    }

    // ============ MarketMaker Revert Tests ============

    function testMarketMakerMakePredictionReverts() public {
        int256[] memory amounts = new int256[](2);
        amounts[0] = 100 * int256(10 ** DECIMALS);
        amounts[1] = 50 * int256(10 ** DECIMALS);

        // Test invalid delta outcome amounts length
        int256[] memory invalidAmounts = new int256[](3);
        vm.expectRevert(abi.encodeWithSelector(IDynamica.InvalidDeltaOutcomeAmountsLength.selector, 3, 2));
        vm.prank(trader0);
        marketMaker.makePrediction(invalidAmounts);

        // Test market already resolved
        vm.warp(block.timestamp + 10 days + 1);
        vm.prank(OWNER);
        marketResolutionManager.resolveMarket(keccak256(bytes("eth/btc")));

        vm.warp(block.timestamp + 10 days + 1);
        vm.prank(OWNER);
        marketResolutionManager.resolveMarket(keccak256(bytes("eth/btc")));
        
        // Test market expired
        vm.warp(block.timestamp + 2 days + 1);
        vm.expectRevert(abi.encodeWithSelector(IDynamica.MarketExpired.selector));
        vm.prank(trader0);
        marketMaker.makePrediction(amounts);
    }

    function testMarketMakerRedeemPayoutReverts() public {
        // Test market not resolved
        vm.expectRevert(abi.encodeWithSelector(IDynamica.MarketNotResolved.selector));
        vm.prank(trader0);
        marketMaker.redeemPayout(1);

        // Test nothing to redeem
        vm.warp(block.timestamp + 10 days + 1);
        vm.prank(OWNER);
        marketResolutionManager.resolveMarket(keccak256(bytes("eth/btc")));
        
        vm.expectRevert(abi.encodeWithSelector(IDynamica.NothingToRedeem.selector));
        vm.prank(trader0);
        marketMaker.redeemPayout(1);
    }

    function testChangeExpirationEpochRevert() public {
        vm.startPrank(OWNER);
        vm.warp(block.timestamp + 10 days);
        marketResolutionManager.resolveMarket(keccak256(bytes("eth/btc")));
        // Test revert condition - covers lines 196-198
        vm.expectRevert(abi.encodeWithSelector(IDynamica.NewExpirationEpochMustBeGreaterThanCurrentEpoch.selector, 1, 2));
        marketMaker.changeExpirationEpoch(1);
        vm.stopPrank();
    }


    function testMarketMakerChangeFeeReverts() public {
        // Test fee too high
        vm.expectRevert(abi.encodeWithSelector(IDynamica.FeeMustBeLessThanRange.selector, 10001, 10000));
        vm.prank(OWNER);
        marketMaker.changeFee(10001);
    }

    function testMarketMakerWithdrawFeeReverts() public {
        // Test no fees to withdraw
        vm.expectRevert(abi.encodeWithSelector(IDynamica.NoFeesToWithdraw.selector));
        vm.prank(OWNER);
        marketMaker.withdrawFee();
    }

    function testMarketMakerInsufficientSharesReverts() public {
        // Test insufficient shares to sell through makePrediction
        int256[] memory amounts = new int256[](2);
        amounts[0] = -1000 * int256(10 ** DECIMALS); // Trying to sell more than owned
        amounts[1] = 0;
        
        vm.expectRevert(abi.encodeWithSelector(IDynamica.InsufficientSharesToSell.selector, trader0, 1000 * 10 ** DECIMALS, 0));
        vm.prank(trader0);
        marketMaker.makePrediction(amounts);
    }

    function testMarketMakerUpdateEpochAndPeriodReverts() public {
        // Test epoch finished but not resolved yet
        vm.warp(block.timestamp + 10 days + 1);
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IDynamica.EpochFinishedButNotResolvedYet.selector, 1));
        marketMaker.updateEpochAndPeriod();
    }

    function testMarketMakerCloseEpochReverts() public {
        // Test only oracle manager can call
        vm.expectRevert(abi.encodeWithSelector(IDynamica.OnlyOracleManager.selector, trader0));
        vm.prank(trader0);
        marketMaker.closeEpoch(new uint256[](2));

        // Test must have exactly outcome slot count
        uint256[] memory invalidPayouts = new uint256[](3);
        vm.expectRevert(abi.encodeWithSelector(IDynamica.MustHaveExactlyOutcomeSlotCount.selector, 3, 2));
        vm.prank(address(marketResolutionManager));
        marketMaker.closeEpoch(invalidPayouts);

        // Test payout is all zeroes
        uint256[] memory zeroPayouts = new uint256[](2);
        zeroPayouts[0] = 0;
        zeroPayouts[1] = 0;
        vm.expectRevert(abi.encodeWithSelector(IDynamica.PayoutIsAllZeroes.selector));
        vm.prank(address(marketResolutionManager));
        marketMaker.closeEpoch(zeroPayouts);
    }

    // ============ MarketResolutionManager Revert Tests ============

    function testMarketResolutionManagerResolveMarketReverts() public {
        // Test last epoch isn't finished yet
        vm.warp(block.timestamp + 8 days + 1);
        vm.expectRevert("Last epoch isn't finished yet");
        vm.prank(OWNER);
        marketResolutionManager.resolveMarket(keccak256(bytes("eth/btc")));
    }

   /* function testMarketResolutionManagerRegisterMarketReverts() public {
        // Test market already registered
        //vm.prank(OWNER);
        //vm.expectRevert("Only factory can call this function");
        marketResolutionManager.registerMarket(
            keccak256(bytes("eth/btc")),
            address(marketMaker),
            2,
            address(implementationResolutionModuleChainlink),
            IMarketResolutionModule.ResolutionModule.CHAINLINK,
            abi.encode(_prepareChainlinkConfig()),
            new uint256[](0)
        );

        vm.startPrank(address(factory));
        vm.expectRevert("Invalid market maker address");
        marketResolutionManager.registerMarket(
            keccak256(bytes("different_question")),
            address(0),
            2,
            address(implementationResolutionModuleChainlink),
            IMarketResolutionModule.ResolutionModule.CHAINLINK,
            abi.encode(_prepareChainlinkConfig()),
            new uint256[](0)
        );

        // Test invalid resolution module address
        vm.expectRevert("Invalid resolution module address");
        marketResolutionManager.registerMarket(
            keccak256(bytes("different_question")),
            address(marketMaker),
            2,
            address(0),
            IMarketResolutionModule.ResolutionModule.CHAINLINK,
            abi.encode(_prepareChainlinkConfig()),
            new uint256[](0)
        );

        // Test single outcome slot
        vm.expectRevert("Must have more than one outcome slot");
        marketResolutionManager.registerMarket(
            keccak256(bytes("different_question")),
            address(marketMaker),
            1,
            address(implementationResolutionModuleChainlink),
            IMarketResolutionModule.ResolutionModule.CHAINLINK,
            abi.encode(_prepareChainlinkConfig()),
            new uint256[](0)
        );
        vm.stopPrank();
    }*/

    // ============ ChainlinkResolutionModule Revert Tests ============

    /*function testChainlinkResolutionModuleConstructorReverts() public {
        vm.expectRevert("Invalid market resolution manager address");
        new ChainlinkResolutionModule();
    }

    function testChainlinkResolutionModuleResolveReverts() public {
        // Test only market resolution manager can call
        vm.expectRevert("Only market resolution manager can call this function");
        vm.prank(trader0);
        ChainlinkResolutionModule(implementationResolutionModuleChainlink).resolveMarket(
            2,
            abi.encode(_prepareChainlinkConfig())
        );

        // Test config mismatch: priceFeedAddresses
        ChainlinkConfig memory invalidConfig = _prepareChainlinkConfig();
        address[] memory invalidPriceFeeds = new address[](3);
        invalidConfig.priceFeedAddresses = invalidPriceFeeds;
        
        vm.expectRevert("Config mismatch: priceFeedAddresses");
        vm.prank(address(marketResolutionManager));
        ChainlinkResolutionModule(implementationResolutionModuleChainlink).resolveMarket(
            2,
            abi.encode(invalidConfig)
        );

        // Test config mismatch: decimals
        ChainlinkConfig memory invalidDecimalsConfig = _prepareChainlinkConfig();
        uint8[] memory invalidDecimals = new uint8[](3);
        invalidDecimalsConfig.decimals = invalidDecimals;
        
        vm.expectRevert("Config mismatch: decimals");
        vm.prank(address(marketResolutionManager));
        ChainlinkResolutionModule(implementationResolutionModuleChainlink).resolveMarket(
            2,
            abi.encode(invalidDecimalsConfig)
        );

        // Test config mismatch: staleness
        ChainlinkConfig memory invalidStalenessConfig = _prepareChainlinkConfig();
        uint256[] memory invalidStaleness = new uint256[](3);
        invalidStalenessConfig.staleness = invalidStaleness;
        
        vm.expectRevert("Config mismatch: staleness");
        vm.prank(address(marketResolutionManager));
        ChainlinkResolutionModule(implementationResolutionModuleChainlink).resolveMarket(
            2,
            abi.encode(invalidStalenessConfig)
        );
    }*/

    // ============ FTSOResolutionModule Revert Tests ============

   /* function testFTSOResolutionModuleConstructorReverts() public {
        vm.expectRevert("Invalid FTSO address");
        new FTSOResolutionModule();
    }

    function testFTSOResolutionModuleResolveReverts() public {
        // Test only market resolution manager can call
        vm.expectRevert("Only market resolution manager can call this function");
        vm.prank(trader0);
        FTSOResolutionModule(implementationResolutionModuleFTSO).resolveMarket(
            2,
            abi.encode(bytes32(0), new uint256[](2))
        );
    }

    */

    // ============ Private Setup Functions ============

    function _setupMockToken() private {
        this.createToken("Token1", "T1");
        IERC20(mockToken).mint(OWNER, 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
    }

    function _deployImplementations() private {
        implementation = new Dynamica();
        implementationResolutionModuleChainlink = address(new ChainlinkResolutionModule());
        implementationResolutionModuleFtso = address(new FTSOResolutionModule());
    }

    function _setupFactory() private {
        factory = new DynamicaFactory(
            address(implementation),
            implementationResolutionModuleChainlink,
            implementationResolutionModuleFtso,
            address(ftsoV2),
            OWNER
        );
        factory.setAllowedToken(address(mockToken), true);
    }

    function _setupMarketResolutionManager() private {
        marketResolutionManager = new MarketResolutionManager(OWNER, address(factory));
        factory.setOracleCoordinator(address(marketResolutionManager));
        IERC20(mockToken).approve(address(factory), 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
    }

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
                resolutionModuleType: IMarketResolutionModule.ResolutionModule.CHAINLINK,
                minPrice: 0,
                maxPrice: 0
            })
        );
        marketMaker = Dynamica(payable(factory.marketMakers(0)));
        vm.deal(address(marketMaker), 1000 ether);
    }

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

    function _mintTokensToTraders() private {
        IERC20(mockToken).mint(trader0, 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
        IERC20(mockToken).mint(trader1, 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
        IERC20(mockToken).mint(trader2, 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
        IERC20(mockToken).mint(trader3, 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
    }
} 