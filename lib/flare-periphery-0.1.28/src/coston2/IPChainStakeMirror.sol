// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;
pragma abicoder v2;

import "./IPChainVotePower.sol";
import "./IPChainStakeMirrorVerifier.sol";


/**
 * Interface for the `PChainStakeMirror` contract.
 */
interface IPChainStakeMirror is IPChainVotePower {

    /**
     * Event emitted when max updates per block is set.
     * @param maxUpdatesPerBlock new number of max updated per block
     */
    event MaxUpdatesPerBlockSet(uint256 maxUpdatesPerBlock);

    /**
     * Event emitted when the stake is confirmed.
     * @param owner The address who opened the stake.
     * @param nodeId Node id to which the stake was added.
     * @param txHash Unique tx hash - keccak256(abi.encode(PChainStake.txId, PChainStake.inputAddress));
     * @param amountWei Stake amount (in wei).
     * @param pChainTxId P-chain transaction id.
     */
    event StakeConfirmed(
        address indexed owner,
        bytes20 indexed nodeId,
        bytes32 indexed txHash,
        uint256 amountWei,
        bytes32 pChainTxId
    );

    /**
     * Event emitted when the stake has ended.
     * @param owner The address whose stake has ended.
     * @param nodeId Node id from which the stake was removed.
     * @param txHash Unique tx hash - keccak256(abi.encode(PChainStake.txId, PChainStake.inputAddress));
     * @param amountWei Stake amount (in wei).
     */
    event StakeEnded(
        address indexed owner,
        bytes20 indexed nodeId,
        bytes32 indexed txHash,
        uint256 amountWei
    );

    /**
     * Event emitted when the stake was revoked.
     * @param owner The address whose stake has ended.
     * @param nodeId Node id from which the stake was removed.
     * @param txHash Unique tx hash - keccak256(abi.encode(PChainStake.txId, PChainStake.inputAddress));
     * @param amountWei Stake amount (in wei).
     */
    event StakeRevoked(
        address indexed owner,
        bytes20 indexed nodeId,
        bytes32 indexed txHash,
        uint256 amountWei
    );

    /**
     * Method for P-chain stake mirroring using `PChainStake` data and Merkle proof.
     * @param _stakeData Information about P-chain stake.
     * @param _merkleProof Merkle proof that should be used to prove the P-chain stake.
     */
    function mirrorStake(
        IPChainStakeMirrorVerifier.PChainStake calldata _stakeData,
        bytes32[] calldata _merkleProof
    )
        external;

    /**
     * Method for checking if active stake (stake start time <= block.timestamp < stake end time) was already mirrored.
     * @param _txId P-chain stake transaction id.
     * @param _inputAddress P-chain address that opened stake.
     * @return True if stake is active and mirrored.
     */
    function isActiveStakeMirrored(bytes32 _txId, bytes20 _inputAddress) external view returns(bool);

    /**
     * Total amount of tokens at current block.
     * @return The current total amount of tokens.
     **/
    function totalSupply() external view returns (uint256);

    /**
     * Total amount of tokens at a specific `_blockNumber`.
     * @param _blockNumber The block number when the totalSupply is queried.
     * @return The total amount of tokens at `_blockNumber`.
     **/
    function totalSupplyAt(uint _blockNumber) external view returns(uint256);

    /**
     * Queries the token balance of `_owner` at current block.
     * @param _owner The address from which the balance will be retrieved.
     * @return The current balance.
     **/
    function balanceOf(address _owner) external view returns (uint256);

    /**
     * Queries the token balance of `_owner` at a specific `_blockNumber`.
     * @param _owner The address from which the balance will be retrieved.
     * @param _blockNumber The block number when the balance is queried.
     * @return The balance at `_blockNumber`.
     **/
    function balanceOfAt(address _owner, uint _blockNumber) external view returns (uint256);
}
