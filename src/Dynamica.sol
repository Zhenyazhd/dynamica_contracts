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
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IHederaTokenService} from "hedera-smart-contracts/system-contracts/hedera-token-service/IHederaTokenService.sol";
import "forge-std/src/console.sol";

/**
 * @title Dynamica
 * @dev A prediction market maker implementing the Logarithmic Market Scoring Rule (LMSR)
 * @notice This contract extends MarketMaker with LMSR-specific pricing and cost calculation logic
 *
 * The LMSR is a market making mechanism that:
 * - Uses logarithmic scoring rules for price discovery
 * - Provides continuous liquidity for all outcomes
 * - Automatically adjusts prices based on trading activity
 * - Prevents arbitrage opportunities through mathematical constraints
 *
 * Key Features:
 * - Fixed-point arithmetic with 18 decimal precision
 * - Numerical stability techniques to prevent overflow
 * - Configurable liquidity parameter (alpha)
 * - Exponential limit protection
 */
contract Dynamica is MarketMaker {
    receive() external payable {}

    // ============ Constants ============

    /// @notice Decimal precision for fixed-point arithmetic (18 decimals)
    int256 public constant UNIT_DEC = 1e18;

    // ============ State Variables ============

    /// @notice Exponential limit to prevent overflow in calculations
    SD59x18 public EXP_LIMIT_DEC;

    /// @notice Liquidity parameter that controls market depth and price sensitivity
    /// @dev Higher alpha = more liquidity, lower price impact
    SD59x18 public alpha;

    // ============ Constructor ============

    /**
     * @dev Constructor that disables initializers for implementation contract
     */
    constructor() {
        _disableInitializers();
    }

    // ============ External Functions ============

    /**
     * @notice Initializes the Dynamica market maker with configuration parameters
     * @param config Configuration struct containing market parameters
     * @dev This function sets up the market with initial funding and outcome tokens
     */
    function initialize(IDynamica.Config calldata config, IHederaTokenService.HederaToken[] memory tokens)
        public
        payable
        initializer
    {
        __Ownable_init(config.owner);

        collateralToken = IERC20(config.collateralToken);
        fee = config.fee;

        // Convert alpha from percentage to fixed-point representation
        alpha = sd((int256(config.alpha) * UNIT_DEC) / 100);

        // Set exponential limit to prevent overflow
        EXP_LIMIT_DEC = sd((int256(config.expLimit) * UNIT_DEC) / 100);

        initializeMarket(
            config.oracle,
            config.question,
            config.outcomeSlotCount,
            config.startFunding,
            config.outcomeTokenAmounts,
            tokens
        );
    }

    // ============ Public Functions ============

    /**
     * @notice Calculates the current marginal price for a specific outcome
     * @param outcomeTokenIndex Index of the outcome token (0-based)
     * @return priceWad The marginal price in fixed-point format
     * @dev This function uses the current market state to calculate prices
     */
    function calcMarginalPrice(uint8 outcomeTokenIndex) public view returns (int256 priceWad) {
        uint256 n = outcomeSlotCount;
        require(outcomeTokenIndex < n, "Invalid outcome index");

        // Convert current outcome token amounts to SD59x18 format
        SD59x18[] memory qWad = new SD59x18[](n);
        for (uint256 i = 0; i < n; i++) {
            int256 qi = int256(outcomeTokenAmounts[i]);
            qWad[i] = sd(qi * UNIT_DEC);
        }

        // Calculate liquidity parameter b
        SD59x18 b = getB(qWad);
        for (uint256 i = 0; i < n; i++) {
            require(b != sd(0), "Liquidity parameter is zero");
            qWad[i] = qWad[i].div(b);
        }

        // Calculate offset for numerical stability
        SD59x18 offset = _computeOffset(qWad);
        SD59x18 sum = sd(0);
        for (uint256 i = 0; i < n; i++) {
            sum = sum.add(exp(qWad[i].sub(offset)));
        }
        require(sum != sd(0), "Sum is zero");

        // Calculate price using LMSR formula
        SD59x18 p = exp(qWad[outcomeTokenIndex].sub(offset)).div(sum);
        priceWad = int256(p.unwrap());
    }

    /**
     * @notice Calculates the net cost of a trade using the LMSR cost function
     * @param deltaOutcomeAmounts Array of token amount changes for each outcome
     * @return netCost The net cost in collateral tokens (positive = cost, negative = payout)
     * @dev This function implements the LMSR cost function:
     *
     * C(q_new) - C(q_old) = b * ln(Σ exp(q_new_i/b)) - b * ln(Σ exp(q_old_i/b))
     *
     * where:
     * - q_old is the current state
     * - q_new is the state after the trade
     * - b is the liquidity parameter
     *
     * Positive netCost means the trader pays collateral tokens
     * Negative netCost means the trader receives collateral tokens
     */
    function calcNetCost(int256[] memory deltaOutcomeAmounts) public view override returns (int256 netCost) {
        uint256 n = outcomeSlotCount;
        require(deltaOutcomeAmounts.length == n, "Invalid outcome amount length");

        // Calculate new state after the trade
        int256[] memory qNew = new int256[](n);
        SD59x18[] memory balancesSd = new SD59x18[](n);
        SD59x18[] memory qNewSd = new SD59x18[](n);

        for (uint256 i = 0; i < n; i++) {
            qNew[i] = int256(outcomeTokenAmounts[i]) + deltaOutcomeAmounts[i];
            qNewSd[i] = sd(qNew[i] * UNIT_DEC);
            balancesSd[i] = sd(int256(outcomeTokenAmounts[i]) * UNIT_DEC);
        }

        // Calculate liquidity parameters for old and new states
        SD59x18 bOld = getB(balancesSd);
        SD59x18 bNew = getB(qNewSd);

        // Calculate exponential sums and offsets for both states
        (SD59x18 sumOld, SD59x18 offOld) = sumExp(balancesSd, bOld);
        (SD59x18 sumNew, SD59x18 offNew) = sumExp(qNewSd, bNew);

        // Calculate cost function values
        SD59x18 cOld = bOld.mul(ln(sumOld).add(offOld));
        SD59x18 cNew = bNew.mul(ln(sumNew).add(offNew));

        // Return the difference in cost
        netCost = int256(cNew.sub(cOld).unwrap()) / int256(UNIT_DEC);
    }

    // ============ Internal Functions ============

    /**
     * @notice Calculates the marginal price for a specific outcome from a given state vector
     * @param qs Array of outcome token amounts representing the market state
     * @param idx Index of the outcome to calculate price for
     * @return priceWad The marginal price in fixed-point format (18 decimals)
     * @dev This is the core pricing function that implements the LMSR formula
     *
     * The LMSR pricing formula is: π_i = exp(q_i/b) / Σ(exp(q_j/b))
     * where:
     * - q_i is the amount of outcome i tokens
     * - b = α * Σ(q_j) is the liquidity parameter
     * - α is the alpha parameter controlling market depth
     */
    function _marginalPriceFromMemory(int256[] memory qs, uint8 idx) internal view returns (int256 priceWad) {
        uint256 n = qs.length;
        require(idx < n, "Invalid outcome index");

        SD59x18[] memory qWad = new SD59x18[](n);

        // Step 1: Convert qs to SD59x18 fixed-point format
        for (uint256 i = 0; i < n; i++) {
            require(qs[i] >= 0, "Negative outcome amount");
            qWad[i] = sd(qs[i] * UNIT_DEC);
        }

        // Step 2: Calculate b = α * Σ qs (liquidity parameter)
        SD59x18 b = getB(qWad);
        require(b.unwrap() > 0, "Liquidity parameter is zero");

        // Step 3: Normalize qWad[i] ← qWad[i]/b
        for (uint256 i = 0; i < n; i++) {
            qWad[i] = qWad[i].div(b);
        }

        // Step 4: Calculate offset and sum for numerical stability
        SD59x18 offset = _computeOffset(qWad);
        SD59x18 sum = sd(0);
        for (uint256 i = 0; i < n; i++) {
            sum = sum.add(exp(qWad[i].sub(offset)));
        }
        require(sum.unwrap() > 0, "Sum is zero");

        // Step 5: Calculate final price using LMSR formula
        SD59x18 numer = exp(qWad[idx].sub(offset));
        priceWad = int256(numer.div(sum).unwrap());
    }

    /**
     * @notice Calculates the liquidity parameter b = α * Σ(q_i)
     * @param q Array of outcome token amounts
     * @return b The liquidity parameter
     * @dev The liquidity parameter controls market depth and price sensitivity
     * Higher b means more liquidity and lower price impact per trade
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
     * @dev This function implements the numerical stability technique:
     *
     * Instead of computing Σ exp(q_i), we compute:
     * exp(offset) * Σ exp(q_i - offset)
     *
     * This prevents overflow when q_i values are large
     */
    function sumExp(SD59x18[] memory q, SD59x18 b) internal view returns (SD59x18 sum, SD59x18 offset) {
        uint256 n = q.length;

        // Normalize q by dividing by b
        SD59x18[] memory z = new SD59x18[](n);
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

        // Apply offset for numerical stability
        offset = offset.sub(EXP_LIMIT_DEC);

        // Calculate sum of exponentials with offset
        sum = sd(0);
        for (uint256 i = 0; i < n; i++) {
            sum = sum.add(exp(z[i].sub(offset)));
        }
    }

    // ============ Private Functions ============

    /**
     * @notice Computes the offset for numerical stability in exponential calculations
     * @param z Array of normalized outcome amounts
     * @return The offset value to prevent overflow
     * @dev This function finds the maximum value and subtracts EXP_LIMIT_DEC
     * to ensure all exponential calculations stay within safe bounds
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
