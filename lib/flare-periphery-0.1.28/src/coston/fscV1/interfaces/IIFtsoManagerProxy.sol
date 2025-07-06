// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

import "./IIFastUpdaterView.sol";
import "../../IFastUpdatesConfiguration.sol";
import "../../IRelay.sol";
import "../../IFlareSystemsManager.sol";

/**
 * FtsoManagerProxy internal interface.
 */
interface IIFtsoManagerProxy {

    function relay() external view returns (IRelay);

    function fastUpdater() external view returns (IIFastUpdaterView);

    function flareSystemsManager() external view returns (IFlareSystemsManager);

    function fastUpdatesConfiguration() external view returns (IFastUpdatesConfiguration);
}
