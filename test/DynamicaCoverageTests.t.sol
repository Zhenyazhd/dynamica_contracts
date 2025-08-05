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
import {console} from "forge-std/src/console.sol";

/**
 * @title DynamicaCoverageTests
 * @dev Tests for specific code coverage areas in Dynamica.sol and MarketMaker.sol
 */
contract DynamicaCoverageTests is OracleSetUP {
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
    address public implementationResolutionModuleFtsO;

    // ============ Test Addresses ============

    /// @notice Oracle address for testing
    address oracle = address(0x1234);

    address public constant OWNER = address(0xABCD);

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

    // ============ calcMarginalPrice Coverage Tests ============

    function testCalcMarginalPriceFullCoverage() public {
        // Test initial state - this will cover lines 122-162
        int256 price0 = marketMaker.calcMarginalPrice(0);
        int256 price1 = marketMaker.calcMarginalPrice(1);
        
        console.log("Initial price 0:", price0);
        console.log("Initial price 1:", price1);
        
        // Make some trades to change market state
        int256[] memory amounts = new int256[](2);
        amounts[0] = 100 * int256(10 ** DECIMALS);
        amounts[1] = 0;
        
        vm.startPrank(trader0);
        IERC20(mockToken).approve(address(marketMaker), 1_000 * 10 ** uint256(DECIMALS_COLLATERAL));
        marketMaker.makePrediction(amounts);
        vm.stopPrank();
        
        // Test calcMarginalPrice after trade - covers the full function
        int256 price0After = marketMaker.calcMarginalPrice(0);
        int256 price1After = marketMaker.calcMarginalPrice(1);
        
        console.log("Price 0 after trade:", price0After);
        console.log("Price 1 after trade:", price1After);
        
        // Test with more trades to ensure full coverage
        amounts[0] = 0;
        amounts[1] = 50 * int256(10 ** DECIMALS);
        
        vm.startPrank(trader1);
        IERC20(mockToken).approve(address(marketMaker), 1_000 * 10 ** uint256(DECIMALS_COLLATERAL));
        marketMaker.makePrediction(amounts);
        vm.stopPrank();
        
        int256 price0Final = marketMaker.calcMarginalPrice(0);
        int256 price1Final = marketMaker.calcMarginalPrice(1);
        
        console.log("Final price 0:", price0Final);
        console.log("Final price 1:", price1Final);
        
        // Verify prices sum to approximately 1e18
        assertApproxEqRel(price0Final + price1Final, 1e18, 0.01e18);
    }

    function testCalcMarginalPriceWithZeroLiquidity() public {
        // This test would cover the ZeroLiquidityParameter revert
        // However, this is hard to trigger in normal conditions
        // We'll test the mathematical edge cases instead
        
        // Make a very large trade to test numerical stability
        int256[] memory largeAmounts = new int256[](2);
        largeAmounts[0] = 10000 * int256(10 ** DECIMALS);
        largeAmounts[1] = 0;
        
        vm.startPrank(trader0);
        IERC20(mockToken).approve(address(marketMaker), 100_000 * 10 ** uint256(DECIMALS_COLLATERAL));
        marketMaker.makePrediction(largeAmounts);
        vm.stopPrank();
        
        // This should still work and test the offset computation
        int256 price0 = marketMaker.calcMarginalPrice(0);
        int256 price1 = marketMaker.calcMarginalPrice(1);
        
        console.log("Price 0 after large trade:", price0);
        console.log("Price 1 after large trade:", price1);
    }

    // ============ _computeOffset Coverage Tests ============

    function testComputeOffsetIndirectly() public {
        // _computeOffset is private, so we test it indirectly through calcMarginalPrice
        
        // Test with different quantities to trigger different offset calculations
        int256[] memory amounts1 = new int256[](2);
        amounts1[0] = 100 * int256(10 ** DECIMALS);
        amounts1[1] = 200 * int256(10 ** DECIMALS);
        
        vm.startPrank(trader0);
        IERC20(mockToken).approve(address(marketMaker), 1_000 * 10 ** uint256(DECIMALS_COLLATERAL));
        marketMaker.makePrediction(amounts1);
        vm.stopPrank();
        
        int256 price0 = marketMaker.calcMarginalPrice(0);
        int256 price1 = marketMaker.calcMarginalPrice(1);
        
        // Test with equal quantities
        int256[] memory amounts2 = new int256[](2);
        amounts2[0] = 150 * int256(10 ** DECIMALS);
        amounts2[1] = 150 * int256(10 ** DECIMALS);
        
        vm.startPrank(trader1);
        IERC20(mockToken).approve(address(marketMaker), 1_000 * 10 ** uint256(DECIMALS_COLLATERAL));
        marketMaker.makePrediction(amounts2);
        vm.stopPrank();
        
        int256 price0After = marketMaker.calcMarginalPrice(0);
        int256 price1After = marketMaker.calcMarginalPrice(1);
        
        console.log("Price 0 after offset test:", price0After);
        console.log("Price 1 after offset test:", price1After);
    }

    // ============ changeExpirationEpoch Coverage Tests ============

    function testChangeExpirationEpoch() public {
        // Test successful change - covers lines 195-201
        vm.startPrank(OWNER);
        marketMaker.changeExpirationEpoch(5);
        vm.stopPrank();
        
        // Verify the change
        assertEq(marketMaker.expirationEpoch(), 5);
    }


    function testChangeExpirationEpochToZero() public {
        // Test setting to zero
        vm.startPrank(OWNER);
        marketMaker.changeExpirationEpoch(0);
        vm.stopPrank();
        
        assertEq(marketMaker.expirationEpoch(), 0);
    }

    // ============ payoutNumerators Coverage Tests ============

    function testPayoutNumerators() public {
        // Test payoutNumerators function - covers lines 247-249
        uint256 payout0 = marketMaker.payoutNumerators(1, 0);
        uint256 payout1 = marketMaker.payoutNumerators(1, 1);
        
        console.log("Payout numerator 0:", payout0);
        console.log("Payout numerator 1:", payout1);
        
        // Initially should be zero
        assertEq(payout0, 0);
        assertEq(payout1, 0);
    }

    // ============ payoutDenominator Coverage Tests ============

    function testPayoutDenominator() public {
        // Test payoutDenominator function - covers lines 255-257
        uint256 denominator = marketMaker.payoutDenominator(1);
        
        console.log("Payout denominator:", denominator);
        
        // Initially should be zero
        assertEq(denominator, 0);
    }

    // ============ outcomeTokenSupplies Coverage Tests ============

    function testOutcomeTokenSupplies() public {
        // Test outcomeTokenSupplies function - covers lines 264-266
        uint256 supply0 = marketMaker.outcomeTokenSupplies(1, 0);
        uint256 supply1 = marketMaker.outcomeTokenSupplies(1, 1);
        
        console.log("Outcome token supply 0:", supply0);
        console.log("Outcome token supply 1:", supply1);
        
        // Should be initial supply
        assertEq(supply0, INITIAL_SUPPLY);
        assertEq(supply1, INITIAL_SUPPLY);
        
        // Make a trade and check supplies change
        int256[] memory amounts = new int256[](2);
        amounts[0] = 100 * int256(10 ** DECIMALS);
        amounts[1] = 0;
        
        vm.startPrank(trader0);
        IERC20(mockToken).approve(address(marketMaker), 1_000 * 10 ** uint256(DECIMALS_COLLATERAL));
        marketMaker.makePrediction(amounts);
        vm.stopPrank();
        
        uint256 supply0After = marketMaker.outcomeTokenSupplies(1, 0);
        uint256 supply1After = marketMaker.outcomeTokenSupplies(1, 1);
        
        console.log("Outcome token supply 0 after trade:", supply0After);
        console.log("Outcome token supply 1 after trade:", supply1After);
        
        assertEq(supply0After, INITIAL_SUPPLY + uint256(amounts[0]));
        assertEq(supply1After, INITIAL_SUPPLY);
    }

    // ============ calcNetCost Coverage Tests ============

    function testCalcNetCost() public {
        // Test calcNetCost function - covers lines 322-325
        int256[] memory amounts = new int256[](2);
        amounts[0] = 100 * int256(10 ** DECIMALS);
        amounts[1] = 0;
        
        int256 netCost = marketMaker.calcNetCost(amounts);
        
        console.log("Net cost:", netCost);
        
        // Should be positive for buying
        assertGt(netCost, 0);
        
        // Test selling
        amounts[0] = -50 * int256(10 ** DECIMALS);
        amounts[1] = 0;
        
        int256 netCostSell = marketMaker.calcNetCost(amounts);
        
        console.log("Net cost for selling:", netCostSell);
        
        // Should be negative for selling
        assertLt(netCostSell, 0);
    }

    // ============ changeFee Coverage Tests ============

    function testChangeFee() public {
        // Test successful fee change - covers lines 332-338
        vm.startPrank(OWNER);
        marketMaker.changeFee(100); // 1%
        vm.stopPrank();
        
        assertEq(marketMaker.fee(), 100);
    }

    function testChangeFeeToZero() public {
        // Test setting fee to zero
        vm.startPrank(OWNER);
        marketMaker.changeFee(0);
        vm.stopPrank();
        
        assertEq(marketMaker.fee(), 0);
    }

    // ============ withdrawFee Coverage Tests ============

    function testWithdrawFeeRevert() public {
        // Test no fees to withdraw - covers lines 345-347
        vm.startPrank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IDynamica.NoFeesToWithdraw.selector));
        marketMaker.withdrawFee();
        vm.stopPrank();
    }

    function testWithdrawFeeSuccess() public {
        // First, make some trades to generate fees
        vm.startPrank(OWNER);
        marketMaker.changeFee(100); // 1% fee
        vm.stopPrank();
        
        int256[] memory amounts = new int256[](2);
        amounts[0] = 100 * int256(10 ** DECIMALS);
        amounts[1] = 0;
        
        vm.startPrank(trader0);
        IERC20(mockToken).approve(address(marketMaker), 1_000 * 10 ** uint256(DECIMALS_COLLATERAL));
        marketMaker.makePrediction(amounts);
        vm.stopPrank();
        
        // Now withdraw fees - covers lines 344-354
        uint256 initialBalance = IERC20(mockToken).balanceOf(OWNER);
        
        vm.startPrank(OWNER);
        marketMaker.withdrawFee();
        vm.stopPrank();
        
        uint256 finalBalance = IERC20(mockToken).balanceOf(OWNER);
        
        // Balance should have increased
        assertGt(finalBalance, initialBalance);
        
        // Fee received should be zero after withdrawal
        assertEq(marketMaker.feeReceived(), 0);
    }

    // ============ emergencyExit Coverage Tests ============

    function testEmergencyExit() public {
        // Test emergencyExit function - covers lines 357-363
        uint256 initialBalance = IERC20(mockToken).balanceOf(OWNER);
        uint256 marketBalance = IERC20(mockToken).balanceOf(address(marketMaker));
        
        vm.startPrank(OWNER);
        marketMaker.emergencyExit(address(mockToken));
        vm.stopPrank();
        
        uint256 finalBalance = IERC20(mockToken).balanceOf(OWNER);
        
        // Owner should have received the market's balance
        assertEq(finalBalance, initialBalance + marketBalance);
        
        // Market should have zero balance
        assertEq(IERC20(mockToken).balanceOf(address(marketMaker)), 0);
    }

    function testEmergencyExitWithDifferentToken() public {
        // Test emergencyExit with a different token
        // Create another mock token
        MockToken otherToken = new MockToken(DECIMALS_COLLATERAL);
        otherToken.mint(address(marketMaker), 1000 * 10 ** uint256(DECIMALS_COLLATERAL));
        
        uint256 initialBalance = otherToken.balanceOf(OWNER);
        uint256 marketBalance = otherToken.balanceOf(address(marketMaker));
        
        vm.startPrank(OWNER);
        marketMaker.emergencyExit(address(otherToken));
        vm.stopPrank();
        
        uint256 finalBalance = otherToken.balanceOf(OWNER);
        
        // Owner should have received the market's balance
        assertEq(finalBalance, initialBalance + marketBalance);
        
        // Market should have zero balance
        assertEq(otherToken.balanceOf(address(marketMaker)), 0);
    }

    // ============ Factory Query Functions Coverage Tests ============

    function testGetAllMarketMakers() public {
        // Test getAllMarketMakers function - covers lines 194-196
        address[] memory allMarketMakers = factory.getAllMarketMakers();
        
        console.log("Number of market makers:", allMarketMakers.length);
        
        // Should have at least one market maker (created in setUp)
        assertGt(allMarketMakers.length, 0);
        
        // First market maker should be our test market
        assertEq(allMarketMakers[0], address(marketMaker));
    }

    function testGetMarketMakerCount() public {
        // Test getMarketMakerCount function - covers lines 202-204
        uint256 count = factory.getMarketMakerCount();
        
        console.log("Market maker count:", count);
        
        // Should have at least one market maker
        assertGt(count, 0);
        
        // Should match the length of getAllMarketMakers
        address[] memory allMarketMakers = factory.getAllMarketMakers();
        assertEq(count, allMarketMakers.length);
    }

    function testGetMarketMakersByCreator() public {
        // Test getMarketMakersByCreator function - covers lines 211-213
        address[] memory creatorMarketMakers = factory.getMarketMakersByCreator(OWNER);
        
        console.log("Market makers by owner:", creatorMarketMakers.length);
        
        // Should have at least one market maker created by owner
        assertGt(creatorMarketMakers.length, 0);
        
        // Should include our test market maker
        assertEq(creatorMarketMakers[0], address(marketMaker));
        
        // Test with non-creator address
        address[] memory nonCreatorMarketMakers = factory.getMarketMakersByCreator(trader0);
        assertEq(nonCreatorMarketMakers.length, 0);
    }

    function testGetMarketMakerCreator() public {
        // Test getMarketMakerCreator function - covers lines 220-222
        address creator = factory.getMarketMakerCreator(address(marketMaker));
        
        console.log("Market maker creator:", creator);
        
        // Should be the owner
        assertEq(creator, OWNER);
        
        // Test with non-existent market maker
        address nonExistentCreator = factory.getMarketMakerCreator(address(0x9999));
        assertEq(nonExistentCreator, address(0));
    }

    function testIsMarketMaker() public {
        // Test isMarketMaker function - covers lines 229-230
        bool isValidMarketMaker = factory.isMarketMaker(address(marketMaker));
        
        console.log("Is valid market maker:", isValidMarketMaker);
        
        // Should be true for our test market maker
        assertTrue(isValidMarketMaker);
        
        // Test with non-existent market maker
        bool isNonExistentMarketMaker = factory.isMarketMaker(address(0x9999));
        assertFalse(isNonExistentMarketMaker);
        
        // Test with zero address
        bool isZeroAddressMarketMaker = factory.isMarketMaker(address(0));
        assertFalse(isZeroAddressMarketMaker);
    }

    function testMultipleMarketMakers() public {
        // Create additional market makers to test multiple scenarios
        ChainlinkResolutionModule.ChainlinkConfig memory chainlinkConfig = _prepareChainlinkConfig();
        
        // Create second market maker
        vm.startPrank(OWNER);
        factory.createMarketMaker(
            IDynamica.Config({
                owner: OWNER,
                collateralToken: address(mockToken),
                oracle: oracle,
                question: "btc/eth",
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
        vm.stopPrank();
        
        // Test getAllMarketMakers with multiple markets
        address[] memory allMarketMakers = factory.getAllMarketMakers();
        assertEq(allMarketMakers.length, 2);
        
        // Test getMarketMakerCount
        uint256 count = factory.getMarketMakerCount();
        assertEq(count, 2);
        
        // Test getMarketMakersByCreator
        address[] memory creatorMarketMakers = factory.getMarketMakersByCreator(OWNER);
        assertEq(creatorMarketMakers.length, 2);
        
        // Test getMarketMakerCreator for second market
        address secondMarketMaker = allMarketMakers[1];
        address creator = factory.getMarketMakerCreator(secondMarketMaker);
        assertEq(creator, OWNER);
        
        // Test isMarketMaker for second market
        bool isValidMarketMaker = factory.isMarketMaker(secondMarketMaker);
        assertTrue(isValidMarketMaker);
        
        console.log("Multiple market makers test completed");
    }

    // ============ Integration Tests ============

    function testFullMarketCycle() public {
        // Test a complete market cycle to ensure all functions work together
        
        // 1. Make trades
        int256[] memory amounts = new int256[](2);
        amounts[0] = 100 * int256(10 ** DECIMALS);
        amounts[1] = 0;
        
        vm.startPrank(trader0);
        IERC20(mockToken).approve(address(marketMaker), 1_000 * 10 ** uint256(DECIMALS_COLLATERAL));
        marketMaker.makePrediction(amounts);
        vm.stopPrank();
        
        // 2. Check prices
        int256 price0 = marketMaker.calcMarginalPrice(0);
        int256 price1 = marketMaker.calcMarginalPrice(1);
        
        // 3. Check supplies
        uint256 supply0 = marketMaker.outcomeTokenSupplies(1, 0);
        uint256 supply1 = marketMaker.outcomeTokenSupplies(1, 1);
        
        // 4. Change fee
        vm.startPrank(OWNER);
        marketMaker.changeFee(50);
        vm.stopPrank();
        
        // 5. Make another trade with fee
        amounts[0] = 0;
        amounts[1] = 50 * int256(10 ** DECIMALS);
        
        vm.startPrank(trader1);
        IERC20(mockToken).approve(address(marketMaker), 1_000 * 10 ** uint256(DECIMALS_COLLATERAL));
        marketMaker.makePrediction(amounts);
        vm.stopPrank();
        
        // 6. Withdraw fees
        vm.startPrank(OWNER);
        marketMaker.withdrawFee();
        vm.stopPrank();
        
        // 7. Change expiration epoch
        vm.startPrank(OWNER);
        marketMaker.changeExpirationEpoch(3);
        vm.stopPrank();
        
        // Verify all changes
        assertEq(marketMaker.fee(), 50);
        assertEq(marketMaker.expirationEpoch(), 3);
        assertEq(marketMaker.feeReceived(), 0);
        
        console.log("Full market cycle completed successfully");
    }

    // ============ Private Setup Functions ============

    function _setupMockToken() private {
        this.createToken("Token1", "T1");
        IERC20(mockToken).mint(OWNER, 1_000_000 * 10 ** uint256(DECIMALS_COLLATERAL));
    }

    function _deployImplementations() private {
        implementation = new Dynamica();
        implementationResolutionModuleChainlink = address(new ChainlinkResolutionModule());
        implementationResolutionModuleFtsO = address(new FTSOResolutionModule());
    }

    function _setupFactory() private {
        factory = new DynamicaFactory(
            address(implementation),
            implementationResolutionModuleChainlink,
            implementationResolutionModuleFtsO,
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