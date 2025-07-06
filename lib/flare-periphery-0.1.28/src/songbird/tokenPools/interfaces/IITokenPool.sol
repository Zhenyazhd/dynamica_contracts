// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

interface IITokenPool {

    /**
     * @notice Return token pool supply data
     * @return _foundationAllocatedFundsWei     Foundation allocated funds (wei)
     * @return _totalInflationAuthorizedWei     Total inflation authorized amount (wei)
     * @return _totalClaimedWei                 Total claimed amount (wei)
     */
    function getTokenPoolSupplyData() external view returns (
        uint256 _foundationAllocatedFundsWei,
        uint256 _totalInflationAuthorizedWei,
        uint256 _totalClaimedWei
    );
}
