// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "./IERC20.sol";

/**
 * @title IDynamica
 * @dev Interface for a simple prediction market maker contract that allows users to buy and sell outcome tokens
 * @notice This interface defines the basic market making mechanism for binary outcomes
 */
interface IDynamica {
    // ============ Events ============

    event MarketMakerCreated(uint256 initialFunding);
    event startFunding(uint256 startFunding, int64 outcomeTokenAmounts);
    event FeeChanged(uint64 newFee);
    event FeeWithdrawal(uint256 fees);
    event OutcomeTokenTrade(
        address indexed trader, int64[] outcomeTokenAmounts, int256 outcomeTokenNetCost, uint256 marketFees
    );
    event ConditionPreparation(address indexed oracle, string indexed question, uint256 outcomeSlotCount);
    event PayoutRedemption(address indexed redeemer, IERC20 indexed collateralToken, string question, uint256 payout);
    event SendMarketsSharesToOwner(uint256 returnToOwner);

    // ============ Errors ============

    error CollateralTokenDecimalsTooHigh(uint8 providedDecimals);
    error InvalidOutcomeIndex(uint256 providedIndex, uint256 maxIndex);
    error ZeroLiquidityParameter();
    error ZeroSum();
    error InvalidDeltaOutcomeAmountsLength(uint256 providedLength, uint256 expectedLength);
    error NegativeOutcomeAmount(int256 amount);
    error MarketAlreadyResolved();
    error MarketNotResolved();
    error OnlyOracleManager(address caller);
    error TransferFailed();
    error MustHaveExactlyOutcomeSlotCount(uint256 provided, uint256 expected);
    error ConditionNotPreparedOrFound();
    error PayoutIsAllZeroes();
    error PayoutNumeratorAlreadySet(uint256 index);
    error NothingToRedeem();
    error FeeMustBeLessThanRange(uint64 provided, uint64 max);
    error NoFeesToWithdraw();
    error InsufficientSharesToSell(address user, uint256 required, uint256 available);
    error FeeTransferFailed();
    error ReturnToOwnerTransferFailed();
    error FailedToCreateToken();
    error FailedToMintToken();
    error FailedToBurnToken();
    error FailedToTransferToken();

    // ============ Structs ============

    struct Config {
        address owner;
        address collateralToken;
        address oracle;
        int32 decimals;
        string question;
        uint256 outcomeSlotCount;
        uint256 startFunding;
        int64 outcomeTokenAmounts;
        uint64 fee;
        int256 alpha;
        int256 expLimit;
    }

    // ============ Constants ============

    function FEE_RANGE() external pure returns (uint64);

    // ============ State Variables ============

    function payoutNumerators(uint256) external view returns (uint256);
    function outcomeTokenSupplies(uint256) external view returns (int256);
    function payoutDenominator() external view returns (uint256);
    function collateralToken() external view returns (IERC20);
    function question() external view returns (string memory);
    function fee() external view returns (uint64);
    function feeReceived() external view returns (uint256);
    function oracleManager() external view returns (address);
    function outcomeSlotCount() external view returns (uint256);

    // ============ External Functions ============

    function makePrediction(int64[] calldata deltaOutcomeAmounts_) external;
    function closeMarket(uint256[] calldata payouts) external;
    function redeemPayout() external;

    // ============ Public Functions ============

    function calcNetCost(int64[] memory outcomeTokenAmounts) external view returns (int256);
    function changeFee(uint64 _fee) external;
    function withdrawFee() external;
}