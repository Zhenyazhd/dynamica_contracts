// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {LMSRMarketMaker} from "./LMSRMarketMaker.sol";
import {MarketMaker} from "./SimpleMarketMaker.sol";

/**
 * @title MarketMakerFactory
 * @dev Factory contract for creating MarketMaker instances
 * @notice This contract allows users to create new prediction markets with different parameters
 */
contract MarketMakerFactory {
    // ============ Events ============

    /// @notice Emitted when a new market maker is created
    event MarketMakerCreated(
        address indexed creator,
        address indexed marketMaker,
        IERC20 indexed collateralToken,
        uint64 fee,
        uint256 funding
    );

    // ============ State Variables ============
    uint64 public constant FEE_RANGE = 10_000;

    /// @notice Array of all created market makers
    address[] public marketMakers;

    /// @notice Mapping from market maker address to creator
    mapping(address => address) public marketMakerCreators;

    /// @notice Mapping from creator to their market makers
    mapping(address => address[]) public creatorMarketMakers;

    // ============ External Functions ============

    /**
     * @notice Creates a new MarketMaker contract
     * @param collateralToken The collateral token to use for trading
     * @param fee The fee rate (must be less than MarketMaker.FEE_RANGE)
     * @return marketMaker The address of the created MarketMaker contract
     */
    function createMarketMaker(IERC20 collateralToken, uint64 fee) external returns (LMSRMarketMaker marketMaker) {
        require(address(collateralToken) != address(0), "Invalid collateral token");
        require(fee < FEE_RANGE, "Fee too high");

        // Create new MarketMaker instance
        marketMaker = new LMSRMarketMaker(collateralToken, fee);

        // Transfer ownership to creator
        marketMaker.transferOwnership(msg.sender);

        // Record the market maker
        address marketMakerAddress = address(marketMaker);
        marketMakers.push(marketMakerAddress);
        marketMakerCreators[marketMakerAddress] = msg.sender;
        creatorMarketMakers[msg.sender].push(marketMakerAddress);

        emit MarketMakerCreated(msg.sender, marketMakerAddress, collateralToken, fee, 0);
    }

    /**
     * @notice Creates a new MarketMaker contract with initial funding
     * @param collateralToken The collateral token to use for trading
     * @param fee The fee rate (must be less than MarketMaker.FEE_RANGE)
     * @param question The question identifier
     * @param oracle The oracle address that will resolve the condition
     * @param outcomeTokenAmounts The initial token amounts for each outcome
     * @param startLiquidity The initial funding amount
     * @param qAmounts The initial token amounts for each outcome
     * @param outcomeTokenAmounts The initial token amounts for each outcome
     * @return marketMaker The address of the created MarketMaker contract
     */
    function createMarketMakerWithFunding(
        IERC20 collateralToken,
        uint64 fee,
        string calldata question,
        address oracle,
        uint256 outcomeTokenAmounts,
        uint256 startLiquidity,
        uint256 qAmounts
    ) external returns (LMSRMarketMaker marketMaker) {
        require(address(collateralToken) != address(0), "Invalid collateral token");
        require(fee < 10 ** 18, "Fee too high");
        require(startLiquidity > 0, "Funding must be positive");

        // Create new MarketMaker instance
        marketMaker = new LMSRMarketMaker(collateralToken, fee);
        // Record the market maker
        address marketMakerAddress = address(marketMaker);
        marketMakers.push(marketMakerAddress);
        marketMakerCreators[marketMakerAddress] = msg.sender;
        creatorMarketMakers[msg.sender].push(marketMakerAddress);

        marketMaker.prepareCondition(oracle, question, outcomeTokenAmounts);
        // Initialize with funding
        require(collateralToken.transferFrom(msg.sender, address(this), startLiquidity), "Funding transfer failed");
        require(collateralToken.approve(marketMakerAddress, startLiquidity), "Funding approval failed");

        marketMaker.initializeMarket(startLiquidity, qAmounts);

        // Transfer ownership to creator
        marketMaker.transferOwnership(msg.sender);

        emit MarketMakerCreated(msg.sender, marketMakerAddress, collateralToken, fee, startLiquidity);
    }

    // ============ View Functions ============

    /**
     * @notice Gets all market makers created by this factory
     * @return Array of all market maker addresses
     */
    function getAllMarketMakers() external view returns (address[] memory) {
        return marketMakers;
    }

    /**
     * @notice Gets the total number of market makers created
     * @return The total count of market makers
     */
    function getMarketMakerCount() external view returns (uint256) {
        return marketMakers.length;
    }

    /**
     * @notice Gets all market makers created by a specific address
     * @param creator The address of the creator
     * @return Array of market maker addresses created by the specified address
     */
    function getMarketMakersByCreator(address creator) external view returns (address[] memory) {
        return creatorMarketMakers[creator];
    }

    /**
     * @notice Gets the creator of a specific market maker
     * @param marketMaker The address of the market maker
     * @return The address of the creator
     */
    function getMarketMakerCreator(address marketMaker) external view returns (address) {
        return marketMakerCreators[marketMaker];
    }

    /**
     * @notice Checks if an address is a market maker created by this factory
     * @param marketMaker The address to check
     * @return True if the address is a market maker created by this factory
     */
    function isMarketMaker(address marketMaker) external view returns (bool) {
        return marketMakerCreators[marketMaker] != address(0);
    }
}
