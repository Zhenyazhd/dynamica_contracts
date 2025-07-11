// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {MockAggregator} from "./MockAggregator.sol";
import {MockFtsoV2} from "./MockFtsoV2.sol";

import {Test} from "forge-std/src/Test.sol";

/**
 * @title OracleSetUP
 * @dev Test setup for mock Chainlink and FTSO oracles for ETH and BTC
 */
contract OracleSetUP is Test {

    address OWNER = address(0xABCD);

    // Mock Chainlink Aggregators
    MockAggregator public ethUsdAggregator;
    MockAggregator public btcUsdAggregator;
    
    // Mock FTSO V2
    MockFtsoV2 public ftsoV2;
    
    // Feed IDs for FTSO (example values - adjust as needed)
    bytes21 public constant ETH_USD_FEED_ID = bytes21("ETH/USD");
    bytes21 public constant BTC_USD_FEED_ID = bytes21("BTC/USD");
    
    // Initial prices (in USD with 8 decimals for Chainlink, 5 decimals for FTSO)
    uint256 public constant ETH_USD_PRICE = 3000 * 1e8; // $3000
    uint256 public constant BTC_USD_PRICE = 45000 * 1e8; // $45000
    
    // FTSO prices (with 5 decimals)
    uint256 public constant ETH_USD_FTSO_PRICE = 3000 * 1e5; // $3000
    uint256 public constant BTC_USD_FTSO_PRICE = 45000 * 1e5; // $45000
    
    // Decimals
    uint8 public constant CHAINLINK_DECIMALS = 8;
    int8 public constant FTSO_DECIMALS = 5;
    
    // FTSO Protocol ID
    uint256 public constant FTSO_PROTOCOL_ID = 1;

    function setUp() public virtual {
        // Deploy mock Chainlink aggregators
        ethUsdAggregator = new MockAggregator(
            int256(ETH_USD_PRICE),
            CHAINLINK_DECIMALS,
            "ETH / USD",
            1
        );
        
        btcUsdAggregator = new MockAggregator(
            int256(BTC_USD_PRICE),
            CHAINLINK_DECIMALS,
            "BTC / USD",
            1
        );
        
        // Deploy mock FTSO V2
        ftsoV2 = new MockFtsoV2(FTSO_PROTOCOL_ID);
        
        // Setup FTSO feed data
        ftsoV2.setFeedData(
            ETH_USD_FEED_ID,
            ETH_USD_FTSO_PRICE,
            FTSO_DECIMALS,
            uint64(block.timestamp)
        );
        
        ftsoV2.setFeedData(
            BTC_USD_FEED_ID,
            BTC_USD_FTSO_PRICE,
            FTSO_DECIMALS,
            uint64(block.timestamp)
        );
    }

    /**
     * @dev Update Chainlink prices
     */
    function updateChainlinkPrices(uint256 ethPrice, uint256 btcPrice) external {
        ethUsdAggregator.setPrice(int256(ethPrice));
        btcUsdAggregator.setPrice(int256(btcPrice));
    }

    /**
     * @dev Update FTSO prices
     */
    function updateFTSOPrices(uint256 ethPrice, uint256 btcPrice) external {
        ftsoV2.setFeedData(
            ETH_USD_FEED_ID,
            ethPrice,
            FTSO_DECIMALS,
            uint64(block.timestamp)
        );
        
        ftsoV2.setFeedData(
            BTC_USD_FEED_ID,
            btcPrice,
            FTSO_DECIMALS,
            uint64(block.timestamp)
        );
    }

    /**
     * @dev Get current Chainlink prices
     */
    function getChainlinkPrices() external view returns (uint256 ethPrice, uint256 btcPrice) {
        (, int256 ethPriceInt,,,) = ethUsdAggregator.latestRoundData();
        (, int256 btcPriceInt,,,) = btcUsdAggregator.latestRoundData();
        
        ethPrice = uint256(ethPriceInt);
        btcPrice = uint256(btcPriceInt);
    }

    /**
     * @dev Get current FTSO prices
     */
    function getFTSOPrices() external returns (uint256 ethPrice, uint256 btcPrice) {
        (ethPrice,,) = ftsoV2.getFeedById(ETH_USD_FEED_ID);
        (btcPrice,,) = ftsoV2.getFeedById(BTC_USD_FEED_ID);
    }

    function testOracleSetup() external {
        // Test Chainlink prices
        (uint256 ethPrice, uint256 btcPrice) = this.getChainlinkPrices();
        assertEq(ethPrice, ETH_USD_PRICE, "ETH Chainlink price mismatch");
        assertEq(btcPrice, BTC_USD_PRICE, "BTC Chainlink price mismatch");
        
        // Test FTSO prices
        (uint256 ethFTSOPrice, uint256 btcFTSOPrice) = this.getFTSOPrices();
        assertEq(ethFTSOPrice, ETH_USD_FTSO_PRICE, "ETH FTSO price mismatch");
        assertEq(btcFTSOPrice, BTC_USD_FTSO_PRICE, "BTC FTSO price mismatch");
        
        // Test FTSO protocol ID
        assertEq(ftsoV2.getFtsoProtocolId(), FTSO_PROTOCOL_ID, "FTSO protocol ID mismatch");
        
        // Test supported feed IDs
        bytes21[] memory supportedFeeds = ftsoV2.getSupportedFeedIds();
        assertEq(supportedFeeds.length, 2, "Should have 2 supported feeds");
        assertEq(supportedFeeds[0], ETH_USD_FEED_ID, "First feed should be ETH/USD");
        assertEq(supportedFeeds[1], BTC_USD_FEED_ID, "Second feed should be BTC/USD");
    }


    function testPriceUpdates() external {
        uint256 newEthPrice = 3500 * 1e8; // $3500
        uint256 newBtcPrice = 50000 * 1e8; // $50000
        
        // Update Chainlink prices
        this.updateChainlinkPrices(newEthPrice, newBtcPrice);
        
        // Update FTSO prices
        this.updateFTSOPrices(newEthPrice / 1e3, newBtcPrice / 1e3); // Convert to FTSO decimals
        
        // Verify updates
        (uint256 ethPrice, uint256 btcPrice) = this.getChainlinkPrices();
        assertEq(ethPrice, newEthPrice, "ETH Chainlink price update failed");
        assertEq(btcPrice, newBtcPrice, "BTC Chainlink price update failed");
        
        (uint256 ethFTSOPrice, uint256 btcFTSOPrice) = this.getFTSOPrices();
        assertEq(ethFTSOPrice, newEthPrice / 1e3, "ETH FTSO price update failed");
        assertEq(btcFTSOPrice, newBtcPrice / 1e3, "BTC FTSO price update failed");
    }
} 