// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ContractRegistry} from "flare-periphery/src/coston2/ContractRegistry.sol";
import {IWeb2Json} from "flare-periphery/src/coston2/IWeb2Json.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";

// ============ Structs ============

/**
 * @title DataTransportObject
 * @dev Structure for transporting data arrays
 */
struct DataTransportObject {
    uint256[] data;
}

// ============ Interfaces ============

/**
 * @title IDriverRatingsList
 * @dev Interface for driver ratings list functionality
 */
interface IDriverRatingsList {
    /**
     * @notice Adds data from a JSON API proof
     * @param data The proof containing the data to add
     */
    function addData(IWeb2Json.Proof calldata data) external;
    
    /**
     * @notice Retrieves all stored data
     * @return Array of all stored ratings data
     */
    function getAllData() external view returns (uint256[] memory);
}

/**
 * @title IMarketMaker
 * @dev Interface for market maker contracts
 */
interface IMarketMaker {
    /**
     * @notice Closes the market with payout data
     * @param payouts Array of payout numerators for each outcome
     */
    function closeMarket(uint256[] calldata payouts) external;
}

// ============ Main Contract ============

/**
 * @title DriverRatingsList
 * @dev Contract for managing driver ratings and market closure
 * @notice This contract handles driver ratings data and closes prediction markets
 */
contract DataFeed is Ownable {
    // ============ Constants ============
    
    /// @notice Multiplier for rating precision (1000)
    uint256 public constant MULTIPLIER = 10**3;

    // ============ State Variables ============
    
    /// @notice Array of stored ratings
    uint256[] public ratings;
    
    /// @notice Current market index
    uint256 public index = 1;

    // ============ Structs ============
    
    /**
     * @title Market
     * @dev Structure representing a prediction market
     */
    struct Market {
        address marketMaker;
        uint256 outcomeSlotCount;
        bytes32[] tokens;
        bool isClosed;
    }

    // ============ Mappings ============
    
    /// @notice Mapping from market index to market data
    mapping(uint256 => Market) public market;

    // ============ Constructor ============
    
    constructor() Ownable(msg.sender) {}

    // ============ External Functions ============
    
    /**
     * @notice Registers a new prediction market
     * @param question The market question
     * @param marketMaker Address of the market maker contract
     * @param outcomeSlotCount Number of possible outcomes
     * @param tokens Array of outcome token identifiers
     */
    function registreNewMarket(
        string calldata question,
        address marketMaker,
        uint256 outcomeSlotCount,
        bytes32[] calldata tokens
    ) external onlyOwner {
        require(marketMaker != address(0), "Invalid market maker address");
        require(outcomeSlotCount > 0, "Invalid outcome slot count");
        require(tokens.length > 0, "Tokens array cannot be empty");
        
        market[index] = Market(marketMaker, outcomeSlotCount, tokens, false);
        index++;
    }

    /**
     * @notice Adds driver ratings data from a JSON API proof
     * @param data The proof containing the ratings data
     */
    function addData(IWeb2Json.Proof calldata data) external {
        require(isJsonApiProofValid(data), "Invalid proof");
        require(index > 1, "No markets registered");
        require(!market[index - 1].isClosed, "Market already closed");

        // Parse ratings from the proof data
        uint256[] memory parsedRatings = abi.decode(
            data.data.responseBody.abiEncodedData,
            (DataTransportObject)
        ).data;

        require(parsedRatings.length > 0, "No ratings data provided");

        // Apply multiplier and store ratings
        for (uint256 i = 0; i < parsedRatings.length; i++) {
            ratings.push(parsedRatings[i] * MULTIPLIER);
        }
        
        // Close the market and trigger payout
        market[index - 1].isClosed = true;
        IMarketMaker(market[index - 1].marketMaker).closeMarket(ratings);
    }

    // ============ Public Functions ============
    
    /**
     * @notice Retrieves all stored ratings data
     * @return Array of all stored ratings
     */
    function getAllData() external view returns (uint256[] memory) {
        return ratings;
    }

    // ============ Private Functions ============
    
    /**
     * @notice Validates a JSON API proof using FDC verification
     * @param _proof The proof to validate
     * @return True if the proof is valid
     */
    function isJsonApiProofValid(
        IWeb2Json.Proof calldata _proof
    ) private view returns (bool) {
        return ContractRegistry.getFdcVerification().verifyJsonApi(_proof);
    }
}