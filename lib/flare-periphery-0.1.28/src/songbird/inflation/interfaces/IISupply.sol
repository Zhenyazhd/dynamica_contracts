// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;


interface IISupply {

    /**
     * @notice Updates circulating supply
     * @dev Also updates the burn address amount
    */
    function updateCirculatingSupply() external;

    /**
     * @notice Updates authorized inflation and circulating supply - emits event if error
     * @param _inflationAuthorizedWei               Authorized inflation
     * @dev Also updates the burn address amount
    */
    function updateAuthorizedInflationAndCirculatingSupply(uint256 _inflationAuthorizedWei) external;

    /**
     * @notice Get approximate circulating supply for given block number from cache - only past block
     * @param _blockNumber                          Block number
     * @return _circulatingSupplyWei Return approximate circulating supply for last known block <= _blockNumber
    */
    function getCirculatingSupplyAtCached(uint256 _blockNumber) external returns(uint256 _circulatingSupplyWei);

    /**
     * @notice Get approximate circulating supply for given block number
     * @param _blockNumber                          Block number
     * @return _circulatingSupplyWei Return approximate circulating supply for last known block <= _blockNumber
    */
    function getCirculatingSupplyAt(uint256 _blockNumber) external view returns(uint256 _circulatingSupplyWei);

    /**
     * @notice Get total inflatable balance (initial genesis amount + total authorized inflation)
     * @return _inflatableBalanceWei Return inflatable balance
    */
    function getInflatableBalance() external view returns(uint256 _inflatableBalanceWei);
}
