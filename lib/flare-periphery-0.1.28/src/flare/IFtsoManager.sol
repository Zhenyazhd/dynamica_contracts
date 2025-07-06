// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

import "./ftso/interfaces/IIFtso.sol";
import "./genesis/interfaces/IFtsoManagerGenesis.sol";

interface IFtsoManager is IFtsoManagerGenesis {

    event FtsoAdded(IIFtso ftso, bool add);
    event FallbackMode(bool fallbackMode);
    event FtsoFallbackMode(IIFtso ftso, bool fallbackMode);
    event RewardEpochFinalized(uint256 votepowerBlock, uint256 startBlock);
    event PriceEpochFinalized(address chosenFtso, uint256 rewardEpochId);
    event InitializingCurrentEpochStateForRevealFailed(IIFtso ftso, uint256 epochId);
    event FinalizingPriceEpochFailed(IIFtso ftso, uint256 epochId, IFtso.PriceFinalizationType failingType);
    event DistributingRewardsFailed(address ftso, uint256 epochId);
    event AccruingUnearnedRewardsFailed(uint256 epochId);
    event UseGoodRandomSet(bool useGoodRandom, uint256 maxWaitForGoodRandomSeconds);

    function active() external view returns (bool);

    function getCurrentRewardEpoch() external view returns (uint256);

    function getRewardEpochVotePowerBlock(uint256 _rewardEpoch) external view returns (uint256);

    function getRewardEpochToExpireNext() external view returns (uint256);
    
    function getCurrentPriceEpochData() external view 
        returns (
            uint256 _priceEpochId,
            uint256 _priceEpochStartTimestamp,
            uint256 _priceEpochEndTimestamp,
            uint256 _priceEpochRevealEndTimestamp,
            uint256 _currentTimestamp
        );

    function getFtsos() external view returns (IIFtso[] memory _ftsos);

    function getPriceEpochConfiguration() external view 
        returns (
            uint256 _firstPriceEpochStartTs,
            uint256 _priceEpochDurationSeconds,
            uint256 _revealEpochDurationSeconds
        );

    function getRewardEpochConfiguration() external view 
        returns (
            uint256 _firstRewardEpochStartTs,
            uint256 _rewardEpochDurationSeconds
        );

    function getFallbackMode() external view 
        returns (
            bool _fallbackMode,
            IIFtso[] memory _ftsos,
            bool[] memory _ftsoInFallbackMode
        );
}
