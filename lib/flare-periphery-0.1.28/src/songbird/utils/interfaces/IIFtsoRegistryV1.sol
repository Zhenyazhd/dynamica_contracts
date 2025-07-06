// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;
pragma abicoder v2;

import "../../ftso/interfaces/IIFtsoManager.sol";


interface IIFtsoRegistryV1 {

    function setFtsoManagerAddress(IIFtsoManager _ftsoManager) external;

    // returns ftso index
    function addFtso(IIFtso _ftsoContract) external returns(uint256);

    function removeFtso(IIFtso _ftso) external;

    function getFtsoBySymbol(string memory _symbol) external view returns(IIFtso _activeFtsoAddress);
    function getSupportedSymbols() external view returns(string[] memory _supportedSymbols);
    function getSupportedFtsos() external view returns(IIFtso[] memory _ftsos);
    function getFtsoIndex(string memory _symbol) external view returns (uint256 _assetIndex);
}
