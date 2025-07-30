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

    /// @notice Emitted when the market is initialized
    /// @param initialFunding The initial funding amount
    /// @param question The market question
    /// @param perOutcomeAmount The amount per outcome
    event MarketInitialized(uint256 indexed initialFunding, string indexed question, int64 perOutcomeAmount);

    /// @notice Emitted when a new outcome token is created
    /// @param tokenAddress The address of the created token
    /// @param outcomeIndex The index of the outcome
    event TokenCreated(address indexed tokenAddress, uint8 outcomeIndex);

    /// @notice Emitted when a trade is made
    /// @param trader The address of the trader
    /// @param outcomeTokenAmounts The amounts for each outcome
    /// @param outcomeTokenNetCost The net cost of the trade
    /// @param marketFees The market fees charged
    event OutcomeTokenTrade(
        address indexed trader,
        int64[] outcomeTokenAmounts,
        int256 outcomeTokenNetCost,
        uint256 marketFees
    );

    /// @notice Emitted when the market is resolved
    /// @param resolver The address that resolved the market
    /// @param payouts The payout numerators for each outcome
    /// @param denominator The payout denominator
    event MarketResolved(address indexed resolver, uint256[] payouts, uint256 denominator);

    /// @notice Emitted when a payout is redeemed
    /// @param redeemer The address redeeming payout
    /// @param collateralToken The collateral token address
    /// @param question The market question
    /// @param payout The payout amount
    event PayoutRedemption(address indexed redeemer, address indexed collateralToken, string indexed question, uint256 payout);

    /// @notice Emitted when the fee is changed
    /// @param timestamp The time of the change
    /// @param newFee The new fee value
    event FeeChanged(uint256 timestamp, uint64 newFee);

    /// @notice Emitted when fees are withdrawn
    /// @param timestamp The time of withdrawal
    /// @param fees The amount withdrawn
    event FeeWithdrawal(uint256 timestamp, uint256 fees);

    /// @notice Emitted when market shares are sent to owner
    /// @param timestamp The time of the transfer
    /// @param returnToOwner The amount returned to owner
    event SendMarketsSharesToOwner(uint256 timestamp, uint256 returnToOwner);

    /// @notice Emitted when tokens are minted
    /// @param to The address receiving tokens
    /// @param token The token address
    /// @param amount The amount minted
    event TokenMinted(address indexed to, address indexed token, int64 amount);

    /// @notice Emitted when tokens are burned
    /// @param from The address burning tokens
    /// @param token The token address
    /// @param amount The amount burned
    event TokenBurned(address indexed from, address indexed token, int64 amount);

    // ============ Errors ============

    /// @notice Thrown if collateral token decimals are too high
    error CollateralTokenDecimalsTooHigh(uint8 providedDecimals);
    /// @notice Thrown if an invalid outcome index is provided
    error InvalidOutcomeIndex(uint256 providedIndex, uint256 maxIndex);
    /// @notice Thrown if the liquidity parameter is zero
    error ZeroLiquidityParameter();
    /// @notice Thrown if the sum is zero
    error ZeroSum();
    /// @notice Thrown if the delta outcome amounts length is invalid
    error InvalidDeltaOutcomeAmountsLength(uint256 providedLength, uint256 expectedLength);
    /// @notice Thrown if a negative outcome amount is provided
    error NegativeOutcomeAmount(int256 amount);
    /// @notice Thrown if the market is already resolved
    error MarketAlreadyResolved();
    /// @notice Thrown if the market is not resolved
    error MarketNotResolved();
    /// @notice Thrown if only the oracle manager can call
    error OnlyOracleManager(address caller);
    /// @notice Thrown if a transfer fails
    error TransferFailed();
    /// @notice Thrown if the outcome slot count does not match
    error MustHaveExactlyOutcomeSlotCount(uint256 provided, uint256 expected);
    /// @notice Thrown if the condition is not prepared or found
    error ConditionNotPreparedOrFound();
    /// @notice Thrown if all payouts are zero
    error PayoutIsAllZeroes();
    /// @notice Thrown if a payout numerator is already set
    error PayoutNumeratorAlreadySet(uint256 index);
    /// @notice Thrown if there is nothing to redeem
    error NothingToRedeem();
    /// @notice Thrown if the fee is not less than the range
    error FeeMustBeLessThanRange(uint64 provided, uint64 max);
    /// @notice Thrown if there are no fees to withdraw
    error NoFeesToWithdraw();
    /// @notice Thrown if the user has insufficient shares to sell
    error InsufficientSharesToSell(address user, uint256 required, uint256 available);
    error InsufficientSharesToSell_(address user, int64 required, int64 available);
    /// @notice Thrown if the fee transfer fails
    error FeeTransferFailed();
    /// @notice Thrown if the return to owner transfer fails
    error ReturnToOwnerTransferFailed();
    /// @notice Thrown if token creation fails
    error FailedToCreateToken();
    /// @notice Thrown if token minting fails
    error FailedToMintToken();
    /// @notice Thrown if token burning fails
    error FailedToBurnToken();
    /// @notice Thrown if token transfer fails
    error FailedToTransferToken();
    /// @notice Thrown if the return to owner transfer fails
    error NotEnoughCollateralToCoverPayouts(uint256 shortfall);

    // ============ Structs ============

    /// @notice Market configuration struct
    struct Config {
        address owner; ///< Owner of the market
        address collateralToken; ///< Collateral token address
        address oracle; ///< Oracle address
        int32 decimals; ///< Decimals for outcome tokens
        string question; ///< Market question
        uint256 outcomeSlotCount; ///< Number of outcomes
        uint256 startFunding; ///< Initial funding
        int64 outcomeTokenAmounts; ///< Amount per outcome
        uint64 fee; ///< Fee in basis points
        int256 alpha; ///< Alpha parameter for LMSR
        int256 expLimit; ///< Exponential limit
        uint32 expirationTime; ///< Expiration time
        uint32 gamma; 
    }

    // ============ Constants ============

    /// @notice Returns the maximum fee range
    function FEE_RANGE() external pure returns (uint64);

    // ============ State Variables ============

    /// @notice Returns the payout numerator for an outcome
    function payoutNumerators(uint256) external view returns (uint256);
    /// @notice Returns the supply for an outcome token
    function outcomeTokenSupplies(uint256) external view returns (int256);
    /// @notice Returns the payout denominator
    function payoutDenominator() external view returns (uint256);
    /// @notice Returns the collateral token address
    function collateralToken() external view returns (address);
    /// @notice Returns the market question
    function question() external view returns (string memory);
    /// @notice Returns the fee
    function fee() external view returns (uint64);
    /// @notice Returns the total fees received
    function feeReceived() external view returns (uint256);
    /// @notice Returns the oracle manager address
    function oracleManager() external view returns (address);
    /// @notice Returns the number of outcome slots
    function outcomeSlotCount() external view returns (uint256);

    // ============ External Functions ============

    /// @notice Makes a prediction by buying or selling outcome tokens
    /// @param deltaOutcomeAmounts_ Array of token amount changes for each outcome
    function makePrediction(int64[] calldata deltaOutcomeAmounts_) external;

    /// @notice Closes the market by resolving the condition
    /// @param payouts Array of payout numerators for each outcome
    function closeMarket(uint256[] calldata payouts) external;

    /// @notice Redeems payout for resolved condition
    function redeemPayout() external;

    // ============ Public Functions ============

    /// @notice Calculates the net cost for a trade
    /// @param outcomeTokenAmounts Array of token amount changes
    /// @return netCost The net cost of the trade
    function calcNetCost(int64[] memory outcomeTokenAmounts) external view returns (int256);

    /// @notice Changes the fee rate
    /// @param _fee The new fee rate
    function changeFee(uint64 _fee) external;

    /// @notice Withdraws accumulated fees
    function withdrawFee() external;
}