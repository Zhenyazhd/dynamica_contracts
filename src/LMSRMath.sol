// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {SD59x18, sd, exp, ln} from "@prb-math/src/SD59x18.sol";

contract LMSRMath {
    int256 public constant UNIT_DEC = 1e18;

    error InvalidOutcomeIndex(uint256 providedIndex, uint256 maxIndex);
    error CollateralTokenDecimalsTooHigh(uint8 providedDecimals);
    error ZeroLiquidityParameter();
    error NegativeOutcomeAmount(int256 amount);
    error ZeroSum();
    error InvalidLength(uint256 providedLength, uint256 expectedLength);

    function getB(SD59x18[] memory q, SD59x18 alpha) public pure returns (SD59x18 b) {
        SD59x18 sum = sd(0);
        uint256 n = q.length;
        for (uint256 i = 0; i < n; i++) {
            sum = sum.add(q[i]);
        }
        b = sum.mul(alpha);
        // TODO: check if sometimes b == sd(0)???????
        // Ensure b is never zero to prevent division by zero
        b = b == sd(0) ? sd(1) : b;
    }

    function sumExp(SD59x18[] memory q, SD59x18 b, SD59x18 expLimitDec)
        public
        pure
        returns (SD59x18 sum, SD59x18 offset)
    {
        uint256 n = q.length;
        SD59x18[] memory z = new SD59x18[](n);

        for (uint256 i = 0; i < n; i++) {
            z[i] = q[i].div(b);
        }

        offset = z[0];
        for (uint256 i = 1; i < n; i++) {
            if (z[i].unwrap() > offset.unwrap()) {
                offset = z[i];
            }
        }

        offset = offset.sub(expLimitDec);

        sum = sd(0);
        for (uint256 i = 0; i < n; i++) {
            sum = sum.add(exp(z[i].sub(offset)));
        }
    }

    function computeOffset(SD59x18[] memory z, SD59x18 expLimitDec) public pure returns (SD59x18) {
        SD59x18 maxZ = z[0];
        for (uint256 i = 1; i < z.length; i++) {
            if (z[i].unwrap() > maxZ.unwrap()) {
                maxZ = z[i];
            }
        }
        return maxZ.sub(expLimitDec);
    }

    function calcMarginalPricePure(int256[] memory qInt, uint8 idx, int256 alphaWad, uint256 expLimit)
        external
        pure
        returns (int256 priceWad)
    {
        uint256 n = qInt.length;
        if (idx >= n) {
            revert InvalidOutcomeIndex(idx, n);
        }

        SD59x18[] memory qWad = new SD59x18[](n);
        for (uint256 i = 0; i < n; i++) {
            if (qInt[i] < 0) revert NegativeOutcomeAmount(qInt[i]);
            qWad[i] = sd(int256(uint256(qInt[i]) * uint256(UNIT_DEC)));
        }

        SD59x18 alpha = sd(int256((uint256(alphaWad) * uint256(UNIT_DEC)) / 100));
        SD59x18 b = getB(qWad, alpha);

        if (b == sd(0)) revert ZeroLiquidityParameter();

        for (uint256 i = 0; i < n; i++) {
            qWad[i] = qWad[i].div(b);
        }

        SD59x18 expLimitDec = sd(int256((uint256(expLimit) * uint256(UNIT_DEC)) / 100));
        SD59x18 offset = computeOffset(qWad, expLimitDec);

        SD59x18 sum = sd(0);
        for (uint256 i = 0; i < n; i++) {
            sum = sum.add(exp(qWad[i].sub(offset)));
        }
        if (sum.unwrap() == 0) revert ZeroSum();

        SD59x18 numer = exp(qWad[idx].sub(offset));
        SD59x18 p = numer.div(sum);
        return p.unwrap();
    }

    function calcNetCostPure(int256[] memory qCurrent, int256[] memory delta, int256 alphaWad, uint256 expLimit)
        external
        pure
        returns (int256 cNewMinusCOldWad)
    {
        uint256 n = qCurrent.length;
        if (delta.length != n) revert InvalidLength(delta.length, n);

        SD59x18[] memory currentSd = new SD59x18[](n);
        SD59x18[] memory newSd = new SD59x18[](n);

        for (uint256 i = 0; i < n; i++) {
            if (qCurrent[i] < 0) revert NegativeOutcomeAmount(qCurrent[i]);
            int256 qNew = qCurrent[i] + delta[i];
            if (qNew < 0) revert NegativeOutcomeAmount(qNew);
            currentSd[i] = sd(int256(uint256(qCurrent[i]) * uint256(UNIT_DEC)));
            newSd[i] = sd(int256(uint256(qNew) * uint256(UNIT_DEC)));
        }

        SD59x18 alpha = sd(int256((uint256(alphaWad) * uint256(UNIT_DEC)) / 100));

        SD59x18 bOld = getB(currentSd, alpha);
        SD59x18 bNew = getB(newSd, alpha);

        SD59x18 expLimitDec = sd(int256((uint256(expLimit) * uint256(UNIT_DEC)) / 100));

        (SD59x18 sumOld, SD59x18 offOld) = sumExp(currentSd, bOld, expLimitDec);
        (SD59x18 sumNew, SD59x18 offNew) = sumExp(newSd, bNew, expLimitDec);

        SD59x18 cOld = bOld.mul(ln(sumOld).add(offOld));
        SD59x18 cNew = bNew.mul(ln(sumNew).add(offNew));

        return cNew.sub(cOld).unwrap();
    }
}
