// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

interface IUpdateValidators {
    /**
    update the validators after reward epoch
     **/
    function updateActiveValidators() external;
}
