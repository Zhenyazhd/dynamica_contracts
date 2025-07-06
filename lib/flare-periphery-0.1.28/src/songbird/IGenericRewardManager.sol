// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

interface IGenericRewardManager {

    event RewardClaimed(
        address indexed beneficiary,
        address indexed sentTo,
        uint256 amount
    );

    event RewardsDistributed(
        address[] addresses,
        uint256[] rewards
    );

    event ClaimExecutorsChanged(
        address rewardOwner,
        address[] executors
    );

    event AllowedClaimRecipientsChanged(
        address rewardOwner,
        address[] recipients
    );

    event RewardManagerActivated(address rewardManager);
    event RewardManagerDeactivated(address rewardManager);


    /**
     * @notice Allows the sender to claim or wrap rewards for reward owner.
     * @notice The caller does not have to be the owner, but must be approved by the owner to claim on his behalf.
     *   this approval is done by calling `setClaimExecutors`.
     * @notice It is actually safe for this to be called by anybody (nothing can be stolen), but by limiting who can
     *   call, we allow the owner to control the timing of the calls.
     * @notice Reward owner can claim to any `_recipient`, while the executor can only claim to the reward owner or
     *   one of the addresses set by `setAllowedClaimRecipients`.
     * @param _rewardOwner          address of the reward owner
     * @param _recipient            address to transfer funds to
     * @param _rewardAmount         amount of rewards to claim
     * @param _wrap                 should reward be wrapped immediately
     */
    function claim(address _rewardOwner, address payable _recipient, uint256 _rewardAmount, bool _wrap) external;

    /**
     * Set the addresses of executors, who are allowed to call `claim`.
     * @param _executors The new executors. All old executors will be deleted and replaced by these.
     */    
    function setClaimExecutors(address[] memory _executors) external;

    /**
     * Set the addresses of allowed recipients in the methods `claim`.
     * Apart from these, the reward owner is always an allowed recipient.
     * @param _recipients The new allowed recipients. All old recipients will be deleted and replaced by these.
     */    
    function setAllowedClaimRecipients(address[] memory _recipients) external;

    /**
     * @notice Allows reward claiming
     */
    function active() external view returns (bool);

    /**
     * @notice Returns information of beneficiary rewards
     * @param _beneficiary          beneficiary address
     * @return _totalReward         number representing the total reward
     * @return _claimedReward       number representing the amount of total reward that has been claimed
     */
    function getStateOfRewards(
        address _beneficiary
    )
        external view 
        returns (
            uint256 _totalReward,
            uint256 _claimedReward
        );

    /**
     * Get the addresses of executors, who are allowed to call `claim`.
     */    
    function claimExecutors(address _rewardOwner) external view returns (address[] memory);
    
    /**
     * Get the addresses of allowed recipients in the methods `claim`.
     * Apart from these, the reward owner is always an allowed recipient.
     */    
    function allowedClaimRecipients(address _rewardOwner) external view returns (address[] memory);
}
