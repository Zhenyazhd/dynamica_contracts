// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;
pragma abicoder v2;

import "../../IFlareAssetRegistry.sol";


interface IIFlareAssetRegistry is IFlareAssetRegistry {
    /**
     * Allows a provider contract to register assets.
     * @param _provider address of the provider (a contract implementing IIFlareAssetRegistryProvider)
     * @param _registerAssets if true, all the assets held by the provider are immediately registered;
     *   should usually be true, but can be false to avoid unbounded work in some cases
     * @dev Only governance can call.
     */
    function registerProvider(address _provider, bool _registerAssets) external;

    /**
     * Remove the provider contract from known providers (e.g. when a new version of the provider is deployed, the
     * old one will be removed).
     * @param _provider address of the provider (a contract implementing IIFlareAssetRegistryProvider)
     * @param _unregisterAssets if true, all the assets belonging to the provider are automatically unregistered;
     *   should usually be true, but can be false to avoid unbounded work in some cases - in this case,
     *   all the assets must be unregistered before calling this method
     * @dev Only governance can call.
     */
    function unregisterProvider(address _provider, bool _unregisterAssets) external;

    /**
     * Unregisters and re-registers all the assets belonging to the given provider.
     * @param _provider address of the provider (a contract implementing IIFlareAssetRegistryProvider)
     * @dev Only governance can call (without timelock).
     */
    function refreshProviderAssets(address _provider) external;
    
    /**
     * Register a new asset.
     * @param _token address of the asset (a contract implementing IERC20 interface with implemented symbol())
     * @dev Can only be called by a registered provider.
     */
    function registerAsset(address _token) external;

    /**
     * Unregister an asset.
     * @param _token address of the asset (a contract implementing IERC20 interface with implemented symbol())
     * @dev Can only be called by the provider which registered the token.
     */
    function unregisterAsset(address _token) external;
}
