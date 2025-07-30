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
import {IHederaTokenService} from "@hashgraph/hedera-smart-contracts/contracts/system-contracts/hedera-token-service/IHederaTokenService.sol";
import "forge-std/src/console.sol";

/**
 * @title Dynamica
 * @dev A prediction market maker implementing the Logarithmic Market Scoring Rule (LMSR)
 * @notice This contract extends MarketMaker with LMSR-specific pricing and cost calculation logic
 */
contract Dynamica is MarketMaker {
    receive() external payable {}    


    /**
     * @dev Constructor that disables initializers for implementation contract
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the Dynamica market maker with configuration parameters
     * @param config Configuration struct containing market parameters
     * @param tokens Array of HederaToken structs for each outcome
     */
    function initialize(IDynamica.Config calldata config, IHederaTokenService.HederaToken[] memory tokens)
        public
        payable
        initializer
    {
        __Ownable_init(config.owner);
        
        fee = config.fee;
        collateralToken = config.collateralToken;
        expirationTime = config.expirationTime;
        
        uint8 collateralTokenDecimals = IERC20(collateralToken).decimals();
        
        if (collateralTokenDecimals > 18) {
            revert CollateralTokenDecimalsTooHigh(collateralTokenDecimals);
        }
          
        gammaPow = new uint32[](EPOCH_NUMBER);
        gammaPow[0] = GAMMA_UNIT;
        epochData[0].outcomeTokenAmounts = new int64[](config.outcomeSlotCount);
        for (uint32 i = 1; i < EPOCH_NUMBER; i++) {
            epochData[i].outcomeTokenAmounts = new int64[](config.outcomeSlotCount);
            gammaPow[i] = (gammaPow[i - 1] * config.gamma) / GAMMA_UNIT;
        }
        epochData[EPOCH_NUMBER].outcomeTokenAmounts = new int64[](config.outcomeSlotCount);

        initializeMarket(
            config.oracle,
            config.question,
            config.outcomeSlotCount,
            config.startFunding,
            config.outcomeTokenAmounts,
            config.decimals,
            tokens
        );
        
        alpha = sd((config.alpha * UNIT_DEC) / 100);   
        EXP_LIMIT_DEC = sd((config.expLimit * UNIT_DEC) / 100);
        DEC_COLLATERAL = int256(10 ** collateralTokenDecimals);
        DEC_Q = int256(10 ** uint32(decimals)); 
    }

    /**
     * @notice Calculates the current marginal price for a specific outcome
     * @param outcomeTokenIndex Index of the outcome token (0-based)
     * @return priceWad The marginal price in fixed-point format
     */
    function calcMarginalPrice(uint8 outcomeTokenIndex) public view returns (int256 priceWad) {
        uint256 n = outcomeSlotCount;
        if (outcomeTokenIndex >= n) {
            revert InvalidOutcomeIndex(outcomeTokenIndex, n);
        }
        SD59x18[] memory qWad = new SD59x18[](n);
        int256[] memory outcomeTokenAmounts_ = new int256[](n);
        for (uint256 i = 0; i < n; i++) {
            outcomeTokenAmounts_[i] = outcomeTokenSupplies[i];
            int256 qi = outcomeTokenAmounts_[i];
            qWad[i] = sd(qi * UNIT_DEC);
        }
        SD59x18 b = getB(qWad);
        for (uint256 i = 0; i < n; i++) {
            if (b == sd(0)) {
                revert ZeroLiquidityParameter();
            }
            qWad[i] = qWad[i].div(b);
        }
        SD59x18 offset = _computeOffset(qWad);
        SD59x18 sum = sd(0);
        for (uint256 i = 0; i < n; i++) {
            sum = sum.add(exp(qWad[i].sub(offset)));
        }
        if (sum == sd(0)) {
            revert ZeroSum();
        }
        SD59x18 p = exp(qWad[outcomeTokenIndex].sub(offset)).div(sum);
        priceWad = int256(p.unwrap());
    }

    /**
     * @notice Calculates the net cost of a trade using the LMSR cost function
     * @param deltaOutcomeAmounts Array of token amount changes for each outcome
     * @return netCost The net cost in collateral tokens (positive = cost, negative = payout)
     */
    function calcNetCost(int64[] memory deltaOutcomeAmounts) public view override returns (int256 netCost) {
        uint256 n = outcomeSlotCount;
        if (deltaOutcomeAmounts.length != n) {
            revert InvalidDeltaOutcomeAmountsLength(deltaOutcomeAmounts.length, n);
        }
        int256[] memory qNew = new int256[](n);
        SD59x18[] memory balancesSd = new SD59x18[](n);
        SD59x18[] memory qNewSd = new SD59x18[](n);
        int256[] memory outcomeTokenAmounts_ = new int256[](n);
        for (uint256 i = 0; i < n; i++) {
            outcomeTokenAmounts_[i] = outcomeTokenSupplies[i];
            qNew[i] = outcomeTokenAmounts_[i] + int256(deltaOutcomeAmounts[i]);
            qNewSd[i] = sd(qNew[i] * UNIT_DEC);
            balancesSd[i] = sd(outcomeTokenAmounts_[i] * UNIT_DEC);
        }
        SD59x18 bOld = getB(balancesSd);
        SD59x18 bNew = getB(qNewSd);
        (SD59x18 sumOld, SD59x18 offOld) = sumExp(balancesSd, bOld);
        (SD59x18 sumNew, SD59x18 offNew) = sumExp(qNewSd, bNew);
        SD59x18 cOld = bOld.mul(ln(sumOld).add(offOld));
        SD59x18 cNew = bNew.mul(ln(sumNew).add(offNew));
        netCost = (cNew.sub(cOld).unwrap() * DEC_COLLATERAL / UNIT_DEC) / DEC_Q;
    }

    /**
     * @notice Calculates the marginal price for a specific outcome from a given state vector
     * @param qs Array of outcome token amounts representing the market state
     * @param idx Index of the outcome to calculate price for
     * @return priceWad The marginal price in fixed-point format (18 decimals)
     */
    function _marginalPriceFromMemory(int256[] memory qs, uint8 idx) internal view returns (int256 priceWad) {
        uint256 n = qs.length;
        if (idx >= n) {
            revert InvalidOutcomeIndex(idx, n);
        }
        SD59x18[] memory qWad = new SD59x18[](n);
        for (uint256 i = 0; i < n; i++) {
            if (qs[i] < 0) {
                revert NegativeOutcomeAmount(qs[i]);
            }
            qWad[i] = sd(qs[i] * UNIT_DEC);
        }
        SD59x18 b = getB(qWad);
        if (b.unwrap() == 0) {
            revert ZeroLiquidityParameter();
        }
        for (uint256 i = 0; i < n; i++) {
            qWad[i] = qWad[i].div(b);
        }
        SD59x18 offset = _computeOffset(qWad);
        SD59x18 sum = sd(0);
        for (uint256 i = 0; i < n; i++) {
            sum = sum.add(exp(qWad[i].sub(offset)));
        }
        if (sum.unwrap() == 0) {
            revert ZeroSum();
        }
        SD59x18 numer = exp(qWad[idx].sub(offset));
        priceWad = numer.div(sum).unwrap();
    }

    /**
     * @notice Calculates the liquidity parameter b = α * Σ(q_i)
     * @param q Array of outcome token amounts
     * @return b The liquidity parameter
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
     * @notice Calculates the exponential sum and offset for numerical stability
     * @param q Array of normalized outcome amounts
     * @param b Liquidity parameter
     * @return sum The sum of exponentials
     * @return offset The offset used for numerical stability
     */
    function sumExp(SD59x18[] memory q, SD59x18 b) internal view returns (SD59x18 sum, SD59x18 offset) {
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
        offset = offset.sub(EXP_LIMIT_DEC);
        sum = sd(0);
        for (uint256 i = 0; i < n; i++) {
            sum = sum.add(exp(z[i].sub(offset)));
        }
    }

    /**
     * @notice Computes the offset for numerical stability in exponential calculations
     * @param z Array of normalized outcome amounts
     * @return The offset value to prevent overflow
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