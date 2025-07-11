// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IMarketResolutionModule {
    enum ResolutionModule {
        CHAINLINK,
        FTSO,
        FDC
    }

    struct MarketResolutionConfig {
        address marketMaker;             // Адрес MarketMaker для этого вопроса
        uint256 outcomeSlotCount;        // Количество исходов
        address resolutionModule;        // Адрес модуля, который будет разрешать этот рынок
        bytes resolutionData;            // Данные, специфичные для модуля (например, какие пары Chainlink, какие токены FTSO)
        bool isResolved;                 // Флаг, указывающий, что рынок уже разрешен
        ResolutionModule resolutionModuleType;
    }

    function resolveMarket(
        bytes32 questionId,
        address marketMakerAddress,
        uint256 outcomeSlotCount,
        bytes calldata resolutionData 
    ) external returns (uint256[] memory payouts);
}