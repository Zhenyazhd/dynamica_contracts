// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

import "../../IFtsoRewardManager.sol";
import "../interfaces/IITokenPool.sol";
import "../../inflation/interfaces/IIInflationReceiverV1.sol";

interface IIFtsoRewardManager is IFtsoRewardManager, IIInflationReceiverV1, IITokenPool {

    event DailyAuthorizedInflationSet(uint256 authorizedAmountWei);
    event InflationReceived(uint256 amountReceivedWei);
    event RewardsBurned(uint256 amountBurnedWei);

    function activate() external;
    function enableClaims() external;
    function deactivate() external;
    function closeExpiredRewardEpoch(uint256 _rewardEpochId) external;

    function distributeRewards(
        address[] memory addresses,
        uint256[] memory weights,
        uint256 totalWeight,
        uint256 epochId,
        address ftso,
        uint256 priceEpochDurationSeconds,
        uint256 currentRewardEpoch,
        uint256 priceEpochEndTime,
        uint256 votePowerBlock
    ) external;

    function accrueUnearnedRewards(
        uint256 epochId,
        uint256 priceEpochDurationSeconds,
        uint256 priceEpochEndTime
    ) external;

    function firstClaimableRewardEpoch() external view returns (uint256);

    /**
     * @notice Returns the information on unclaimed reward of `_dataProvider` for `_rewardEpoch`
     * @param _rewardEpoch          reward epoch number
     * @param _dataProvider         address representing the data provider
     * @return _amount              number representing the unclaimed amount
     * @return _weight              number representing the share that has not yet been claimed
     */
    function getUnclaimedReward(
        uint256 _rewardEpoch,
        address _dataProvider
    )
        external view
        returns (
            uint256 _amount,
            uint256 _weight
        );
}
