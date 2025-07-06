
// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

import "./IFtsoGenesis.sol";


interface IFtsoRegistryGenesis {

    function getFtsos(uint256[] memory _indices) external view returns(IFtsoGenesis[] memory _ftsos);
}
