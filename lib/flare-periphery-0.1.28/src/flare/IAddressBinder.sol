// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

/**
 * Interface for the `AddressBinder` contract.
 */
interface IAddressBinder {

    /**
     * @notice Event emitted when c-chan and P-chain addresses are registered
     */
    event AddressesRegistered(bytes publicKey, bytes20 pAddress, address cAddress);

    /**
     * Register P-chain and C-chain addresses.
     * @param _publicKey Public key from which addresses to register are derived from.
     * @param _pAddress P-chain address to register.
     * @param _cAddress C-chain address to register.
     */
    function registerAddresses(bytes calldata _publicKey, bytes20 _pAddress, address _cAddress) external;

    /**
     * Register P-chain and C-chain addresses derived from given public key.
     * @param _publicKey Public key from which addresses to register are derived from.
     * @return _pAddress Registered P-chain address.
     * @return _cAddress Registered C-chain address.
     */
    function registerPublicKey(bytes calldata _publicKey) external returns(bytes20 _pAddress, address _cAddress);

    /**
     * @dev Queries the C-chain address for given P-chain address.
     * @param _pAddress The P-chain address for which corresponding C-chain address will be retrieved.
     * @return _cAddress The corresponding c-address.
     **/
    function pAddressToCAddress(bytes20 _pAddress) external view returns(address _cAddress);

    /**
     * @dev Queries the P-chain address for given C-chain address.
     * @param _cAddress The C-chain address for which corresponding P-chain address will be retrieved.
     * @return _pAddress The corresponding p-address.
     **/
    function cAddressToPAddress(address _cAddress) external view returns(bytes20 _pAddress);
}