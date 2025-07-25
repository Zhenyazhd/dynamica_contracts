// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {FtsoV2Interface} from "flare-periphery/src/coston2/FtsoV2Interface.sol";
import {IMarketResolutionModule} from "../../interfaces/IMarketResolutionModule.sol";
import {Initializable} from "@openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

// Структура для параметров FTSO
struct FTSOConfig {
    bytes21[] ftsoIds; // ID FTSO для каждого исхода
    uint256[] staleness; // Максимальное время устаревания для каждого ID
}

contract FTSOResolutionModule is Initializable, IMarketResolutionModule {
    FtsoV2Interface public ftso; // Адрес FTSO v2
    address public marketResolutionManager;

    modifier onlyMarketResolutionManager() {
        require(msg.sender == marketResolutionManager, "Only market resolution manager can call this function");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address _ftsoV2Address, address _marketResolutionManager) public initializer {
        require(_ftsoV2Address != address(0), "Invalid FTSO address");
        require(_marketResolutionManager != address(0), "Invalid market resolution manager address");
        ftso = FtsoV2Interface(_ftsoV2Address);
        marketResolutionManager = _marketResolutionManager;
    }

    /**
     * @notice Реализация интерфейса IMarketResolutionModule.
     * @dev Декодирует resolutionData, получает данные от FTSO и вычисляет payout.
     * @param outcomeSlotCount Количество исходов
     * @param resolutionData Закодированные FTSOConfig
     * @return payouts Массив результатов для MarketMaker
     */
    function resolveMarket(uint256 outcomeSlotCount, bytes calldata resolutionData)
        external
        onlyMarketResolutionManager
        returns (uint256[] memory payouts)
    {
        FTSOConfig memory config = abi.decode(resolutionData, (FTSOConfig));
        require(config.ftsoIds.length == outcomeSlotCount, "Config mismatch: ftsoIds");
        require(config.staleness.length == outcomeSlotCount, "Config mismatch: staleness");

        uint64 currentTimestamp = uint64(block.timestamp);
        uint256[] memory valuesAdjusted = new uint256[](outcomeSlotCount);

        uint256 denominator = 0;
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            (uint256 value, int8 decimals_, uint64 timestamp) = ftso.getFeedById(config.ftsoIds[i]);
            require(currentTimestamp - timestamp <= config.staleness[i], "Oracle data is stale");
            valuesAdjusted[i] = value * 10 ** (18 - uint8(decimals_));
            denominator += valuesAdjusted[i];
        }

        require(denominator > 0, "Denominator cannot be zero");

        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            valuesAdjusted[i] = (valuesAdjusted[i] * 10 ** 18) / denominator;
        }

        return payouts;
    }
}
