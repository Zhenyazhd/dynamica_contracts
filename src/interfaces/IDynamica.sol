// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin-contracts/token/ERC20/IERC20.sol";

/**
 * @title IDynamica
 * @dev Interface for a simple prediction market maker contract that allows users to buy and sell outcome tokens
 * @notice This interface defines the basic market making mechanism for binary outcomes
 */
interface IDynamica {
    // ============ Constants ============
    
    /// @notice Maximum fee that can be set (100%)
    function FEE_RANGE() external pure returns (uint64);

    // ============ Events ============
    
    /// @notice Emitted when the market maker is created
    event MarketMakerCreated(uint256 initialFunding);
    
    /// @notice Emitted when funding is changed
    event startFunding(uint256 startFunding, uint256 outcomeTokenAmounts);
    
    /// @notice Emitted when fee is changed
    event FeeChanged(uint64 newFee);
    
    /// @notice Emitted when fees are withdrawn
    event FeeWithdrawal(uint256 fees);
    
    /// @notice Emitted when a trade is made
    event OutcomeTokenTrade(
        address indexed trader,
        int256[] outcomeTokenAmounts,
        int256 outcomeTokenNetCost,
        uint256 marketFees
    );

    /// @notice Emitted when a condition is prepared
    event ConditionPreparation(
        address indexed oracle,
        string indexed question,
        uint256 outcomeSlotCount
    );

    /// @notice Emitted when payout is redeemed
    event PayoutRedemption(
        address indexed redeemer,
        IERC20 indexed collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 conditionId,
        uint256[] indexSets,
        uint256 payout
    );

    /// @notice Emitted when market shares are sent to owner
    event SendMarketsSharesToOwner(uint256 returnToOwner);

    // ============ Structs ============
    
    struct Config {
        address owner; 
        address collateralToken;
        address oracle;
        string  question;
        uint256 outcomeSlotCount;
        uint256 startFunding;
        uint256 outcomeTokenAmounts;
        uint64  fee;
        uint256 alpha;
        uint256 expLimit;
    }

    // ============ State Variables ============
    
    /// @notice Array of payout numerators for each outcome
    function payoutNumerators(uint256) external view returns (uint256);
    
    /// @notice Payout denominator
    function payoutDenominator() external view returns (uint256);
    
    /// @notice The collateral token used for trading
    function collateralToken() external view returns (IERC20);
    
    /// @notice The question that this prediction market resolves
    function question() external view returns (string memory);
    
    /// @notice The fee rate (in basis points)
    function fee() external view returns (uint64);
    
    /// @notice Total funding in the market
    function funding() external view returns (uint256);
    
    /// @notice Total fees received
    function feeReceived() external view returns (uint256);
    
    /// @notice Array of outcome token amounts in the pool
    function outcomeTokenAmounts(uint256) external view returns (uint256);

    /// @notice Oracle manager address
    function oracleManager() external view returns (address);
    
    /// @notice Mapping from user address to their shares for each outcome
    function userShares(address, uint256) external view returns (int256);
    
    /// @notice Number of outcome slots
    function outcomeSlotCount() external view returns (uint256);

    // ============ External Functions ============
    
    /**
     * @notice Makes a prediction by buying or selling outcome tokens
     * @param deltaOutcomeAmounts_ Array of token amount changes for each outcome
     */
    function makePrediction(int256[] calldata deltaOutcomeAmounts_) external;
    
    /**
     * @notice Closes the market by resolving the condition
     * @param payouts Array of payout numerators for each outcome
     */
    function closeMarket(uint256[] calldata payouts) external;

    /**
     * @notice Redeems payout for resolved condition
     */
    function redeemPayout() external;

    // ============ Public Functions ============
    
    /**
     * @notice Calculates the net cost for a trade
     * @param outcomeTokenAmounts Array of token amount changes
     * @return netCost The net cost of the trade
     */
    function calcNetCost(int256[] memory outcomeTokenAmounts) external view returns (int256);
    
    /**
     * @notice Changes the fee rate
     * @param _fee The new fee rate
     */
    function changeFee(uint64 _fee) external;
    
    /**
     * @notice Withdraws accumulated fees
     */
    function withdrawFee() external;
}