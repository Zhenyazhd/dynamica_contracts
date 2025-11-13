// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IMarketResolutionModule {
    /// @notice Emitted when a new market is registered
    event MarketRegistered(bytes32 indexed questionId, address indexed marketMaker, address indexed resolutionModule);

    /// @notice Emitted when a market is resolved with payout ratios
    event MarketResolved(bytes32 indexed questionId, uint256[] payouts);

    enum ResolutionModule {
        CHAINLINK,
        FTSO,
        FDC
    }

    struct MarketResolutionConfig {
        address marketMaker;
        uint256 outcomeSlotCount;
        address resolutionModule;
        bytes resolutionData;
        bool isResolved;
        ResolutionModule resolutionModuleType;
    }

    function resolveMarket(
        uint256 outcomeSlotCount,
        bytes calldata resolutionData
    ) external returns (uint256[] memory payouts);
    
    function getCurrentMarketData(bytes32 questionId)
        external
        returns (uint256[] memory payouts); 
}