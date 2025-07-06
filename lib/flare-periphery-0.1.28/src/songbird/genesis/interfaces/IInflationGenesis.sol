
// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;


interface IInflationGenesis {
    /**
     * @notice Receive newly minted native tokens from the FlareDaemon.
     * @dev Assume that the amount received will be >= last topup requested across all services.
     *   If there is not enough balance sent to cover the topup request, expect library method will revert.
     *   Also assume that any balance received greater than the topup request calculated
     *   came from self-destructor sending a balance to this contract.
     */
    function receiveMinting() external payable;
}
