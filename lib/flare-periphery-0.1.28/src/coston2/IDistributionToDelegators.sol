// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;
pragma abicoder v2;

interface IDistributionToDelegators {
    // Events
    event UseGoodRandomSet(bool useGoodRandom, uint256 maxWaitForGoodRandomSeconds);
    event EntitlementStart(uint256 entitlementStartTs);
    event AccountClaimed(address indexed whoClaimed, address indexed sentTo, uint256 month, uint256 amountWei);
    event AccountOptOut(address indexed theAccount, bool confirmed);


    // Methods
    /**
     * @notice Allows the sender to claim or wrap rewards for reward owner.
     * @notice The caller does not have to be the owner, but must be approved by the owner to claim on his behalf,
     *   this approval is done by calling `setClaimExecutors`.
     * @notice It is actually safe for this to be called by anybody (nothing can be stolen), but by limiting who can
     *   call, we allow the owner to control the timing of the calls.
     * @notice Reward owner can claim to any `_recipient`, while the executor can only claim to the reward owner,
     *   reward owners's personal delegation account or one of the addresses set by `setAllowedClaimRecipients`.
     * @param _rewardOwner          address of the reward owner
     * @param _recipient            address to transfer funds to
     * @param _month                last month to claim for
     * @param _wrap                 should reward be wrapped immediately
     * @return _rewardAmount        amount of total claimed rewards
     */
    function claim(address _rewardOwner, address _recipient, uint256 _month, bool _wrap)
        external returns(uint256 _rewardAmount);

    /**
     * @notice Allows batch claiming for the list of '_rewardOwners' up to given '_month'.
     * @notice If reward owner has enabled delegation account, rewards are also claimed for that delegation account and
     *   total claimed amount is sent to that delegation account, otherwise claimed amount is sent to owner's account.
     * @notice Claimed amount is automatically wrapped.
     * @notice Method can be used by reward owner or executor. If executor is registered with fee > 0,
     *   then fee is paid to executor for each claimed address from the list.
     * @param _rewardOwners         list of reward owners to claim for
     * @param _month                last month to claim for
     */
    function autoClaim(address[] calldata _rewardOwners, uint256 _month) external;
    
    /**
     * @notice Method to opt-out of receiving airdrop rewards
     */
    function optOutOfAirdrop() external;
    
    /**
     * @notice Returns the next claimable month for '_rewardOwner'.
     * @param _rewardOwner          address of the reward owner
     */
    function nextClaimableMonth(address _rewardOwner) external view returns (uint256);

    /**
     * @notice get claimable amount of wei for requesting account for specified month
     * @param _month month of interest
     * @return _amountWei amount of wei available for this account and provided month
     */
    function getClaimableAmount(uint256 _month) external view returns(uint256 _amountWei);

    /**
     * @notice get claimable amount of wei for account for specified month
     * @param _account the address of an account we want to get the claimable amount of wei
     * @param _month month of interest
     * @return _amountWei amount of wei available for provided account and month
     */
    function getClaimableAmountOf(address _account, uint256 _month) external view returns(uint256 _amountWei);

    /**
     * @notice Returns the current month
     * @return _currentMonth Current month, 0 before entitlementStartTs
     */
    function getCurrentMonth() external view returns (uint256 _currentMonth);

    /**
     * @notice Returns the month that will expire next
     * @return _monthToExpireNext Month that will expire next, 1100 when last month expired
     */
    function getMonthToExpireNext() external view returns (uint256 _monthToExpireNext);

    /**
     * @notice Returns claimable months - reverts if none
     * @return _startMonth first claimable month
     * @return _endMonth last claimable month
     */
    function getClaimableMonths() external view returns(uint256 _startMonth, uint256 _endMonth);
}
