// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";
import {IDynamica} from "../interfaces/IDynamica.sol";
import {IMarketResolutionModule} from "../interfaces/IMarketResolutionModule.sol";
import {console} from "forge-std/src/console.sol";

/**
 * @title MarketResolutionManager
 * @dev Manages the resolution of prediction markets through various resolution modules
 * @notice This contract acts as a central coordinator for market resolution, allowing
 * different types of resolution modules to handle market outcomes
 *
 * The contract provides:
 * - Market registration with specific resolution modules
 * - Market resolution through configured modules
 * - Centralized tracking of market states
 */
contract MarketResolutionManager is Ownable  {
    // ============ State Variables ============

    /// @notice Address of the factory contract that can register markets
    address public factory;

    /// @notice Mapping from question ID to market resolution configuration
    mapping(bytes32 => IMarketResolutionModule.MarketResolutionConfig) public marketConfigs;

    // ============ Events ============

    /// @notice Emitted when a new market is registered
    event MarketRegistered(bytes32 indexed questionId, address indexed marketMaker, address indexed resolutionModule);

    /// @notice Emitted when a market is resolved with payout ratios
    event MarketResolved(bytes32 indexed questionId, uint256[] payouts);

    // ============ Modifiers ============

    /// @notice Ensures only the factory contract can call the function
    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory can call this function");
        _;
    }

    modifier onlyWhenExpired(uint32 expirationTime) {
        require(block.timestamp > expirationTime, "Market not expired");
        _;
    }

    // ============ Constructor ============

    /**
     * @notice Initializes the MarketResolutionManager
     * @param owner The owner of the contract
     * @param _factory The address of the factory contract
     */
    constructor(address owner, address _factory) Ownable(owner) {
        require(_factory != address(0), "Invalid factory address");
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
     * @dev Only callable by the factory contract
     */
    function registerMarket(
        bytes32 questionId,
        address marketMaker,
        uint256 outcomeSlotCount,
        address resolutionModule,
        uint32 expirationTime,
        IMarketResolutionModule.ResolutionModule resolutionModuleType,
        bytes calldata resolutionData
    ) external onlyFactory {
        _validateMarketRegistration(questionId, marketMaker, outcomeSlotCount, resolutionModule);

        marketConfigs[questionId] = IMarketResolutionModule.MarketResolutionConfig(
            marketMaker,
            outcomeSlotCount,
            resolutionModule,
            resolutionData,
            false, // isResolve
            expirationTime,
            resolutionModuleType
        );

        emit MarketRegistered(questionId, marketMaker, resolutionModule);
    }

    /**
     * @notice Resolves a market by calling the appropriate resolution module
     * @param questionId The question/market ID to resolve
     * @dev Only callable by the owner. Calls the resolution module and passes
     * the result to the MarketMaker contract
     */
    function resolveMarket(bytes32 questionId)
        external
        onlyOwner
        onlyWhenExpired(marketConfigs[questionId].expirationTime)
    {
        IMarketResolutionModule.MarketResolutionConfig storage config = marketConfigs[questionId];

        _validateMarketResolution(config);

        // Call the resolution module to get payout ratios
        uint256[] memory payouts = _getMarketPayouts(config);

        // Close the market with the calculated payouts
        IDynamica(config.marketMaker).closeMarket(payouts);

        // Mark the market as resolved
        config.isResolved = true;

        emit MarketResolved(questionId, payouts);
    }



    function getCurrentMarketData(bytes32 questionId)
        external
        returns (uint256[] memory payouts)
    {
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
        require(marketConfigs[questionId].marketMaker == address(0), "Market already registered");
        require(marketMaker != address(0), "Invalid market maker address");
        require(resolutionModule != address(0), "Invalid resolution module address");
        require(outcomeSlotCount > 1, "Must have more than one outcome slot");
    }

    /**
     * @notice Validates that a market can be resolved
     * @param config The market resolution configuration
     */
    function _validateMarketResolution(
        IMarketResolutionModule.MarketResolutionConfig storage config
    ) private view {
        require(config.marketMaker != address(0), "Market not registered");
        require(!config.isResolved, "Market already resolved");
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
            config.outcomeSlotCount,
            config.resolutionData
        );
    }
}