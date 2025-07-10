// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SD59x18, sd, exp, ln} from "@prb-math/src/SD59x18.sol";
import {MarketMaker} from "./SimpleMarketMaker.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";

/**
 * @title LMSRMarketMaker
 * @dev Logarithmic Market Scoring Rule (LMSR) market maker implementation
 * @notice This contract implements LMSR pricing mechanism for prediction markets
 */
contract LMSRMarketMaker is MarketMaker {
    // ============ Constants ============

    /// @notice Decimal precision for fixed-point arithmetic
    int256 public constant UNIT_DEC = 1e18;

    /// @notice Exponential limit to prevent overflow in price calculations
    SD59x18 public immutable EXP_LIMIT_DEC = sd(1275 * UNIT_DEC / 10);

    /// @notice LMSR liquidity parameter (alpha)
    SD59x18 public alpha = sd(3 * UNIT_DEC / 100);

    // ============ Constructor ============

    /**
     * @notice Constructor for LMSRMarketMaker
     * @param _collateralToken The ERC20 token used as collateral
     * @param _fee The fee rate in basis points
     */
    constructor(IERC20 _collateralToken, uint64 _fee) MarketMaker(_collateralToken, _fee) {}

    // ============ Public Functions ============

    /**
     * @notice Calculate delta for 2-outcome market to achieve target price for outcome 0
     * @param q0 Current quantity of outcome 0 (in base units)
     * @param q1 Current quantity of outcome 1 (in base units)
     * @param targetWad Target price for outcome 0 as SD59x18 (e.g., 0.7e18 for 0.7)
     * @param first Whether this is the first outcome (affects delta calculation)
     * @return delta Quantity change to add to q0 to achieve target price
     */
    function getDelta(int256 q0, int256 q1, int256 targetWad, bool first) public view returns (int256 delta) {
        require(q0 >= 0 && q1 >= 0, "Quantities must be non-negative");
        require(targetWad > 0 && targetWad < UNIT_DEC, "Target must be in (0,1)");

        SD59x18[] memory qs = new SD59x18[](2);
        qs[0] = sd(q0 * UNIT_DEC);
        qs[1] = sd(q1 * UNIT_DEC);

        SD59x18 b = getB(qs);
        require(b.unwrap() > 0, "B parameter is zero");

        // Calculate target / (1 - target)
        SD59x18 target = sd(targetWad);
        SD59x18 one = sd(UNIT_DEC);
        SD59x18 ratio = target.div(one.sub(target));

        // Calculate ln(ratio)
        SD59x18 lnRatio = ln(ratio);

        int256 raw = int256(b.mul(lnRatio).unwrap() / int256(UNIT_DEC));

        if (first) {
            delta = raw + (q1 - q0);
        } else {
            delta = raw + (q0 - q1);
        }
    }

    /**
     * @notice Calculate delta for generic multi-outcome market to achieve target price
     * @param qs Current quantities array (not modified)
     * @param idx Index of the outcome to price
     * @param targetWad Target price for outcome idx as SD59x18 (0 < targetWad < 1e18)
     * @return delta Calculated delta for outcome idx
     */
    function getDeltaGeneric(int256[] memory qs, uint8 idx, int256 targetWad) public view returns (int256 delta) {
        require(qs.length > idx, "Invalid outcome index");
        require(targetWad > 0 && targetWad < UNIT_DEC, "Target must be in (0,1)");

        // Binary search range for delta
        uint256 lo = 0;
        uint256 hi = 10 ** 27; // Maximum 1e27 tokens

        // Binary search with ~60 iterations for precision
        for (uint256 i = 0; i < 60; i++) {
            uint256 mid = (lo + hi) >> 1;

            // Test with delta = mid
            qs[idx] += int256(mid);
            int256 priceWad = _marginalPriceFromMemory(qs, idx);
            qs[idx] -= int256(mid); // Revert for next iteration

            if (priceWad > targetWad) {
                hi = mid; // Price too high, reduce delta
            } else {
                lo = mid; // Price too low, increase delta
            }
        }

        delta = int256(lo);
    }

    /**
     * @notice Calculate marginal price for a specific outcome
     * @param idx Index of the outcome
     * @return priceWad Marginal price as SD59x18
     */
    function calcMarginalPrice(uint8 idx) public view returns (int256 priceWad) {
        int256[] memory qs = new int256[](outcomeSlotCount);
        for (uint256 i = 0; i < qs.length; i++) {
            qs[i] = int256(outcomeTokenAmounts[i]);
        }
        return _marginalPriceFromMemory(qs, idx);
    }

    /**
     * @notice Calculate net cost for trading outcome tokens
     * @param deltaOutcomeAmounts Array of token amount changes for each outcome
     * @return netCost Net cost of the trade
     */
    function calcNetCost(int256[] memory deltaOutcomeAmounts) public view override returns (int256 netCost) {
        uint256 n = outcomeSlotCount;
        require(deltaOutcomeAmounts.length == n, "Invalid outcome amount length");

        int256[] memory q_new = new int256[](n);
        SD59x18[] memory balances_sd = new SD59x18[](n);
        SD59x18[] memory q_new_sd = new SD59x18[](n);

        for (uint256 i = 0; i < n; i++) {
            q_new[i] = int256(outcomeTokenAmounts[i]) + deltaOutcomeAmounts[i];
            q_new_sd[i] = sd(q_new[i] * UNIT_DEC);
            balances_sd[i] = sd(int256(outcomeTokenAmounts[i]) * UNIT_DEC);
        }

        SD59x18 b_old = getB(balances_sd);
        SD59x18 b_new = getB(q_new_sd);

        (SD59x18 sumOld, SD59x18 offOld) = sumExp(balances_sd, b_old);
        (SD59x18 sumNew, SD59x18 offNew) = sumExp(q_new_sd, b_new);

        SD59x18 c_old = b_old.mul(ln(sumOld).add(offOld));
        SD59x18 c_new = b_new.mul(ln(sumNew).add(offNew));

        netCost = int256(c_new.sub(c_old).unwrap()) / int256(UNIT_DEC);
    }

    // ============ Internal Functions ============

    /**
     * @notice Calculate marginal price from memory array
     * @param qs Quantities array
     * @param idx Outcome index
     * @return priceWad Marginal price as SD59x18
     */
    function _marginalPriceFromMemory(int256[] memory qs, uint8 idx) internal view returns (int256 priceWad) {
        uint256 n = qs.length;
        require(idx < n, "Invalid outcome index");

        SD59x18[] memory qWad = new SD59x18[](n);

        // Convert qs to SD59x18 format
        for (uint256 i = 0; i < n; i++) {
            require(qs[i] >= 0, "Quantity must be non-negative");
            qWad[i] = sd(qs[i] * UNIT_DEC);
        }

        // Calculate b = α * Σ qs
        SD59x18 b = getB(qWad);
        require(b.unwrap() > 0, "B parameter is zero");

        // Normalize qWad[i] = qWad[i]/b
        for (uint256 i = 0; i < n; i++) {
            qWad[i] = qWad[i].div(b);
        }

        // Calculate offset and sum
        SD59x18 offset = _computeOffset(qWad);
        SD59x18 sum = sd(0);
        for (uint256 i = 0; i < n; i++) {
            sum = sum.add(exp(qWad[i].sub(offset)));
        }
        require(sum.unwrap() > 0, "Sum is zero");

        // Calculate final price
        SD59x18 numer = exp(qWad[idx].sub(offset));
        priceWad = int256(numer.div(sum).unwrap());
    }

    /**
     * @notice Calculate B parameter for LMSR
     * @param q Quantities array
     * @return b B parameter
     */
    function getB(SD59x18[] memory q) internal view returns (SD59x18 b) {
        SD59x18 sum = sd(0);
        for (uint256 i = 0; i < q.length; i++) {
            sum = sum.add(q[i]);
        }
        b = sum.mul(alpha);
        b = b == sd(0) ? sd(1) : b;
    }

    /**
     * @notice Calculate exponential sum with offset for numerical stability
     * @param q Quantities array
     * @param b B parameter
     * @return sum Exponential sum
     * @return offset Offset used for numerical stability
     */
    function sumExp(SD59x18[] memory q, SD59x18 b) internal view returns (SD59x18 sum, SD59x18 offset) {
        uint256 n = q.length;

        SD59x18[] memory z = new SD59x18[](n);
        for (uint256 i = 0; i < n; i++) {
            z[i] = q[i].div(b);
        }

        // Find maximum for offset calculation
        offset = z[0];
        for (uint256 i = 1; i < n; i++) {
            if (z[i].unwrap() > offset.unwrap()) {
                offset = z[i];
            }
        }
        offset = offset.sub(EXP_LIMIT_DEC);

        // Calculate exponential sum
        sum = sd(0);
        for (uint256 i = 0; i < n; i++) {
            sum = sum.add(exp(z[i].sub(offset)));
        }
    }

    /**
     * @notice Compute offset for numerical stability in exponential calculations
     * @param z Normalized quantities array
     * @return offset Computed offset
     */
    function _computeOffset(SD59x18[] memory z) private view returns (SD59x18 offset) {
        SD59x18 maxZ = z[0];
        for (uint256 i = 1; i < z.length; i++) {
            if (z[i].unwrap() > maxZ.unwrap()) {
                maxZ = z[i];
            }
        }
        return maxZ.sub(EXP_LIMIT_DEC);
    }
}
