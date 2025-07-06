// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

interface IGovernanceVotePower {
    /**
     * @notice Delegate all governance vote power of `msg.sender` to `_to`.
     * @param _to The address of the recipient
     **/
    function delegate(address _to) external;

    /**
     * @notice Undelegate all governance vote power of `msg.sender``.
     **/
    function undelegate() external;

    /**
    * @notice Get the governance vote power of `_who` at block `_blockNumber`
    * @param _who The address to get voting power.
    * @param _blockNumber The block number at which to fetch.
    * @return _votePower    Governance vote power of `_who` at `_blockNumber`.
    */
    function votePowerOfAt(address _who, uint256 _blockNumber) external view returns(uint256);

    /**
    * @notice Get the vote power of `account` at the current block.
    * @param account The address to get voting power.
    * @return Vote power of `account` at the current block number.
    */    
    function getVotes(address account) external view returns (uint256);

    /**
    * @notice Get the delegate's address of `_who` at block `_blockNumber`
    * @param _who The address to get delegate's address.
    * @param _blockNumber The block number at which to fetch.
    * @return Delegate's address of `_who` at `_blockNumber`.
    */
    function getDelegateOfAt(address _who, uint256 _blockNumber) external view returns (address);

    /**
    * @notice Get the delegate's address of `_who` at the current block.
    * @param _who The address to get delegate's address.
    * @return Delegate's address of `_who` at the current block number.
    */    
    function getDelegateOfAtNow(address _who) external  view returns (address);

}
