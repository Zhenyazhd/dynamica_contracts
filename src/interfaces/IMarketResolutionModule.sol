// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IMarketResolutionModule {
    /// @notice Emitted when a new market is registered
    event MarketRegistered(bytes32 indexed questionId, address indexed marketMaker, address indexed resolutionModule);

    /// @notice Emitted when a market is resolved with payout ratios
    event MarketResolved(bytes32 indexed questionId, uint256[] payouts);

    /// @notice Resolution module types
    enum ResolutionModule {
        CHAINLINK,
        FTSO,
        FDC
    }

    /// @notice Market resolution configuration
    struct MarketResolutionConfig {
        /// @notice Market maker address
        address marketMaker;
        /// @notice Number of outcome slots
        uint256 outcomeSlotCount;
        /// @notice Resolution module address
        address resolutionModule;
        /// @notice Resolution data
        bytes resolutionData;
        /// @notice Whether the market is resolved
        bool isResolved;
        /// @notice Resolution module type
        ResolutionModule resolutionModuleType;
        /// @notice Minimum price for ranged market
        uint256 minPrice;
        /// @notice Maximum price for ranged market
        uint256 maxPrice;
    }

    /// @notice Resolve a market
    /// @param outcomeSlotCount Number of outcome slots
    /// @param resolutionData Resolution data
    /// @return payouts Payouts for each outcome slot
    function resolveMarket(
        uint256 outcomeSlotCount,
        bytes calldata resolutionData
    ) external returns (uint256[] memory payouts);
}