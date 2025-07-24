// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {FtsoV2Interface} from "flare-periphery/src/flare/FtsoV2Interface.sol";

/**
 * @title MockFtsoV2
 * @dev Mock implementation of FtsoV2Interface for testing purposes
 */
contract MockFtsoV2 is FtsoV2Interface {
    mapping(bytes21 => uint256) private _feedValues;
    mapping(bytes21 => int8) private _feedDecimals;
    mapping(bytes21 => uint64) private _feedTimestamps;
    bytes21[] private _supportedFeedIds;
    uint256 private _protocolId;

    constructor(uint256 protocolId) {
        _protocolId = protocolId;
    }

    /**
     * @dev Set feed data for testing
     */
    function setFeedData(bytes21 feedId, uint256 value, int8 decimals, uint64 timestamp) external {
        _feedValues[feedId] = value;
        _feedDecimals[feedId] = decimals;
        _feedTimestamps[feedId] = timestamp;

        // Add to supported feed ids if not already present
        bool exists = false;
        for (uint256 i = 0; i < _supportedFeedIds.length; i++) {
            if (_supportedFeedIds[i] == feedId) {
                exists = true;
                break;
            }
        }
        if (!exists) {
            _supportedFeedIds.push(feedId);
        }
    }

    /**
     * @dev Get the FTSO protocol id
     */
    function getFtsoProtocolId() external view override returns (uint256) {
        return _protocolId;
    }

    /**
     * @dev Get supported feed ids
     */
    function getSupportedFeedIds() external view override returns (bytes21[] memory) {
        return _supportedFeedIds;
    }

    /**
     * @dev Get feed id changes (empty for mock)
     */
    function getFeedIdChanges() external pure override returns (FeedIdChange[] memory) {
        return new FeedIdChange[](0);
    }

    /**
     * @dev Calculate fee for fetching a feed (returns 0 for mock)
     */
    function calculateFeeById(bytes21) external pure override returns (uint256) {
        return 0;
    }

    /**
     * @dev Calculate fee for fetching feeds (returns 0 for mock)
     */
    function calculateFeeByIds(bytes21[] memory) external pure override returns (uint256) {
        return 0;
    }

    /**
     * @dev Get feed data by id
     */
    function getFeedById(bytes21 _feedId)
        external
        payable
        override
        returns (uint256 _value, int8 _decimals, uint64 _timestamp)
    {
        return (_feedValues[_feedId], _feedDecimals[_feedId], _feedTimestamps[_feedId]);
    }

    /**
     * @dev Get feeds data by ids
     */
    function getFeedsById(bytes21[] memory _feedIds)
        external
        payable
        override
        returns (uint256[] memory _values, int8[] memory _decimals, uint64 _timestamp)
    {
        _values = new uint256[](_feedIds.length);
        _decimals = new int8[](_feedIds.length);

        for (uint256 i = 0; i < _feedIds.length; i++) {
            _values[i] = _feedValues[_feedIds[i]];
            _decimals[i] = _feedDecimals[_feedIds[i]];
        }

        // Return the latest timestamp among all feeds
        _timestamp = 0;
        for (uint256 i = 0; i < _feedIds.length; i++) {
            if (_feedTimestamps[_feedIds[i]] > _timestamp) {
                _timestamp = _feedTimestamps[_feedIds[i]];
            }
        }
    }

    /**
     * @dev Get feed value in wei by id
     */
    function getFeedByIdInWei(bytes21 _feedId) external payable override returns (uint256 _value, uint64 _timestamp) {
        uint256 baseValue = _feedValues[_feedId];
        int8 decimals = _feedDecimals[_feedId];

        // Convert to wei (18 decimals)
        if (decimals < 18) {
            _value = baseValue * (10 ** (18 - uint8(decimals)));
        } else if (decimals > 18) {
            _value = baseValue / (10 ** (uint8(decimals) - 18));
        } else {
            _value = baseValue;
        }

        _timestamp = _feedTimestamps[_feedId];
    }

    /**
     * @dev Get feeds values in wei by ids
     */
    function getFeedsByIdInWei(bytes21[] memory _feedIds)
        external
        payable
        override
        returns (uint256[] memory _values, uint64 _timestamp)
    {
        _values = new uint256[](_feedIds.length);

        for (uint256 i = 0; i < _feedIds.length; i++) {
            uint256 baseValue = _feedValues[_feedIds[i]];
            int8 decimals = _feedDecimals[_feedIds[i]];

            // Convert to wei (18 decimals)
            if (decimals < 18) {
                _values[i] = baseValue * (10 ** (18 - uint8(decimals)));
            } else if (decimals > 18) {
                _values[i] = baseValue / (10 ** (uint8(decimals) - 18));
            } else {
                _values[i] = baseValue;
            }
        }

        // Return the latest timestamp among all feeds
        _timestamp = 0;
        for (uint256 i = 0; i < _feedIds.length; i++) {
            if (_feedTimestamps[_feedIds[i]] > _timestamp) {
                _timestamp = _feedTimestamps[_feedIds[i]];
            }
        }
    }

    /**
     * @dev Verify feed data (always returns true for mock)
     */
    function verifyFeedData(FeedDataWithProof calldata) external pure override returns (bool) {
        return true;
    }
}