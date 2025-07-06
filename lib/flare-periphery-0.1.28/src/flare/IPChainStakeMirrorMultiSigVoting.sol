// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;
pragma abicoder v2;

/**
 * Interface for the `PChainStakeMirrorMultiSigVoting` contract.
 */
interface IPChainStakeMirrorMultiSigVoting {

    /**
     * Structure describing votes.
     */
    struct PChainVotes {
        bytes32 merkleRoot;
        address[] votes;
    }

    /**
     * Event emitted when voting for specific epoch is reset.
     * @param epochId Epoch id.
     */
    event PChainStakeMirrorVotingReset(uint256 epochId);

    /**
     * Event emitted when voting threshold is updated.
     * @param votingThreshold New voting threshold.
     */
    event PChainStakeMirrorVotingThresholdSet(uint256 votingThreshold);

    /**
     * Event emitted when voters are set.
     * @param voters List of new voters.
     */
    event PChainStakeMirrorVotersSet(address[] voters);

    /**
     * Event emitted when voting for specific epoch is finalized.
     * @param epochId Epoch id.
     * @param merkleRoot Voted Merkle root for that epoch id.
     */
    event PChainStakeMirrorVotingFinalized(uint256 indexed epochId, bytes32 merkleRoot);

    /**
     * Event emitted when vote for specific epoch is submitted.
     * @param epochId Epoch id.
     * @param voter Voter address.
     * @param merkleRoot Merkle root voter voted for in given epoch.
     */
    event PChainStakeMirrorVoteSubmitted(uint256 epochId, address voter, bytes32 merkleRoot);

    /**
     * Event emitted when validator uptime vote for specific reward epoch is submitted.
     * @param rewardEpochId Reward epoch id.
     * @param timestamp Timestamp of the block when the vote happened, in seconds from UNIX epoch.
     * @param voter Voter address.
     * @param nodeIds List of node ids with high enough uptime.
     */
    event PChainStakeMirrorValidatorUptimeVoteSubmitted(
        uint256 indexed rewardEpochId,
        uint256 indexed timestamp,
        address voter,
        bytes20[] nodeIds
    );

    /**
     * Method for submitting Merkle roots for given epoch.
     * @param _epochId Epoch id voter is submitting vote for.
     * @param _merkleRoot Merkle root for given epoch.
     * **NOTE**: It reverts in case voter is not eligible to vote, epoch has not ended yet or is already finalized
     *          or voter is submitting vote for the second time for the same Merkle root
                (voter can submit a vote for a different Merkle root even if voted already).
     */
    function submitVote(uint256 _epochId, bytes32 _merkleRoot) external;

    /**
     * Method for submitting node ids of those validators that have high enough uptime in given reward epoch.
     * @param _rewardEpochId Reward epoch id voter is submitting vote for.
     * @param _nodeIds List of validators (node ids) with high enough uptime in given reward epoch.
     * **NOTE**: Reward epochs are aligned with FTSO reward epochs.
     */
    function submitValidatorUptimeVote(uint256 _rewardEpochId, bytes20[] calldata _nodeIds) external;

    /**
     * Returns epochs configuration data.
     * @return _firstEpochStartTs First epoch start timestamp
     * @return _epochDurationSeconds Epoch duration in seconds
     */
    function getEpochConfiguration() external view
        returns (
            uint256 _firstEpochStartTs,
            uint256 _epochDurationSeconds
        );

    /**
     * Returns id of the epoch at the specified timestamp.
     * @param _timestamp Timestamp as seconds from unix epoch
     */
    function getEpochId(uint256 _timestamp) external view returns (uint256);

    /**
     * Returns Merkle root for the given `_epochId`.
     * @param _epochId Epoch id of the interest.
     * @return Merkle root for finalized epoch id and `bytes32(0)` otherwise.
     */
    function getMerkleRoot(uint256 _epochId) external view returns(bytes32);

     /**
     * Returns all votes for the given `_epochId` util epoch is finalized. Reverts later.
     * @param _epochId Epoch id of the interest.
     * @return Votes for for the given `_epochId`.
     */
    function getVotes(uint256 _epochId) external view returns(PChainVotes[] memory);

    /**
     * Checks if `_voter` should vote for the given `_epochId`.
     * @param _epochId Epoch id of the interest.
     * @param _voter Address of the voter.
     * @return False if voter is not eligible to vote, epoch already finalized or voter already voted. True otherwise.
     * **NOTE**: The method will return true even if epoch has not ended yet - `submitVote` will revert in that case.
     */
    function shouldVote(uint256 _epochId, address _voter) external view returns(bool);

    /**
     * Returns the list of all voters.
     * @return List of all voters.
     */
    function getVoters() external view returns(address[] memory);

     /**
     * Returns the voting threshold.
     * @return Voting threshold.
     */
    function getVotingThreshold() external view returns(uint256);

    /**
     * Returns current epoch id.
     * @return Current epoch id.
     */
    function getCurrentEpochId() external view returns (uint256);
}
