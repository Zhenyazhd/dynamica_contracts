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
import {IMarketResolutionModule} from "../interfaces/IMarketResolutionModule.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC1155Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC1155HolderUpgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import {SD59x18, sd, exp, ln} from "@prb-math/src/SD59x18.sol";
import "forge-std/src/console.sol";
import "forge-std/src/Test.sol";

/**
 * @title MarketMaker v2
 * @dev A perpetual prediction market maker contract that allows users to buy and sell outcome tokens.
 *      Implements epoch and period-based market making logic for multi-outcome prediction markets.
 *      Uses ERC1155 tokens for outcome representation with time-weighted rewards.
 *      Supports continuous trading with automatic epoch transitions and LMSR pricing.
 */
contract MarketMaker is Initializable, OwnableUpgradeable, ERC1155Upgradeable, ERC1155HolderUpgradeable, IDynamica {
    
    // ============ CONSTANTS ============
    
    /// @notice Maximum number of outcome slots supported
    uint256 public constant MAX_SLOT_COUNT = 10;
    
    /// @notice Maximum fee that can be set (100% in basis points)
    uint32 public constant RANGE = 10_000;
    
    /// @notice Unit decimal for calculations (18 decimals)
    int256 public constant UNIT_DEC = 1e18;

    // ============ STATE VARIABLES ============
    
    // Time Management
    /// @notice Duration of each epoch in seconds
    uint32 public epochDuration = 10 days;
    
    /// @notice Duration of each period within an epoch in seconds
    uint32 public periodDuration = 1 days;
    
    /// @notice Current period number (1-based)
    uint32 public currentPeriodNumber = 1;
    
    /// @notice Current epoch number (1-based)
    uint32 public currentEpochNumber = 1;
    
    // Decimal Precision
    /// @notice Collateral token decimals
    int256 public DEC_COLLATERAL;
    
    /// @notice Outcome token decimals
    int256 public DEC_Q;

    /// @notice Array of gamma power values for time-weighted rewards
    uint32[] public gammaPow;
    
    /// @notice Liquidity parameter that controls market depth and price sensitivity
    SD59x18 public alpha;

    // ============ STRUCTS ============
    
    /// @notice Structure to store epoch-specific data
    struct EpochData {
        /// @notice Start timestamp of the epoch
        uint32 epochStart;
        /// @notice Payout denominator for calculating final payouts
        uint256 payoutDenominator;       
        /// @notice Array of payout numerators for each outcome
        uint256[MAX_SLOT_COUNT] payoutNumerators;
        /// @notice Array of supplies for each outcome token
        uint256[MAX_SLOT_COUNT] outcomeTokenSupplies; 
        /// @notice Array of base quantities for cost calculations
        int64[MAX_SLOT_COUNT] q_base;
        /// @notice Base cost for the market
        int256 c_base;
    }

    /// @notice Structure to store period-specific data
    struct PeriodData {
        /// @notice Epoch number this period belongs to
        uint32 epochNumber;
        /// @notice Start timestamp of the period
        uint32 periodStart;
        /// @notice Array of outcome token amounts for this period
        int64[MAX_SLOT_COUNT] outcomeTokenAmounts;
    }

    // ============ MAPPINGS ============
    
    /// @notice Mapping from epoch number to epoch data
    mapping(uint256 => EpochData) public epochData;
    
    /// @notice Mapping from epoch number to period number to period data
    mapping(uint256 => mapping(uint256 => PeriodData)) public periodData;
    
    /// @notice Mapping from user address to their cost array per epoch
    mapping(address => int256[MAX_SLOT_COUNT]) public c_user;
    
    // Market Configuration
    /// @notice Address of the ERC20 collateral token
    address public collateralToken;
    
    /// @notice The question that this prediction market resolves
    string public question;
    
    /// @notice The fee rate in basis points (e.g., 300 = 3%)
    uint64 public fee;
    
    /// @notice Total fees received from trades
    uint256 public feeReceived;
    
    /// @notice Array of addresses for created outcome tokens
    address[MAX_SLOT_COUNT] public outcomeTokenAddresses;
    
    /// @notice Decimals for outcome tokens
    int32 public decimals;
    
    /// @notice Address of the oracle manager that can resolve the market
    address public oracleManager;
    
    /// @notice Number of possible outcomes in the market
    uint256 public outcomeSlotCount;
    
    /// @notice Expiration time of the market
    uint32 public expirationTime;

    // ============ MODIFIERS ============

    /// @notice Ensures the epoch is not yet resolved
    modifier epochNotResolved(uint256 epoch) {
        if (epochData[epoch].payoutDenominator != 0 || epochData[epoch].epochStart + epochDuration < block.timestamp) {
            revert MarketAlreadyResolved();
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
        oracleManager = oracle;
        question = _question;
        outcomeSlotCount = _outcomeSlotCount;

        // Initialize first epoch and period
        epochData[currentEpochNumber].epochStart = uint32(block.timestamp);
        periodData[currentEpochNumber][currentPeriodNumber].epochNumber = currentEpochNumber;
        periodData[currentEpochNumber][currentPeriodNumber].periodStart = uint32(block.timestamp);
     
        // Transfer initial funding
        if (!IERC20(collateralToken).transferFrom(msg.sender, address(this), _startFunding)) {
            revert TransferFailed();
        }
        
        // Set decimals and initialize decimal constants
        decimals = _decimals;
        uint8 collateralTokenDecimals = IERC20(collateralToken).decimals();
        DEC_COLLATERAL = int256(10 ** uint256(collateralTokenDecimals));
        DEC_Q = int256(10 ** uint256(uint32(_decimals)));
        
        // Create initial outcome tokens
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            _mint(
                address(this),
                shareId(currentEpochNumber, currentPeriodNumber, i),
                _outcomeTokenAmounts,
                ""
            );   
            epochData[currentEpochNumber].outcomeTokenSupplies[i] = _outcomeTokenAmounts;
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
    function makePrediction(int256[] memory deltaOutcomeAmounts_) external epochNotResolved(currentEpochNumber) {
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

    /**
     * @notice Returns the payout numerator for a specific outcome in the previous epoch
     * @param i Index of the outcome
     * @return The payout numerator
     */
    function payoutNumerators(uint256 i) external view returns (uint256) {
        return epochData[currentEpochNumber-1].payoutNumerators[i];
    }

    /**
     * @notice Returns the payout denominator for the previous epoch
     * @return The payout denominator
     */
    function payoutDenominator() external view returns (uint256) {
        return epochData[currentEpochNumber-1].payoutDenominator;
    }

    /**
     * @notice Returns the supply for a specific outcome token in the current epoch
     * @param i Index of the outcome
     * @return The token supply
     */
    function outcomeTokenSupplies(uint256 i) external view returns (uint256) {
        return epochData[currentEpochNumber].outcomeTokenSupplies[i];
    }

    /**
     * @notice Closes the current epoch by resolving it with payout ratios
     * @param payouts Array of payout numerators for each outcome
     * @dev Only callable by the oracle manager. Emits MarketResolved event.
     */
    function closeMarket(uint256[] calldata payouts) external onlyOracleManager epochNotResolved(currentEpochNumber) {
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

        // Calculate base quantities for cost calculations
        SD59x18[] memory q_sd = new SD59x18[](_outcomeSlotCount);
        for (uint256 i = 0; i < _outcomeSlotCount; i++) {
            q_sd[i] = sd(int256(uint256(epochData[currentEpochNumber].outcomeTokenSupplies[i]) * uint256(UNIT_DEC)));
        }

        // Set payout numerators and calculate base prices
        uint256 totalPayout = 0;
        for (uint256 i = 0; i < _outcomeSlotCount; i++) {
            if (epochData[currentEpochNumber].payoutNumerators[i] != 0) {
                revert PayoutNumeratorAlreadySet(i);
            }
            
            epochData[currentEpochNumber].payoutNumerators[i] = payouts[i];
            
            // Calculate base quantities for cost function
            SD59x18 x_i = ln(sd(int256(uint256(payouts[i]) * uint256(UNIT_DEC))).div(sd(int256(uint256(payoutDenominator_) * uint256(UNIT_DEC)))));
            epochData[currentEpochNumber].q_base[i] = int64((getB_(q_sd).mul(x_i)).unwrap() / UNIT_DEC);
        }
        
        // Calculate base cost
        epochData[currentEpochNumber].c_base = costOf(epochData[currentEpochNumber].q_base);

        //_sendMarketsSharesToOwner(totalPayout);
        emit MarketResolved(msg.sender, payouts, epochData[currentEpochNumber].payoutDenominator);
    }

    /**
     * @notice Redeems payout for resolved epoch
     * @dev Calculates payout based on user's shares and resolved outcome ratios. Emits PayoutRedemption event.
     */
    function redeemPayout() external epochResolved(currentEpochNumber) {
        uint256 totalPayout = 0;
        uint256 periodsPerEpoch = epochDuration / periodDuration;

        // Calculate user's delta quantities across all periods
        int64[MAX_SLOT_COUNT] memory delta;
        for (uint256 j = 1; j <= periodsPerEpoch; j++) {
            for (uint256 i = 0; i < outcomeSlotCount; i++) {
                uint256 balance = balanceOf(msg.sender, shareId(currentEpochNumber, j, i));
                if (balance > 0) {
                    delta[i] += int64(int256(uint256(balance) * uint256(gammaPow[j-1]) / uint256(RANGE)));
                    _burnToken(msg.sender, balance, shareId(currentEpochNumber, j, i));
                }
            }
        }

        // Add base quantities to delta
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            delta[i] += epochData[currentEpochNumber].q_base[i];
        }
        
        // Calculate user's reward
        int256 c_user_ = costOf(delta);
        int256 new_reward = c_user_ - epochData[currentEpochNumber].c_base;

        if (new_reward == 0) {
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
    }

    /**
     * @notice Calculates the cost of a given quantity vector
     * @param q Array of quantities
     * @return netCost The cost in collateral tokens
     */
    function costOf(int64[MAX_SLOT_COUNT] memory q) public view virtual returns (int256 netCost) {
        // TODO: implement
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
     * @param pd Period data storage reference
     * @param deltaOutcomeAmounts_ Array of token amount changes
     * @dev Mints or burns outcome tokens as needed
     */
    function _updateUserShares(PeriodData storage pd, int256[] memory deltaOutcomeAmounts_) private {
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            if (deltaOutcomeAmounts_[i] > 0) {
                // Mint tokens for buying
                uint256 deltaOutcomeAmount = uint256(deltaOutcomeAmounts_[i]);
                epochData[currentEpochNumber].outcomeTokenSupplies[i] += deltaOutcomeAmount;
                pd.outcomeTokenAmounts[i] += int64(deltaOutcomeAmounts_[i]);
                _mintToken(msg.sender, deltaOutcomeAmount, shareId(currentEpochNumber, currentPeriodNumber, i));
            } else if (deltaOutcomeAmounts_[i] < 0) {
                // Burn tokens for selling
                uint256 deltaOutcomeAmount = uint256(-deltaOutcomeAmounts_[i]);
                epochData[currentEpochNumber].outcomeTokenSupplies[i] -= deltaOutcomeAmount;
                pd.outcomeTokenAmounts[i] -= int64(-deltaOutcomeAmounts_[i]);
                _burnToken(msg.sender, deltaOutcomeAmount, shareId(currentEpochNumber, currentPeriodNumber, i));
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
    function _updateEpochAndPeriod() public {       
        uint32 now32 = uint32(block.timestamp);
        uint32 newEpoch = 0;
        
        // Check if epoch should advance
        if (now32 >= epochData[currentEpochNumber].epochStart + epochDuration) {
            newEpoch = (now32 - epochData[currentEpochNumber].epochStart) / epochDuration;
            currentEpochNumber += newEpoch;
            epochData[currentEpochNumber].epochStart = now32;
            currentPeriodNumber = 1; 
            periodData[currentEpochNumber][currentPeriodNumber].periodStart = now32;
            periodData[currentEpochNumber][currentPeriodNumber].epochNumber = currentEpochNumber;
        }
        
        // Check if period should advance within current epoch
        if (newEpoch == 0 && now32 >= periodData[currentEpochNumber][currentPeriodNumber].periodStart + periodDuration) {
            uint32 currentPeriod = (now32 - periodData[currentEpochNumber][currentPeriodNumber].periodStart) / periodDuration;
            currentPeriodNumber += currentPeriod;
            periodData[currentEpochNumber][currentPeriodNumber].periodStart = now32;
            periodData[currentEpochNumber][currentPeriodNumber].epochNumber = currentEpochNumber;
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

    /**
     * @notice Returns the ERC20 balance for a given token and address
     * @param token Address of the token
     * @param to Address to check balance for
     * @return Balance of the token for the address
     */
    function getHtsBalanceERC20(address token, address to) public view returns (uint256) {
        return IERC20(token).balanceOf(to);
    }

    /**
     * @notice Calculates the liquidity parameter b = α * Σ(q_i)
     * @param q Array of outcome token amounts in fixed-point format
     * @return b The liquidity parameter
     * @dev The liquidity parameter controls market depth and price sensitivity
     */
    function getB_(SD59x18[] memory q) public view returns (SD59x18 b) {
        SD59x18 sum = sd(0);
        for (uint256 i = 0; i < q.length; i++) {
            sum = sum.add(q[i]);
        }
        b = sum.mul(alpha);
        // Ensure b is never zero to prevent division by zero
        b = b == sd(0) ? sd(1) : b;
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
    function shareId(
        uint256 epoch,
        uint256 period,
        uint256 outcome
    ) public view returns (uint256) {
        uint256 e = epoch - 1;
        uint256 p = period - 1;
        uint256 periodsPerEpoch = epochDuration / periodDuration;
        uint256 epochOffset = e * periodsPerEpoch * outcomeSlotCount;
        uint256 periodOffset = p * outcomeSlotCount;
        return epochOffset + periodOffset + outcome;
    }
}