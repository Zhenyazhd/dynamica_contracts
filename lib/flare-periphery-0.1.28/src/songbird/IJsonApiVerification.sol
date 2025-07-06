// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

import "./IJsonApi.sol";

interface IJsonApiVerification {
  function verifyJsonApi(IJsonApi.Proof calldata _proof) external view returns (bool _proved);
}
