// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;
pragma abicoder v2;


interface IIFlareAssetRegistryProvider {
    /**
     * Returns a unique hash identifying this provider and its assets.
     */
    function assetType() external view returns (bytes32);
    
    /**
     * @notice Returns the addresses of all Flare Assets
     */
    function allAssets() external view returns (address[] memory);

     /**
     * @notice Returns a generic asset attribute value.
     * @param _token The token's address
     * @param _nameHash attributes name's hash
     * @return _defined true if the attribute is defined for this token
     * @return _value attribute value, may have to be cast into some other type
     */
    function getAttribute(address _token, bytes32 _nameHash) external view returns (bool _defined, bytes32 _value);
    
}
