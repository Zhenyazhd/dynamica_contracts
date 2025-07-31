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

import {SD59x18, sd, exp, ln} from "@prb-math/src/SD59x18.sol";
import {MarketMaker} from "./MarketMaker.sol";
import {IDynamica} from "../interfaces/IDynamica.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import "forge-std/src/console.sol";

/**
 * @title Dynamica
 * @dev A prediction market maker implementing the Logarithmic Market Scoring Rule (LMSR)
 * @notice This contract extends MarketMaker with LMSR-specific pricing and cost calculation logic.
 *         Uses epoch-based time-weighted rewards to incentivize early predictions.
 */
contract Dynamica is MarketMaker {


    // ============ CONSTRUCTOR ============
    
    /**
     * @dev Constructor that disables initializers for implementation contract
     */
    constructor() {
        _disableInitializers();
    }

    // ============ INITIALIZATION ============
    
    /**
     * @notice Initializes the Dynamica market maker with configuration parameters
     * @param config Configuration struct containing market parameters
     * @dev This function:
     * 1. Initializes the base MarketMaker contract
     * 2. Sets up LMSR-specific parameters (alpha, expLimit)
     * 3. Initializes epoch-based gamma powers for time-weighted rewards
     * 4. Sets up decimal precision for calculations
     */
    function initialize(IDynamica.Config calldata config)
        public
        payable
        initializer
    {
        // Initialize base contract
        __Ownable_init(config.owner);
        __ERC1155_init("");
        __ERC1155Holder_init();
        
        // Set basic market parameters
        fee = config.fee;
        collateralToken = config.collateralToken;
        expirationTime = config.expirationTime;
        
        // Validate collateral token decimals
        uint8 collateralTokenDecimals = IERC20(collateralToken).decimals();
        if (collateralTokenDecimals > 18) {
            revert CollateralTokenDecimalsTooHigh(collateralTokenDecimals);
        }
        
        // Initialize epoch data and gamma powers for time-weighted rewards
        _initializeEpochData(config.outcomeSlotCount, config.gamma);
        
        // Initialize the market with basic parameters
        initializeMarket(
            config.oracle,
            config.question,
            config.outcomeSlotCount,
            config.startFunding,
            config.outcomeTokenAmounts,
            config.decimals
        );
        
        // Set LMSR-specific mathematical parameters
        alpha = sd((config.alpha * UNIT_DEC) / 100);   
        EXP_LIMIT_DEC = sd((config.expLimit * UNIT_DEC) / 100);
        DEC_COLLATERAL = int256(10 ** collateralTokenDecimals);
        DEC_Q = int256(10 ** uint32(decimals));
    }

    // ============ PUBLIC FUNCTIONS ============
    
    /**
     * @notice Calculates the current marginal price for a specific outcome
     * @param outcomeTokenIndex Index of the outcome token (0-based)
     * @return priceWad The marginal price in fixed-point format (18 decimals)
     * @dev Uses LMSR pricing formula: P_i = exp(q_i/b) / Σ(exp(q_j/b))
     */
    function calcMarginalPrice(uint8 outcomeTokenIndex) public view returns (int256 priceWad) {
        uint256 n = outcomeSlotCount;
        if (outcomeTokenIndex >= n) {
            revert InvalidOutcomeIndex(outcomeTokenIndex, n);
        }
        
        // Convert current supplies to fixed-point format
        SD59x18[] memory qWad = new SD59x18[](n);
        for (uint256 i = 0; i < n; i++) {
            int256 qi = int256(outcomeTokenSupplies[i]);
            qWad[i] = sd(qi * UNIT_DEC);
        }
        
        // Calculate liquidity parameter b = α * Σ(q_i)
        SD59x18 b = getB(qWad);
        if (b == sd(0)) {
            revert ZeroLiquidityParameter();
        }
        
        // Normalize quantities by dividing by b
        for (uint256 i = 0; i < n; i++) {
            qWad[i] = qWad[i].div(b);
        }
        
        // Calculate offset for numerical stability
        SD59x18 offset = _computeOffset(qWad);
        
        // Calculate sum of exponentials
        SD59x18 sum = sd(0);
        for (uint256 i = 0; i < n; i++) {
            sum = sum.add(exp(qWad[i].sub(offset)));
        }
        
        if (sum == sd(0)) {
            revert ZeroSum();
        }
        
        // Calculate marginal price for the specified outcome
        SD59x18 p = exp(qWad[outcomeTokenIndex].sub(offset)).div(sum);
        priceWad = int256(p.unwrap());
    }

    /**
     * @notice Calculates the net cost of a trade using the LMSR cost function
     * @param deltaOutcomeAmounts Array of token amount changes for each outcome
     * @return netCost The net cost in collateral tokens (positive = cost, negative = payout)
     * @dev Uses LMSR cost function: C(q') - C(q) where C(q) = b * ln(Σ(exp(q_i/b)))
     */
    function calcNetCost(int256[] memory deltaOutcomeAmounts) public view override returns (int256 netCost) {
        uint256 n = outcomeSlotCount;
        if (deltaOutcomeAmounts.length != n) {
            revert InvalidDeltaOutcomeAmountsLength(deltaOutcomeAmounts.length, n);
        }
        
        // Calculate new state after trade
        int256[] memory qNew = new int256[](n);
        SD59x18[] memory balancesSd = new SD59x18[](n);
        SD59x18[] memory qNewSd = new SD59x18[](n);
        
        for (uint256 i = 0; i < n; i++) {
            int256 currentSupply = int256(outcomeTokenSupplies[i]);
            qNew[i] = currentSupply + deltaOutcomeAmounts[i];
            qNewSd[i] = sd(qNew[i] * UNIT_DEC);
            balancesSd[i] = sd(currentSupply * UNIT_DEC);
        }
        
        // Calculate liquidity parameters for old and new states
        SD59x18 bOld = getB(balancesSd);
        SD59x18 bNew = getB(qNewSd);
        
        // Calculate cost function values for old and new states
        (SD59x18 sumOld, SD59x18 offOld) = sumExp(balancesSd, bOld);
        (SD59x18 sumNew, SD59x18 offNew) = sumExp(qNewSd, bNew);
        
        SD59x18 cOld = bOld.mul(ln(sumOld).add(offOld));
        SD59x18 cNew = bNew.mul(ln(sumNew).add(offNew));
        
        // Calculate net cost difference
        netCost = (cNew.sub(cOld).unwrap() * DEC_COLLATERAL / UNIT_DEC) / DEC_Q;
    }

    // ============ INTERNAL FUNCTIONS ============
    
    /**
     * @notice Initializes epoch data and gamma powers for time-weighted rewards
     * @param outcomeSlotCount Number of possible outcomes
     * @param gamma Gamma parameter for time decay (basis points)
     * @dev Sets up decreasing multipliers for later epochs to incentivize early predictions
     */
    function _initializeEpochData(uint256 outcomeSlotCount, uint32 gamma) internal {
        // Initialize gamma powers array
        gammaPow = new uint32[](EPOCH_NUMBER);
        gammaPow[0] = RANGE; // First epoch gets full reward
        
        // Initialize epoch data arrays
        epochData[0].outcomeTokenAmounts = new uint256[](outcomeSlotCount);
        
        // Calculate decreasing gamma powers for subsequent epochs
        for (uint32 i = 1; i < EPOCH_NUMBER; i++) {
            epochData[i].outcomeTokenAmounts = new uint256[](outcomeSlotCount);
            // Apply gamma decay: each epoch gets gamma% of previous epoch's reward
            gammaPow[i] = (gammaPow[i - 1] * gamma) / RANGE;
        }
        
        // Initialize final epoch
        epochData[EPOCH_NUMBER].outcomeTokenAmounts = new uint256[](outcomeSlotCount);
    }

    /**
     * @notice Calculates the marginal price for a specific outcome from a given state vector
     * @param qs Array of outcome token amounts representing the market state
     * @param idx Index of the outcome to calculate price for
     * @return priceWad The marginal price in fixed-point format (18 decimals)
     * @dev Internal function for price calculation from arbitrary state
     */
    function _marginalPriceFromMemory(int256[] memory qs, uint8 idx) internal view returns (int256 priceWad) {
        uint256 n = qs.length;
        if (idx >= n) {
            revert InvalidOutcomeIndex(idx, n);
        }
        
        // Convert quantities to fixed-point format
        SD59x18[] memory qWad = new SD59x18[](n);
        for (uint256 i = 0; i < n; i++) {
            if (qs[i] < 0) {
                revert NegativeOutcomeAmount(qs[i]);
            }
            qWad[i] = sd(qs[i] * UNIT_DEC);
        }
        
        // Calculate liquidity parameter
        SD59x18 b = getB(qWad);
        if (b.unwrap() == 0) {
            revert ZeroLiquidityParameter();
        }
        
        // Normalize quantities
        for (uint256 i = 0; i < n; i++) {
            qWad[i] = qWad[i].div(b);
        }
        
        // Calculate offset for numerical stability
        SD59x18 offset = _computeOffset(qWad);
        
        // Calculate sum of exponentials
        SD59x18 sum = sd(0);
        for (uint256 i = 0; i < n; i++) {
            sum = sum.add(exp(qWad[i].sub(offset)));
        }
        
        if (sum.unwrap() == 0) {
            revert ZeroSum();
        }
        
        // Calculate marginal price
        SD59x18 numer = exp(qWad[idx].sub(offset));
        priceWad = numer.div(sum).unwrap();
    }

    /**
     * @notice Calculates the liquidity parameter b = α * Σ(q_i)
     * @param q Array of outcome token amounts in fixed-point format
     * @return b The liquidity parameter
     * @dev The liquidity parameter controls market depth and price sensitivity
     */
    function getB(SD59x18[] memory q) internal view returns (SD59x18 b) {
        SD59x18 sum = sd(0);
        for (uint256 i = 0; i < q.length; i++) {
            sum = sum.add(q[i]);
        }
        b = sum.mul(alpha);
        // Ensure b is never zero to prevent division by zero
        b = b == sd(0) ? sd(1) : b;
    }

    /**
     * @notice Calculates the exponential sum and offset for numerical stability
     * @param q Array of normalized outcome amounts
     * @param b Liquidity parameter
     * @return sum The sum of exponentials
     * @return offset The offset used for numerical stability
     * @dev Uses offset to prevent overflow in exponential calculations
     */
    function sumExp(SD59x18[] memory q, SD59x18 b) internal view returns (SD59x18 sum, SD59x18 offset) {
        uint256 n = q.length;
        SD59x18[] memory z = new SD59x18[](n);
        
        // Normalize quantities by dividing by b
        for (uint256 i = 0; i < n; i++) {
            z[i] = q[i].div(b);
        }
        
        // Find maximum value for offset calculation
        offset = z[0];
        for (uint256 i = 1; i < n; i++) {
            if (z[i].unwrap() > offset.unwrap()) {
                offset = z[i];
            }
        }
        
        // Apply exponential limit offset for numerical stability
        offset = offset.sub(EXP_LIMIT_DEC);
        
        // Calculate sum of exponentials with offset
        sum = sd(0);
        for (uint256 i = 0; i < n; i++) {
            sum = sum.add(exp(z[i].sub(offset)));
        }
    }

    /**
     * @notice Computes the offset for numerical stability in exponential calculations
     * @param z Array of normalized outcome amounts
     * @return The offset value to prevent overflow
     * @dev Subtracts EXP_LIMIT_DEC from the maximum value to prevent overflow
     */
    function _computeOffset(SD59x18[] memory z) private view returns (SD59x18) {
        SD59x18 maxZ = z[0];
        for (uint256 i = 1; i < z.length; i++) {
            if (z[i].unwrap() > maxZ.unwrap()) {
                maxZ = z[i];
            }
        }
        return maxZ.sub(EXP_LIMIT_DEC);
    }

    // ============ FALLBACK FUNCTIONS ============
    
    /**
     * @notice Allows the contract to receive ETH
     * @dev Required for some operations that may send ETH to the contract
     */
    receive() external payable {}
}