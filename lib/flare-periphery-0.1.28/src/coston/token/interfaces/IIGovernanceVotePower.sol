// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

import "../../IVPToken.sol";
import "../../IGovernanceVotePower.sol";

interface IIGovernanceVotePower is IGovernanceVotePower {
    /**
     * Event triggered when an delegator's balance changes.
     *
     * Note: the event is always emitted from `GovernanceVotePower`.
     */
    event DelegateVotesChanged(
    address indexed delegate, 
    uint256 previousBalance, 
    uint256 newBalance
    );

    /**
     * Event triggered when an account delegates to another account.
     *
     * Note: the event is always emitted from `GovernanceVotePower`.
     */
    event DelegateChanged(
    address indexed delegator, 
    address indexed fromDelegate, 
    address indexed toDelegate
    );

    /**
     * Update vote powers when tokens are transferred.
     **/
    function updateAtTokenTransfer(
        address _from,
        address _to,
        uint256 _fromBalance,
        uint256 _toBalance,
        uint256 _amount
    ) external;

    /**
     * Set the cleanup block number.
     * Historic data for the blocks before `cleanupBlockNumber` can be erased,
     * history before that block should never be used since it can be inconsistent.
     * In particular, cleanup block number must be before current vote power block.
     * @param _blockNumber The new cleanup block number.
     */
    function setCleanupBlockNumber(uint256 _blockNumber) external;

    /**
     * Set the contract that is allowed to call history cleaning methods.
     */
    function setCleanerContract(address _cleanerContract) external;

    /**
     * @notice Get the token that this governance vote power contract belongs to.
     */
    function ownerToken() external view returns (IVPToken);

    function getCleanupBlockNumber() external view returns(uint256);
}
