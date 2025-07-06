// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;


interface IIAddressUpdatable {
    /**
     * @notice Updates contract addresses - should be called only from AddressUpdater contract
     * @param _contractNameHashes       list of keccak256(abi.encode(...)) contract names
     * @param _contractAddresses        list of contract addresses corresponding to the contract names
     */
    function updateContractAddresses(
        bytes32[] memory _contractNameHashes,
        address[] memory _contractAddresses
        ) external;
}
