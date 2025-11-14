// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title IMarketResolutionModule
 * @dev Interface for market resolution modules
 * @notice This interface defines the API for resolution modules that determine market outcomes
 */
interface IMarketResolutionModule {
    // ============ Events ============

    /// @notice Emitted when a new market is registered
    /// @param questionId Unique question ID
    /// @param marketMaker Address of the MarketMaker contract
    /// @param resolutionModule Address of the resolution module
    event MarketRegistered(bytes32 indexed questionId, address indexed marketMaker, address indexed resolutionModule);

    /// @notice Emitted when a market is resolved with payout ratios
    /// @param questionId Unique question ID
    /// @param payouts Array of payout numerators for each outcome
    event MarketResolved(bytes32 indexed questionId, uint256[] payouts);

    // ============ Types ============

    /// @notice Enumeration of supported resolution module types
    enum ResolutionModule {
        CHAINLINK,
        FTSO,
        FDC
    }

    /// @notice Configuration structure for market resolution
    struct MarketResolutionConfig {
        /// @notice Address of the MarketMaker contract
        address marketMaker;
        /// @notice Number of possible outcomes
        uint256 outcomeSlotCount;
        /// @notice Address of the resolution module contract
        address resolutionModule;
        /// @notice Module-specific resolution data
        bytes resolutionData;
        /// @notice Whether the market has been resolved
        bool isResolved;
        /// @notice Type of resolution module
        ResolutionModule resolutionModuleType;
    }

    // ============ Errors ============

    /// @notice Thrown if the caller is not the market resolution manager
    error OnlyMarketResolutionManager(address caller);

    /// @notice Thrown if the market resolution manager address is invalid
    error InvalidMarketResolutionManagerAddress();

    /// @notice Thrown if price feed addresses length mismatch
    error PriceFeedAddressesLengthMismatch(uint256 provided, uint256 expected);

    /// @notice Thrown if decimals array length mismatch
    error DecimalsLengthMismatch(uint256 provided, uint256 expected);

    /// @notice Thrown if staleness array length mismatch
    error StalenessLengthMismatch(uint256 provided, uint256 expected);

    /// @notice Thrown if oracle data is stale
    error OracleDataStale(uint256 index, uint256 staleness, uint256 updatedAt, uint256 currentTimestamp);

    /// @notice Thrown if denominator cannot be zero
    error DenominatorCannotBeZero();

    // ============ External Functions ============

    /// @notice Resolves a market using the resolution module's logic
    /// @param outcomeSlotCount Number of possible outcomes
    /// @param resolutionData Encoded module-specific resolution data
    /// @return payouts Array of payout numerators that sum to 1e18
    function resolveMarket(uint256 outcomeSlotCount, bytes calldata resolutionData)
        external
        returns (uint256[] memory payouts);

    /// @notice Gets current market data without resolving
    /// @param questionId The question/market ID
    /// @return payouts Array of payout numerators for each outcome
    function getCurrentMarketData(bytes32 questionId) external returns (uint256[] memory payouts);
}
