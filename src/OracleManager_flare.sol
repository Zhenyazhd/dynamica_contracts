// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FtsoV2Interface
 * @dev Interface for FTSO V2 oracle system
 */
interface FtsoV2Interface {
    // ============ Structs ============
    
    /// @notice Feed data structure
    struct FeedData {
        uint32 votingRoundId;
        bytes21 id;
        int32 value;
        uint16 turnoutBIPS;
        int8 decimals;
    }

    /// @notice Feed data with proof structure
    struct FeedDataWithProof {
        bytes32[] proof;
        FeedData body;
    }

    /// @notice Feed id change structure
    struct FeedIdChange {
        bytes21 oldFeedId;
        bytes21 newFeedId;
    }

    // ============ Events ============
    
    /// @notice Event emitted when a feed id is changed
    event FeedIdChanged(bytes21 indexed oldFeedId, bytes21 indexed newFeedId);

    // ============ Functions ============
    
    /**
     * @notice Returns the FTSO protocol id
     * @return _feedIds The list of supported feed ids
     */
    function getFtsoProtocolId() external view returns (uint256);

    /**
     * @notice Returns the list of supported feed ids
     * @return _feedIds The list of supported feed ids
     */
    function getSupportedFeedIds() external view returns (bytes21[] memory _feedIds);

    /**
     * @notice Returns the list of feed id changes
     * @return _feedIdChanges The list of changed feed id pairs
     */
    function getFeedIdChanges() external view returns (FeedIdChange[] memory _feedIdChanges);

    /**
     * @notice Calculates the fee for fetching a feed
     * @param _feedId The id of the feed
     * @return _fee The fee for fetching the feed
     */
    function calculateFeeById(bytes21 _feedId) external view returns (uint256 _fee);

    /**
     * @notice Calculates the fee for fetching feeds
     * @param _feedIds The list of feed ids
     * @return _fee The fee for fetching the feeds
     */
    function calculateFeeByIds(bytes21[] memory _feedIds) external view returns (uint256 _fee);

    /**
     * @notice Returns stored data of a feed
     * @param _feedId The id of the feed
     * @return _value The value for the requested feed
     * @return _decimals The decimal places for the requested feed
     * @return _timestamp The timestamp of the last update
     */
    function getFeedById(bytes21 _feedId)
        external payable
        returns (
            uint256 _value,
            int8 _decimals,
            uint64 _timestamp
        );

    /**
     * @notice Returns stored data of each feed
     * @param _feedIds The list of feed ids
     * @return _values The list of values for the requested feeds
     * @return _decimals The list of decimal places for the requested feeds
     * @return _timestamp The timestamp of the last update
     */
    function getFeedsById(bytes21[] memory _feedIds)
        external payable
        returns (
            uint256[] memory _values,
            int8[] memory _decimals,
            uint64 _timestamp
        );

    /**
     * @notice Returns value in wei and timestamp of a feed
     * @param _feedId The id of the feed
     * @return _value The value for the requested feed in wei
     * @return _timestamp The timestamp of the last update
     */
    function getFeedByIdInWei(bytes21 _feedId)
        external payable
        returns (
            uint256 _value,
            uint64 _timestamp
        );

    /**
     * @notice Returns value of each feed and a timestamp
     * @param _feedIds Ids of the feeds
     * @return _values The list of values for the requested feeds in wei
     * @return _timestamp The timestamp of the last update
     */
    function getFeedsByIdInWei(bytes21[] memory _feedIds)
        external payable
        returns (
            uint256[] memory _values,
            uint64 _timestamp
        );

    /**
     * @notice Checks if the feed data is valid
     * @param _feedData Structure containing data about the feed and Merkle proof
     * @return true if the feed data is valid
     */
    function verifyFeedData(FeedDataWithProof calldata _feedData) external view returns (bool);
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

/**
 * @title OracleManager
 * @dev Manages oracle data for prediction markets
 * @notice This contract handles price feeds from both Chainlink and FTSO oracles
 */
contract OracleManager is Ownable {
    // ============ State Variables ============
    
    /// @notice FTSO V2 interface
    FtsoV2Interface public ftso;

    /// @notice Market structure
    struct Market {
        address marketMaker;
        uint256 outcomeSlotCount;
        bytes32[] tokens;
        bool isClosed;
    }

    /// @notice Staleness period for each oracle
    mapping(bytes21 => uint256) public staleness;
    
    /// @notice Oracle ID for each token
    mapping(bytes32 => bytes21) public oracleForToken;
    
    /// @notice Market data for each question
    mapping(string => Market) public market;

    // ============ Constructor ============
    
    /**
     * @notice Constructor for OracleManager
     * @param ftsoV2Address The address of the FTSO V2 contract
     */
    constructor(address ftsoV2Address) Ownable(msg.sender) {
        ftso = FtsoV2Interface(ftsoV2Address);
    }

    // ============ External Functions ============
    
    /**
     * @notice Adds a new oracle for a token
     * @param token The token identifier
     * @param id The oracle feed ID
     * @param staleness_ The staleness period in seconds
     */
    function addOracle(bytes32 token, bytes21 id, uint256 staleness_) external onlyOwner {
        require(oracleForToken[token] == bytes21(0), "Oracle already exists");
        oracleForToken[token] = id;
        staleness[id] = staleness_;
    }

    /**
     * @notice Registers a new market
     * @param question The market question
     * @param marketMaker The market maker contract address
     * @param outcomeSlotCount The number of possible outcomes
     * @param tokens Array of token identifiers for price feeds
     */
    function registreNewMarket(
        string calldata question,
        address marketMaker,
        uint256 outcomeSlotCount,
        bytes32[] calldata tokens
    ) external onlyOwner {
        require(market[question].marketMaker == address(0), "Market already exists");
        market[question] = Market(marketMaker, outcomeSlotCount, tokens, false);
    }

 
    /**
     * @notice Closes market using FTSO oracle data
     * @param question The market question
     * @return results Array of payout numerators
     */
    function closeMarket_ftso(string calldata question) external returns (uint256[] memory results) {
        require(!market[question].isClosed, "Market already closed");
        require(market[question].outcomeSlotCount > 1, "Market must have more than one outcome slot");

        Market memory currentMarket = market[question];
        uint256[] memory values = new uint256[](currentMarket.outcomeSlotCount);
        uint8[] memory decimals = new uint8[](currentMarket.outcomeSlotCount);
        uint8 maxDecimals = 0;
        uint64 currentTimestamp = uint64(block.timestamp);
        
        // Get price data from FTSO for each token
        for (uint256 i = 0; i < currentMarket.outcomeSlotCount; i++) {
            bytes21 id = oracleForToken[currentMarket.tokens[i]];
            require(id != bytes21(0), "Oracle not found");
            
            (uint256 value, int8 decimals_, uint64 timestamp) = ftso.getFeedById(id);
            require(currentTimestamp - timestamp <= staleness[id], "Oracle data is stale");
            
            values[i] = value;
            decimals[i] = uint8(decimals_);
            
            if (uint8(decimals_) > maxDecimals) {
                maxDecimals = uint8(decimals_);
            }
        }
        
        // Normalize values to same decimal precision
        uint256 denominator = 0;
        for (uint256 i = 0; i < currentMarket.outcomeSlotCount; i++) {
            values[i] = values[i] * 10**(maxDecimals - decimals[i]);
            denominator += values[i];
        }
        
        // Calculate payout ratios
        results = new uint256[](currentMarket.outcomeSlotCount);
        for (uint256 i = 0; i < currentMarket.outcomeSlotCount; i++) {
            results[i] = values[i] * (10**maxDecimals) / denominator;
        }
        
        // Mark market as closed and notify market maker
        market[question].isClosed = true;
        IMarketMaker(currentMarket.marketMaker).closeMarket(results);
    }
}