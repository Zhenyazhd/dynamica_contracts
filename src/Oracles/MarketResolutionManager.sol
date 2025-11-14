// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";
import {IDynamica} from "../interfaces/IDynamica.sol";
import {IMarketResolutionModule} from "../interfaces/Oracles/IMarketResolutionModule.sol";
import {IMarketResolutionManager} from "../interfaces/Oracles/IMarketResolutionManager.sol";

/**
 * @title MarketResolutionManager
 * @dev Manages the resolution of prediction markets through various resolution modules
 * @notice This contract acts as a central coordinator for market resolution, allowing
 * different types of resolution modules to handle market outcomes. For detailed
 * documentation, see {IMarketResolutionManager}.
 */
contract MarketResolutionManager is Ownable, IMarketResolutionManager {
    // ============ State Variables ============

    /// @notice Address of the factory contract that can register markets
    address public factory;

    /// @notice Mapping from question ID to market resolution configuration
    mapping(bytes32 => IMarketResolutionModule.MarketResolutionConfig) public marketConfigs;

    // ============ Structs ============

    /**
     * @notice Chainlink configuration structure for resolution data validation
     * @dev Must match ChainlinkResolutionModule.ChainlinkConfig structure
     */
    struct ChainlinkConfig {
        address[] priceFeedAddresses;
        uint256[] staleness;
        uint8[] decimals;
    }

    // ============ Modifiers ============

    /// @notice Ensures only the factory contract can call the function
    modifier onlyFactory() {
        if (msg.sender != factory) {
            revert OnlyFactory(msg.sender);
        }
        _;
    }

    // ============ Constructor ============

    /**
     * @notice Initializes the MarketResolutionManager
     * @param owner The owner of the contract
     * @param _factory The address of the factory contract
     * @dev See {IMarketResolutionManager} for interface documentation
     */
    constructor(address owner, address _factory) Ownable(owner) {
        if (_factory == address(0)) {
            revert InvalidFactoryAddress();
        }
        factory = _factory;
    }

    // ============ External Functions ============

    /**
     * @notice Registers a new market with its resolution parameters
     * @param questionId Unique question ID (e.g., keccak256("ETH_BTC_PRICE_10_JULY_2025"))
     * @param marketMaker Address of the MarketMaker contract
     * @param outcomeSlotCount Number of possible outcomes
     * @param resolutionModule Address of the resolution module contract for this market
     * @param resolutionModuleType Type of resolution module (e.g., FTSO, Chainlink, etc.)
     * @param resolutionData Module-specific resolution data (e.g., oracle pairs list)
     * @dev See {IMarketResolutionManager-registerMarket}
     */
    function registerMarket(
        bytes32 questionId,
        address marketMaker,
        uint256 outcomeSlotCount,
        address resolutionModule,
        IMarketResolutionModule.ResolutionModule resolutionModuleType,
        bytes calldata resolutionData
    ) external onlyFactory {
        _validateMarketRegistration(questionId, marketMaker, outcomeSlotCount, resolutionModule);
        _validateResolutionData(resolutionModuleType, resolutionData, outcomeSlotCount);

        marketConfigs[questionId] = IMarketResolutionModule.MarketResolutionConfig(
            marketMaker,
            outcomeSlotCount,
            resolutionModule,
            resolutionData,
            false, // isResolved
            resolutionModuleType
        );

        emit MarketRegistered(questionId, marketMaker, resolutionModule);
    }

    /**
     * @notice Resolves a market by calling the appropriate resolution module
     * @param questionId The question/market ID to resolve
     * @dev See {IMarketResolutionManager-resolveMarket}
     */
    function resolveMarket(bytes32 questionId) external onlyOwner {
        IMarketResolutionModule.MarketResolutionConfig storage config = marketConfigs[questionId];

        if (!IDynamica(config.marketMaker).checkEpoch()) {
            revert LastEpochNotFinishedYet();
        }

        _validateMarketResolution(config);

        // Call the resolution module to get payout ratios
        uint256[] memory payouts = _getMarketPayouts(config);

        // Close the market with the calculated payouts
        config.isResolved = IDynamica(config.marketMaker).closeEpoch(payouts);

        emit MarketResolved(questionId, payouts);
    }

    /**
     * @notice Gets current market data without resolving
     * @param questionId The question/market ID
     * @return payouts Array of payout numerators for each outcome
     * @dev See {IMarketResolutionManager-getCurrentMarketData}
     */
    function getCurrentMarketData(bytes32 questionId) external returns (uint256[] memory payouts) {
        IMarketResolutionModule.MarketResolutionConfig storage config = marketConfigs[questionId];
        _validateMarketResolution(config);
        payouts = _getMarketPayouts(config);
    }

    // ============ Private Functions ============

    /**
     * @notice Validates market registration parameters
     * @param questionId The question ID to validate
     * @param marketMaker The market maker address to validate
     * @param outcomeSlotCount The number of outcome slots to validate
     * @param resolutionModule The resolution module address to validate
     */
    function _validateMarketRegistration(
        bytes32 questionId,
        address marketMaker,
        uint256 outcomeSlotCount,
        address resolutionModule
    ) private view {
        if (marketConfigs[questionId].marketMaker != address(0)) {
            revert MarketAlreadyRegistered(questionId);
        }
        if (marketMaker == address(0)) {
            revert InvalidMarketMakerAddress();
        }
        if (resolutionModule == address(0)) {
            revert InvalidResolutionModuleAddress();
        }
        if (outcomeSlotCount <= 1) {
            revert MustHaveMoreThanOneOutcomeSlot();
        }
    }

    /**
     * @notice Validates that a market can be resolved
     * @param config The market resolution configuration
     */
    function _validateMarketResolution(IMarketResolutionModule.MarketResolutionConfig storage config) private view {
        if (config.marketMaker == address(0)) {
            revert MarketNotRegistered();
        }
        if (config.isResolved) {
            revert MarketAlreadyResolved();
        }
    }

    /**
     * @notice Validates resolution data based on the resolution module type
     * @param resolutionModuleType Type of resolution module
     * @param resolutionData Encoded resolution data to validate
     * @param outcomeSlotCount Expected number of outcomes
     */
    function _validateResolutionData(
        IMarketResolutionModule.ResolutionModule resolutionModuleType,
        bytes calldata resolutionData,
        uint256 outcomeSlotCount
    ) private pure {
        if (resolutionModuleType == IMarketResolutionModule.ResolutionModule.CHAINLINK) {
            _validateChainlinkResolutionData(resolutionData, outcomeSlotCount);
        }
        // Add validation for other module types as needed
    }

    /**
     * @notice Validates Chainlink resolution data structure
     * @param resolutionData Encoded ChainlinkConfig to validate
     * @param outcomeSlotCount Expected number of outcomes
     * @dev Uses the same ChainlinkConfig structure as ChainlinkResolutionModule
     */
    function _validateChainlinkResolutionData(bytes calldata resolutionData, uint256 outcomeSlotCount) private pure {
        // Decode the configuration data
        // This will revert if the data format is invalid
        ChainlinkConfig memory config = abi.decode(resolutionData, (ChainlinkConfig));

        // Validate array lengths match outcomeSlotCount
        if (config.priceFeedAddresses.length != outcomeSlotCount) {
            revert PriceFeedAddressesLengthMismatch(config.priceFeedAddresses.length, outcomeSlotCount);
        }
        if (config.staleness.length != outcomeSlotCount) {
            revert StalenessArrayLengthMismatch(config.staleness.length, outcomeSlotCount);
        }
        if (config.decimals.length != outcomeSlotCount) {
            revert DecimalsArrayLengthMismatch(config.decimals.length, outcomeSlotCount);
        }

        // Validate each price feed address is not zero
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            if (config.priceFeedAddresses[i] == address(0)) {
                revert InvalidPriceFeedAddress(i);
            }
            if (config.staleness[i] == 0) {
                revert StalenessMustBePositive(i, config.staleness[i]);
            }
            if (config.decimals[i] > 18) {
                revert DecimalsMustBeLessThanOrEqual18(i, config.decimals[i]);
            }
        }
    }

    /**
     * @notice Gets market payouts from the resolution module
     * @param config The market resolution configuration
     * @return payouts Array of payout numerators for each outcome
     */
    function _getMarketPayouts(IMarketResolutionModule.MarketResolutionConfig storage config)
        private
        returns (uint256[] memory payouts)
    {
        payouts = IMarketResolutionModule(config.resolutionModule).resolveMarket(
            config.outcomeSlotCount, config.resolutionData
        );
    }
}
