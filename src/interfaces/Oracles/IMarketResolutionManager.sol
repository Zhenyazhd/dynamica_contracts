// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IMarketResolutionModule} from "./IMarketResolutionModule.sol";

/**
 * @title IMarketResolutionManager
 * @dev Interface for the MarketResolutionManager contract
 * @notice This interface defines the external API for managing market resolution
 */
interface IMarketResolutionManager {
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

    // ============ Errors ============

    /// @notice Thrown if the factory address is invalid
    error InvalidFactoryAddress();

    /// @notice Thrown if the caller is not the factory
    error OnlyFactory(address caller);

    /// @notice Thrown if the market is already registered
    error MarketAlreadyRegistered(bytes32 questionId);

    /// @notice Thrown if the market maker address is invalid
    error InvalidMarketMakerAddress();

    /// @notice Thrown if the resolution module address is invalid
    error InvalidResolutionModuleAddress();

    /// @notice Thrown if there must be more than one outcome slot
    error MustHaveMoreThanOneOutcomeSlot();

    /// @notice Thrown if the market is not registered
    error MarketNotRegistered();

    /// @notice Thrown if the market is already resolved
    error MarketAlreadyResolved();

    /// @notice Thrown if the last epoch is not finished yet
    error LastEpochNotFinishedYet();

    /// @notice Thrown if price feed addresses length mismatch
    error PriceFeedAddressesLengthMismatch(uint256 provided, uint256 expected);

    /// @notice Thrown if staleness array length mismatch
    error StalenessArrayLengthMismatch(uint256 provided, uint256 expected);

    /// @notice Thrown if decimals array length mismatch
    error DecimalsArrayLengthMismatch(uint256 provided, uint256 expected);

    /// @notice Thrown if a price feed address is invalid
    error InvalidPriceFeedAddress(uint256 index);

    /// @notice Thrown if staleness must be positive
    error StalenessMustBePositive(uint256 index, uint256 value);

    /// @notice Thrown if decimals must be <= 18
    error DecimalsMustBeLessThanOrEqual18(uint256 index, uint8 value);

    // ============ External Functions ============

    /// @notice Registers a new market with its resolution parameters
    /// @param questionId Unique question ID
    /// @param marketMaker Address of the MarketMaker contract
    /// @param outcomeSlotCount Number of possible outcomes
    /// @param resolutionModule Address of the resolution module contract
    /// @param resolutionModuleType Type of resolution module
    /// @param resolutionData Module-specific resolution data
    function registerMarket(
        bytes32 questionId,
        address marketMaker,
        uint256 outcomeSlotCount,
        address resolutionModule,
        IMarketResolutionModule.ResolutionModule resolutionModuleType,
        bytes calldata resolutionData
    ) external;

    /// @notice Resolves a market by calling the appropriate resolution module
    /// @param questionId The question/market ID to resolve
    function resolveMarket(bytes32 questionId) external;

    /// @notice Gets current market data without resolving
    /// @param questionId The question/market ID
    /// @return payouts Array of payout numerators for each outcome
    function getCurrentMarketData(bytes32 questionId) external returns (uint256[] memory payouts);
}
