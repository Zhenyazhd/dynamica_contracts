// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AggregatorV3Interface} from "smartcontractkit-chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title MockAggregator
 * @dev Mock implementation of AggregatorV3Interface for testing purposes
 */
contract MockAggregator is AggregatorV3Interface {
    int256 private _price;
    uint8 private _decimals;
    string private _description;
    uint256 private _version;
    uint256 private _updatedAt;
    uint80 private _roundId;

    constructor(
        int256 price,
        uint8 decimals,
        string memory description,
        uint256 version
    ) {
        _price = price;
        _decimals = decimals;
        _description = description;
        _version = version;
        _updatedAt = block.timestamp;
        _roundId = 1;
    }

    /**
     * @dev Set the price for testing
     */
    function setPrice(int256 price) external {
        _price = price;
        _updatedAt = block.timestamp;
        _roundId++;
    }

    /**
     * @dev Set the timestamp for testing
     */
    function setUpdatedAt(uint256 timestamp) external {
        _updatedAt = timestamp;
    }

    /**
     * @dev Get the latest round data
     */
    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _price, _updatedAt, block.timestamp - 1, _roundId);
    }

    /**
     * @dev Get the number of decimals
     */
    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Get the description
     */
    function description() external view override returns (string memory) {
        return _description;
    }

    /**
     * @dev Get the version
     */
    function version() external view override returns (uint256) {
        return _version;
    }

    /**
     * @dev Get round data by round ID (not implemented for mock)
     */
    function getRoundData(uint80 _id)
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        revert("MockAggregator: getRoundData not implemented");
    }
} 