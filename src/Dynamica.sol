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
import {IDynamica} from "./interfaces/IDynamica.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import "forge-std/src/console.sol";

/**
 * @title Dynamica v2
 * @dev A perpetual prediction market maker implementing the Logarithmic Market Scoring Rule (LMSR)
 * @notice This contract extends MarketMaker v2 with LMSR-specific pricing and cost calculation logic.
 *         Supports continuous trading with automatic epoch transitions and time-weighted rewards.
 *         Implements advanced scaling mechanisms for market efficiency.
 */
contract Dynamica is MarketMaker {
    
    // ============ CONSTANTS ============
    
    /// @notice Decimal precision for fixed-point arithmetic (18 decimals)
    int256 public constant SCALING_FACTOR = 5000;
    
    /// @notice Scaling interval for periodic market adjustments
    uint256 public constant SCALING_INTERVAL = 7 days;
    
    /// @notice Number of periods per epoch
    uint32 public constant PERIOD_NUMBER = 10;
    
    /// @notice Scaling factor unit for calculations
    int256 public constant SCALING_FACTOR_UNIT = 10000;

    // ============ STATE VARIABLES ============
    
    /// @notice Global scaling parameter for market efficiency
    SD59x18 public G;
    
    /// @notice Exponential limit to prevent overflow in calculations
    SD59x18 public EXP_LIMIT_DEC;
    
    /// @notice Liquidity parameter that controls market depth and price sensitivity
    SD59x18 public alpha;

    // ============ EVENTS ============
    
    /// @notice Emitted when the market is scaled for efficiency
    event MarketScaled(uint256 oldG, uint256 newG, uint256 liberatedCollateral);

    // ============ CONSTRUCTOR ============
    
    /**
     * @dev Constructor that disables initializers for implementation contract
     */
    constructor() {
        _disableInitializers();
    }

    // ============ INITIALIZATION ============

    /**
     * @notice Initializes the Dynamica v2 market maker with configuration parameters
     * @param config Configuration struct containing market parameters
     * @dev This function:
     * 1. Initializes the base MarketMaker v2 contract
     * 2. Sets up LMSR-specific parameters (alpha, expLimit, gamma)
     * 3. Initializes gamma powers for time-weighted rewards
     * 4. Sets up decimal precision and global scaling parameter
     */
    function initialize(IDynamica.Config calldata config)
        public
        initializer
    {
        // Initialize base contract
        __Ownable_init(config.owner);
        __ERC1155_init("");
        __ERC1155Holder_init();
        
        // Set basic market parameters
        collateralToken = config.collateralToken;
        fee = config.fee;
        
        // Validate collateral token decimals
        uint8 collateralTokenDecimals = IERC20(collateralToken).decimals();
        if (collateralTokenDecimals > 18) {
            revert CollateralTokenDecimalsTooHigh(collateralTokenDecimals);
        }
        
        // Set LMSR-specific parameters
        alpha = sd(int256((uint256(config.alpha) * uint256(UNIT_DEC)) / 100));
        EXP_LIMIT_DEC = sd(int256((uint256(config.expLimit) * uint256(UNIT_DEC)) / 100));
        
        // Initialize gamma powers for time-weighted rewards
        _initializeGammaPowers(config.gamma);
        // Initialize the market with basic parameters
        initializeMarket(
            config
        );
        
        // Set decimal precision and global scaling parameter
        DEC_COLLATERAL = int256(10 ** uint256(collateralTokenDecimals));
        DEC_Q = int256(10 ** uint256(uint32(config.decimals)));
        G = sd(UNIT_DEC); // Initialize global scaling parameter
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
            int256 qi = int256(epochData[currentEpochNumber].outcomeTokenSupplies[i]);
            qWad[i] = sd(int256(uint256(qi) * uint256(UNIT_DEC)));
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
            int256 currentSupply = int256(epochData[currentEpochNumber].outcomeTokenSupplies[i]);
            qNew[i] = currentSupply + deltaOutcomeAmounts[i];
            qNewSd[i] = sd(int256(uint256(qNew[i]) * uint256(UNIT_DEC)));
            balancesSd[i] = sd(int256(uint256(currentSupply) * uint256(UNIT_DEC)));
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
     * @notice Initializes gamma powers for time-weighted rewards
     * @param gamma The gamma parameter for reward decay
     * @dev Sets up decreasing multipliers for later periods to incentivize early predictions
     */
    function _initializeGammaPowers(uint32 gamma) internal {
        gammaPow = new uint32[](PERIOD_NUMBER);
        gammaPow[0] = RANGE; // First period gets full reward
        
        for (uint32 i = 1; i < PERIOD_NUMBER; i++) {
            gammaPow[i] = (gammaPow[i - 1] * gamma) / RANGE;
        }
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
        
        // Validate all quantities are non-negative
        SD59x18[] memory qWad = new SD59x18[](n);
        for (uint256 i = 0; i < n; i++) {
            if (qs[i] < 0) {
                revert NegativeOutcomeAmount(qs[i]);
            }
            qWad[i] = sd(int256(uint256(qs[i]) * uint256(UNIT_DEC)));
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
        
        // Calculate offset and sum for numerical stability
        SD59x18 offset = _computeOffset(qWad);
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
}