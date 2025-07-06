// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;


/**
 * @title Validator registry contract
 * @notice This contract is used as a mapping from data provider's address to {node id, P-Chain public key}
 * @notice In order to get the ability to become a validator, data provider must register using this contract
 * @dev Only whitelisted data provider can register
 */
interface IValidatorRegistry {

    event DataProviderRegistered(address indexed dataProvider, string nodeId, string pChainPublicKey);
    event DataProviderUnregistered(address indexed dataProvider);

    /**
     * @notice Register data provider's address as a validator - emits DataProviderRegistered event
     * @param _nodeId Data provider's node id
     * @param _pChainPublicKey Data provider's P-Chain public key
     * @dev Data provider must be whitelisted
     * @dev `_nodeId` and `_pChainPublicKey` should not be already in use by some other data provider
     */
    function registerDataProvider(string memory _nodeId, string memory _pChainPublicKey) external;

    /**
     * @notice Unregister data provider's address as a validator - emits DataProviderUnregistered event
     */
    function unregisterDataProvider() external;

    /**
     * @notice Returns data provider's node id and P-Chain public key
     * @param _dataProvider Data provider's address
     * @return _nodeId Data provider's node id
     * @return _pChainPublicKey Data provider's P-Chain public key
     */
    function getDataProviderInfo(address _dataProvider)
        external view returns (string memory _nodeId, string memory _pChainPublicKey);

    /**
     * @notice Returns data provider's address that was registered with given node id
     * @param _nodeId Data provider's node id hash
     * @return _dataProvider Data provider's address
     */
    function getDataProviderForNodeId(bytes32 _nodeId) 
        external view returns (address _dataProvider);

    /**
     * @notice Returns data provider's address that was registered with given P-Chain public key
     * @param _pChainPublicKey Data provider's P-Chain public key hash
     * @return _dataProvider Data provider's address
     */
    function getDataProviderForPChainPublicKey(bytes32 _pChainPublicKey) 
        external view returns (address _dataProvider);
}
