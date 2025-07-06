// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

/**
 * Interface for contracts delegating their governance vote power.
 */
interface IGovernanceVotePower {
    /**
     * Delegates all governance vote power of `msg.sender` to address `_to`.
     * @param _to The address of the recipient.
     */
    function delegate(address _to) external;

    /**
     * Undelegates all governance vote power of `msg.sender`.
     */
    function undelegate() external;

    /**
     * Gets the governance vote power of an address at a given block number, including
     * all delegations made to it.
     * @param _who The address being queried.
     * @param _blockNumber The block number at which to fetch the vote power.
     * @return Governance vote power of `_who` at `_blockNumber`.
     */
    function votePowerOfAt(address _who, uint256 _blockNumber) external view returns(uint256);

    /**
     * Gets the governance vote power of an address at the latest block, including
     * all delegations made to it.
     * @param _who The address being queried.
     * @return Governance vote power of `account` at the lastest block.
     */
    function getVotes(address _who) external view returns (uint256);

    /**
     * Gets the address an account is delegating its governance vote power to, at a given block number.
     * @param _who The address being queried.
     * @param _blockNumber The block number at which to fetch the address.
     * @return Address where `_who` was delegating its governance vote power at block `_blockNumber`.
     */
    function getDelegateOfAt(address _who, uint256 _blockNumber) external view returns (address);

    /**
     * Gets the address an account is delegating its governance vote power to, at the latest block number.
     * @param _who The address being queried.
     * @return Address where `_who` is currently delegating its governance vote power.
     */
    function getDelegateOfAtNow(address _who) external view returns (address);
}
