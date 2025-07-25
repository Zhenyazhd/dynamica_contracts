// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AggregatorV3Interface} from
    "smartcontractkit-chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IMarketResolutionModule} from "../../interfaces/IMarketResolutionModule.sol";
import {Initializable} from "@openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

/**
 * @title ChainlinkConfig
 * @dev Configuration structure for Chainlink price feeds
 * @notice Contains arrays of price feed addresses, staleness periods, and decimal places
 */
struct ChainlinkConfig {
    /// @notice Array of Chainlink price feed contract addresses
    address[] priceFeedAddresses;
    /// @notice Array of staleness periods in seconds for each price feed
    uint256[] staleness;
    /// @notice Array of decimal places for each price feed
    uint8[] decimals;
}

/**
 * @title ChainlinkResolutionModule
 * @dev Resolution module that uses Chainlink price feeds to determine market outcomes
 * @notice This module resolves prediction markets based on real-time price data from
 * Chainlink oracles, normalizing the results to payout ratios
 *
 * The module:
 * - Fetches price data from multiple Chainlink price feeds
 * - Validates data freshness against staleness thresholds
 * - Normalizes prices to payout ratios that sum to 1e18
 * - Handles precision adjustments to ensure exact payout distribution
 */
contract ChainlinkResolutionModule is Initializable, IMarketResolutionModule {
    // ============ State Variables ============

    /// @notice Address of the market resolution manager contract
    address public marketResolutionManager;

    // ============ Modifiers ============

    /// @notice Ensures only the market resolution manager can call the function
    modifier onlyMarketResolutionManager() {
        require(msg.sender == marketResolutionManager, "Only market resolution manager can call this function");
        _;
    }

    // ============ Constructor ============

    /**
     * @notice Constructor that disables initializers for implementation contract
     */
    constructor() {
        _disableInitializers();
    }

    // ============ External Functions ============

    /**
     * @notice Initializes the Chainlink resolution module
     * @param _marketResolutionManager Address of the market resolution manager
     */
    function initialize(address _marketResolutionManager) public initializer {
        require(_marketResolutionManager != address(0), "Invalid market resolution manager address");
        marketResolutionManager = _marketResolutionManager;
    }

    /**
     * @notice Resolves a market using Chainlink price feed data
     * @dev Decodes resolutionData, fetches Chainlink data, and calculates payout ratio
     * @param outcomeSlotCount Number of possible outcomes
     * @param resolutionData Encoded ChainlinkConfig containing price feed addresses and parameters
     * @return payouts Array of payout numerators that sum to 1e18
     */
    function resolveMarket(
        uint256 outcomeSlotCount,
        bytes calldata resolutionData
    ) external view onlyMarketResolutionManager returns (uint256[] memory payouts) {
        // Decode the configuration data
        ChainlinkConfig memory config = abi.decode(resolutionData, (ChainlinkConfig));

        // Validate configuration consistency
        _validateConfig(config, outcomeSlotCount);

        // Initialize payout array
        payouts = new uint256[](outcomeSlotCount);

        // Get current timestamp for staleness validation
        uint64 currentTimestamp = uint64(block.timestamp);

        // Fetch and process price data from all feeds
        uint256 denominator = _fetchAndProcessPrices(config, outcomeSlotCount, currentTimestamp, payouts);

        // Normalize payouts to sum to 1e18
        _normalizePayouts(payouts, denominator);

        // Ensure exact payout distribution
        _adjustPayoutPrecision(payouts);

        return payouts;
    }

    // ============ Private Functions ============

    /**
     * @notice Validates the Chainlink configuration parameters
     * @param config The Chainlink configuration to validate
     * @param outcomeSlotCount The expected number of outcomes
     */
    function _validateConfig(ChainlinkConfig memory config, uint256 outcomeSlotCount) private pure {
        require(config.priceFeedAddresses.length == outcomeSlotCount, "Config mismatch: priceFeedAddresses");
        require(config.decimals.length == outcomeSlotCount, "Config mismatch: decimals");
        require(config.staleness.length == outcomeSlotCount, "Config mismatch: staleness");
    }

    /**
     * @notice Fetches price data from Chainlink feeds and calculates initial payouts
     * @param config The Chainlink configuration
     * @param outcomeSlotCount Number of outcomes
     * @param currentTimestamp Current block timestamp
     * @param payouts Array to store the calculated payouts
     * @return denominator Sum of all raw payout values
     */
    function _fetchAndProcessPrices(
        ChainlinkConfig memory config,
        uint256 outcomeSlotCount,
        uint64 currentTimestamp,
        uint256[] memory payouts
    ) private view returns (uint256 denominator) {
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            AggregatorV3Interface priceFeed = AggregatorV3Interface(config.priceFeedAddresses[i]);

            // Fetch latest price data
            (, int256 price,, uint256 updatedAt,) = priceFeed.latestRoundData();

            // Validate data freshness
            require(currentTimestamp - updatedAt <= config.staleness[i], "Oracle data is stale");

            // Convert price to 18 decimal precision and add to payouts
            payouts[i] = uint256(price) * 10 ** (18 - config.decimals[i]);
            denominator += payouts[i];
        }

        require(denominator > 0, "Denominator cannot be zero");
    }

    /**
     * @notice Normalizes payout values to sum to 1e18
     * @param payouts Array of payout values to normalize
     * @param denominator The sum of all raw payout values
     */
    function _normalizePayouts(uint256[] memory payouts, uint256 denominator) private pure {
        for (uint256 i = 0; i < payouts.length; i++) {
            payouts[i] = (payouts[i] * 1e18) / denominator;
        }
    }

    /**
     * @notice Adjusts payout precision to ensure exact distribution
     * @param payouts Array of payout values to adjust
     * @dev Adds any rounding errors to the highest payout value to ensure total equals 1e18
     */
    function _adjustPayoutPrecision(uint256[] memory payouts) private pure {
        uint256 total = 0;
        for (uint256 i = 0; i < payouts.length; i++) {
            total += payouts[i];
        }

        // If total is less than 1e18 due to rounding, add the difference to the highest payout
        if (total < 1e18) {
            uint256 diff = 1e18 - total;
            uint256 maxIndex = _findMaxPayoutIndex(payouts);
            payouts[maxIndex] += diff;
        }
    }

    /**
     * @notice Finds the index of the highest payout value
     * @param payouts Array of payout values
     * @return maxIndex Index of the highest payout value
     */
    function _findMaxPayoutIndex(uint256[] memory payouts) private pure returns (uint256 maxIndex) {
        for (uint256 i = 1; i < payouts.length; i++) {
            if (payouts[i] > payouts[maxIndex]) {
                maxIndex = i;
            }
        }
    }
}
