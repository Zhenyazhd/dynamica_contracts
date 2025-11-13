// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {MockAggregator} from "./MockAggregator.sol";

import {Test} from "forge-std/src/Test.sol";

/**
 * @title OracleSetUP
 * @dev Test setup for mock Chainlink oracles for ETH and BTC
 */
contract OracleSetUP is Test {
    address owner = address(0xABCD);

    // Mock Chainlink Aggregators
    MockAggregator public ethUsdAggregator;
    MockAggregator public btcUsdAggregator;


    // Feed IDs  (example values - adjust as needed)
    bytes21 public constant ETH_USD_FEED_ID = bytes21("ETH/USD");
    bytes21 public constant BTC_USD_FEED_ID = bytes21("BTC/USD");

    // Initial prices (in USD with 8 decimals for Chainlink)
    uint256 public constant ETH_USD_PRICE = 3000 * 1e8; // $3000
    uint256 public constant BTC_USD_PRICE = 45000 * 1e8; // $45000

    // Decimals
    uint8 public constant CHAINLINK_DECIMALS = 8;

    function setUp() public virtual {
        // Deploy mock Chainlink aggregators
        ethUsdAggregator = new MockAggregator(int256(ETH_USD_PRICE), CHAINLINK_DECIMALS, "ETH / USD", 1);

        btcUsdAggregator = new MockAggregator(int256(BTC_USD_PRICE), CHAINLINK_DECIMALS, "BTC / USD", 1);

    }

    /**
     * @dev Update Chainlink prices
     */
    function updateChainlinkPrices(uint256 ethPrice, uint256 btcPrice) external {
        ethUsdAggregator.setPrice(int256(ethPrice));
        btcUsdAggregator.setPrice(int256(btcPrice));
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

    
    function testOracleSetup() external {
        // Test Chainlink prices
        (uint256 ethPrice, uint256 btcPrice) = this.getChainlinkPrices();
        assertEq(ethPrice, ETH_USD_PRICE, "ETH Chainlink price mismatch");
        assertEq(btcPrice, BTC_USD_PRICE, "BTC Chainlink price mismatch");
    }

    function testPriceUpdates() external {
        uint256 newEthPrice = 3500 * 1e8; // $3500
        uint256 newBtcPrice = 50000 * 1e8; // $50000

        // Update Chainlink prices
        this.updateChainlinkPrices(newEthPrice, newBtcPrice);

      
        // Verify updates
        (uint256 ethPrice, uint256 btcPrice) = this.getChainlinkPrices();
        assertEq(ethPrice, newEthPrice, "ETH Chainlink price update failed");
        assertEq(btcPrice, newBtcPrice, "BTC Chainlink price update failed");
    }
}