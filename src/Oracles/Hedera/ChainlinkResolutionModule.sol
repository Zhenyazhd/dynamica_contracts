// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AggregatorV3Interface} from
    "smartcontractkit-chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IMarketResolutionModule} from "../../interfaces/Oracles/IMarketResolutionModule.sol";
import {Initializable} from "@openzeppelin-contracts/proxy/utils/Initializable.sol";

/**
 * @title ChainlinkResolutionModule
 * @dev Resolution module that uses Chainlink price feeds to determine market outcomes
 * @notice This module resolves prediction markets based on real-time price data from
 * Chainlink oracles, normalizing the results to payout ratios. For detailed
 * documentation, see {IMarketResolutionModule}.
 *
 * The module:
 * - Fetches price data from multiple Chainlink price feeds
 * - Validates data freshness against staleness thresholds
 * - Normalizes prices to payout ratios that sum to 1e18
 * - Handles precision adjustments to ensure exact payout distribution
 */
contract ChainlinkResolutionModule is Initializable, IMarketResolutionModule {
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
    // ============ State Variables ============

    /// @notice Address of the market resolution manager contract
    address public marketResolutionManager;

    // ============ Modifiers ============

    /// @notice Ensures only the market resolution manager can call the function
    modifier onlyMarketResolutionManager() {
        if (msg.sender != marketResolutionManager) {
            revert OnlyMarketResolutionManager(msg.sender);
        }
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
     * @dev See {IMarketResolutionModule} for interface documentation
     */
    function initialize(address _marketResolutionManager) public initializer {
        if (_marketResolutionManager == address(0)) {
            revert InvalidMarketResolutionManagerAddress();
        }
        marketResolutionManager = _marketResolutionManager;
    }

    /**
     * @notice Resolves a market using Chainlink price feed data
     * @dev Decodes resolutionData, fetches Chainlink data, and calculates payout ratio
     * @param outcomeSlotCount Number of possible outcomes
     * @param resolutionData Encoded ChainlinkConfig containing price feed addresses and parameters
     * @return payouts Array of payout numerators that sum to 1e18
     * @dev See {IMarketResolutionModule-resolveMarket}
     */
    function resolveMarket(uint256 outcomeSlotCount, bytes calldata resolutionData)
        external
        view
        onlyMarketResolutionManager
        returns (uint256[] memory payouts)
    {
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
        if (config.priceFeedAddresses.length != outcomeSlotCount) {
            revert PriceFeedAddressesLengthMismatch(config.priceFeedAddresses.length, outcomeSlotCount);
        }
        if (config.decimals.length != outcomeSlotCount) {
            revert DecimalsLengthMismatch(config.decimals.length, outcomeSlotCount);
        }
        if (config.staleness.length != outcomeSlotCount) {
            revert StalenessLengthMismatch(config.staleness.length, outcomeSlotCount);
        }
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
            if (currentTimestamp - updatedAt > config.staleness[i]) {
                revert OracleDataStale(i, config.staleness[i], updatedAt, currentTimestamp);
            }

            // Convert price to 18 decimal precision and add to payouts
            payouts[i] = uint256(price) * 10 ** (18 - config.decimals[i]);
            denominator += payouts[i];
        }

        if (denominator == 0) {
            revert DenominatorCannotBeZero();
        }
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

    /**
     * @notice Gets current market data without resolving
     * @return payouts Array of payout numerators for each outcome
     * @dev See {IMarketResolutionModule-getCurrentMarketData}
     *      Note: questionId parameter is unused in this implementation
     */
    function getCurrentMarketData(bytes32 /* questionId */ ) external pure returns (uint256[] memory payouts) {
        payouts = new uint256[](2);
        payouts[0] = 1000;
        payouts[1] = 2000;
        return payouts;
    }
}
