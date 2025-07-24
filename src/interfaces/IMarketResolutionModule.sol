// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IMarketResolutionModule {
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
        uint32 expirationTime;
        ResolutionModule resolutionModuleType;
    }

    function resolveMarket(
        bytes32 questionId,
        address marketMakerAddress,
        uint256 outcomeSlotCount,
        bytes calldata resolutionData
    ) external returns (uint256[] memory payouts);
}
