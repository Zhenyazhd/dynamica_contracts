// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LMSRMath} from "../../src/LMSRMath.sol";

contract LMSRMathEchidnaTest {
    LMSRMath public lmsrMath;
    
    // State variables for storing roundtrip results
    int256 public lastCost1;
    int256 public lastCost2;
    bool public lastRoundtripValid;
    
    // State variables for storing monotone results
    int256 public lastCostSmall;
    int256 public lastCostLarge;
    bool public lastMonotoneValid;
    
    // State variables for storing marginal prices results
    int256 public lastMarginalPricesSum;
    bool public lastMarginalPricesValid;

    constructor() {
        lmsrMath = new LMSRMath();
    }

    /// @notice Fuzz function that performs roundtrip trade actions
    function fuzz_roundtrip_trade(
        int256[] memory q,
        int256[] memory delta,
        int256 alpha
    ) public {
        if (q.length == 0 || q.length != delta.length || q.length > 10) {
            lastRoundtripValid = false;
            return;
        }
        
        // Normalize alpha: 1-100 (representing 1% to 100%)
        int256 alphaNorm = int256(uint256(alpha < 0 ? -alpha : alpha) % 100) + 1;
        uint256 expLimitNorm = 12_750;
        
        for (uint256 i = 0; i < q.length; i++) {
            if (q[i] < 0 || q[i] > 1e10) {
                lastRoundtripValid = false;
                return;
            }
        }
        
        try lmsrMath.calcNetCostPure(q, delta, alphaNorm, expLimitNorm) returns (int256 c1) {
            lastCost1 = c1;
            
            int256[] memory q2 = new int256[](q.length);
            for (uint256 i = 0; i < q.length; i++) {
                int256 v = q[i] + delta[i];
                if (v < 0) {
                    lastRoundtripValid = false;
                    return;
                }
                q2[i] = v;
            }
            
            int256[] memory deltaBack = new int256[](q.length);
            for (uint256 i = 0; i < q.length; i++) {
                deltaBack[i] = -delta[i];
            }
            
            try lmsrMath.calcNetCostPure(q2, deltaBack, alphaNorm, expLimitNorm) returns (int256 c2) {
                lastCost2 = c2;
                lastRoundtripValid = true;
            } catch {
                lastRoundtripValid = false;
            }
        } catch {
            lastRoundtripValid = false;
        }
    }


    /// @notice Fuzz function that performs monotone trade actions
    function fuzz_monotone_trade(
        int256[] memory q,
        uint8 idx,
        int256 alpha,
        uint256 expLimit,
        uint256 x,
        uint256 y
    ) public {
        if (q.length == 0 || idx >= q.length) {
            lastMonotoneValid = false;
            return;
        }
        
        int256 alphaNorm = int256(uint256(alpha < 0 ? -alpha : alpha) % 100) + 1;
        uint256 expLimitNorm = (expLimit % 151) + 50;
        
        for (uint256 i = 0; i < q.length; i++) {
            if (q[i] < 0 || q[i] > 1e10) {
                lastMonotoneValid = false;
                return;
            }
        }
        
        int256[] memory dSmall = new int256[](q.length);
        int256[] memory dLarge = new int256[](q.length);

        uint256 amountSmall = (x % 1e6) + 1;
        uint256 amountLarge = amountSmall + (y % 1e6);

        dSmall[idx] = int256(amountSmall);
        dLarge[idx] = int256(amountLarge);

        try lmsrMath.calcNetCostPure(q, dSmall, alphaNorm, expLimitNorm) returns (int256 cSmall) {
            try lmsrMath.calcNetCostPure(q, dLarge, alphaNorm, expLimitNorm) returns (int256 cLarge) {
                lastCostSmall = cSmall;
                lastCostLarge = cLarge;
                lastMonotoneValid = true;
            } catch {
                lastMonotoneValid = false;
            }
        } catch {
            lastMonotoneValid = false;
        }
    }

    /// @notice Fuzz function that calculates marginal prices for all outcomes
    function fuzz_marginal_prices(
        int256[] memory q,
        int256 alpha,
        uint256 expLimit
    ) public {
        if (q.length == 0 || q.length > 10) {
            lastMarginalPricesValid = false;
            return;
        }
        
        int256 alphaNorm = int256(uint256(alpha < 0 ? -alpha : alpha) % 100) + 1;
        uint256 expLimitNorm = (expLimit % 151) + 50;
        
        for (uint256 i = 0; i < q.length; i++) {
            if (q[i] < 0 || q[i] > 1e10) {
                lastMarginalPricesValid = false;
                return;
            }
        }
        
        int256 sum = 0;
        bool allPricesCalculated = true;
        for (uint8 i = 0; i < q.length; i++) {
            try lmsrMath.calcMarginalPricePure(q, i, alphaNorm, expLimitNorm) returns (int256 price) {
                sum += price;
            } catch {
                allPricesCalculated = false;
                break;
            }
        }
        
        if (allPricesCalculated) {
            lastMarginalPricesSum = sum;
            lastMarginalPricesValid = true;
        } else {
            lastMarginalPricesValid = false;
        }
    }

    /// @notice Invariant check: sum of all marginal prices should be approximately 1e18
    function echidna_marginal_prices_sum_to_one() public view returns (bool) {
        if (!lastMarginalPricesValid) return true;
        
        int256 diff = lastMarginalPricesSum - 1e18;
        if (diff < 0) diff = -diff;
        return diff < 1e12;
    }


    /// @notice Invariant check: larger purchase should cost more than smaller purchase
    function echidna_monotone_in_size() public view returns (bool) {
        if (!lastMonotoneValid) return true;
        
        if (lastCostSmall <= 0 || lastCostLarge <= 0) return true;
        return lastCostLarge >= lastCostSmall;
    }


    /// @notice Invariant check: roundtrip cost should be approximately zero
    function echidna_roundtrip_zero_cost() public view returns (bool) {
        if (!lastRoundtripValid) return true;
        
        int256 total = lastCost1 + lastCost2;
        if (total < 0) total = -total;
        return total < 1e12;
    }

}