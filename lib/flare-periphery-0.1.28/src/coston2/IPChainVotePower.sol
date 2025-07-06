// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

/**
 * Interface for the vote power part of the `PChainStakeMirror` contract.
 */
interface IPChainVotePower {

    /**
     * Event triggered when a stake is confirmed or at the time it ends.
     * Definition: `votePowerFromTo(owner, nodeId)` is `changed` from `priorVotePower` to `newVotePower`.
     * @param owner The account that has changed the amount of vote power it is staking.
     * @param nodeId The node id whose received vote power has changed.
     * @param priorVotePower The vote power originally on that node id.
     * @param newVotePower The new vote power that triggered this event.
     */
    event VotePowerChanged(
        address indexed owner,
        bytes20 indexed nodeId,
        uint256 priorVotePower,
        uint256 newVotePower
    );

    /**
     * Emitted when a vote power cache entry is created.
     * Allows history cleaners to track vote power cache cleanup opportunities off-chain.
     * @param nodeId The node id whose vote power has just been cached.
     * @param blockNumber The block number at which the vote power has been cached.
     */
    event VotePowerCacheCreated(bytes20 nodeId, uint256 blockNumber);

    /**
    * Get the vote power of `_owner` at block `_blockNumber` using cache.
    *   It tries to read the cached value and if not found, reads the actual value and stores it in cache.
    *   Can only be used if _blockNumber is in the past, otherwise reverts.
    * @param _owner The node id to get voting power.
    * @param _blockNumber The block number at which to fetch.
    * @return Vote power of `_owner` at `_blockNumber`.
    */
    function votePowerOfAtCached(bytes20 _owner, uint256 _blockNumber) external returns(uint256);

    /**
    * Get the total vote power at block `_blockNumber` using cache.
    *   It tries to read the cached value and if not found, reads the actual value and stores it in cache.
    *   Can only be used if `_blockNumber` is in the past, otherwise reverts.
    * @param _blockNumber The block number at which to fetch.
    * @return The total vote power at the block (sum of all accounts' vote powers).
    */
    function totalVotePowerAtCached(uint256 _blockNumber) external returns(uint256);

    /**
     * Get the current total vote power.
     * @return The current total vote power (sum of all accounts' vote powers).
     */
    function totalVotePower() external view returns(uint256);

    /**
    * Get the total vote power at block `_blockNumber`
    * @param _blockNumber The block number at which to fetch.
    * @return The total vote power at the block  (sum of all accounts' vote powers).
    */
    function totalVotePowerAt(uint _blockNumber) external view returns(uint256);

    /**
     * Get the amounts and node ids being staked to by a vote power owner.
     * @param _owner The address being queried.
     * @return _nodeIds Array of node ids.
     * @return _amounts Array of staked amounts, for each node id.
     */
    function stakesOf(address _owner)
        external view
        returns (
            bytes20[] memory _nodeIds,
            uint256[] memory _amounts
        );

    /**
     * Get the amounts and node ids being staked to by a vote power owner,
     * at a given block.
     * @param _owner The address being queried.
     * @param _blockNumber The block number being queried.
     * @return _nodeIds Array of node ids.
     * @return _amounts Array of staked amounts, for each node id.
     */
    function stakesOfAt(
        address _owner,
        uint256 _blockNumber
    )
        external view
        returns (
            bytes20[] memory _nodeIds,
            uint256[] memory _amounts
        );

    /**
     * Get the current vote power of `_nodeId`.
     * @param _nodeId The node id to get voting power.
     * @return Current vote power of `_nodeId`.
     */
    function votePowerOf(bytes20 _nodeId) external view returns(uint256);

    /**
    * Get the vote power of `_nodeId` at block `_blockNumber`
    * @param _nodeId The node id to get voting power.
    * @param _blockNumber The block number at which to fetch.
    * @return Vote power of `_nodeId` at `_blockNumber`.
    */
    function votePowerOfAt(bytes20 _nodeId, uint256 _blockNumber) external view returns(uint256);

    /**
    * Get current staked vote power from `_owner` staked to `_nodeId`.
    * @param _owner Address of vote power owner.
    * @param _nodeId Node id.
    * @return The staked vote power.
    */
    function votePowerFromTo(address _owner, bytes20 _nodeId) external view returns(uint256);

    /**
    * Get current staked vote power from `_owner` staked to `_nodeId` at `_blockNumber`.
    * @param _owner Address of vote power owner.
    * @param _nodeId Node id.
    * @param _blockNumber The block number at which to fetch.
    * @return The staked vote power.
    */
    function votePowerFromToAt(address _owner, bytes20 _nodeId, uint _blockNumber) external view returns(uint256);

    /**
     * Return vote powers for several node ids in a batch.
     * @param _nodeIds The list of node ids to fetch vote power of.
     * @param _blockNumber The block number at which to fetch.
     * @return A list of vote powers.
     */
    function batchVotePowerOfAt(
        bytes20[] memory _nodeIds,
        uint256 _blockNumber
    ) external view returns(uint256[] memory);
}
