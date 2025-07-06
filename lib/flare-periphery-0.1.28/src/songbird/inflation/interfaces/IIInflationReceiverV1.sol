// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

interface IIInflationReceiverV1 {
    /**
     * Notify the receiver that it is entitled to receive `_toAuthorizeWei` inflation amount.
     * @param _toAuthorizeWei the amount of inflation that can be awarded in the coming day
     */
    function setDailyAuthorizedInflation(uint256 _toAuthorizeWei) external;

    /**
     * Receive native tokens from inflation.
     */
    function receiveInflation() external payable;

    /**
     * Inflation receivers have a reference to the Inflation contract.
     */
    function getInflationAddress() external returns(address);

    /**
     * Implement this function for updating inflation receiver contracts through AddressUpdater.
     */
    function getContractName() external view returns (string memory);
}
