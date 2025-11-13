// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

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
    event MarketInitialized(uint256 indexed initialFunding, string indexed question, uint256 perOutcomeAmount);

    /// @notice Emitted when a trade is made
    /// @param trader The address of the trader
    /// @param outcomeTokenAmounts The amounts for each outcome
    /// @param outcomeTokenNetCost The net cost of the trade
    /// @param marketFees The market fees charged
    event OutcomeTokenTrade(
        address indexed trader, int256[] outcomeTokenAmounts, int256 outcomeTokenNetCost, uint256 marketFees
    );

    /// @notice Emitted when a payout is redeemed
    /// @param redeemer The address redeeming payout
    /// @param collateralToken The collateral token address
    /// @param question The market question
    /// @param payout The payout amount
    event PayoutRedemption(
        address indexed redeemer, address indexed collateralToken, string indexed question, uint256 payout
    );

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
    /// @param tokenId The token id
    /// @param amount The amount minted
    event TokenMinted(address indexed to, uint256 indexed tokenId, uint256 amount);

    /// @notice Emitted when tokens are burned
    /// @param from The address burning tokens
    /// @param tokenId The token id
    /// @param amount The amount burned
    event TokenBurned(address indexed from, uint256 indexed tokenId, uint256 amount);

    /// @notice Emitted when the contract is exited
    /// @param timestamp The time of the exit
    /// @param token The token withdrawn
    /// @param amount The amount exited
    event EmergencyExit(uint256 timestamp, address token, uint256 amount);

    /// @notice Emitted when the epoch is resolved
    /// @param resolver The address that resolved the epoch
    /// @param payouts The payout numerators for each outcome
    /// @param denominator The payout denominator
    event EpochResolved(address indexed resolver, uint256[] payouts, uint256 denominator);

    /// @notice Emitted when the expiration epoch is changed
    /// @param newExpirationEpoch The new expiration epoch
    /// @param timestamp The time of the change
    event ExpirationEpochChanged(uint32 newExpirationEpoch, uint256 timestamp);

    /// @notice Emitted when the epoch and period are updated
    /// @param epoch The epoch number
    /// @param period The period number
    event EpochAndPeriodUpdated(uint32 epoch, uint32 period);

    /// @notice Emitted when tokens are unblocked
    /// @param user The address of the user
    /// @param deltaOutcomeAmounts_ Array of token amount changes for each outcome
    /// @param epoch The epoch number
    /// @param period The period number
    event TokensUnblocked(address indexed user, uint256[] deltaOutcomeAmounts_, uint32 epoch, uint32 period);

    /// @notice Emitted when a user claims tokens for a new epoch
    /// @param user The address of the user
    /// @param deltaOutcomeAmounts Array of token amount changes for each outcome
    /// @param epoch The epoch number
    /// @param period The period number
    event ClaimForNewEpoch(address indexed user, int256[] deltaOutcomeAmounts, uint32 epoch, uint32 period);

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
    error InvalidLength(uint256 providedLength, uint256 expectedLength);
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
    /// @notice Thrown if all payouts are zero
    error PayoutIsAllZeroes();
    /// @notice Thrown if there is nothing to redeem
    error NothingToRedeem();
    /// @notice Thrown if the fee is not less than the range
    error FeeMustBeLessThanRange(uint64 provided, uint64 max);
    /// @notice Thrown if the problem with balance
    error InsufficientBalance(uint256 available, uint256 required);
    /// @notice Thrown if the epoch is finished but not resolved yet
    error EpochFinishedButNotResolvedYet(uint32 epoch);
    /// @notice Thrown if the market is expired
    error MarketExpired();
    /// @notice Thrown if the new expiration epoch is less than the current epoch
    error NewExpirationEpochMustBeGreaterThanCurrentEpoch(uint32 newExpirationEpoch, uint32 currentEpoch);

    // ============ Structs ============

    /// @notice Market configuration struct
    struct Config {
        /// @notice Owner of the market
        address owner;
        /// @notice Collateral token address
        address collateralToken;
        /// @notice Oracle address
        address oracle;
        /// @notice Decimals for outcome tokens
        uint8 decimals;
        /// @notice Market question
        string question;
        /// @notice Number of outcomes
        uint256 outcomeSlotCount;
        /// @notice Initial funding
        uint256 startFunding;
        /// @notice Amount per outcome
        uint256 outcomeTokenAmounts;
        /// @notice Fee in basis points
        uint64 fee;
        /// @notice Alpha parameter for LMSR
        int256 alpha;
        /// @notice Exponential limit
        int256 expLimit;
        /// @notice Expiration time
        uint32 expirationEpoch;
        /// @notice Fee adjustment parameter
        uint32 gamma;
        /// @notice Duration of each epoch
        uint32 epochDuration;
        /// @notice Duration of each period
        uint32 periodDuration;
    }

    /// @notice Structure to store epoch-specific data
    struct EpochData {
        /// @notice Start timestamp of the epoch
        uint32 epochStart;
        /// @notice Payout denominator for calculating final payouts
        uint256 payoutDenominator;
        /// @notice Funding for the epoch
        uint256 funding;
        /// @notice Funding for rollover
        uint256 fundingForRollover;
        /// @notice Array of base prices for each outcome
        uint256[10] basePrice;
        /// @notice Array of payout numerators for each outcome
        uint256[10] payoutNumerators;
        /// @notice Array of supplies for each outcome token
        uint256[10] initialTokenSupply;
    }

    // ============ State Variables ============

    /// @notice Returns the payout numerator for an outcome
    function payoutNumerators(uint256, uint256) external view returns (uint256);
    /// @notice Returns the supply for an outcome token
    function outcomeTokenSupplies(uint256, uint256, uint256) external view returns (uint256);
    /// @notice Returns the payout denominator
    function payoutDenominator(uint256) external view returns (uint256);
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
    /// @notice Returns whether the current epoch should be checked
    function checkEpoch() external view returns (bool);
    /// @notice Returns the decimals for outcome tokens
    function decimals() external view returns (uint8);
    /// @notice Returns the current epoch number
    function currentEpochNumber() external view returns (uint32);
    /// @notice Returns the current period number
    function currentPeriodNumber() external view returns (uint32);
    /// @notice Returns the expiration epoch
    function expirationEpoch() external view returns (uint32);
    /// @notice Returns the epoch duration in seconds
    function epochDuration() external view returns (uint32);
    /// @notice Returns the period duration in seconds
    function periodDuration() external view returns (uint32);

    // ============ External Functions ============

    /// @notice Makes a prediction by buying or selling outcome tokens
    /// @param deltaOutcomeAmounts_ Array of token amount changes for each outcome
    function makePrediction(int256[] memory deltaOutcomeAmounts_, bool isRollover) external;

    /// @notice Closes the epoch by resolving the condition
    /// @param payouts Array of payout numerators for each outcome
    function closeEpoch(uint256[] calldata payouts) external returns (bool);

    /// @notice Redeems payout for resolved condition
    function redeemPayout(uint32 epoch) external;

    /// @notice Unblocks tokens for a given epoch and period
    /// @param deltaOutcomeAmounts_ Array of token amount changes for each outcome
    /// @param epochs Array of epochs
    /// @param periods Array of periods
    function unblockTokens(uint256[][] memory deltaOutcomeAmounts_, uint32[] memory epochs, uint32[] memory periods)
        external;

    /// @notice Claims tokens for a new epoch based on blocked tokens from previous epoch
    /// @param user The address of the user to claim for
    function claimForNewEpoch(address user) external;

    /// @notice Updates the current epoch and period based on elapsed time
    /// @dev Only callable by owner
    function updateEpochAndPeriod() external;

    /// @notice Changes the expiration epoch
    /// @param newExpirationEpoch The new expiration epoch
    /// @dev Only callable by owner
    function changeExpirationEpoch(uint32 newExpirationEpoch) external;

    /// @notice Emergency exit function to withdraw all tokens of a specific type
    /// @param token The address of the token to withdraw
    /// @dev Only callable by owner
    function emergencyExit(address token) external;

    // ============ Public Functions ============

    /// @notice Returns the supply for an outcome token per epoch
    /// @param epoch Epoch number
    /// @param outcomeSlot Outcome slot number
    /// @return The supply for the outcome token per epoch
    function outcomeTokenSuppliesPerEpoch(uint256 epoch, uint256 outcomeSlot) external view returns (uint256);

    /// @notice Changes the fee rate
    /// @param _fee The new fee rate
    function changeFee(uint64 _fee) external;

    /// @notice Withdraws accumulated fees
    function withdrawFee() external;

    /// @notice Returns the epoch data for a given epoch
    /// @param epoch The epoch number
    /// @return The epoch data
    function getEpochData(uint256 epoch) external view returns (EpochData memory);

    /// @notice Calculates the unique share ID for (epoch, period, outcome)
    /// @param epoch Epoch number
    /// @param period Period number
    /// @param outcome Outcome index
    /// @return The unique share ID
    function shareId(uint256 epoch, uint256 period, uint256 outcome) external view returns (uint256);

    /// @notice Decodes a share ID back into epoch, period, and outcome
    /// @param id The share ID to decode
    /// @return epoch Epoch number
    /// @return period Period number
    /// @return outcome Outcome index
    function decodeShareId(uint256 id) external view returns (uint256 epoch, uint256 period, uint256 outcome);
}
