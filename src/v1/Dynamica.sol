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
 * @title Dynamica v1
 * @dev A prediction market maker implementing the Logarithmic Market Scoring Rule (LMSR)
 * @notice This contract extends MarketMaker with LMSR-specific pricing and cost calculation logic.
 *         Provides automated market making with bounded loss and continuous liquidity.
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
     * 2. Sets up LMSR-specific parameters (alpha, expLimit, gamma)
     * 3. Initializes gamma powers for time-weighted rewards
     * 4. Sets up decimal precision for calculations
     */
    function initialize(IDynamica.Config calldata config)
        public
        payable
        initializer
    {
        // Initialize base contract
        __Ownable_init(config.owner);
        
        // Set basic market parameters
        fee = config.fee;
        collateralToken = config.collateralToken;
        expirationTime = config.expirationTime;
        
        // Validate collateral token decimals
        uint8 collateralTokenDecimals = IERC20(collateralToken).decimals();
        if (collateralTokenDecimals > 18) {
            revert CollateralTokenDecimalsTooHigh(collateralTokenDecimals);
        }
        
        // Initialize gamma powers for time-weighted rewards
        gammaPow = new uint32[](EPOCH_NUMBER);
        gammaPow[0] = RANGE; // First epoch gets full reward
        
        // Initialize epoch data arrays
        for (uint32 i = 0; i <= EPOCH_NUMBER; i++) {
            epochData[i].outcomeTokenAmounts = new uint256[](config.outcomeSlotCount);
        }
        
        // Calculate decreasing gamma powers for subsequent epochs
        for (uint32 i = 1; i < EPOCH_NUMBER; i++) {
            gammaPow[i] = (gammaPow[i - 1] * config.gamma) / RANGE;
        }

        // Initialize the market with base configuration
        initializeMarket(
            config.oracle,
            config.question,
            config.outcomeSlotCount,
            config.startFunding,
            config.outcomeTokenAmounts,
            config.decimals
        );

        // Set LMSR-specific parameters
        alpha = sd(int256((uint256(config.alpha) * uint256(UNIT_DEC)) / 100));   
        EXP_LIMIT_DEC = sd(int256((uint256(config.expLimit) * uint256(UNIT_DEC)) / 100));
        DEC_COLLATERAL = int256(10 ** uint256(collateralTokenDecimals));
        DEC_Q = int256(10 ** uint256(uint32(config.decimals)));
        
    }

    // ============ PUBLIC FUNCTIONS ============

    /**
     * @notice Calculates the current marginal price for a specific outcome
     * @param outcomeTokenIndex Index of the outcome token (0-based)
     * @return priceWad The marginal price in fixed-point format (18 decimals)
     * @dev Uses LMSR formula: P_i = exp(q_i/b) / Σ(exp(q_j/b))
     */
    function calcMarginalPrice(uint8 outcomeTokenIndex) public view returns (int256 priceWad) {
        uint256 n = outcomeSlotCount;
        if (outcomeTokenIndex >= n) {
            revert InvalidOutcomeIndex(outcomeTokenIndex, n);
        }
        
        // Convert current supplies to fixed-point format
        SD59x18[] memory qWad = new SD59x18[](n);
        for (uint256 i = 0; i < n; i++) {
            uint256 qi = outcomeTokenSupplies[i];
            qWad[i] = sd(int256(qi * uint256(UNIT_DEC)));
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
     * @notice Calculates the cost of a given quantity vector using LMSR
     * @param q Array of quantities
     * @return netCost The cost in collateral tokens
     * @dev Uses LMSR cost function: C(q) = b * ln(Σ(exp(q_i/b)))
     */
    function costOf(int256[] memory q) public view override returns (int256 netCost) {
        uint256 n = outcomeSlotCount;
        if (q.length != n) {
            revert InvalidDeltaOutcomeAmountsLength(q.length, n);
        }
        
        // Convert quantities to fixed-point format
        SD59x18[] memory balancesSd = new SD59x18[](n);
        SD59x18[] memory q_sd = new SD59x18[](n);
        for (uint256 i = 0; i < n; i++) {
            q_sd[i] = sd(q[i] * UNIT_DEC);
            balancesSd[i] = sd(int256(outcomeTokenSupplies[i]) * UNIT_DEC);
        }
        
        // Calculate liquidity parameter
        SD59x18 b = getB(balancesSd);
        
        // Calculate exponential sum and offset
        (SD59x18 sum, SD59x18 off) = sumExp(q_sd, b);
        
        // Calculate cost: C(q) = b * ln(Σ(exp(q_i/b)))
        SD59x18 c = b.mul(ln(sum).add(off));
        netCost = (c.unwrap() * DEC_COLLATERAL / UNIT_DEC) / DEC_Q;
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

    // ============ FALLBACK FUNCTIONS ============
    
    /**
     * @notice Allows the contract to receive ETH
     * @dev Required for some operations that may send ETH to the contract
     */
    receive() external payable {}
}

