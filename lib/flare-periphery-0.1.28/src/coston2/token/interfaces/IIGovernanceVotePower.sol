// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

import "../../IVPToken.sol";
import "../../IPChainStakeMirror.sol";
import "../../IGovernanceVotePower.sol";

/**
 * Internal interface for contracts delegating their governance vote power.
 */
interface IIGovernanceVotePower is IGovernanceVotePower {
    /**
     * Emitted when a delegate's vote power changes, as a result of a new delegation
     * or a token transfer, for example.
     *
     * The event is always emitted from a `GovernanceVotePower` contract.
     * @param delegate The account receiving the changing delegated vote power.
     * @param previousBalance Delegated vote power before the change.
     * @param newBalance Delegated vote power after the change.
     */
    event DelegateVotesChanged(
        address indexed delegate,
        uint256 previousBalance,
        uint256 newBalance
    );

    /**
     * Emitted when an account starts delegating vote power or switches its delegation
     * to another address.
     *
     * The event is always emitted from a `GovernanceVotePower` contract.
     * @param delegator Account delegating its vote power.
     * @param fromDelegate Account receiving the delegation before the change.
     * Can be address(0) if there was no previous delegation.
     * @param toDelegate Account receiving the delegation after the change.
     * Can be address(0) if `delegator` just undelegated all its vote power.
     */
    event DelegateChanged(
        address indexed delegator,
        address indexed fromDelegate,
        address indexed toDelegate
    );

    /**
     * Update governance vote power of all involved delegates after tokens are transferred.
     *
     * This function **MUST** be called after each governance token transfer for the
     * delegates to reflect the correct balance.
     * @param _from Source address of the transfer.
     * @param _to Destination address of the transfer.
     * @param _fromBalance _Ignored._
     * @param _toBalance _Ignored._
     * @param _amount Amount being transferred.
     */
    function updateAtTokenTransfer(
        address _from,
        address _to,
        uint256 _fromBalance,
        uint256 _toBalance,
        uint256 _amount
    ) external;

    /**
     * Set the cleanup block number.
     * Historic data for the blocks before `cleanupBlockNumber` can be erased.
     * History before that block should never be used since it can be inconsistent.
     * In particular, cleanup block number must be lower than the current vote power block.
     * @param _blockNumber The new cleanup block number.
     */
    function setCleanupBlockNumber(uint256 _blockNumber) external;

    /**
     * Set the contract that is allowed to call history cleaning methods.
     * @param _cleanerContract Address of the cleanup contract.
     * Usually this will be an instance of `CleanupBlockNumberManager`.
     */
    function setCleanerContract(address _cleanerContract) external;

    /**
     * Get the token that this governance vote power contract belongs to.
     * @return The IVPToken interface owning this contract.
     */
    function ownerToken() external view returns (IVPToken);

    /**
     * Get the stake mirror contract that this governance vote power contract belongs to.
     * @return The IPChainStakeMirror interface owning this contract.
     */
    function pChainStakeMirror() external view returns (IPChainStakeMirror);

    /**
     * Get the current cleanup block number set with `setCleanupBlockNumber()`.
     * @return The currently set cleanup block number.
     */
    function getCleanupBlockNumber() external view returns(uint256);
}
