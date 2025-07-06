// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;


// interface for the first version of ftso manger (V1 = oldest version) - last version is always without any Vx
interface IIFtsoManagerV1 {
    function rewardEpochsStartTs() external view returns(uint256);
    function rewardEpochDurationSeconds() external view returns(uint256);

    function getCurrentRewardEpoch() external view returns(uint256);
    
    function rewardEpochs(uint256 _rewardEpochId) external view returns (
        uint256 _votepowerBlock,
        uint256 _startBlock,
        uint256 _startTimestamp
    );

    function getPriceEpochConfiguration() external view 
        returns (
            uint256 _firstPriceEpochStartTs,
            uint256 _priceEpochDurationSeconds,
            uint256 _revealEpochDurationSeconds
        );
}
