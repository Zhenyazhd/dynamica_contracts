// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;
pragma abicoder v2;


interface IFlareAssetRegistry {

    /**
     * @notice Returns if the token is a Flare Asset
     * @dev All other methods that accept token address will fail if this method returns false
     * @param token The token to be checked
     */
    function isFlareAsset(address token) external view returns (bool);

    /**
     * Return the asset type of the token. Asset type is a hash uniquely identifying the asset type.
     * For example, for wrapped native token, the type is `keccak256("wrapped native")`,
     * and for all f-assets the type will be `keccak256("f-asset")`.
     */
    function assetType(address _token) external view returns (bytes32);
    
     /**
     * @notice Returns the address of the Flare Asset with the selected symbol
     * @param symbol The token's symbol
     */
    function assetBySymbol(string calldata symbol) external view returns (address);

    /**
     * @notice Returns if the Flare Asset supports delegation via IVPToken interface
     * @param token The token to be checked
     */
    function supportsFtsoDelegation(address token) external view returns (bool);

    /**
     * @notice Returns the maximum allowed number of delegates by percent for the selected token
     * @param token The token to be checked
     */
    function maxDelegatesByPercent(address token) external view returns (uint256);

    /**
     * @notice Returns the incentive pool address for the selected token
     * @param token The token to be checked
     */
    function incentivePoolFor(address token) external view returns (address);

    /**
     * @notice Returns the addresses of all Flare Assets
     */
    function allAssets() external view returns (address[] memory);

    /**
     * @notice Returns the addresses and associated symbols of all Flare Assets
     */
    function allAssetsWithSymbols() external view returns (address[] memory, string[] memory);

    /**
     * @notice Returns all asset types.
     */
    function allAssetTypes() external view returns (bytes32[] memory);
        
    /**
     * @notice Returns the addresses of all Flare Assets of given type.
     * @param _assetType a type hash, all returned assets will have this assetType
     */
    function allAssetsOfType(bytes32 _assetType) external view returns (address[] memory);
    
    /**
     * @notice Returns the addresses and associated symbols of all Flare Assets of given type.
     * @param _assetType a type hash, all returned assets will have this assetType
     */
    function allAssetsOfTypeWithSymbols(bytes32 _assetType) external view returns (address[] memory, string[] memory);

     /**
     * @notice Returns a generic asset attribute value.
     * @param token The token's address
     * @param nameHash attributes name's hash
     * @return defined true if the attribute is defined for this token
     * @return value attribute value, may have to be cast into some other type
     */
    function getAttribute(address token, bytes32 nameHash) external view returns (bool defined, bytes32 value);
}
