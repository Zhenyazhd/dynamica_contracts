// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MarketMaker
 * @dev A simple prediction market maker contract that allows users to buy and sell outcome tokens
 * @notice This contract implements a basic market making mechanism for prediction markets
 */
contract MarketMaker is Ownable {
    // ============ Constants ============
    
    /// @notice Maximum fee that can be set (100%)
    uint64 public constant FEE_RANGE = 10_000;

    // ============ Events ============
    
    /// @notice Emitted when the market maker is created
    event MarketMakerCreated(uint256 initialFunding);
    
    /// @notice Emitted when funding is changed
    event FundingChanged(uint256 fundingChange, uint256 outcomeTokenAmounts);
    
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

    // ============ State Variables ============
    
    /// @notice Array of payout numerators for each outcome
    uint256[] public payoutNumerators;
    
    /// @notice Payout denominator
    uint256 public payoutDenominator;
    
    /// @notice The collateral token used for trading
    IERC20 public collateralToken;
    
    /// @notice The question that this prediction market resolves
    string public question;
    
    /// @notice The fee rate (in basis points)
    uint64 public fee;
    
    /// @notice Total funding in the market
    uint256 public funding;
    
    /// @notice Total fees received
    uint256 public feeReceived;
    
    /// @notice Array of outcome token amounts in the pool
    uint256[] public outcomeTokenAmounts;

    /// @notice Oracle address that can resolve the market
    address public oracleManager;
    
    /// @notice Mapping from user address to their shares for each outcome
    mapping(address => int256[]) public userShares;
    
    /// @notice Number of outcome slots
    uint256 public outcomeSlotCount;

    // ============ Constructor ============
    
    /**
     * @notice Constructor for MarketMaker
     * @param _collateralToken The collateral token to use
     * @param _fee The fee rate (must be less than FEE_RANGE)
     */
    constructor(IERC20 _collateralToken, uint64 _fee) Ownable(msg.sender) {
        require(_fee < FEE_RANGE, "Fee must be less than FEE_RANGE");
        require(address(_collateralToken) != address(0), "Invalid collateral token");
        
        collateralToken = _collateralToken;
        fee = _fee;
        
        emit MarketMakerCreated(0);
    }

    // ============ External Functions ============
    
    /**
     * @notice Prepares a condition for trading
     * @param oracle The oracle address that will resolve the condition
     * @param _question The question text that this market resolves
     * @param _outcomeSlotCount The number of possible outcomes
     */
    function prepareCondition(
        address oracle,
        string calldata _question,
        uint256 _outcomeSlotCount
    ) external {
        require(_outcomeSlotCount <= 5, "Too many outcome slots");
        require(_outcomeSlotCount > 1, "Must have more than one outcome slot");
        require(oracle != address(0), "Invalid oracle address");
        require(bytes(_question).length > 0, "Question cannot be empty");
        require(payoutNumerators.length == 0, "Condition already prepared");
        
        oracleManager = oracle;
        question = _question;
        outcomeSlotCount = _outcomeSlotCount;
        
        payoutNumerators = new uint256[](_outcomeSlotCount);
        outcomeTokenAmounts = new uint256[](_outcomeSlotCount);
        
        emit ConditionPreparation(oracle, question, _outcomeSlotCount);
    }

    /**
     * @notice Initializes the market with funding
     * @param fundingChange The amount of funding to add
     * @param outcomeTokenAmounts_ The initial token amounts for each outcome
     */
    function initializeMarket(uint256 fundingChange, uint256 outcomeTokenAmounts_) external onlyOwner {
        require(fundingChange != 0, "Funding change must be non-zero");
        require(collateralToken.transferFrom(msg.sender, address(this), fundingChange), "Transfer failed");
        
        funding += fundingChange;
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            outcomeTokenAmounts[i] = outcomeTokenAmounts_;
        }
        
        emit FundingChanged(fundingChange, outcomeTokenAmounts_);
    }

    /**
     * @notice Makes a prediction by buying or selling outcome tokens
     * @param deltaOutcomeAmounts_ Array of token amount changes for each outcome
     */
    function makePrediction(int256[] calldata deltaOutcomeAmounts_) external {
        require(deltaOutcomeAmounts_.length == outcomeSlotCount, "Invalid outcome amount length");
        
        // Initialize user shares array if needed
        if (userShares[msg.sender].length == 0) {
            userShares[msg.sender] = new int256[](outcomeSlotCount);
        }
        
        // Check if user has enough shares to sell
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            if (deltaOutcomeAmounts_[i] < 0) {
                require(
                    userShares[msg.sender][i] >= -deltaOutcomeAmounts_[i],
                    "Insufficient shares to sell"
                );
            }
        }
        
        // Calculate net cost of the trade
        int256 netCost = calcNetCost(deltaOutcomeAmounts_);
        
        // Handle fee calculation and token transfers
        uint256 feeAmount = 0;
        if (netCost > 0) {
            // User is buying - they need to pay
            uint256 shouldPay = uint256(netCost) * FEE_RANGE / (FEE_RANGE - fee);
            feeReceived += (shouldPay - uint256(netCost));
            require(
                collateralToken.transferFrom(msg.sender, address(this), uint256(netCost)),
                "Transfer failed"
            );
        } else {
            // User is selling - they receive payout
            uint256 absoluteNetCost = uint256(-netCost);
            feeAmount = absoluteNetCost * fee / FEE_RANGE;
            feeReceived += feeAmount;
            uint256 payoutAmount = absoluteNetCost - feeAmount;
            require(collateralToken.transfer(msg.sender, payoutAmount), "Transfer failed");
        }
        
        // Update token amounts in pool
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            if (deltaOutcomeAmounts_[i] > 0) {
                outcomeTokenAmounts[i] += uint256(deltaOutcomeAmounts_[i]);
            } else {
                outcomeTokenAmounts[i] -= uint256(-deltaOutcomeAmounts_[i]);
            }
        }
        
        // Update user shares
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            userShares[msg.sender][i] += deltaOutcomeAmounts_[i];
        }
        
        emit OutcomeTokenTrade(msg.sender, deltaOutcomeAmounts_, netCost, feeAmount);
    }
    
    /**
     * @notice Closes the market by resolving the condition
     * @param payouts Array of payout numerators for each outcome
     */
    function closeMarket(uint256[] calldata payouts) external {
        require(oracleManager == msg.sender, "Only oracle manager can close the market");
        uint256 _outcomeSlotCount = payouts.length;
        require(_outcomeSlotCount == outcomeSlotCount, "Must have exactly outcomeSlotCount outcomes");
        require(payoutNumerators.length == _outcomeSlotCount, "Condition not prepared or found");
        require(payoutDenominator == 0, "Payout denominator already set");

        uint256 denominator = 0;
        for (uint256 i = 0; i < _outcomeSlotCount; i++) {
            uint256 numerator = payouts[i];
            denominator += numerator;

            require(payoutNumerators[i] == 0, "Payout numerator already set");
            payoutNumerators[i] = numerator;
        }
        
        require(denominator > 0, "Payout is all zeroes");
        payoutDenominator = denominator;
    }

    /**
     * @notice Redeems payout for resolved condition
     */
    function redeemPayout() external {
        uint256 denominator = payoutDenominator;
        require(denominator != 0, "Condition not resolved");

        uint256 n = outcomeSlotCount;
        int256[] storage shares = userShares[msg.sender];

        uint256 totalPayout = 0;
        for (uint256 i = 0; i < n; i++) {
            if (shares[i] <= 0 || payoutNumerators[i] == 0) continue;
            totalPayout += uint256(shares[i]) * payoutNumerators[i] / denominator;
            // Reset to prevent double redemption
            shares[i] = 0;
        }

        require(totalPayout > 0, "Nothing to redeem");
        require(collateralToken.transfer(msg.sender, totalPayout), "Transfer failed");

        emit PayoutRedemption(
            msg.sender,
            collateralToken,
            bytes32(0), // parentCollectionId
            bytes32(0), // conditionId
            new uint256[](0), // indexSets
            totalPayout
        );
    }

    // ============ Public Functions ============
    
    /**
     * @notice Calculates the net cost for a trade
     * @param outcomeTokenAmounts Array of token amount changes
     * @return netCost The net cost of the trade
     */
    function calcNetCost(int256[] memory outcomeTokenAmounts) public virtual view returns (int256 netCost) {
    }
    
    /**
     * @notice Changes the fee rate
     * @param _fee The new fee rate
     */
    function changeFee(uint64 _fee) external onlyOwner {
        require(_fee < FEE_RANGE, "Fee must be less than FEE_RANGE");
        fee = _fee;
        emit FeeChanged(fee);
    }
    
    /**
     * @notice Withdraws accumulated fees
     */
    function withdrawFee() external onlyOwner {
        require(feeReceived > 0, "No fees to withdraw");
        uint256 amount = feeReceived;
        feeReceived = 0; // Reset accumulated fees
        require(collateralToken.transfer(owner(), amount), "Fee transfer failed");
        emit FeeWithdrawal(amount);
    }
}