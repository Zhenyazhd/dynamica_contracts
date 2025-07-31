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

import {IERC20} from "../interfaces/IERC20.sol";
import {IDynamica} from "../interfaces/IDynamica.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {SD59x18, sd, exp, ln} from "@prb-math/src/SD59x18.sol";
import {ERC1155Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC1155HolderUpgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "forge-std/src/console.sol";
import "forge-std/src/Test.sol";

/**
 * @title MarketMaker
 * @dev A prediction market maker contract that allows users to buy and sell outcome tokens.
 *      Implements epoch-based market making logic for multi-outcome prediction markets.
 *      Uses ERC1155 tokens for outcome representation with time-weighted rewards.
 */
contract MarketMaker is Initializable, OwnableUpgradeable, ERC1155Upgradeable, ERC1155HolderUpgradeable, IDynamica {
    // ============ CONSTANTS ============
    
    /// @notice Maximum fee/gamma that can be set (100% in basis points)
    uint32 public constant RANGE = 10_000;
    
    /// @notice Number of epochs for the market lifecycle
    uint32 public constant EPOCH_NUMBER = 10;
        
    /// @notice Decimal precision for fixed-point arithmetic (18 decimals)
    int256 public constant UNIT_DEC = 1e18;

    // ============ STATE VARIABLES ============
    
    // Market Configuration
    /// @notice Address of the ERC20 collateral token
    address public collateralToken;
    
    /// @notice The question that this prediction market resolves
    string public question;
    
    /// @notice Number of possible outcomes in the market
    uint256 public outcomeSlotCount;
    
    /// @notice Expiration time of the market
    uint32 public expirationTime;
    
    /// @notice The fee rate in basis points (e.g., 300 = 3%)
    uint64 public fee;
    
    /// @notice Address of the oracle manager that can resolve the market
    address public oracleManager;
    
    /// @notice Decimals for outcome tokens
    int32 public decimals;
    
    // Market State
    /// @notice Array of payout numerators for each outcome
    uint256[] public payoutNumerators;
    
    /// @notice Payout denominator for calculating final payouts
    uint256 public payoutDenominator;
    
    /// @notice Total fees received from trades
    uint256 public feeReceived;
    
    /// @notice Array of supplies for each outcome token
    uint256[] public outcomeTokenSupplies;
    
    // Epoch Management
    /// @notice Duration of each epoch in seconds
    uint32 public epochDuration;
    
    /// @notice Current epoch number (1-based)
    uint32 public currentEpochNumber;
    
    /// @notice Array of gamma power values for each epoch (time-weighted multipliers)
    uint32[] public gammaPow;
    
    // Mathematical Parameters
    /// @notice Decimal precision for collateral calculations
    int256 public DEC_COLLATERAL;
    
    /// @notice Decimal precision for quantity calculations
    int256 public DEC_Q;
    
    /// @notice Exponential limit to prevent overflow in calculations
    SD59x18 public EXP_LIMIT_DEC;
    
    /// @notice Liquidity parameter that controls market depth and price sensitivity
    SD59x18 public alpha;
    
    /// @notice Array of base prices for each outcome
    uint256[] public basePrice;

    // ============ STRUCTS ============
    
    /// @notice Structure to store epoch-specific data
    struct EpochData {
        /// @notice Start timestamp of the epoch
        uint32 epochStart;
        /// @notice Array of outcome token amounts for this epoch
        uint256[] outcomeTokenAmounts;
    }

    // ============ MAPPINGS ============
    
    /// @notice Mapping from epoch number to epoch data
    mapping(uint256 => EpochData) public epochData;

    // ============ MODIFIERS ============

    /// @notice Ensures the market is not yet resolved
    modifier marketNotResolved() {
        if (payoutDenominator != 0) {
            revert MarketAlreadyResolved();
        }
        _;
    }

    /// @notice Ensures the market is resolved
    modifier marketResolved() {
        if (payoutDenominator == 0) {
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
     * @param oracle The oracle address that will resolve the condition
     * @param _question The question text that this market resolves
     * @param _outcomeSlotCount The number of possible outcomes
     * @param _startFunding The amount of funding to add to the market
     * @param _outcomeTokenAmounts The initial token amounts for each outcome
     * @param _decimals The decimals for the outcome tokens
     * @dev Emits MarketInitialized event
     */
    function initializeMarket(
        address oracle,
        string calldata _question,
        uint256 _outcomeSlotCount,
        uint256 _startFunding,
        uint256 _outcomeTokenAmounts,
        int32 _decimals
    ) internal {
        
        // Set market configuration
        oracleManager = oracle;
        question = _question;
        outcomeSlotCount = _outcomeSlotCount;
        
        // Initialize arrays for market state
        payoutNumerators = new uint256[](_outcomeSlotCount);
        outcomeTokenSupplies = new uint256[](_outcomeSlotCount);
        
        // Calculate epoch duration based on remaining time
        epochDuration = (expirationTime - uint32(block.timestamp)) / EPOCH_NUMBER;

        // Initialize first epoch
        currentEpochNumber = 1;
        epochData[currentEpochNumber].epochStart = uint32(block.timestamp);
        epochData[currentEpochNumber].outcomeTokenAmounts = new uint256[](_outcomeSlotCount);

        // Transfer initial funding from sender to contract
        if (!IERC20(collateralToken).transferFrom(msg.sender, address(this), _startFunding)) {
            revert TransferFailed();
        }
        
        // Set token decimals and initialize base price array
        decimals = _decimals;
        basePrice = new uint256[](_outcomeSlotCount);
        
        
        // Create outcome tokens for each possible outcome
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            _mint(
                address(this),
                shareId(currentEpochNumber, i),
                _outcomeTokenAmounts,
                ""
            );
            outcomeTokenSupplies[i] = _outcomeTokenAmounts;
        }
        emit MarketInitialized(msg.value, _question, _outcomeTokenAmounts);
    }

    // ============ PUBLIC FUNCTIONS ============

    /**
     * @notice Makes a prediction by buying or selling outcome tokens
     * @param deltaOutcomeAmounts_ Array of token amount changes for each outcome
     *        Positive values = buying tokens, Negative values = selling tokens
     * @dev Emits OutcomeTokenTrade event
     */
    function makePrediction(int256[] calldata deltaOutcomeAmounts_) external marketNotResolved {
        _updateEpoch();
        
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
        uint256 feeAmount = _handleTradePayment(cost, isBuy);
        
        // Update user shares
        _updateUserShares(deltaOutcomeAmounts_);
        
        emit OutcomeTokenTrade(msg.sender, deltaOutcomeAmounts_, netCost, feeAmount);
    }

    /**
     * @notice Closes the market by resolving the condition with payout ratios
     * @param payouts Array of payout numerators for each outcome
     * @dev Only callable by the oracle manager. Emits MarketResolved event.
     */
    function closeMarket(uint256[] calldata payouts) external onlyOracleManager marketNotResolved {
        uint256 _outcomeSlotCount = payouts.length;
     
        // Validate payout array length
        if (_outcomeSlotCount != outcomeSlotCount) {
            revert MustHaveExactlyOutcomeSlotCount(_outcomeSlotCount, outcomeSlotCount);
        }
        
        // Calculate payout denominator
        payoutDenominator = _calculatePayoutDenominator(payouts);
        if (payoutDenominator == 0) {
            revert PayoutIsAllZeroes();
        }

        uint256 totalPayout = 0;
        uint256[] memory totalWeightedShares = new uint256[](_outcomeSlotCount);

        // Calculate total weighted shares across all epochs
        for (uint256 i = 1; i <= EPOCH_NUMBER; i++) {
            for (uint256 j = 0; j < outcomeSlotCount; j++) {
                totalWeightedShares[j] += ((epochData[i].outcomeTokenAmounts[j] * gammaPow[i-1]) / RANGE);
            }
        }

        // Set payout numerators and calculate base prices
        for (uint256 i = 0; i < _outcomeSlotCount; i++) {
            if (payoutNumerators[i] != 0) {
                revert PayoutNumeratorAlreadySet(i);
            }
            payoutNumerators[i] = payouts[i];
            uint256 totalPayout_i = (totalWeightedShares[i] * payoutNumerators[i]) / payoutDenominator;
            totalPayout += totalPayout_i;
            
            if (totalWeightedShares[i] != 0) {
                basePrice[i] = (totalPayout_i * uint256(DEC_COLLATERAL)) / totalWeightedShares[i];
            }
        }
  
        _sendMarketsSharesToOwner(totalPayout);
        emit MarketResolved(msg.sender, payouts, payoutDenominator);
    }

    /**
     * @notice Redeems payout for resolved condition
     * @dev Calculates payout based on user's shares and resolved outcome ratios. Emits PayoutRedemption event.
     */
    function redeemPayout() external marketResolved {
        uint256 totalPayout = 0;
        
        // Calculate payout for each outcome
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            for (uint256 j = 1; j <= EPOCH_NUMBER; j++) {
                uint256 id = shareId(j, i);
                uint256 balance = balanceOf(msg.sender, id);
                
                if (balance > 0) {
                    totalPayout += (balance * gammaPow[j-1] * basePrice[i] / uint256(DEC_Q)) / RANGE;
                    _burnToken(msg.sender, balance, id);
                }
            }
        }
        
        if (totalPayout == 0) {
            revert NothingToRedeem();
        }
        
        if (!IERC20(collateralToken).transfer(msg.sender, totalPayout)) {
            revert TransferFailed();
        }
        
        emit PayoutRedemption(msg.sender, collateralToken, question, totalPayout);
    }

    /**
     * @notice Calculates the net cost for a trade
     * @param outcomeTokenAmounts Array of token amount changes
     * @return netCost The net cost of the trade (positive = user pays, negative = user receives)
     */
    function calcNetCost(int256[] memory outcomeTokenAmounts) public view virtual returns (int256) {
        // This function should be implemented by derived contracts
        //revert("Not implemented");
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
    function withdrawFee() external onlyOwner {
        if (feeReceived == 0) {
            revert NoFeesToWithdraw();
        }
        uint256 amount = feeReceived;
        feeReceived = 0;
        if (!IERC20(collateralToken).transfer(owner(), amount)) {
            revert FeeTransferFailed();
        }
        emit FeeWithdrawal(block.timestamp, amount);
    }
    /**
     * @notice Calculates the share ID for a given epoch and outcome
     * @param epoch The epoch number
     * @param outcome The outcome index
     * @return The unique share ID
     */
    function shareId(uint256 epoch, uint256 outcome) public view returns (uint256) {
        return epoch * outcomeSlotCount + outcome;
    }

    /**
     * @notice Updates the current epoch based on elapsed time since epoch start
     * @dev Calculates if enough time has passed to advance to the next epoch
     *      and initializes new epoch data if necessary. Ensures epoch number
     *      doesn't exceed the maximum EPOCH_NUMBER.
     */
    function _updateEpoch() public {       
        if (block.timestamp >= epochData[currentEpochNumber].epochStart + epochDuration) {
            // Calculate how many epochs have passed
            uint32 currentEpoch = (uint32(block.timestamp) - epochData[currentEpochNumber].epochStart) / epochDuration;
            // Update epoch number, but don't exceed maximum
            currentEpochNumber = currentEpochNumber + currentEpoch > EPOCH_NUMBER ? EPOCH_NUMBER : currentEpochNumber + currentEpoch;
            // Initialize new epoch data
            epochData[currentEpochNumber].epochStart = uint32(block.timestamp);
            epochData[currentEpochNumber].outcomeTokenAmounts = new uint256[](outcomeSlotCount);
        }
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @notice Validates that user has enough shares to sell
     * @param deltaOutcomeAmounts_ Array of token amount changes
     * @dev Reverts if user does not have enough shares
     */
    function _validateSellAmounts(int256[] calldata deltaOutcomeAmounts_) private view {
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            if (deltaOutcomeAmounts_[i] < 0) {
                uint256 balance = balanceOf(msg.sender, shareId(currentEpochNumber, i));
                uint256 amount = uint256((-deltaOutcomeAmounts_[i]));
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
            if (!IERC20(collateralToken).transferFrom(msg.sender, address(this), shouldPay)) {
                revert TransferFailed();
            }
        } else {
            feeAmount = (netCost * fee) / RANGE;
            feeReceived += feeAmount;
            uint256 payoutAmount = netCost - feeAmount;
            if (!IERC20(collateralToken).transfer(msg.sender, payoutAmount)) {
                revert TransferFailed();
            }
        }
    }

    /**
     * @notice Updates user shares for each outcome
     * @param deltaOutcomeAmounts_ Array of token amount changes
     * @dev Mints or burns outcome tokens as needed
     */
    function _updateUserShares(int256[] calldata deltaOutcomeAmounts_) private {    
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            if (deltaOutcomeAmounts_[i] > 0) {
                // Mint tokens for buying
                outcomeTokenSupplies[i] += uint256(deltaOutcomeAmounts_[i]);
                epochData[currentEpochNumber].outcomeTokenAmounts[i] += uint256(deltaOutcomeAmounts_[i]);
                _mintToken(msg.sender, uint256(deltaOutcomeAmounts_[i]), shareId(currentEpochNumber, i));
            } else if (deltaOutcomeAmounts_[i] < 0) {
                // Burn tokens for selling
                outcomeTokenSupplies[i] -= uint256(-deltaOutcomeAmounts_[i]);
                epochData[currentEpochNumber].outcomeTokenAmounts[i] -= uint256(-deltaOutcomeAmounts_[i]);
                _burnToken(msg.sender, uint256(-deltaOutcomeAmounts_[i]), shareId(currentEpochNumber, i));
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
     * @notice Sends remaining market shares to the owner after resolution
     * @param totalPayout The total payout amount
     * @dev Emits SendMarketsSharesToOwner event
     */
    function _sendMarketsSharesToOwner(uint256 totalPayout) private {
        uint256 balance = IERC20(collateralToken).balanceOf(address(this));
        if (balance < totalPayout) {
            revert NotEnoughCollateralToCoverPayouts(totalPayout - balance);
        }
        uint256 returnToOwner = balance - totalPayout;
        if (!IERC20(collateralToken).transfer(owner(), returnToOwner)) {
            revert TransferFailed();
        }
        emit SendMarketsSharesToOwner(block.timestamp, returnToOwner);
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
}