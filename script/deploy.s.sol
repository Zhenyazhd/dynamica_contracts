// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {console} from "forge-std/src/console.sol";
import {Script} from "forge-std/src/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {MockToken} from "../test/MockToken.sol";
import {Dynamica} from "../src/Dynamica.sol";
import {DynamicaFactory} from "../src/DynamicaFactory.sol";
import {MarketResolutionManager} from "../src/Oracles/MarketResolutionManager.sol";
import {ChainlinkResolutionModule} from "../src/Oracles/Hedera/ChainlinkResolutionModule.sol";
import {MockAggregator} from "../test/MockOracles/MockAggregator.sol";
import {IMarketResolutionModule} from "../src/interfaces/Oracles/IMarketResolutionModule.sol";
import {IDynamica} from "../src/interfaces/IDynamica.sol";
import {LMSRMath} from "../src/LMSRMath.sol";

/**
 * @title Deploy Script
 * @dev Deployment script for Dynamica prediction market system
 * @notice Based on LMSRMarketMaker.t.sol test structure
 * 
 * Usage:
 * PRIVATE_KEY=0x... forge script script/deploy.s.sol:Deploy --rpc-url <RPC_URL> --broadcast
 * 
 * forge script script/deploy.s.sol:Deploy \
 *    --rpc-url https://testnet.hashio.io/api \
 *    --broadcast \
 *    --verify \
 *    --verifier sourcify \
 *    --verifier-url https://server-verify.hashscan.io \
 *    -vvvv
 */
contract Deploy is Script {
    // ============ Constants ============
    int256 public constant ETH_USD_PRICE = 3000 * 1e8; // $3000
    int256 public constant BTC_USD_PRICE = 45000 * 1e8; // $45000
    address public constant OWNER = 0x9611BFE86DE11989cf9E250DC3c16c8b8e97De87;
    uint8 constant DECIMALS = 10;
    uint8 constant DECIMALS_COLLATERAL = 18;
    uint256 constant INITIAL_SUPPLY = 500 * (10 ** DECIMALS);
    uint256 constant START_FUNDING = 1000 * 10 ** DECIMALS_COLLATERAL;

    // ============ State Variables ============
    Dynamica public implementation = Dynamica(0xA062102c0E8a6bd89c757010CBd88fca064a602E);
    LMSRMath public lmsrMath = LMSRMath(0x44a2AfbBBbE83CBf7357D94a7C8F1aced4A6a6CE);
    MockAggregator public ethUsdAggregator = MockAggregator(0xC12386C5E75DD63c1F6555Aaf0Eeb511276a0140);
    MockAggregator public btcUsdAggregator = MockAggregator(0x49F8ECd7Ac3fA36B279DB0B86519Ff86de709f6A);
    MockToken public mockToken = MockToken(0x058cBe9f46E687Dbeb949E96704f31FdCa4b63f4);
    ChainlinkResolutionModule public implementationResolutionModuleChainlink = ChainlinkResolutionModule(0x76746B81d32EF112AD3d66b99B6B5A8d1439B5ED);
    DynamicaFactory public factory = DynamicaFactory(0xcBBC65FECb9f86568AfC53D4EB41D80B518CB97d);
    MarketResolutionManager public marketResolutionManager = MarketResolutionManager(0x34388c1edE399d64Cbc1B2969e994140ca69f3e0);
    Dynamica public marketMaker = Dynamica(0xb287A35Ec9Fb1B90d900A30e723672f646BAb81F);


    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        _deployMockToken();
        _deployMockAggregators();
        _deployImplementations();
        _deployFactory();
        _setupMarketResolutionManager();
        _createMarketMaker();

        _printDeploymentSummary();

        vm.stopBroadcast();
    }

    // ============ Private Deployment Functions ============

    /**
     * @notice Deploys mock token for testing
     */
    function _deployMockToken() private {
        mockToken = new MockToken(DECIMALS_COLLATERAL);
        console.log("Deployed mockToken at:", address(mockToken));
        
        // Mint tokens to owner
        mockToken.mint(OWNER, 1_000_000 * 10 ** DECIMALS_COLLATERAL);
        console.log("Minted tokens to owner:", OWNER);
    }

    /**
     * @notice Deploys mock Chainlink aggregators
     */
    function _deployMockAggregators() private {
        ethUsdAggregator = new MockAggregator(int256(ETH_USD_PRICE), 8, "ETH / USD", 1);
        console.log("Deployed ethUsdAggregator at:", address(ethUsdAggregator));

        btcUsdAggregator = new MockAggregator(int256(BTC_USD_PRICE), 8, "BTC / USD", 1);
        console.log("Deployed btcUsdAggregator at:", address(btcUsdAggregator));
    }

    /**
     * @notice Deploys implementation contracts
     */
    function _deployImplementations() private {
        implementation = new Dynamica();
        console.log("Deployed Dynamica implementation at:", address(implementation));

        implementationResolutionModuleChainlink = new ChainlinkResolutionModule();
        console.log("Deployed ChainlinkResolutionModule at:", address(implementationResolutionModuleChainlink));

        lmsrMath = new LMSRMath();
        console.log("Deployed LMSRMath at:", address(lmsrMath));
    }

    /**
     * @notice Deploys and configures the factory contract
     */
    function _deployFactory() private {
        factory = new DynamicaFactory(
            address(implementation),
            address(implementationResolutionModuleChainlink),
            OWNER,
            address(lmsrMath)
        );
        console.log("Deployed DynamicaFactory at:", address(factory));

        // Add mock token as allowed collateral
        factory.addAllowedCollateralToken(address(mockToken));
        console.log("Added mockToken as allowed collateral");
    }

    /**
     * @notice Sets up the market resolution manager
     */
    function _setupMarketResolutionManager() private {
        marketResolutionManager = new MarketResolutionManager(OWNER, address(factory));
        console.log("Deployed MarketResolutionManager at:", address(marketResolutionManager));

        factory.setOracleCoordinator(address(marketResolutionManager));
        console.log("Set oracle coordinator in factory");

        // Approve factory to spend tokens from owner
        mockToken.approve(address(factory), 1_000_000 * 10 ** DECIMALS_COLLATERAL);
        console.log("Approved factory to spend tokens from owner");
    }

    /**
     * @notice Prepares Chainlink configuration for the market
     */
    function _prepareChainlinkConfig() private view returns (ChainlinkResolutionModule.ChainlinkConfig memory config) {
        address[] memory priceFeedAddresses = new address[](2);
        uint256[] memory staleness = new uint256[](2);
        uint8[] memory decimals = new uint8[](2);

        priceFeedAddresses[0] = address(ethUsdAggregator);
        priceFeedAddresses[1] = address(btcUsdAggregator);

        staleness[0] = 3600; // 1 hour
        staleness[1] = 3600; // 1 hour

        decimals[0] = ethUsdAggregator.decimals();
        decimals[1] = btcUsdAggregator.decimals();

        config = ChainlinkResolutionModule.ChainlinkConfig({
            priceFeedAddresses: priceFeedAddresses,
            staleness: staleness,
            decimals: decimals
        });
    }

    /**
     * @notice Creates a test market maker
     */
    function _createMarketMaker() private {
        ChainlinkResolutionModule.ChainlinkConfig memory chainlinkConfig = _prepareChainlinkConfig();

        factory.createMarketMaker(
            IDynamica.Config({
                owner: OWNER,
                collateralToken: address(mockToken),
                oracle: OWNER,
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
        console.log("Created marketMaker at:", address(marketMaker));
    }

    /**
     * @notice Prints deployment summary
     */
    function _printDeploymentSummary() private view {
        console.log("\n============ Deployment Summary ============");
        console.log("MockToken:", address(mockToken));
        console.log("ETH/USD Aggregator:", address(ethUsdAggregator));
        console.log("BTC/USD Aggregator:", address(btcUsdAggregator));
        console.log("Dynamica Implementation:", address(implementation));
        console.log("ChainlinkResolutionModule:", address(implementationResolutionModuleChainlink));
        console.log("LMSRMath:", address(lmsrMath));
        console.log("DynamicaFactory:", address(factory));
        console.log("MarketResolutionManager:", address(marketResolutionManager));
        console.log("MarketMaker:", address(marketMaker));
        console.log("===========================================\n");
    }
} 
