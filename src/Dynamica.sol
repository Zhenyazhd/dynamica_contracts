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
import {IDynamica} from "./interfaces/IDynamica.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC1155Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC1155HolderUpgradeable} from
    "@openzeppelin-contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import {ERC1155SupplyUpgradeable} from
    "@openzeppelin-contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {LMSRMath} from "./LMSRMath.sol";

import {DataLayoutLibrary as DL} from "./libraries/DataLayoutLibrary.sol";
/**
 * @title MarketMaker v2
 * @dev A perpetual prediction market maker contract that allows users to buy and sell outcome tokens.
 *      Implements epoch and period-based market making logic for multi-outcome prediction markets.
 *      Uses ERC1155 tokens for outcome representation with time-weighted rewards.
 *      Supports continuous trading with automatic epoch transitions.
 */
contract Dynamica is
    Initializable,
    OwnableUpgradeable,
    ERC1155HolderUpgradeable,
    ERC1155SupplyUpgradeable,
    ReentrancyGuardUpgradeable,
    IDynamica
{
    using SafeERC20 for IERC20;

    // ============ Constants ============

    /// @notice Maximum number of outcome slots supported
    uint256 internal constant MAX_SLOT_COUNT = 10;

    /// @notice Maximum fee/gamma that can be set (100% in basis points)
    uint32 public constant RANGE = 10_000;

    /// @notice Unit decimal for calculations (18 decimals)
    int256 public constant UNIT_DEC = 1e18;

    // ============ State Variables ============

    /// @notice LMSR math contract
    LMSRMath public lmsrMath;

    /// @notice Exponential limit to prevent overflow in calculations
    int256 public expLimit;

    /// @notice Collateral token decimals multiplier
    int128 public decCollateral;

    /// @notice Outcome token decimals multiplier
    int128 public decQ;

    // ============ Market Configuration ============
   
    /// @notice Address of the ERC20 collateral token
    address public collateralToken;

    /// @notice Address of the oracle manager that can resolve the market
    address public oracleManager;

    /// @notice The question that this prediction market resolves
    string public question;

    /// @notice Array of gamma power values for time-weighted rewards
    uint32[] public gammaPow;

    // ============ Mappings ============

    /// @notice Mapping from epoch number to epoch data
    mapping(uint256 => EpochData) public epochData;

    /// @notice Mapping from user address to token ID to blocked amount
    mapping(address => mapping(uint256 => uint256)) public blockedForUser;

    /// @notice Mapping from token ID to blocked amount for epoch
    mapping(uint256 => uint256) public blockedForEpoch;


    uint256[50] private __gap;


    // ============ Constructor ============

    /**
     * @notice Constructor that disables initializers for implementation contract
     * @dev This prevents the implementation contract from being initialized directly
     */
    constructor() {
        _disableInitializers();
    }

    // ============ Modifiers ============

    /// @notice Ensures only the oracle manager can call the function
    modifier onlyOracleManager() {
        if (oracleManager != msg.sender) {
            revert OnlyOracleManager(msg.sender);
        }
        _;
    }

    // ============ Initialization ============

    /**
     * @notice Initializes the market with funding and outcome configuration
     * @param config The configuration for the market
     * @param lmsrMathAddress Address of the LMSR math contract
     * @dev Emits MarketInitialized event
     */
    function initialize(Config calldata config, address lmsrMathAddress) public initializer {
        __Ownable_init(config.owner);
        __ERC1155_init("");
        __ERC1155Supply_init();
        __ERC1155Holder_init();
        __ReentrancyGuard_init();

        if (config.owner == address(0)) revert ZeroAddress("owner");
        if (config.collateralToken == address(0)) revert ZeroAddress("collateralToken");
        if (config.oracle == address(0)) revert ZeroAddress("oracle");
        if (config.outcomeSlotCount == 0 || config.outcomeSlotCount > MAX_SLOT_COUNT) {
            revert InvalidOutcomeSlotCount(config.outcomeSlotCount, MAX_SLOT_COUNT);
        }
        if (config.periodDuration == 0) revert InvalidDuration("periodDuration");
        if (config.epochDuration == 0) revert InvalidDuration("epochDuration");
        if (config.epochDuration % config.periodDuration != 0) revert InvalidDuration("epochDuration%periodDuration");
        collateralToken = config.collateralToken;
        uint8 collateralTokenDecimals = IERC20Metadata(collateralToken).decimals();
        if (collateralTokenDecimals > 18) {
            revert CollateralTokenDecimalsTooHigh(collateralTokenDecimals);
        }

        oracleManager = config.oracle;
        question = config.question;
        // Initialize decimal constants
        decCollateral = int128(uint128(10 ** collateralTokenDecimals));
        decQ = int128(uint128(10 ** config.decimals));



        // Initialize time values using DataLayoutLibrary
        DL.TimeUpdate memory timeUpdate = DL.TimeUpdate({
            currentEpoch: 1,
            currentPeriod: 1,
            expirationEpoch: config.expirationEpoch,
            epochDuration: config.epochDuration,
            periodDuration: config.periodDuration,
            periodStart: uint32(block.timestamp),
            epochStart: uint32(block.timestamp)
        });
        uint8 timeFlags = DL.FLAG_UPDATE_CURRENT_EPOCH 
                        | DL.FLAG_UPDATE_CURRENT_PERIOD 
                        | DL.FLAG_UPDATE_EXPIRATION_EPOCH
                        | DL.FLAG_UPDATE_EPOCH_DURATION
                        | DL.FLAG_UPDATE_PERIOD_DURATION
                        | DL.FLAG_UPDATE_PERIOD_START
                        | DL.FLAG_UPDATE_EPOCH_START;
        DL.batchUpdateTimeInfo(timeUpdate, timeFlags);

        // Initialize config values using DataLayoutLibrary
        DL.ConfigUpdate memory configUpdate = DL.ConfigUpdate({
            version: 1,
            fee: config.fee,
            gamma: config.gamma,
            alpha: config.alpha,
            decimals: config.decimals,
            outcomeSlotCount: uint8(config.outcomeSlotCount),
            feeReceived: 0
        });
        uint8 configFlags = DL.FLAG_UPDATE_VERSION 
                          | DL.FLAG_UPDATE_FEE 
                          | DL.FLAG_UPDATE_GAMMA
                          | DL.FLAG_UPDATE_DECIMALS
                          | DL.FLAG_UPDATE_OUTCOME_SLOT_COUNT
                          | DL.FLAG_UPDATE_ALPHA;
        DL.batchUpdateConfigInfo(configUpdate, configFlags);

        _initializeGammaPowers(config.gamma);
        lmsrMath = LMSRMath(lmsrMathAddress);

        expLimit = config.expLimit;
        epochData[1].funding = config.startFunding;

        uint256 periodsPerEpoch = config.epochDuration / config.periodDuration;
        // Create initial outcome tokens
        for (uint256 i = 0; i < config.outcomeSlotCount; i++) {
            uint256 id = _shareId(1, 1, i, config.outcomeSlotCount, periodsPerEpoch);
            _mint(address(this), id, config.outcomeTokenAmounts, "");
            blockedForEpoch[id] = config.outcomeTokenAmounts;
            blockedForUser[address(this)][id] = config.outcomeTokenAmounts;
        }

        emit MarketInitialized(config.startFunding, config.question, config.outcomeTokenAmounts);
    }

    // ============ External Functions ============

    /**
     * @notice Makes a prediction by buying or selling outcome tokens
     * @param deltaOutcomeAmounts_ Array of token amount changes for each outcome
     *        Positive values = buying tokens, Negative values = selling tokens
     * @param isRollover Whether this is a rollover trade
     * @dev Emits OutcomeTokenTrade event
     */
    function makePrediction(int256[] calldata deltaOutcomeAmounts_, bool isRollover)
        external
        nonReentrant
    {
        uint256 packedTime = DL._getStorageData(DL._TIME_SLOT);
        uint256 packedConfig = DL._getStorageData(DL._CONFIG_SLOT);
        uint32 currentEpoch;
        uint32 epochStart;
        uint32 epochDur;
        uint32 expEpoch;
        uint8 slotCount;
        uint8 alphaUint8;
        uint32 periodDur;
        uint32 periodStartTime;
        uint64 currentFee;
        uint32 currentPeriod;
        uint128 feeReceived;
        assembly {
            currentEpoch := and(packedTime, 0xffffffff)
            expEpoch := and(shr(64, packedTime), 0xffffffff)
            epochDur := and(shr(96, packedTime), 0xffffffff)
            epochStart := and(shr(192, packedTime), 0xffffffff)
            slotCount := and(shr(24, packedConfig), 0xff)
            alphaUint8 := and(shr(8, packedConfig), 0xff)
            periodDur := and(shr(128, packedTime), 0xffffffff)
            periodStartTime := and(shr(160, packedTime), 0xffffffff)
            currentFee := and(shr(32, packedConfig), 0xffffffffffffffff)
            currentPeriod := and(shr(32, packedTime), 0xffffffff)
            feeReceived := and(shr(128, packedConfig), 0xffffffffffffffffffffffffffffffff)
        }
        if (!epochNotResolvedAndNotExpired(currentEpoch, epochStart, epochDur, expEpoch)) {
            revert MarketAlreadyResolved();
        }        
        if(isRollover && currentEpoch + 1 == expEpoch) {
            revert RolloverNotAllowedAfterExpiration();
        }
        if (deltaOutcomeAmounts_.length != uint256(slotCount)) {
            revert InvalidLength(deltaOutcomeAmounts_.length, uint256(slotCount));
        }
       
        uint32 newStart;
        (currentPeriod, newStart) = _updateEpochAndPeriod(uint32(block.timestamp), epochStart, epochDur, periodDur, periodStartTime, currentEpoch, currentPeriod);
       
        if (newStart != periodStartTime) {
            DL._setStorageDataWithMask(DL._TIME_SLOT, DL.MASK_PERIOD_START, DL.SHIFT_PERIOD_START, newStart);
            DL._setStorageDataWithMask(DL._TIME_SLOT, DL.MASK_CURRENT_PERIOD, DL.SHIFT_PERIOD, currentPeriod);
        }

        int256 alpha_ = int256(uint256(alphaUint8));
        address user = msg.sender;
        int256[] memory qCurrent = new int256[](slotCount);
        uint256[] memory shareIds = new uint256[](slotCount);
        uint256 periodsPerEpoch = epochDur / periodDur;
        for (uint256 i = 0; i < slotCount; i++) {
            qCurrent[i] = int256(outcomeTokenSuppliesPerEpoch(currentEpoch, i));
            shareIds[i] = _shareId(currentEpoch, currentPeriod, i, slotCount, periodsPerEpoch);
        }

        // Validate sell amounts
        _validateSellAmounts(shareIds, deltaOutcomeAmounts_, slotCount, user, isRollover);

        int256 netCost = (
            lmsrMath.calcNetCostPure(qCurrent, deltaOutcomeAmounts_, alpha_, uint256(expLimit)) * decCollateral
                / UNIT_DEC
        ) / decQ;
        bool isBuy = netCost > 0;
        uint256 cost = isBuy ? uint256(netCost) : uint256(-netCost);
      
        _updateUserShares(user, shareIds, deltaOutcomeAmounts_, slotCount, isRollover);

        uint256 feeAmount = _handleTradePayment(cost, user, currentEpoch, currentFee, isBuy);
        if (feeAmount > 0) {
            uint128 feeAmount128 = uint128(feeAmount);
            uint128 newFeeReceived = feeReceived + feeAmount128;
            DL._setStorageDataWithMask(DL._CONFIG_SLOT, DL.MASK_FEE_RECIEVED, DL.SHIFT_FEE_RECIEVED, newFeeReceived);
        }

        emit OutcomeTokenTrade(user, deltaOutcomeAmounts_, netCost, feeAmount);
    }

    /**
     * @notice Closes the current epoch by resolving it with payout ratios
     * @param payouts Array of payout numerators for each outcome
     * @return True if market is expired and shares sent to owner
     * @dev Only callable by the oracle manager. Emits EpochResolved event.
     */
    function closeEpoch(uint256[] calldata payouts)
        external
        onlyOracleManager
        nonReentrant
        returns (bool)
    {
        
        uint256 packedTime = DL._getStorageData(DL._TIME_SLOT);
        uint32 currentEpoch;
        uint32 expEpoch;
        uint32 epochStart;
        uint32 epochDur;
        assembly {
            currentEpoch := and(packedTime, 0xffffffff)
            expEpoch := and(shr(64, packedTime), 0xffffffff)
            epochStart := and(shr(192, packedTime), 0xffffffff)
            epochDur := and(shr(96, packedTime), 0xffffffff)
        }
        if (!epochNotResolvedAndNotExpired(currentEpoch, epochStart, epochDur, expEpoch)) {
            revert MarketAlreadyResolved();
        }
        _closeEpoch(payouts);

        bool isExpired = expEpoch != 0 && currentEpoch > expEpoch;
        if (isExpired) {
            _sendMarketsSharesToOwner();
        }
        emit EpochResolved(msg.sender, payouts, epochData[currentEpoch - 1].payoutDenominator);
        return isExpired;
    }

    /**
     * @notice Redeems payout for resolved epoch
     * @param epoch The epoch number to redeem for
     * @dev Calculates payout based on user's shares and resolved outcome ratios. Emits PayoutRedemption event.
     */
    function redeemPayout(uint32 epoch) external nonReentrant {
        if (!epochResolved(epoch)) {
            revert MarketNotResolved();
        }
        EpochData storage e = epochData[epoch];
        uint256 totalPayout;
        uint256 packedTime = DL._getStorageData(DL._TIME_SLOT);
        uint32 epochDur;
        uint32 periodDur;
        assembly {
            epochDur := and(shr(96, packedTime), 0xffffffff)
            periodDur := and(shr(128, packedTime), 0xffffffff)
        }
        uint256 periodsPerEpoch = epochDur / periodDur;
        address user = msg.sender;

        uint256 packedConfig = DL._getStorageData(DL._CONFIG_SLOT);
        uint8 slotCount;
        assembly {
            slotCount := and(shr(24, packedConfig), 0xff)
        }

        // Calculate payout for each outcome across all periods
        for (uint256 i = 0; i < slotCount; i++) {
            for (uint256 j = 1; j <= periodsPerEpoch; j++) {
                uint256 id = _shareId(epoch, j, i, slotCount, periodsPerEpoch);
                uint256 balance = balanceOf(user, id);
                if (balance > 0) {
                    uint256 weighted = (balance * gammaPow[j - 1]) / RANGE;   
                    totalPayout += (weighted * e.basePrice[i]) / uint128(decQ);
                    _burn(user, id, balance);
                }
            }
        }

        if (totalPayout == 0) {
            revert NothingToRedeem();
        }
      
        IERC20(collateralToken).safeTransfer(user, totalPayout);

        emit PayoutRedemption(user, collateralToken, question, totalPayout);
    }

    /**
     * @notice Claims tokens for a new epoch based on blocked tokens from previous epoch
     * @param epoch The epoch number to redeem for
     * @dev Converts blocked tokens from previous epoch to new epoch tokens based on base prices
     */
    function redeemBlockedTokens(uint32 epoch) external nonReentrant {
        if (!epochResolved(epoch+1)) {
            revert MarketNotResolved();
        }
        _redeemBlocked(msg.sender, epoch, msg.sender);
    }

    /**
     * @notice Emergency exit function to withdraw all tokens of a specific type
     * @param token The address of the token to withdraw
     * @dev Only callable by owner
     */
    function emergencyExit(address token) external onlyOwner nonReentrant {
        uint256 amount = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(owner(), amount);
        emit EmergencyExit(block.timestamp, token, amount);
    }

    /**
     * @notice Returns the epoch data for a given epoch
     * @param epoch The epoch number
     * @return The epoch data
     */
    function getEpochData(uint256 epoch) external view returns (IDynamica.EpochData memory) {
        return epochData[epoch];
    }




    // ============ Public Functions ============

    /**
     * @notice Updates the current epoch and period based on elapsed time
     * @dev Only callable by owner. Automatically advances epochs and periods as time passes.
     */
    function updateEpochAndPeriod() public onlyOwner {
        uint256 packedTime = DL._getStorageData(DL._TIME_SLOT);
        uint32 now32 = uint32(block.timestamp);
        uint32 currentEpoch;
        uint32 epochStart;
        uint32 epochDur;
        uint32 periodDur;
        uint32 periodStartTime;
        uint32 currentPeriod;
        assembly {
            epochStart := and(shr(192, packedTime), 0xffffffff)
            epochDur := and(shr(96, packedTime), 0xffffffff)
            periodDur := and(shr(128, packedTime), 0xffffffff)
            periodStartTime := and(shr(160, packedTime), 0xffffffff)
            currentEpoch := and(packedTime, 0xffffffff)
            currentPeriod := and(shr(32, packedTime), 0xffffffff)
        }
        _updateEpochAndPeriod(now32, epochStart, epochDur, periodDur, periodStartTime, currentEpoch, currentPeriod);
    }

    /**
     * @notice Checks if the current epoch should be resolved
     * @return True if epoch duration has passed or market is expired
     */
    function checkEpoch() public view returns (bool) {
        uint256 packedTime = DL._getStorageData(DL._TIME_SLOT);
        uint32 currentEpoch;
        uint32 epochDur;
        uint32 expEpoch;
        uint32 epochStart;
        assembly {
            currentEpoch := and(packedTime, 0xffffffff)
            epochDur := and(shr(96, packedTime), 0xffffffff)
            expEpoch := and(shr(64, packedTime), 0xffffffff)
            epochStart := and(shr(192, packedTime), 0xffffffff)
        }
        return (block.timestamp >= epochStart + epochDur)
            || (expEpoch != 0 && currentEpoch > expEpoch);
    }

    /**
     * @notice Returns the payout numerator for a specific outcome in a given epoch
     * @param epoch Epoch number
     * @param i Index of the outcome
     * @return The payout numerator
     */
    function payoutNumerators(uint256 epoch, uint256 i) external view returns (uint256) {
        return epochData[epoch].payoutNumerators[i];
    }

    /**
     * @notice Returns the payout denominator for a given epoch
     * @param epoch Epoch number
     * @return The payout denominator
     */
    function payoutDenominator(uint256 epoch) external view returns (uint256) {
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
        uint256 amount;
        uint256 packedTime = DL._getStorageData(DL._TIME_SLOT);
        uint256 packedConfig = DL._getStorageData(DL._CONFIG_SLOT);
        uint32 epochDur;
        uint32 periodDur;
        uint8 slotCount;
        assembly {
            epochDur := and(shr(96, packedTime), 0xffffffff)
            periodDur := and(shr(128, packedTime), 0xffffffff)
            slotCount := and(shr(24, packedConfig), 0xff)
        }
        uint256 periodsPerEpoch = epochDur / periodDur;
        uint32 currentPeriod;
        assembly {
            currentPeriod := and(shr(32, packedTime), 0xffffffff)
        }
        for (uint256 j = 1; j <= currentPeriod; j++) {
            amount += totalSupply(_shareId(epoch, j, outcomeSlot, slotCount, periodsPerEpoch));
        }
        return amount;
    }

    /**
     * @notice Changes the expiration epoch
     * @param newExpirationEpoch The new expiration epoch
     * @dev Only callable by owner. Emits ExpirationEpochChanged event.
     */
    function changeExpirationEpoch(uint32 newExpirationEpoch) public onlyOwner {
        uint256 packedTime = DL._getStorageData(DL._TIME_SLOT);
        uint32 currentEpoch;
        uint32 expEpoch;
        assembly {
            currentEpoch := and(packedTime, 0xffffffff)
            expEpoch := and(shr(64, packedTime), 0xffffffff)
        }
        if (
            (newExpirationEpoch < currentEpoch && newExpirationEpoch != 0) || currentEpoch > expEpoch
        ) {
            revert NewExpirationEpochMustBeGreaterThanCurrentEpoch(newExpirationEpoch, currentEpoch);
        }
        DL.TimeUpdate memory update = DL.TimeUpdate({
            currentEpoch: 0,
            currentPeriod: 0,
            expirationEpoch: newExpirationEpoch,
            epochDuration: 0,
            periodDuration: 0,
            periodStart: 0,
            epochStart: 0
        });
        DL.batchUpdateTimeInfo(update, DL.FLAG_UPDATE_EXPIRATION_EPOCH);
        emit ExpirationEpochChanged(newExpirationEpoch, block.timestamp);
    }

    /**
     * @notice Changes the fee rate
     * @param newFee The new fee rate in basis points
     * @dev Only callable by owner. Emits FeeChanged event.
     */
    function changeFee(uint64 newFee) external onlyOwner {
        if (newFee >= RANGE) {
            revert FeeMustBeLessThanRange(newFee, RANGE);
        }
        DL.ConfigUpdate memory update = DL.ConfigUpdate({
            version: 0,
            alpha: 0,
            fee: newFee,
            gamma: 0,
            decimals: 0,
            outcomeSlotCount: 0,
            feeReceived: 0
        });
        DL.batchUpdateConfigInfo(update, DL.FLAG_UPDATE_FEE);
        emit FeeChanged(block.timestamp, newFee);
    }

    /**
     * @notice Withdraws accumulated fees to the owner
     * @dev Only callable by owner. Emits FeeWithdrawal event.
     */
    function withdrawFee() external onlyOwner {
        uint256 packedConfig = DL._getStorageData(DL._CONFIG_SLOT);
        uint128 currentFeeReceived = uint128((packedConfig & DL.MASK_FEE_RECIEVED) >> DL.SHIFT_FEE_RECIEVED);
        if (currentFeeReceived == 0) {
            revert InsufficientBalance(0, currentFeeReceived);
        }
        DL.ConfigUpdate memory update = DL.ConfigUpdate({
            version: 0,
            fee: 0,
            gamma: 0,
            decimals: 0,
            outcomeSlotCount: 0,
            alpha: 0,
            feeReceived: -int128(currentFeeReceived)
        });
        DL.batchUpdateConfigInfo(update, DL.FLAG_UPDATE_FEE_RECEIVED);
        IERC20(collateralToken).safeTransfer(owner(), currentFeeReceived);
        emit FeeWithdrawal(block.timestamp, currentFeeReceived);
    }

    // ============ Internal Functions ============

    /**
     * @notice Validates that user has enough shares to sell
     * @param shareIds Array of share IDs for each outcome
     * @param deltaOutcomeAmounts_ Array of token amount changes
     * @param slots Number of outcome slots
     * @param user Address of the user
     * @param isRollover Whether this is a rollover trade
     * @dev Reverts if user does not have enough shares
     */
    function _validateSellAmounts(uint256[] memory shareIds, int256[] calldata deltaOutcomeAmounts_, uint8 slots, address user, bool isRollover) internal view {
        for (uint256 i = 0; i < slots; ++i) {
            uint256 id = shareIds[i];
            if (deltaOutcomeAmounts_[i] < 0) {
                uint256 balance = balanceOf(user, id);
                if (isRollover) {
                    balance = blockedForUser[user][id];
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
     * @param normalizedCost Absolute trade amount expressed in collateral units
     * @param user Address of the user making the trade
     * @param currentEpoch Current epoch number
     * @param currentFee Current fee rate in basis points
     * @param isBuy True if the user is buying, false if selling
     * @return feeAmount The fee amount charged
     */
    function _handleTradePayment(uint256 normalizedCost, address user, uint32 currentEpoch, uint64 currentFee, bool isBuy) internal returns (uint256 feeAmount) {
        if (isBuy) {
            uint256 shouldPay = (normalizedCost * RANGE) / (RANGE - currentFee);
            feeAmount = shouldPay - normalizedCost;
            epochData[currentEpoch].funding += normalizedCost;
            IERC20(collateralToken).safeTransferFrom(user, address(this), shouldPay);
        } else {
            feeAmount = (normalizedCost * currentFee) / RANGE;
            if ( epochData[currentEpoch].funding < normalizedCost) {
                revert InsufficientBalance(epochData[currentEpoch].funding, normalizedCost);
            }
            epochData[currentEpoch].funding -= normalizedCost;
            IERC20(collateralToken).safeTransfer(user, normalizedCost - feeAmount);
        }
    }

    /**
     * @notice Updates user shares for each outcome
     * @param user Address of the user
     * @param shareIds Array of share IDs for each outcome
     * @param deltaOutcomeAmounts_ Array of token amount changes
     * @param slots Number of outcome slots
     * @param isRollover Whether this is a rollover trade
     * @dev Mints or burns outcome tokens as needed
     */
    function _updateUserShares(address user, uint256[] memory shareIds, int256[] calldata deltaOutcomeAmounts_, uint8 slots, bool isRollover) internal {
        for (uint256 i = 0; i < slots; ++i) {
            uint256 id = shareIds[i];
            if (deltaOutcomeAmounts_[i] > 0) {
                if (isRollover) {
                    blockedForUser[user][id] += uint256(deltaOutcomeAmounts_[i]);
                    blockedForEpoch[id] += uint256(deltaOutcomeAmounts_[i]);
                    _mint(address(this), id, uint256(deltaOutcomeAmounts_[i]), "");
                } else {
                    _mint(user, id, uint256(deltaOutcomeAmounts_[i]), "");
                }
            } else if (deltaOutcomeAmounts_[i] < 0) {
                if (isRollover) {
                    blockedForUser[user][id] -= uint256(-deltaOutcomeAmounts_[i]);
                    blockedForEpoch[id] -= uint256(-deltaOutcomeAmounts_[i]);
                    _burn(address(this), id, uint256(-deltaOutcomeAmounts_[i]));
                } else {
                    _burn(user, id, uint256(-deltaOutcomeAmounts_[i]));
                }
            }
        }
    }

    /**
     * @notice Computes and stores base prices for each outcome based on payouts
     * @param payouts Array of payout numerators for each outcome
     * @param ctx Epoch context containing current epoch, denominator and collateral decimals
     * @dev Writes base prices directly to storage, avoiding unnecessary memory copies
     */
    function _computeAndStoreBasePrices(uint256[] calldata payouts, EpochContext memory ctx) internal {
        EpochData storage epoch = epochData[ctx.currentEpoch];
        for (uint256 i = 0; i < ctx.slotCount; i++) {
            epoch.basePrice[i] = (payouts[i] * ctx.decCollateral) / ctx.payoutDenominator;
        }
    }

    /**
     * @notice Processes all periods of an epoch, calculating payouts and rollover amounts
     * @param ctx Epoch context containing slot count and other epoch data
     * @return r Result containing total payout and total payout rollover
     * @dev Iterates through all outcomes and periods, calculates weighted shares, burns tokens, and computes payouts
     */
    function _processEpochPeriods(EpochContext memory ctx) internal returns (CloseEpochResult memory r) {
        uint256 packedTime = DL._getStorageData(DL._TIME_SLOT);
        uint32 currentEpoch;
        uint32 epochDur;
        uint32 periodDur;
        assembly {
            currentEpoch := and(packedTime, 0xffffffff)
            epochDur := and(shr(96, packedTime), 0xffffffff)
            periodDur := and(shr(128, packedTime), 0xffffffff)
        }
        
        EpochData storage epoch = epochData[currentEpoch];
        uint256 periodsPerEpoch = epochDur / periodDur;
        uint256 weightedShares;
        uint256 totalPayoutRollover_i;
        uint256 outcomeTokenAmount_i;
        uint256 newTokenId;
        
        for (uint256 i = 0; i < ctx.slotCount; i++) {
            weightedShares = 0;
            for (uint256 j = 1; j <= periodsPerEpoch; j++) {
                newTokenId = _shareId(currentEpoch, j, i, ctx.slotCount, periodsPerEpoch);
                uint256 supply = totalSupply(newTokenId);
                outcomeTokenAmount_i = supply - blockedForEpoch[newTokenId];

                if (outcomeTokenAmount_i != 0) {
                    weightedShares += (outcomeTokenAmount_i * gammaPow[j - 1]);
                }
                totalPayoutRollover_i += blockedForEpoch[newTokenId]; 
                _burn(address(this), newTokenId, blockedForEpoch[newTokenId]);
            }
            uint256 rolloverForOutcome = (totalPayoutRollover_i - blockedForUser[address(this)][_shareId(currentEpoch, 1, i, ctx.slotCount, periodsPerEpoch)]) * epoch.basePrice[i];
            r.totalPayoutRollover += rolloverForOutcome;
            totalPayoutRollover_i = 0;
            weightedShares /= RANGE;
            r.totalPayout += weightedShares * epoch.basePrice[i];
        }
        r.totalPayoutRollover /= uint128(decQ);
        r.totalPayout /= uint128(decQ);
    }

    /**
     * @notice Stores end epoch funding data (total payout and rollover funding)
     * @param epoch The epoch number to store funding for
     * @param r Close epoch result containing total payout and rollover amounts
     * @dev Saves funding data to packed storage for the specified epoch
     */
    function _storeEndEpochFunding(uint32 epoch, CloseEpochResult memory r) internal {
        bytes32 slot = DL.calculateMapPackedEndEpochFundingSlot(DL._END_EPOCH_FUNDING_SLOT, epoch);
        uint256 packedEndEpochFunding = DL._getStorageData(slot);
        packedEndEpochFunding = (packedEndEpochFunding & ~DL.MASK_FUNDING_FOR_ROLLOVER) | (uint256(r.totalPayoutRollover) << DL.SHIFT_FUNDING_FOR_ROLLOVER);
        packedEndEpochFunding = (packedEndEpochFunding & ~DL.MASK_TOTAL_PAYOUT) | (uint256(r.totalPayout) << DL.SHIFT_TOTAL_PAYOUT);
        DL._setStorageData(slot, packedEndEpochFunding);
    }

    /**
     * @notice Advances to the next epoch, updating time state and epoch funding
     * @param ctx Epoch context containing current epoch and slot count
     * @param r Close epoch result containing total payout
     * @dev Updates current epoch, resets period to 1, sets new epoch start time, and updates funding
     */
    function _advanceEpoch(EpochContext memory ctx, CloseEpochResult memory r) internal {
        uint32 newEpoch = ctx.currentEpoch + 1;
        uint32 now32 = uint32(block.timestamp);
        
        // Update epoch and period using DataLayoutLibrary
        DL.TimeUpdate memory timeUpdate = DL.TimeUpdate({
            currentEpoch: newEpoch,
            currentPeriod: 1,
            expirationEpoch: 0,
            epochDuration: 0,
            periodDuration: 0,
            periodStart: now32,
            epochStart: now32
        });
        uint8 timeFlags = DL.FLAG_UPDATE_CURRENT_EPOCH 
                        | DL.FLAG_UPDATE_CURRENT_PERIOD
                        | DL.FLAG_UPDATE_PERIOD_START
                        | DL.FLAG_UPDATE_EPOCH_START;
        DL.batchUpdateTimeInfo(timeUpdate, timeFlags);
        
        epochData[newEpoch].funding =
            epochData[ctx.currentEpoch].funding - r.totalPayout;
    }

    /**
     * @notice Mints rollover shares for the new epoch based on rollover payout
     * @param ctx Epoch context containing slot count
     * @param r Rollover data containing new epoch, current epoch, payout amount, and decimals
     * @dev Calculates and mints tokens for each outcome based on rollover payout and base prices from storage
     */
    function _mintRolloverShares(EpochContext memory ctx, RolloverData memory r) internal {
        uint256 packedTime = DL._getStorageData(DL._TIME_SLOT);
        uint32 epochDur;
        uint32 periodDur;
        assembly {
            epochDur := and(shr(96, packedTime), 0xffffffff)
            periodDur := and(shr(128, packedTime), 0xffffffff)
        }
        EpochData storage epoch = epochData[r.currentEpoch];
        uint256 periodsPerEpoch = epochDur / periodDur;
        for (uint256 i = 0; i < ctx.slotCount; i++) {
            uint256 newTokenId = _shareId(r.newEpoch, 1, i, ctx.slotCount, periodsPerEpoch);
            uint256 rolloverAmount = r.totalPayoutRollover * r.decQ / epoch.basePrice[i];
            blockedForEpoch[newTokenId] += rolloverAmount;
            _mint(address(this), newTokenId, blockedForEpoch[newTokenId], "");
        }
    }

    /**
     * @notice Closes the current epoch by processing payouts and advancing to the next epoch
     * @param payouts Array of payout numerators for each outcome
     * @dev Validates payouts, calculates base prices, processes epoch periods, mints rollover shares, stores funding data, and advances epoch
     */
    function _closeEpoch(uint256[] calldata payouts) internal {
        uint256 payoutLength = payouts.length;
        uint256 packedTime = DL._getStorageData(DL._TIME_SLOT);
        uint256 packedConfig = DL._getStorageData(DL._CONFIG_SLOT);
        uint32 currentEpoch;
        uint8 slotCount;
        assembly {
            currentEpoch := and(packedTime, 0xffffffff)
            slotCount := and(shr(24, packedConfig), 0xff)
        }
        
        // Validate payout array length
        if (payoutLength != uint256(slotCount)) {
            revert InvalidLength(payoutLength, uint256(slotCount));
        }

        // Calculate payout denominator
        uint256 payoutDenominator_ = _calculatePayoutDenominator(payouts);
        if (payoutDenominator_ == 0) {
            revert PayoutIsAllZeroes();
        }

        epochData[currentEpoch].payoutDenominator = payoutDenominator_;

        // Store payout numerators
        for (uint256 i = 0; i < slotCount; i++) {
            epochData[currentEpoch].payoutNumerators[i] = payouts[i];
        }

        // Compute and store base prices directly to storage
        EpochContext memory context = EpochContext({
            currentEpoch: currentEpoch,
            payoutDenominator: payoutDenominator_,
            decCollateral: uint128(decCollateral),
            slotCount: slotCount
        });
        _computeAndStoreBasePrices(payouts, context);

        CloseEpochResult memory r = _processEpochPeriods(context);

        uint32 newEpoch = currentEpoch + 1;
        RolloverData memory rolloverData = RolloverData({
            newEpoch: newEpoch,
            currentEpoch: currentEpoch,
            totalPayoutRollover: r.totalPayoutRollover,
            decQ: uint128(decQ)
        });
        _mintRolloverShares(context, rolloverData);
        
        _storeEndEpochFunding(context.currentEpoch, r);
        _advanceEpoch(context, r);
    }

    /**
     * @notice Redeems blocked tokens for a user
     * @param user Address of the user
     * @param epoch Epoch number
     * @param to Address to redeem to
     * @dev Emits Redeemed event
     */
    function _redeemBlocked(address user, uint32 epoch, address to) internal {
        uint256 totalPayout;
        uint256 id;
        uint256 balance;
        uint256 packedConfig = DL._getStorageData(DL._CONFIG_SLOT);
        uint256 packedTime = DL._getStorageData(DL._TIME_SLOT);
        uint8 slotCount;
        uint32 epochDur;
        uint32 periodDur;
        assembly {
            slotCount := and(shr(24, packedConfig), 0xff)
            epochDur := and(shr(96, packedTime), 0xffffffff)
            periodDur := and(shr(128, packedTime), 0xffffffff)
        }
        uint256[] memory deltaOutcomeAmounts = new uint256[](slotCount);
        uint256 periodsPerEpoch = epochDur / periodDur;        

        for (uint256 i = 0; i < slotCount; i++) {
            for (uint256 j = 1; j <= periodsPerEpoch; j++) {
                id = _shareId(epoch, j, i, slotCount, periodsPerEpoch);
                balance = blockedForUser[user][id];
                blockedForUser[user][id] = 0;
                deltaOutcomeAmounts[i] += balance;
            }
        }

        uint32 currentEpoch;
        assembly {
            currentEpoch := and(packedTime, 0xffffffff)
        }
        for (uint256 e = epoch; e < currentEpoch; e++) {
            for (uint256 i = 0; i < slotCount; i++) {
                totalPayout += ((deltaOutcomeAmounts[i] * epochData[e].basePrice[i])/uint128(decQ)); // decQ * decColl
            }

            if(totalPayout > 0) {
                for (uint256 i = 0; i < slotCount; i++) {
                    // decQ * decColl / decColl
                    deltaOutcomeAmounts[i] = totalPayout * uint128(decQ) / epochData[e].basePrice[i];
                }  
                if (e != currentEpoch - 1) totalPayout = 0;
            }      
        }
        for (uint256 i = 0; i < slotCount; i++) {
            id = _shareId(currentEpoch, 1, i, slotCount, periodsPerEpoch);
            blockedForEpoch[id] -= deltaOutcomeAmounts[i];
            _burn(address(this), id, deltaOutcomeAmounts[i]);
        }
        IERC20(collateralToken).safeTransfer(to, totalPayout);
        uint32 currentPeriod;
        assembly {
            currentPeriod := and(shr(32, packedTime), 0xffffffff)
        }
        emit ClaimForNewEpoch(user, deltaOutcomeAmounts, currentEpoch, currentPeriod);
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
     * @param now32 Current block timestamp
     * @param epochStart Start timestamp of the current epoch
     * @param epochDur Duration of an epoch in seconds
     * @param periodDur Duration of a period in seconds
     * @param periodStartTime Start timestamp of the current period
     * @param currentEpoch Current epoch number
     * @param currentPeriod Current period number
     * @return newCurrentPeriod Updated current period number
     * @return newStart Updated period start timestamp
     * @dev Automatically advances epochs and periods as time passes
     */
    function _updateEpochAndPeriod(
        uint32 now32, 
        uint32 epochStart, 
        uint32 epochDur, 
        uint32 periodDur, 
        uint32 periodStartTime,
        uint32 currentEpoch,
        uint32 currentPeriod
    ) private returns (uint32 newCurrentPeriod, uint32 newStart) {
        if (now32 >= epochStart + epochDur) {
            revert EpochFinishedButNotResolvedYet(currentEpoch);
        }
        newCurrentPeriod = currentPeriod;
        newStart = periodStartTime;

        if (now32 < periodStartTime + periodDur) return (newCurrentPeriod, newStart);

        uint32 steps = (now32 - periodStartTime) / periodDur; // >=1

        uint32 periodsPerEpoch = epochDur / periodDur;
        uint32 target = currentPeriod + steps;
        if (target > periodsPerEpoch) {
            target = periodsPerEpoch;
        }

        newStart = periodStartTime + (target - currentPeriod) * periodDur;
        newCurrentPeriod = target;
        emit EpochAndPeriodUpdated(currentEpoch, target);
    }

    /**
     * @notice Sends remaining market shares to the owner after resolution
     * @dev Emits SendMarketsSharesToOwner event
     */
    function _sendMarketsSharesToOwner() private {
        uint256 packedTime = DL._getStorageData(DL._TIME_SLOT);
        uint32 currentEpoch;
        assembly {
            currentEpoch := and(packedTime, 0xffffffff)
        }
        bytes32 slot = DL.calculateMapPackedEndEpochFundingSlot(DL._END_EPOCH_FUNDING_SLOT, currentEpoch - 1);
        uint256 packedEndEpochFunding = DL._getStorageData(slot);
        uint256 fundingForRollover = uint256((packedEndEpochFunding & DL.MASK_FUNDING_FOR_ROLLOVER) >> DL.SHIFT_FUNDING_FOR_ROLLOVER);
        uint256 returnToOwner = epochData[currentEpoch].funding - fundingForRollover;
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
        override(ERC1155HolderUpgradeable, ERC1155Upgradeable)
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
    function _shareId(uint256 epoch, uint256 period, uint256 outcome, uint256 slotCount, uint256 periodsPerEpoch) internal pure returns (uint256) {
        uint256 e = epoch - 1;
        uint256 p = period - 1;
        uint256 epochOffset = e * periodsPerEpoch * slotCount;
        uint256 periodOffset = p * slotCount;
        return epochOffset + periodOffset + outcome;
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
        uint256 packedTime = DL._getStorageData(DL._TIME_SLOT);
        uint256 packedConfig = DL._getStorageData(DL._CONFIG_SLOT);
        uint32 epochDur;
        uint32 periodDur;
        uint8 slotCount;
        assembly {
            epochDur := and(shr(96, packedTime), 0xffffffff)
            periodDur := and(shr(128, packedTime), 0xffffffff)
            slotCount := and(shr(24, packedConfig), 0xff)
        }
        uint256 periodsPerEpoch = epochDur / periodDur;
        return _shareId(epoch, period, outcome, slotCount, periodsPerEpoch);
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
        uint256 packedTime = DL._getStorageData(DL._TIME_SLOT);
        uint256 packedConfig = DL._getStorageData(DL._CONFIG_SLOT);
        uint32 epochDur;
        uint32 periodDur;
        uint8 slotCount;
        assembly {
            epochDur := and(shr(96, packedTime), 0xffffffff)
            periodDur := and(shr(128, packedTime), 0xffffffff)
            slotCount := and(shr(24, packedConfig), 0xff)
        }
        uint256 periodsPerEpoch = epochDur / periodDur;

        // Decode outcome: id % outcomeSlotCount
        outcome = id % slotCount;

        // Decode period and epoch from periodOffset
        uint256 periodOffset = id - outcome;
        uint256 periodIndex = periodOffset / slotCount;

        // Decode period: periodIndex % periodsPerEpoch
        period = (periodIndex % periodsPerEpoch) + 1; // Convert to 1-based

        // Decode epoch: periodIndex / periodsPerEpoch
        epoch = (periodIndex / periodsPerEpoch) + 1; // Convert to 1-based
    }

    /**
     * @notice Checks if the epoch is not resolved and not expired
     * @param currentEpoch Current epoch number
     * @param epochStart Start timestamp of the current epoch
     * @param epochDur Duration of an epoch in seconds
     * @param expEpoch Expiration epoch number (0 if no expiration)
     * @return True if epoch is not resolved and not expired
     */
    function epochNotResolvedAndNotExpired(uint256 currentEpoch, uint32 epochStart, uint32 epochDur, uint32 expEpoch) internal view returns (bool) {
        if (epochData[currentEpoch].payoutDenominator != 0 && block.timestamp < epochStart + epochDur) {
            return false;
        }
        if (expEpoch != 0 && currentEpoch > expEpoch) {
            return false;
        }
        return true;
    }

    /**
     * @notice Checks if the epoch has been resolved
     * @param currentEpoch Epoch number to check
     * @return True if the epoch has been resolved (payout denominator is set)
     */
    function epochResolved(uint256 currentEpoch) internal view returns (bool) {
        if (epochData[currentEpoch].payoutDenominator == 0) {
            return false;
        }
        return true;
    }

    /**
     * @notice Initializes gamma powers for time-weighted rewards
     * @param gamma The gamma parameter for reward decay
     * @dev Sets up decreasing multipliers for later periods to incentivize early predictions
     */
    function _initializeGammaPowers(uint32 gamma) internal {
        uint256 packedTime = DL._getStorageData(DL._TIME_SLOT);
        uint32 epochDur;
        uint32 periodDur;
        assembly {
            epochDur := and(shr(96, packedTime), 0xffffffff)
            periodDur := and(shr(128, packedTime), 0xffffffff)
        }
        uint32 periodNumber = epochDur / periodDur;
        gammaPow = new uint32[](periodNumber);
        gammaPow[0] = RANGE;

        for (uint32 i = 1; i < periodNumber; i++) {
            gammaPow[i] = (gammaPow[i - 1] * gamma) / RANGE;
        }
    }


}
