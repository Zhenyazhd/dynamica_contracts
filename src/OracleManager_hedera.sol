// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";
import {AggregatorV3Interface} from
    "smartcontractkit-chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

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

    /// @notice Market structure
    struct Market {
        address marketMaker;
        uint256 outcomeSlotCount;
        bool isClosed;
    }

    /// @notice Market data for each question
    mapping(string => Market) public market;

    // ============ Constructor ============

    /**
     * @notice Constructor for OracleManager
     */
    constructor() Ownable(msg.sender) {}

    // ============ External Functions ============

    /**
     * @notice Registers a new market
     * @param question The market question
     * @param marketMaker The market maker contract address
     * @param outcomeSlotCount The number of possible outcomes
     */
    function registreNewMarket(string calldata question, address marketMaker, uint256 outcomeSlotCount)
        external
        onlyOwner
    {
        require(market[question].marketMaker == address(0), "Market already exists");
        market[question] = Market(marketMaker, outcomeSlotCount, false);
    }

    /**
     * @notice Closes market using Chainlink oracle data
     * @param question The market question
     * @return results Array of payout numerators
     */
    function closeMarket_chainlink(string calldata question) external returns (uint256[] memory results) {
        require(!market[question].isClosed, "Market already closed");
        require(market[question].outcomeSlotCount > 1, "Market must have more than one outcome slot");

        Market memory currentMarket = market[question];

        AggregatorV3Interface priceFeedETH = AggregatorV3Interface(0xb9d461e0b962aF219866aDfA7DD19C52bB9871b9); // ETH
        (, int256 priceETH,,,) = priceFeedETH.latestRoundData();
        uint256 decimalsETH = priceFeedETH.decimals();

        AggregatorV3Interface priceFeedBTC = AggregatorV3Interface(0x058fE79CB5775d4b167920Ca6036B824805A9ABd); // BTC
        (, int256 priceBTC,,,) = priceFeedBTC.latestRoundData();
        uint256 decimalsBTC = priceFeedBTC.decimals();

        // Create results array
        results = new uint256[](currentMarket.outcomeSlotCount);
        results[0] = uint256(priceETH) * 10 ** (18 - decimalsETH);
        results[1] = uint256(priceBTC) * 10 ** (18 - decimalsBTC);

        // Mark market as closed
        market[question].isClosed = true;
        IMarketMaker(currentMarket.marketMaker).closeMarket(results);
    }
}
