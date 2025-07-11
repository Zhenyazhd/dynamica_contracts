// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/*
██████╗ ██╗   ██╗███╗   ██╗ █████╗ ███╗   ███╗██╗ ██████╗ █████╗ 
██╔══██╗╚██╗ ██╔╝████╗  ██║██╔══██╗████╗ ████║██║██╔════╝██╔══██╗
██║  ██║ ╚████╔╝ ██╔██╗ ██║███████║██╔████╔██║██║██║     ███████║
██║  ██║  ╚██╔╝  ██║╚██╗██║██╔══██║██║╚██╔╝██║██║██║     ██╔══██║
██████╔╝   ██║   ██║ ╚████║██║  ██║██║ ╚═╝ ██║██║╚██████╗██║  ██║
╚═════╝    ╚═╝   ╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝ ╚═════╝╚═╝  ╚═╝
*/

import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IDynamica} from "./interfaces/IDynamica.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "forge-std/src/console.sol";
import "forge-std/src/Test.sol";

/**
 * @title MarketMaker
 * @dev A simple prediction market maker contract that allows users to buy and sell outcome tokens
 * @notice This contract implements a basic market making mechanism for binary outcomes
 *
 * The contract manages a prediction market where users can:
 * - Make predictions by buying/selling outcome tokens
 * - Redeem payouts when the market is resolved
 * - Pay fees on trades
 *
 * The market uses a simple constant product market maker model with fees.
 */
contract MarketMaker is Initializable, OwnableUpgradeable, IDynamica {
    // ============ Constants ============

    /// @notice Maximum fee that can be set (100% in basis points)
    uint64 public constant FEE_RANGE = 10_000;

    // ============ State Variables ============

    /// @notice Array of payout numerators for each outcome
    uint256[] public payoutNumerators;

    /// @notice Payout denominator for calculating final payouts
    uint256 public payoutDenominator;

    /// @notice The collateral token used for trading
    IERC20 public collateralToken;

    /// @notice The question that this prediction market resolves
    string public question;

    /// @notice The fee rate in basis points (e.g., 300 = 3%)
    uint64 public fee;

    /// @notice Total funding in the market
    uint256 public funding;

    /// @notice Total fees received from trades
    uint256 public feeReceived;

    /// @notice Array of outcome token amounts in the pool for each outcome
    uint256[] public outcomeTokenAmounts;

    /// @notice Array tracking total user outcome tokens for each outcome
    uint256[] public usersOutcomes;

    /// @notice Address of the oracle manager that can resolve the market
    address public oracleManager;

    /// @notice Mapping from user address to their shares for each outcome
    mapping(address => int256[]) public userShares;

    /// @notice Number of possible outcomes in the market
    uint256 public outcomeSlotCount;

    // ============ Events ============

    // Events are defined in the IDynamica interface

    // ============ Modifiers ============

    /// @notice Ensures the market is not yet resolved
    modifier marketNotResolved() {
        require(payoutDenominator == 0, "Market already resolved");
        _;
    }

    /// @notice Ensures the market is resolved
    modifier marketResolved() {
        require(payoutDenominator != 0, "Market not resolved");
        _;
    }

    /// @notice Ensures only the oracle manager can call the function
    modifier onlyOracleManager() {
        require(
            oracleManager == msg.sender,
            "Only oracle manager can call this"
        );
        _;
    }

    // ============ External Functions ============

    /**
     * @notice Initializes the market with funding and outcome configuration
     * @param oracle The oracle address that will resolve the condition
     * @param _question The question text that this market resolves
     * @param _outcomeSlotCount The number of possible outcomes
     * @param _startFunding The amount of funding to add to the market
     * @param _outcomeTokenAmounts The initial token amounts for each outcome
     */
    function initializeMarket(
        address oracle,
        string calldata _question,
        uint256 _outcomeSlotCount,
        uint256 _startFunding,
        uint256 _outcomeTokenAmounts
    ) internal {
        require(oracle != address(0), "Invalid oracle address");
        require(_outcomeSlotCount > 0, "Must have at least one outcome");
        require(_startFunding > 0, "Start funding must be positive");
        require(
            _outcomeTokenAmounts > 0,
            "Outcome token amounts must be positive"
        );

        oracleManager = oracle;
        question = _question;
        outcomeSlotCount = _outcomeSlotCount;

        // Initialize arrays
        payoutNumerators = new uint256[](_outcomeSlotCount);
        outcomeTokenAmounts = new uint256[](_outcomeSlotCount);
        usersOutcomes = new uint256[](_outcomeSlotCount);

        // Transfer initial funding from sender
        require(
            collateralToken.transferFrom(
                msg.sender,
                address(this),
                _startFunding
            ),
            "Transfer failed"
        );

        funding += _startFunding;

        // Set initial token amounts for each outcome
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            outcomeTokenAmounts[i] = _outcomeTokenAmounts;
        }

        emit startFunding(_startFunding, _outcomeTokenAmounts);
    }

    /**
     * @notice Makes a prediction by buying or selling outcome tokens
     * @param deltaOutcomeAmounts_ Array of token amount changes for each outcome
     *        Positive values = buying tokens, Negative values = selling tokens
     */
    function makePrediction(
        int256[] calldata deltaOutcomeAmounts_
    ) external marketNotResolved {
        require(
            deltaOutcomeAmounts_.length == outcomeSlotCount,
            "Invalid outcome amount length"
        );

        // Initialize user shares array if not exists
        if (userShares[msg.sender].length == 0) {
            userShares[msg.sender] = new int256[](outcomeSlotCount);
        }

        // Validate user has enough shares to sell
        _validateSellAmounts(deltaOutcomeAmounts_);

        // Calculate net cost of the trade
        int256 netCost = calcNetCost(deltaOutcomeAmounts_);
        console.log("netCost", netCost);

        // Handle fee calculation and token transfers
        uint256 feeAmount = _handleTradePayment(netCost);

        // Update pool and user state
        _updateTokenAmounts(deltaOutcomeAmounts_);
        _updateUserShares(deltaOutcomeAmounts_);

        emit OutcomeTokenTrade(
            msg.sender,
            deltaOutcomeAmounts_,
            netCost,
            feeAmount
        );
    }

    /**
     * @notice Closes the market by resolving the condition with payout ratios
     * @param payouts Array of payout numerators for each outcome
     * @dev Only callable by the oracle manager
     */
    function closeMarket(
        uint256[] calldata payouts
    ) external onlyOracleManager marketNotResolved {
        uint256 _outcomeSlotCount = payouts.length;
        require(
            _outcomeSlotCount == outcomeSlotCount,
            "Must have exactly outcomeSlotCount outcomes"
        );

        require(
            payoutNumerators.length == _outcomeSlotCount,
            "Condition not prepared or found"
        );

        // Calculate and validate payout denominator
        uint256 denominator = _calculatePayoutDenominator(payouts);
        require(denominator > 0, "Payout is all zeroes");

        // Set payout numerators
        for (uint256 i = 0; i < _outcomeSlotCount; i++) {
            require(payoutNumerators[i] == 0, "Payout numerator already set");
            payoutNumerators[i] = payouts[i];
        }

        payoutDenominator = denominator;
        _sendMarketsSharesToOwner();
    }

    /**
     * @notice Redeems payout for resolved condition
     * @dev Calculates payout based on user's shares and resolved outcome ratios
     */
    function redeemPayout() external marketResolved {
        uint256 denominator = payoutDenominator;
        int256[] storage shares = userShares[msg.sender];

        uint256 totalPayout = _calculateUserPayout(shares, denominator);
        require(totalPayout > 0, "Nothing to redeem");

        // Clear user shares after payout
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            if (shares[i] > 0 && payoutNumerators[i] > 0) {
                shares[i] = 0;
            }
        }

        require(
            collateralToken.transfer(msg.sender, totalPayout),
            "Transfer failed"
        );

        emit PayoutRedemption(
            msg.sender,
            collateralToken,
            bytes32(0), // parentCollectionId
            bytes32(0), // conditionId (not used anymore)
            new uint256[](0), // indexSets
            totalPayout
        );
    }

    // ============ Public Functions ============

    /**
     * @notice Calculates the net cost for a trade
     * @param outcomeTokenAmounts Array of token amount changes
     * @return netCost The net cost of the trade (positive = user pays, negative = user receives)
     */
    function calcNetCost(
        int256[] memory outcomeTokenAmounts
    ) public view virtual returns (int256) {
        // This function should be implemented by derived contracts
        // to provide specific market making logic
    }

    /**
     * @notice Changes the fee rate
     * @param _fee The new fee rate in basis points
     * @dev Only callable by owner
     */
    function changeFee(uint64 _fee) external onlyOwner {
        require(_fee < FEE_RANGE, "Fee must be less than FEE_RANGE");
        fee = _fee;
        emit FeeChanged(fee);
    }

    /**
     * @notice Withdraws accumulated fees to the owner
     * @dev Only callable by owner
     */
    function withdrawFee() external onlyOwner {
        require(feeReceived > 0, "No fees to withdraw");
        uint256 amount = feeReceived;
        feeReceived = 0; // Reset accumulated fees
        require(
            collateralToken.transfer(owner(), amount),
            "Fee transfer failed"
        );
        emit FeeWithdrawal(amount);
    }

    // ============ Private Functions ============

    /**
     * @notice Validates that user has enough shares to sell
     * @param deltaOutcomeAmounts_ Array of token amount changes
     */
    function _validateSellAmounts(
        int256[] calldata deltaOutcomeAmounts_
    ) private view {
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            if (deltaOutcomeAmounts_[i] < 0) {
                require(
                    userShares[msg.sender][i] >= -deltaOutcomeAmounts_[i],
                    "Insufficient shares to sell"
                );
            }
        }
    }

    /**
     * @notice Handles payment processing for trades including fee calculation
     * @param netCost The net cost of the trade
     * @return feeAmount The fee amount charged
     */
    function _handleTradePayment(
        int256 netCost
    ) private returns (uint256 feeAmount) {
        uint256 absoluteNetCost = netCost > 0
            ? uint256(netCost)
            : uint256(-netCost);

        if (netCost > 0) {
            // User is buying - calculate fee and transfer tokens
            uint256 shouldPay = (uint256(netCost) * FEE_RANGE) /
                (FEE_RANGE - fee);
            feeAmount = shouldPay - uint256(netCost);
            feeReceived += feeAmount;

            require(
                collateralToken.transferFrom(
                    msg.sender,
                    address(this),
                    uint256(netCost)
                ),
                "Transfer failed"
            );
        } else {
            // User is selling - calculate fee and pay out tokens
            feeAmount = (absoluteNetCost * fee) / FEE_RANGE;
            feeReceived += feeAmount;
            uint256 payoutAmount = uint256(-netCost) - feeAmount;

            require(
                collateralToken.transfer(msg.sender, payoutAmount),
                "Transfer failed"
            );
        }
    }

    /**
     * @notice Updates token amounts in the pool
     * @param deltaOutcomeAmounts_ Array of token amount changes
     */
    function _updateTokenAmounts(
        int256[] calldata deltaOutcomeAmounts_
    ) private {
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            if (deltaOutcomeAmounts_[i] > 0) {
                outcomeTokenAmounts[i] += uint256(deltaOutcomeAmounts_[i]);
                usersOutcomes[i] += uint256(deltaOutcomeAmounts_[i]);
            } else {
                outcomeTokenAmounts[i] -= uint256(-deltaOutcomeAmounts_[i]);
                usersOutcomes[i] -= uint256(-deltaOutcomeAmounts_[i]);
            }
        }
    }

    /**
     * @notice Updates user shares for each outcome
     * @param deltaOutcomeAmounts_ Array of token amount changes
     */
    function _updateUserShares(int256[] calldata deltaOutcomeAmounts_) private {
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            userShares[msg.sender][i] += deltaOutcomeAmounts_[i];
        }
    }

    /**
     * @notice Calculates the payout denominator from payout numerators
     * @param payouts Array of payout numerators
     * @return denominator The calculated denominator
     */
    function _calculatePayoutDenominator(
        uint256[] calldata payouts
    ) private pure returns (uint256 denominator) {
        for (uint256 i = 0; i < payouts.length; i++) {
            denominator += payouts[i];
        }
    }

    /**
     * @notice Calculates user's total payout based on shares and resolved outcome
     * @param shares User's shares for each outcome
     * @param denominator Payout denominator
     * @return totalPayout The total payout amount
     */
    function _calculateUserPayout(
        int256[] storage shares,
        uint256 denominator
    ) private view returns (uint256 totalPayout) {
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            if (shares[i] <= 0 || payoutNumerators[i] == 0) continue;
            totalPayout +=
                (uint256(shares[i]) * payoutNumerators[i]) /
                denominator;
        }
    }

    /**
     * @notice Sends remaining market shares to the owner after resolution
     */
    function _sendMarketsSharesToOwner() private {
        uint256 totalPayout = _calculateTotalMarketPayout();
        uint256 returnToOwner = collateralToken.balanceOf(address(this)) -
            totalPayout;

        require(
            collateralToken.transfer(msg.sender, returnToOwner),
            "Transfer failed"
        );
        emit SendMarketsSharesToOwner(returnToOwner);
    }

    /**
     * @notice Calculates total payout for all market participants
     * @return totalPayout The total payout amount
     */
    function _calculateTotalMarketPayout()
        private
        view
        returns (uint256 totalPayout)
    {
        for (uint256 i = 0; i < outcomeTokenAmounts.length; i++) {
            totalPayout +=
                (usersOutcomes[i] * payoutNumerators[i]) /
                payoutDenominator;
        }
    }
}
