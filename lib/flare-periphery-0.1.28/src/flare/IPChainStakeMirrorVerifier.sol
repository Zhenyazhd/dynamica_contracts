// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;
pragma abicoder v2;

/**
 * Interface with structure for P-chain stake mirror verifications.
 */
interface IPChainStakeMirrorVerifier {

    /**
     * Structure describing the P-chain stake.
     */
    struct PChainStake {
        // Hash of the transaction on the underlying chain.
        bytes32 txId;
        // Type of the staking/delegation transaction: '0' for 'ADD_VALIDATOR_TX' and '1' for 'ADD_DELEGATOR_TX'.
        uint8 stakingType;
        // Input address that triggered the staking or delegation transaction.
        // See https://support.avax.network/en/articles/4596397-what-is-an-address for address definition for P-chain.
        bytes20 inputAddress;
        // NodeID to which staking or delegation is done.
        // For definitions, see https://github.com/ava-labs/avalanchego/blob/master/ids/node_id.go.
        bytes20 nodeId;
        // Start time of the staking/delegation in seconds (Unix epoch).
        uint64 startTime;
        // End time of the staking/delegation in seconds (Unix epoch).
        uint64 endTime;
        // Staked or delegated amount in Gwei (nano FLR).
        uint64 weight;
    }
}
