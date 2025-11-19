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
import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IDynamica} from "../../src/interfaces/IDynamica.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";
import {ERC1155} from "@openzeppelin-contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Holder} from "@openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC1155Supply} from "@openzeppelin-contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {LMSRMath} from "../../src/LMSRMath.sol";
import {console} from "forge-std/src/console.sol";
/**
 * @title MarketMaker v2
 * @dev A perpetual prediction market maker contract that allows users to buy and sell outcome tokens.
 *      Implements epoch and period-based market making logic for multi-outcome prediction markets.
 *      Uses ERC1155 tokens for outcome representation with time-weighted rewards.
 *      Supports continuous trading with automatic epoch transitions.
 */
contract Dynamica is
    Ownable,
    ERC1155Holder,
    ERC1155Supply,
    ReentrancyGuard,
    IDynamica
{
    using SafeERC20 for IERC20;

    // ============ Constants ============

    /// @notice Maximum number of outcome slots supported
    uint256 constant MAX_SLOT_COUNT = 10;

    /// @notice Maximum fee/gamma that can be set (100% in basis points)
    uint32 public constant RANGE = 10_000;

    /// @notice Unit decimal for calculations (18 decimals)
    int256 public constant UNIT_DEC = 1e18;
    uint32 public lastEpoch;

    // ============ State Variables ============

    uint256 public version;

    /// @notice LMSR math contract
    LMSRMath public lmsrMath;

    /// @notice Alpha parameter for LMSR calculations
    int256 public alpha;

    /// @notice Exponential limit to prevent overflow in calculations
    int256 public expLimit;

    /// @notice Collateral token decimals multiplier
    int256 public decCollateral;

    /// @notice Outcome token decimals multiplier
    int256 public decQ;

    // Time Management
    /// @notice Duration of each epoch in seconds
    uint32 public epochDuration;

    /// @notice Duration of each period within an epoch in seconds
    uint32 public periodDuration;

    /// @notice Current period start time
    uint32 public periodStart;

    /// @notice Current period number (1-based)
    uint32 public currentPeriodNumber;

    /// @notice Current epoch number (1-based)
    uint32 public currentEpochNumber;

    /// @notice Array of gamma power values for time-weighted rewards
    uint32[] public gammaPow;

    address constant USER1 = address(0x10000);
    address constant USER2 = address(0x20000);
    address constant OWNER = address(0x30000);

    mapping(uint256 => bool) public redeemForEpoch;

    // ============ Mappings ============

    /// @notice Mapping from epoch number to epoch data
    mapping(uint256 => EpochData) public epochData;

    /// @notice Mapping from user address to token ID to blocked amount
    mapping(address => mapping(uint256 => uint256)) public blockedForUser;

    /// @notice Mapping from token ID to blocked amount for epoch
    mapping(uint256 => uint256) public blockedForEpoch;

    // ============ Market Configuration ============
    /// @notice Address of the ERC20 collateral token
    address public collateralToken;

    /// @notice The question that this prediction market resolves
    string public question;

    /// @notice The fee rate in basis points (e.g., 300 = 3%)
    uint64 public fee;

    /// @notice Total fees received from trades
    uint256 public feeReceived;

    /// @notice Decimals for outcome tokens
    uint8 public decimals;

    /// @notice Address of the oracle manager that can resolve the market
    address public oracleManager;

    /// @notice Number of possible outcomes in the market
    uint256 public outcomeSlotCount;

    /// @notice Expiration time of the market
    uint32 public expirationEpoch;

    bool public initialized;

    // ============ Constructor ============

    constructor() ERC1155("") Ownable(msg.sender) {

    }
    /**
     * @notice Initializes the market with funding and outcome configuration
     * @param config The configuration for the market
     * @param lmsrMathAddress Address of the LMSR math contract
     * @dev Emits MarketInitialized event
     */
    function initialize(Config memory config, address lmsrMathAddress) public {
        if (initialized) return;
        initialized = true;
        version = 1;

        if (config.owner == address(0)) revert ZeroAddress("owner");
        if (config.collateralToken == address(0)) revert ZeroAddress("collateralToken");
        if (config.oracle == address(0)) revert ZeroAddress("oracle");
        if (config.outcomeSlotCount == 0 || config.outcomeSlotCount > MAX_SLOT_COUNT) {
            revert InvalidOutcomeSlotCount(config.outcomeSlotCount, MAX_SLOT_COUNT);
        }
        if (owner() != config.owner) {
            _transferOwnership(config.owner);
        }
        collateralToken = config.collateralToken;
        fee = config.fee;

        uint8 collateralTokenDecimals = IERC20Metadata(collateralToken).decimals();
        if (collateralTokenDecimals > 18) {
            revert CollateralTokenDecimalsTooHigh(collateralTokenDecimals);
        }

        if (config.periodDuration == 0) revert InvalidDuration("periodDuration");
        if (config.epochDuration == 0) revert InvalidDuration("epochDuration");
        if (config.epochDuration % config.periodDuration != 0) {
            revert InvalidDuration("epochDuration%periodDuration");
        }

        currentEpochNumber = 1;
        currentPeriodNumber = 1;
        epochDuration = config.epochDuration;
        periodDuration = config.periodDuration;
        oracleManager = config.oracle;
        question = config.question;
        outcomeSlotCount = config.outcomeSlotCount;
        expirationEpoch = config.expirationEpoch;

        _initializeGammaPowers(config.gamma);
        lmsrMath = LMSRMath(lmsrMathAddress);

        alpha = config.alpha;
        expLimit = config.expLimit;

        epochData[currentEpochNumber].epochStart = uint32(block.timestamp);
        periodStart = uint32(block.timestamp);

        epochData[currentEpochNumber].funding = config.startFunding;

        decimals = config.decimals;
        decCollateral = int256(10 ** collateralTokenDecimals);
        decQ = int256(10 ** uint32(decimals));

        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            uint256 id = shareId(currentEpochNumber, currentPeriodNumber, i);
            _mint(address(this), id, config.outcomeTokenAmounts, "");
            blockedForEpoch[id] = config.outcomeTokenAmounts;
            blockedForUser[address(this)][id] = config.outcomeTokenAmounts;
        }

        emit MarketInitialized(config.startFunding, config.question, config.outcomeTokenAmounts);
    }

    // ============ Modifiers ============

    /// @notice Ensures the epoch is not yet resolved
    modifier epochNotResolved(uint256 epoch) {
        if (epochData[epoch].payoutDenominator != 0 && block.timestamp < epochData[currentEpochNumber].epochStart + epochDuration) {
            revert MarketAlreadyResolved();
        }
        if (expirationEpoch != 0 && epoch > expirationEpoch) {
            revert MarketExpired();
        }
        _;
    }

    /// @notice Ensures the epoch is resolved
    modifier epochResolved(uint256 epoch) {
        if (epochData[epoch].payoutDenominator == 0) {
            revert MarketNotResolved();
        }
        _;
    }

    /// @notice Ensures only the oracle manager can call the function
    modifier onlyOracleManager() {
        if (oracleManager != msg.sender) {
            revert OnlyOracleManager(msg.sender);
        }
        _;
    }

    // ============ External Functions ============

    /**
     * @notice Makes a prediction by buying or selling outcome tokens
     * @param deltaOutcomeAmounts_ Array of token amount changes for each outcome
     *        Positive values = buying tokens, Negative values = selling tokens
     * @param isRollover Whether this is a rollover trade
     * @dev Emits OutcomeTokenTrade event
     */
    function makePrediction(int256[] memory deltaOutcomeAmounts_, bool isRollover)
        public
        nonReentrant
        epochNotResolved(currentEpochNumber)
    {
        require(msg.sender == USER1 || msg.sender == USER2, "Only user1 or user2 can trade");

        if(isRollover && currentEpochNumber + 1 == expirationEpoch) {
            revert RolloverNotAllowedAfterExpiration();
        }
        
        _updateEpochAndPeriod();

        if (deltaOutcomeAmounts_.length != outcomeSlotCount) {
            revert InvalidLength(deltaOutcomeAmounts_.length, outcomeSlotCount);
        }

        _validateSellAmounts(deltaOutcomeAmounts_, isRollover);

        int256[] memory qCurrent = new int256[](outcomeSlotCount);
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            qCurrent[i] = int256(outcomeTokenSuppliesPerEpoch(currentEpochNumber, i));
        }
        int256 netCost = (
            lmsrMath.calcNetCostPure(qCurrent, deltaOutcomeAmounts_, alpha, uint256(expLimit)) * decCollateral
                / UNIT_DEC
        ) / decQ;
        bool isBuy = netCost > 0;
        uint256 cost = isBuy ? uint256(netCost) : uint256(-netCost);

        _updateUserShares(tx.origin, deltaOutcomeAmounts_, isRollover);

        uint256 feeAmount = _handleTradePayment(cost, isBuy);

        emit OutcomeTokenTrade(tx.origin, deltaOutcomeAmounts_, netCost, feeAmount);
    }

    /**
     * @notice Closes the current epoch by resolving it with payout ratios
     * @param payouts Array of payout numerators for each outcome
     * @return True if market is expired and shares sent to owner
     * @dev Only callable by the oracle manager. Emits EpochResolved event.
     */
    function closeEpoch(uint256[] calldata payouts)
        public
        nonReentrant
        epochNotResolved(currentEpochNumber)
        returns (bool)
    {
        _closeEpoch(payouts);
        if (expirationEpoch != 0 && currentEpochNumber > expirationEpoch) {
            _sendMarketsSharesToOwner();
            return true;
        }
        emit EpochResolved(msg.sender, payouts, epochData[currentEpochNumber - 1].payoutDenominator);
        return false;
    }

    /**
     * @notice Redeems payout for resolved epoch
     * @param epoch The epoch number to redeem for
     * @dev Calculates payout based on user's shares and resolved outcome ratios. Emits PayoutRedemption event.
     */
    function redeemPayout(uint32 epoch) public nonReentrant epochResolved(epoch) {
        require(msg.sender == USER1 || msg.sender == USER2, "Only user1 or user2 can trade");
        redeemForEpoch[epoch] = true;
        uint256 totalPayout = 0;
        uint256 periodsPerEpoch = epochDuration / periodDuration;

        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            for (uint256 j = 1; j <= periodsPerEpoch; j++) {
                uint256 id = shareId(epoch, j, i);
                uint256 balance = balanceOf(tx.origin, id) - blockedForUser[tx.origin][id];
                if (balance > 0) {
                    totalPayout += (balance * gammaPow[j - 1] * epochData[epoch].basePrice[i] / uint256(decQ)) / RANGE;
                    _burnToken(tx.origin, balance, id);
                }
            }
        }

        if (totalPayout == 0) {
            revert NothingToRedeem();
        }

        IERC20(collateralToken).safeTransfer(tx.origin, totalPayout);

        emit PayoutRedemption(tx.origin, collateralToken, question, totalPayout);
    }

    /**
     * @notice Claims tokens for a new epoch based on blocked tokens from previous epoch
     * @param epoch The epoch number to claim for
     * @dev Converts blocked tokens from previous epoch to new epoch tokens based on base prices
     */
    function redeemBlockedTokens(uint32 epoch) public nonReentrant epochResolved(epoch + 1) {
        require(msg.sender == USER1 || msg.sender == USER2, "Only user1 or user2 can trade");
        redeemForEpoch[epoch] = true;
        _redeemBlocked(tx.origin, epoch, tx.origin);
    }

    /**
     * @notice Unblocks tokens for a given epoch and period
     * @param deltaOutcomeAmounts_ Array of token amount changes for each outcome
     * @param epoch The epoch number
     * @param period The period number
     * @dev Transfers blocked tokens from contract to user
     */
    function unblockTokens(uint256[] memory deltaOutcomeAmounts_, uint32 epoch, uint32 period)
        public
        nonReentrant
    {
        require(msg.sender == USER1 || msg.sender == USER2, "Only user1 or user2 can trade");

        uint256[] memory ids = new uint256[](outcomeSlotCount);
        for (uint256 j = 0; j < outcomeSlotCount; j++) {
            ids[j] = shareId(epoch, period, j);
            if (blockedForUser[tx.origin][ids[j]] < deltaOutcomeAmounts_[j]) {
                revert InsufficientBalance(blockedForUser[tx.origin][ids[j]], deltaOutcomeAmounts_[j]);
            }
            blockedForUser[tx.origin][ids[j]] -= deltaOutcomeAmounts_[j];
            blockedForEpoch[ids[j]] -= deltaOutcomeAmounts_[j];
        }
        _safeBatchTransferFrom(address(this), tx.origin, ids, deltaOutcomeAmounts_, "");
        emit TokensUnblocked(tx.origin, deltaOutcomeAmounts_, epoch,period);
    }


    /**
     * @notice Returns the epoch data for a given epoch
     * @param epoch The epoch number
     * @return The epoch data
     */
    function getEpochData(uint256 epoch) public view returns (IDynamica.EpochData memory) {
        return epochData[epoch];
    }

    // ============ Public Functions ============

    /**
     * @notice Updates the current epoch and period based on elapsed time
     * @dev Only callable by owner. Automatically advances epochs and periods as time passes.
     */
    function updateEpochAndPeriod() public onlyOwner {
        _updateEpochAndPeriod();
    }

    /**
     * @notice Checks if the current epoch should be resolved
     * @return True if epoch duration has passed or market is expired
     */
    function checkEpoch() public view returns (bool) {
        return (block.timestamp >= epochData[currentEpochNumber].epochStart + epochDuration)
            || (expirationEpoch != 0 && currentEpochNumber > expirationEpoch);
    }

    /**
     * @notice Returns the payout numerator for a specific outcome in the previous epoch
     * @param i Index of the outcome
     * @return The payout numerator
     */
    function payoutNumerators(uint256 epoch, uint256 i) public view returns (uint256) {
        return epochData[epoch].payoutNumerators[i];
    }

    /**
     * @notice Returns the payout denominator for the previous epoch
     * @return The payout denominator
     */
    function payoutDenominator(uint256 epoch) public view returns (uint256) {
        return epochData[epoch].payoutDenominator;
    }

    /**
     * @notice Returns the supply for a specific outcome token in the current epoch
     * @param epoch Epoch number
     * @param period Period number
     * @param outcomeSlot Index of the outcome
     * @return The token supply
     */
    function outcomeTokenSupplies(uint256 epoch, uint256 period, uint256 outcomeSlot) public view returns (uint256) {
        return totalSupply(shareId(epoch, period, outcomeSlot));
    }

    /**
     * @notice Returns the supply for an outcome token per epoch
     * @param epoch Epoch number
     * @param outcomeSlot Outcome slot number
     * @return The supply for the outcome token per epoch
     */
    function outcomeTokenSuppliesPerEpoch(uint256 epoch, uint256 outcomeSlot) public view returns (uint256) {
        uint256 amount = 0;
        for (uint256 j = 1; j <= currentPeriodNumber; j++) {
            amount += totalSupply(shareId(epoch, j, outcomeSlot));
        }
        return amount;
    }

    /**
     * @notice Changes the expiration epoch
     * @param newExpirationEpoch The new expiration epoch
     * @dev Only callable by owner. Emits ExpirationEpochChanged event.
     */
    function changeExpirationEpoch(uint32 newExpirationEpoch) public onlyOwner {
        if (
            newExpirationEpoch < currentEpochNumber + 1 && newExpirationEpoch != 0
        ) {
            revert NewExpirationEpochMustBeGreaterThanCurrentEpoch(newExpirationEpoch, currentEpochNumber);
        }
        expirationEpoch = newExpirationEpoch;
        emit ExpirationEpochChanged(newExpirationEpoch, block.timestamp);
    }

    /**
     * @notice Changes the fee rate
     * @param _fee The new fee rate in basis points
     * @dev Only callable by owner. Emits FeeChanged event.
     */
    function changeFee(uint64 _fee) public onlyOwner {
        if (_fee >= RANGE) {
            revert FeeMustBeLessThanRange(_fee, RANGE);
        }
        fee = _fee;
        emit FeeChanged(block.timestamp, _fee);
    }

    /**
     * @notice Withdraws accumulated fees to the owner
     * @dev Only callable by owner. Emits FeeWithdrawal event.
     */
    function withdrawFee() public onlyOwner {
        if (feeReceived == 0) {
            revert InsufficientBalance(0, feeReceived);
        }
        uint256 amount = feeReceived;
        feeReceived = 0;
        IERC20(collateralToken).safeTransfer(owner(), amount);
        emit FeeWithdrawal(block.timestamp, amount);
    }

    // ============ Internal Functions ============

    /**
     * @notice Validates that user has enough shares to sell
     * @param deltaOutcomeAmounts_ Array of token amount changes
     * @dev Reverts if user does not have enough shares
     */
    function _validateSellAmounts(int256[] memory deltaOutcomeAmounts_, bool isRollover) private view {
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            uint256 id = shareId(currentEpochNumber, currentPeriodNumber, i);
            if (deltaOutcomeAmounts_[i] < 0) {
                uint256 balance = balanceOf(tx.origin, id);
                if (isRollover) {
                    balance = blockedForUser[tx.origin][id];
                }
                uint256 amount = uint256(-deltaOutcomeAmounts_[i]);
                if (balance < amount) {
                    revert InsufficientBalance(balance, amount);
                }
            }
        }
    }

    /**
     * @notice Handles payment processing for trades including fee calculation
     * @param netCost The net cost of the trade
     * @param isBuy True if the user is buying, false if selling
     * @return feeAmount The fee amount charged
     */
    function _handleTradePayment(uint256 netCost, bool isBuy) private returns (uint256 feeAmount) {
        if (isBuy) {
            uint256 shouldPay = (netCost * RANGE) / (RANGE - fee);
            feeAmount = shouldPay - netCost;
            feeReceived += feeAmount;
            epochData[currentEpochNumber].funding += netCost;
            IERC20(collateralToken).safeTransferFrom(tx.origin, address(this), shouldPay);
        } else {
            feeAmount = (netCost * fee) / RANGE;
            feeReceived += feeAmount;
            uint256 payoutAmount = netCost - feeAmount;
            epochData[currentEpochNumber].funding -= netCost;
            IERC20(collateralToken).safeTransfer(tx.origin, payoutAmount);
        }
    }

    /**
     * @notice Updates user shares for each outcome
     * @param user Address of the user
     * @param deltaOutcomeAmounts_ Array of token amount changes
     * @param isRollover Whether this is a rollover trade
     * @dev Mints or burns outcome tokens as needed
     */
    function _updateUserShares(address user, int256[] memory deltaOutcomeAmounts_, bool isRollover) private {
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            uint256 id = shareId(currentEpochNumber, currentPeriodNumber, i);
            if (deltaOutcomeAmounts_[i] > 0) {
                if (isRollover) {
                    blockedForUser[user][id] += uint256(deltaOutcomeAmounts_[i]);
                    blockedForEpoch[id] += uint256(deltaOutcomeAmounts_[i]);
                    _mintToken(address(this), uint256(deltaOutcomeAmounts_[i]), id);
                } else {
                    _mintToken(user, uint256(deltaOutcomeAmounts_[i]), id);
                }
            } else if (deltaOutcomeAmounts_[i] < 0) {
                if (isRollover) {
                    blockedForUser[user][id] -= uint256(-deltaOutcomeAmounts_[i]);
                    blockedForEpoch[id] -= uint256(-deltaOutcomeAmounts_[i]);
                    _burnToken(address(this), uint256(-deltaOutcomeAmounts_[i]), id);
                } else {
                    _burnToken(user, uint256(-deltaOutcomeAmounts_[i]), id);
                }
            }
        }
    }

    function _closeEpoch(uint256[] calldata payouts) internal {
        uint256 _outcomeSlotCount = payouts.length;
        uint256 totalPayout;
        uint256 totalPayoutRollover;
        uint256 newTokenId;
        // Validate payout array length
        if (_outcomeSlotCount != outcomeSlotCount) {
            revert InvalidLength(_outcomeSlotCount, outcomeSlotCount);
        }

        // Calculate payout denominator
        uint256 payoutDenominator_ = _calculatePayoutDenominator(payouts);
        if (payoutDenominator_ == 0) {
            revert PayoutIsAllZeroes();
        }

        epochData[currentEpochNumber].payoutDenominator = payoutDenominator_;
        payoutDenominator_ = payoutDenominator_ * uint256(decCollateral);

        uint256[] memory totalWeightedShares = new uint256[](_outcomeSlotCount);
        uint256 periodsPerEpoch = epochDuration / periodDuration;
        uint256 totalPayoutRollover_i;
        uint256 outcomeTokenAmount_i;
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            epochData[currentEpochNumber].payoutNumerators[i] = payouts[i];
            epochData[currentEpochNumber].basePrice[i] = (payouts[i] * uint256(decCollateral)) /  epochData[currentEpochNumber].payoutDenominator;
            for (uint256 j = 1; j <= periodsPerEpoch; j++) {
                newTokenId = shareId(currentEpochNumber, j, i);
                outcomeTokenAmount_i = outcomeTokenSupplies(currentEpochNumber, j, i) - blockedForEpoch[newTokenId];

                if (outcomeTokenAmount_i != 0) {
                    totalWeightedShares[i] += (outcomeTokenAmount_i * gammaPow[j - 1]);
                }
                totalPayoutRollover_i += blockedForEpoch[newTokenId]; 
                _burn(address(this), newTokenId, blockedForEpoch[newTokenId]);
            }
            totalPayoutRollover += (totalPayoutRollover_i - blockedForUser[address(this)][shareId(currentEpochNumber, 1, i)]) * epochData[currentEpochNumber].basePrice[i]; // decQ * decColl   
            totalPayoutRollover_i = 0;
            totalWeightedShares[i] /= RANGE;
            totalPayout += totalWeightedShares[i] * epochData[currentEpochNumber].basePrice[i];
        }
        totalPayoutRollover /= uint256(decQ);
        totalPayout /= uint256(decQ);

        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            newTokenId = shareId(currentEpochNumber + 1, 1, i);
            blockedForEpoch[newTokenId] += totalPayoutRollover * uint256(decQ) / epochData[currentEpochNumber].basePrice[i];
            _mint(address(this), newTokenId, blockedForEpoch[newTokenId], "");
        }
        uint32 now32 = uint32(block.timestamp);
        epochData[currentEpochNumber].fundingForRollover = totalPayoutRollover;
        epochData[currentEpochNumber].totalPayout = totalPayout;
        lastEpoch = currentEpochNumber;

        currentEpochNumber += 1;
        currentPeriodNumber = 1;
        epochData[currentEpochNumber].epochStart = now32;
        epochData[currentEpochNumber].funding =
            epochData[currentEpochNumber - 1].funding - totalPayout;
        periodStart = now32;
    }


    function _redeemBlocked(address user, uint32 epoch, address to) internal {
        uint256 totalPayout;
        uint256 id;
        uint256 balance;
        uint256[] memory totalPayoutPerOutcome = new uint256[](outcomeSlotCount);
        uint256[] memory deltaOutcomeAmounts = new uint256[](outcomeSlotCount);
        uint256 periodsPerEpoch = epochDuration / periodDuration;

        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            for (uint256 j = 1; j <= periodsPerEpoch; j++) {
                id = shareId(epoch, j, i);
                balance = blockedForUser[user][id];
                blockedForUser[user][id] = 0;
                totalPayoutPerOutcome[i] += balance;
            }
            deltaOutcomeAmounts[i] = totalPayoutPerOutcome[i];
        }

        for (uint256 e = epoch; e < currentEpochNumber; e++) {
            for (uint256 i = 0; i < outcomeSlotCount; i++) {
                totalPayout += (deltaOutcomeAmounts[i] * epochData[e].basePrice[i]);
            }

            if (totalPayout > 0) {
                for (uint256 i = 0; i < outcomeSlotCount; i++) {
                    deltaOutcomeAmounts[i] = totalPayout / epochData[e].basePrice[i];
                }
                if (e != currentEpochNumber - 1) totalPayout = 0;
            }
        }

        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            id = shareId(currentEpochNumber, 1, i);
            uint256 amount = deltaOutcomeAmounts[i];
            if (amount == 0) continue;
            blockedForEpoch[id] -= amount;
            _burnToken(address(this), amount, id);
        }

        IERC20(collateralToken).safeTransfer(to, totalPayout / uint256(decQ));
        emit ClaimForNewEpoch(user, deltaOutcomeAmounts, currentEpochNumber, currentPeriodNumber);
    }

    /**
     * @notice Burns tokens from a user
     * @param from Address to burn from
     * @param burnAmount Amount to burn
     * @param id The token id
     * @dev Emits TokenBurned event
     */
    function _burnToken(address from, uint256 burnAmount, uint256 id) internal {
        _burn(from, id, burnAmount);
        emit TokenBurned(from, id, burnAmount);
    }

    /**
     * @notice Mints tokens to a user
     * @param to Address to mint to
     * @param mintAmount Amount to mint
     * @param id The token id
     * @dev Emits TokenMinted event
     */
    function _mintToken(address to, uint256 mintAmount, uint256 id) internal {
        _mint(to, id, mintAmount, "");
        emit TokenMinted(to, id, mintAmount);
    }

    /**
     * @notice Calculates the payout denominator from payout numerators
     * @param payouts Array of payout numerators
     * @return denominator The calculated denominator
     */
    function _calculatePayoutDenominator(uint256[] calldata payouts) private pure returns (uint256 denominator) {
        for (uint256 i = 0; i < payouts.length; i++) {
            denominator += payouts[i];
        }
    }

    /**
     * @notice Updates the current epoch and period based on elapsed time
     * @dev Automatically advances epochs and periods as time passes
     */
    function _updateEpochAndPeriod() private {
        uint32 now32 = uint32(block.timestamp);

        if (now32 >= epochData[currentEpochNumber].epochStart + epochDuration) {
            revert EpochFinishedButNotResolvedYet(currentEpochNumber);
        }

        if (now32 < periodStart + periodDuration) return;

        uint32 steps = (now32 - periodStart) / periodDuration;

        uint32 periodsPerEpoch = epochDuration / periodDuration;
        uint32 target = currentPeriodNumber + steps;
        if (target > periodsPerEpoch) {
            target = periodsPerEpoch;
        }

        uint32 newStart = periodStart + (target - currentPeriodNumber) * periodDuration;

        currentPeriodNumber = target;
        periodStart = newStart;
        emit EpochAndPeriodUpdated(currentEpochNumber, currentPeriodNumber);
    }

    /**
     * @notice Sends remaining market shares to the owner after resolution
     * @dev Emits SendMarketsSharesToOwner event
     */
    function _sendMarketsSharesToOwner() private {
        uint256 returnToOwner = epochData[currentEpochNumber].funding - epochData[currentEpochNumber-1].fundingForRollover;
        if (IERC20(collateralToken).balanceOf(address(this)) < returnToOwner) {
            revert InsufficientBalance(IERC20(collateralToken).balanceOf(address(this)), returnToOwner);
        }
        IERC20(collateralToken).safeTransfer(owner(), returnToOwner);
        emit SendMarketsSharesToOwner(block.timestamp, returnToOwner);
    }
    // ============ Override Functions ============

    /**
     * @notice Checks if the contract supports a specific interface
     * @param interfaceId The interface identifier
     * @return True if the interface is supported
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Holder, ERC1155)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @notice Calculates the unique share ID for (epoch, period, outcome)
     * @param epoch Epoch number
     * @param period Period number
     * @param outcome Outcome index
     * @return The unique share ID
     * @dev Uses a hierarchical ID system: epoch * periodsPerEpoch * outcomeSlotCount + period * outcomeSlotCount + outcome
     */
    function shareId(uint256 epoch, uint256 period, uint256 outcome) public view returns (uint256) {
        uint256 e = epoch - 1;
        uint256 p = period - 1;
        uint256 periodsPerEpoch = epochDuration / periodDuration;
        uint256 epochOffset = e * periodsPerEpoch * outcomeSlotCount;
        uint256 periodOffset = p * outcomeSlotCount;
        return epochOffset + periodOffset + outcome;
    }

    /**
     * @notice Decodes a share ID back into epoch, period, and outcome
     * @param id The share ID to decode
     * @return epoch Epoch number
     * @return period Period number
     * @return outcome Outcome index
     * @dev Inverse function of shareId(). The decoding is unambiguous.
     */
    function decodeShareId(uint256 id) public view returns (uint256 epoch, uint256 period, uint256 outcome) {
        uint256 periodsPerEpoch = epochDuration / periodDuration;

        outcome = id % outcomeSlotCount;

        uint256 periodOffset = id - outcome;
        uint256 periodIndex = periodOffset / outcomeSlotCount;

        period = (periodIndex % periodsPerEpoch) + 1;
        epoch = (periodIndex / periodsPerEpoch) + 1;
    }

    /**
     * @notice Initializes gamma powers for time-weighted rewards
     * @param gamma The gamma parameter for reward decay
     * @dev Sets up decreasing multipliers for later periods to incentivize early predictions
     */
    function _initializeGammaPowers(uint32 gamma) internal {
        uint32 periodNumber = epochDuration / periodDuration;
        gammaPow = new uint32[](periodNumber);
        gammaPow[0] = RANGE;

        for (uint32 i = 1; i < periodNumber; i++) {
            gammaPow[i] = (gammaPow[i - 1] * gamma) / RANGE;
        }
    }
}
