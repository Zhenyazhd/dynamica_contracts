// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

interface IIPreInflationCalculation {
    /**
     * @notice A method that is triggered before new inflation is calculated
     */
    function trigger() external;
}
