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
import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IDynamica} from "./interfaces/IDynamica.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC1155Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC1155HolderUpgradeable} from
    "@openzeppelin-contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {console} from "forge-std/src/console.sol";

/**
 * @title MarketMaker v2
 * @dev A perpetual prediction market maker contract that allows users to buy and sell outcome tokens.
 *      Implements epoch and period-based market making logic for multi-outcome prediction markets.
 *      Uses ERC1155 tokens for outcome representation with time-weighted rewards.
 *      Supports continuous trading with automatic epoch transitions.
 */
contract MarketMaker is
    Initializable,
    OwnableUpgradeable,
    ERC1155Upgradeable,
    ERC1155HolderUpgradeable,
    ReentrancyGuard,
    IDynamica
{
    using SafeERC20 for IERC20;

    // ============ CONSTANTS ============

    /// @notice Maximum number of outcome slots supported
    uint256 public constant MAX_SLOT_COUNT = 10;

    /// @notice Maximum fee/gamma that can be set (100% in basis points)
    uint32 public constant RANGE = 10_000;

    /// @notice Unit decimal for calculations (18 decimals)
    int256 public constant UNIT_DEC = 1e18;

    // ============ STATE VARIABLES ============

    // Time Management
    /// @notice Duration of each epoch in seconds
    uint32 public epochDuration;

    /// @notice Duration of each period within an epoch in seconds
    uint32 public periodDuration;

    /// @notice Current period number (1-based)
    uint32 public currentPeriodNumber;

    /// @notice Current epoch number (1-based)
    uint32 public currentEpochNumber;

    /// @notice Last epoch number
    uint32 public lastEpoch;

    // Decimal Precision
    /// @notice Collateral token decimals
    int256 public decCollateral;

    /// @notice Outcome token decimals
    int256 public decQ;

    /// @notice Array of gamma power values for time-weighted rewards
    uint32[] public gammaPow;

    // ============ MAPPINGS ============

    /// @notice Mapping from epoch number to epoch data
    mapping(uint256 => EpochData) public epochData;

    /// @notice Mapping from epoch number to period number to period data
    mapping(uint256 => mapping(uint256 => PeriodData)) public periodData;

    // Market Configuration
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

    // ============ MODIFIERS ============

    /// @notice Ensures the epoch is not yet resolved
    modifier epochNotResolved(uint256 epoch) {
        if (epochData[epoch].payoutDenominator != 0) {
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

    // ============ INITIALIZATION ============

    /**
     * @notice Initializes the market with funding and outcome configuration
     * @param config The configuration for the market
     * @dev Emits MarketInitialized event
     */
    function initializeMarket(Config calldata config) internal {
        currentEpochNumber = 1;
        currentPeriodNumber = 1;
        epochDuration = config.epochDuration;
        periodDuration = config.periodDuration;
        oracleManager = config.oracle;
        question = config.question;
        outcomeSlotCount = config.outcomeSlotCount;
        expirationEpoch = config.expirationEpoch;

        // Initialize first epoch and period
        epochData[currentEpochNumber].epochStart = uint32(block.timestamp);
        periodData[currentEpochNumber][currentPeriodNumber].epochNumber = currentEpochNumber;
        periodData[currentEpochNumber][currentPeriodNumber].periodStart = uint32(block.timestamp);
        epochData[currentEpochNumber].funding = config.startFunding;

        // Transfer initial funding
        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), config.startFunding);

        // Set decimals and initialize decimal constants
        decimals = config.decimals;
        uint8 collateralTokenDecimals = IERC20Metadata(collateralToken).decimals();
        decCollateral = int256(10 ** collateralTokenDecimals);
        decQ = int256(10 ** uint32(decimals));

        // Create initial outcome tokens
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            _mint(address(this), shareId(currentEpochNumber, currentPeriodNumber, i), config.outcomeTokenAmounts, "");
            epochData[currentEpochNumber].outcomeTokenSupplies[i] = config.outcomeTokenAmounts;
        }

        emit MarketInitialized(msg.value, config.question, config.outcomeTokenAmounts);
    }

    // ============ PUBLIC FUNCTIONS ============

    function updateEpochAndPeriod() public onlyOwner {
        _updateEpochAndPeriod();
    }

    /**
     * @notice Changes the expiration epoch
     * @param newExpirationEpoch The new expiration epoch
     * @dev Only callable by owner. Emits ExpirationEpochChanged event.
     */
    function changeExpirationEpoch(uint32 newExpirationEpoch) public onlyOwner {
        if (
            (newExpirationEpoch < currentEpochNumber && newExpirationEpoch != 0) || currentEpochNumber > expirationEpoch
        ) {
            revert NewExpirationEpochMustBeGreaterThanCurrentEpoch(newExpirationEpoch, currentEpochNumber);
        }
        expirationEpoch = newExpirationEpoch;
        emit ExpirationEpochChanged(newExpirationEpoch, block.timestamp);
    }

    /**
     * @notice Makes a prediction by buying or selling outcome tokens
     * @param deltaOutcomeAmounts_ Array of token amount changes for each outcome
     *        Positive values = buying tokens, Negative values = selling tokens
     * @dev Emits OutcomeTokenTrade event
     */
    function makePrediction(int256[] memory deltaOutcomeAmounts_)
        external
        nonReentrant
        epochNotResolved(currentEpochNumber)
    {
        // Update epoch and period if needed
        _updateEpochAndPeriod();

        // Get current period data
        PeriodData storage pd = periodData[currentEpochNumber][currentPeriodNumber];

        // Validate input length
        if (deltaOutcomeAmounts_.length != outcomeSlotCount) {
            revert InvalidDeltaOutcomeAmountsLength(deltaOutcomeAmounts_.length, outcomeSlotCount);
        }

        // Validate sell amounts
        _validateSellAmounts(deltaOutcomeAmounts_);

        // Calculate net cost and process payment
        int256 netCost = calcNetCost(deltaOutcomeAmounts_);
        bool isBuy = netCost > 0;
        uint256 cost = isBuy ? uint256(netCost) : uint256(-netCost);

        // Update user shares
        _updateUserShares(pd, deltaOutcomeAmounts_);

        // Handle payment and fees
        uint256 feeAmount = _handleTradePayment(cost, isBuy);

        emit OutcomeTokenTrade(msg.sender, deltaOutcomeAmounts_, netCost, feeAmount);
    }

    function checkEpoch() public view returns (bool) {
        return (block.timestamp >= epochData[currentEpochNumber].epochStart + epochDuration)
            || (expirationEpoch != 0 && currentEpochNumber > expirationEpoch);
    }

    /**
     * @notice Returns the payout numerator for a specific outcome in the previous epoch
     * @param i Index of the outcome
     * @return The payout numerator
     */
    function payoutNumerators(uint256 epoch, uint256 i) external view returns (uint256) {
        return epochData[epoch].payoutNumerators[i];
    }

    /**
     * @notice Returns the payout denominator for the previous epoch
     * @return The payout denominator
     */
    function payoutDenominator(uint256 epoch) external view returns (uint256) {
        return epochData[epoch].payoutDenominator;
    }

    /**
     * @notice Returns the supply for a specific outcome token in the current epoch
     * @param i Index of the outcome
     * @return The token supply
     */
    function outcomeTokenSupplies(uint256 epoch, uint256 i) external view returns (uint256) {
        return epochData[epoch].outcomeTokenSupplies[i];
    }

    /**
     * @notice Closes the current epoch by resolving it with payout ratios
     * @param payouts Array of payout numerators for each outcome
     * @dev Only callable by the oracle manager. Emits MarketResolved event.
     */
    function closeEpoch(uint256[] calldata payouts)
        external
        onlyOracleManager
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
     * @dev Calculates payout based on user's shares and resolved outcome ratios. Emits PayoutRedemption event.
     */
    function redeemPayout(uint32 epoch) external nonReentrant epochResolved(epoch) {
        uint256 totalPayout = 0;
        uint256 periodsPerEpoch = epochDuration / periodDuration;

        // Calculate payout for each outcome across all periods
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            for (uint256 j = 1; j <= periodsPerEpoch; j++) {
                uint256 id = shareId(epoch, j, i);
                uint256 balance = balanceOf(msg.sender, id);

                if (balance > 0) {
                    totalPayout += (balance * gammaPow[j - 1] * epochData[epoch].basePrice[i] / uint256(decQ)) / RANGE;
                    _burnToken(msg.sender, balance, id);
                }
            }
        }

        if (totalPayout == 0) {
            revert NothingToRedeem();
        }

        console.log("totalPayout", totalPayout);

        IERC20(collateralToken).safeTransfer(msg.sender, totalPayout);

        emit PayoutRedemption(msg.sender, collateralToken, question, totalPayout);
    }

    /**
     * @notice Calculates the net cost for a trade
     * @param outcomeTokenAmounts Array of token amount changes
     * @return netCost The net cost of the trade (positive = user pays, negative = user receives)
     */
    function calcNetCost(int256[] memory outcomeTokenAmounts) public view virtual returns (int256) {
        // This function should be implemented by derived contracts
        // revert("Not implemented");
    }

    /**
     * @notice Changes the fee rate
     * @param _fee The new fee rate in basis points
     * @dev Only callable by owner. Emits FeeChanged event.
     */
    function changeFee(uint64 _fee) external onlyOwner {
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
    function withdrawFee() external nonReentrant onlyOwner {
        if (feeReceived == 0) {
            revert NoFeesToWithdraw();
        }
        uint256 amount = feeReceived;
        feeReceived = 0;
        IERC20(collateralToken).safeTransfer(owner(), amount);
        emit FeeWithdrawal(block.timestamp, amount);
    }

    function emergencyExit(address token) external nonReentrant onlyOwner {
        uint256 amount = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(owner(), amount);
        emit EmergencyExit(block.timestamp, token, amount);
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @notice Validates that user has enough shares to sell
     * @param deltaOutcomeAmounts_ Array of token amount changes
     * @dev Reverts if user does not have enough shares
     */
    function _validateSellAmounts(int256[] memory deltaOutcomeAmounts_) private view {
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            if (deltaOutcomeAmounts_[i] < 0) {
                uint256 balance = balanceOf(msg.sender, shareId(currentEpochNumber, currentPeriodNumber, i));
                uint256 amount = uint256(-deltaOutcomeAmounts_[i]);
                if (balance < amount) {
                    revert InsufficientSharesToSell(msg.sender, amount, balance);
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
            epochData[currentEpochNumber].funding += shouldPay;
            IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), shouldPay);
        } else {
            feeAmount = (netCost * fee) / RANGE;
            feeReceived += feeAmount;
            uint256 payoutAmount = netCost - feeAmount;
            epochData[currentEpochNumber].funding -= payoutAmount;
            IERC20(collateralToken).safeTransfer(msg.sender, payoutAmount);
        }
    }

    /**
     * @notice Updates user shares for each outcome
     * @param pd Period data storage reference
     * @param deltaOutcomeAmounts_ Array of token amount changes
     * @dev Mints or burns outcome tokens as needed
     */
    function _updateUserShares(PeriodData storage pd, int256[] memory deltaOutcomeAmounts_) private {
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            if (deltaOutcomeAmounts_[i] > 0) {
                // Mint tokens for buying
                epochData[currentEpochNumber].outcomeTokenSupplies[i] += uint256(deltaOutcomeAmounts_[i]);
                pd.outcomeTokenAmounts[i] += uint256(deltaOutcomeAmounts_[i]);
                _mintToken(
                    msg.sender, uint256(deltaOutcomeAmounts_[i]), shareId(currentEpochNumber, currentPeriodNumber, i)
                );
            } else if (deltaOutcomeAmounts_[i] < 0) {
                // Burn tokens for selling
                epochData[currentEpochNumber].outcomeTokenSupplies[i] -= uint256(-deltaOutcomeAmounts_[i]);
                pd.outcomeTokenAmounts[i] -= uint256(-deltaOutcomeAmounts_[i]);
                _burnToken(
                    msg.sender, uint256(-deltaOutcomeAmounts_[i]), shareId(currentEpochNumber, currentPeriodNumber, i)
                );
            }
        }
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
        uint32 newEpoch = 0;

        // Check if epoch should advance
        if (now32 >= epochData[currentEpochNumber].epochStart + epochDuration) {
            revert EpochFinishedButNotResolvedYet(currentEpochNumber);
        }

        // Check if period should advance within current epoch
        if (newEpoch == 0 && now32 >= periodData[currentEpochNumber][currentPeriodNumber].periodStart + periodDuration)
        {
            uint32 currentPeriod =
                (now32 - periodData[currentEpochNumber][currentPeriodNumber].periodStart) / periodDuration;
            currentPeriodNumber += currentPeriod;
            periodData[currentEpochNumber][currentPeriodNumber].periodStart = now32;
            periodData[currentEpochNumber][currentPeriodNumber].epochNumber = currentEpochNumber;
        }
    }

    /**
     * @notice Sends remaining market shares to the owner after resolution
     * @dev Emits SendMarketsSharesToOwner event
     */
    function _sendMarketsSharesToOwner() private {
        uint256 balance = epochData[currentEpochNumber].funding;
        if (IERC20(collateralToken).balanceOf(address(this)) < balance) {
            revert NotEnoughCollateralToCoverPayouts(balance - IERC20(collateralToken).balanceOf(address(this)));
        }
        uint256 returnToOwner = balance;
        IERC20(collateralToken).safeTransfer(owner(), returnToOwner);
        emit SendMarketsSharesToOwner(block.timestamp, returnToOwner);
    }

    function _closeEpoch(uint256[] calldata payouts) private {
        uint256 _outcomeSlotCount = payouts.length;

        // Validate payout array length
        if (_outcomeSlotCount != outcomeSlotCount) {
            revert MustHaveExactlyOutcomeSlotCount(_outcomeSlotCount, outcomeSlotCount);
        }

        // Calculate payout denominator
        uint256 payoutDenominator_ = _calculatePayoutDenominator(payouts);
        if (payoutDenominator_ == 0) {
            revert PayoutIsAllZeroes();
        }

        epochData[currentEpochNumber].payoutDenominator = payoutDenominator_;

        // Calculate total weighted shares across all periods in the epoch
        uint256[] memory totalWeightedShares = new uint256[](_outcomeSlotCount);
        uint256 periodsPerEpoch = epochDuration / periodDuration;

        for (uint256 i = 1; i <= periodsPerEpoch; i++) {
            for (uint256 j = 0; j < outcomeSlotCount; j++) {
                if (periodData[currentEpochNumber][i].outcomeTokenAmounts[j] != 0) {
                    totalWeightedShares[j] +=
                        ((periodData[currentEpochNumber][i].outcomeTokenAmounts[j] * gammaPow[i - 1]) / RANGE);
                }
            }
        }
        uint256 totalPayout;
        // Set payout numerators and calculate base prices
        for (uint256 i = 0; i < _outcomeSlotCount; i++) {
            if (epochData[currentEpochNumber].payoutNumerators[i] != 0) {
                revert PayoutNumeratorAlreadySet(i);
            }

            epochData[currentEpochNumber].payoutNumerators[i] = payouts[i];

            if (totalWeightedShares[i] != 0) {
                totalPayout += ((totalWeightedShares[i] * payouts[i] * uint256(DEC_COLLATERAL)) / payoutDenominator_ /uint256(DEC_Q));
                epochData[currentEpochNumber].basePrice[i] = (payouts[i] * uint256(DEC_COLLATERAL)) / payoutDenominator_;
                console.log('epochData[currentEpochNumber].basePrice[i]', epochData[currentEpochNumber].basePrice[i]);
            }
        }

        for (uint256 i = 0; i < _outcomeSlotCount; i++) {
            epochData[currentEpochNumber + 1].outcomeTokenSupplies[i] = epochData[currentEpochNumber].basePrice[i]
                * (epochData[currentEpochNumber].funding - totalPayout) / uint256(decCollateral);
            console.log("NEXT EPOCH", epochData[currentEpochNumber + 1].outcomeTokenSupplies[i]);
        }

        console.log("totalPayout", totalPayout);
        console.log("funds next epoch:", epochData[currentEpochNumber].funding - totalPayout);

        uint32 now32 = uint32(block.timestamp);
        uint32 newEpoch = (now32 - epochData[currentEpochNumber].epochStart) / epochDuration;
        lastEpoch = currentEpochNumber;
        currentEpochNumber += newEpoch;
        currentPeriodNumber = 1;
        epochData[currentEpochNumber].epochStart = now32;
        epochData[currentEpochNumber].funding = epochData[lastEpoch].funding - totalPayout;

        periodData[currentEpochNumber][currentPeriodNumber].periodStart = now32;
        periodData[currentEpochNumber][currentPeriodNumber].epochNumber = currentEpochNumber;
    }

    // ============ OVERRIDE FUNCTIONS ============

    /**
     * @notice Checks if the contract supports a specific interface
     * @param interfaceId The interface identifier
     * @return True if the interface is supported
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Upgradeable, ERC1155HolderUpgradeable)
        returns (bool)
    {
        return ERC1155Upgradeable.supportsInterface(interfaceId);
    }

    /**
     * @notice Calculates the unique share ID for (epoch, period, outcome)
     * @param epoch 1-based epoch number (1..∞)
     * @param period 1-based period number within epoch (1..periodsPerEpoch)
     * @param outcome 0-based outcome index (0..outcomeSlotCount-1)
     * @return The unique share ID
     * @dev Uses a hierarchical ID system: epoch * periodsPerEpoch * outcomeSlotCount + period * outcomeSlotCount + outcome
     */
    function shareId(uint256 epoch, uint256 period, uint256 outcome) public view returns (uint256) {
        uint256 e = epoch - 1;
        uint256 p = period - 1;
        uint256 epochOffset = e * epochDuration * outcomeSlotCount / periodDuration;
        uint256 periodOffset = p * outcomeSlotCount;
        return epochOffset + periodOffset + outcome;
    }
}