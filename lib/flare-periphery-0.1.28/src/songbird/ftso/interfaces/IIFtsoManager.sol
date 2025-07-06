// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;
pragma abicoder v2;

import "../../ftso/interfaces/IIFtso.sol";
import "../../IFtsoManager.sol";
import "../../genesis/interfaces/IFlareDaemonize.sol";
import "../../token/interfaces/IIVPToken.sol";


interface IIFtsoManager is IFtsoManager, IFlareDaemonize {

    struct RewardEpochData {
        uint256 votepowerBlock;
        uint256 startBlock;
        uint256 startTimestamp;
    }

    event ClosingExpiredRewardEpochFailed(uint256 rewardEpoch);
    event CleanupBlockNumberManagerFailedForBlock(uint256 blockNumber);
    event UpdatingActiveValidatorsTriggerFailed(uint256 rewardEpoch);
    event FtsoDeactivationFailed(IIFtso ftso);
    event ChillingNonrevealingDataProvidersFailed();

    function activate() external;

    function setInitialRewardData(
        uint256 _nextRewardEpochToExpire,
        uint256 _rewardEpochsLength,
        uint256 _currentRewardEpochEnds
    ) external;

    function setGovernanceParameters(
        uint256 _updateTs,
        uint256 _maxVotePowerNatThresholdFraction,
        uint256 _maxVotePowerAssetThresholdFraction,
        uint256 _lowAssetUSDThreshold,
        uint256 _highAssetUSDThreshold,
        uint256 _highAssetTurnoutThresholdBIPS,
        uint256 _lowNatTurnoutThresholdBIPS,
        uint256 _elasticBandRewardBIPS,
        uint256 _rewardExpiryOffsetSeconds,
        address[] memory _trustedAddresses
    ) external;
    

    function addFtso(IIFtso _ftso) external;

    function addFtsosBulk(IIFtso[] memory _ftsos) external;

    function removeFtso(IIFtso _ftso) external;

    function replaceFtso(
        IIFtso _ftsoToAdd,
        bool copyCurrentPrice,
        bool copyAssetOrAssetFtsos
    ) external;

    function replaceFtsosBulk(
        IIFtso[] memory _ftsosToAdd,
        bool copyCurrentPrice,
        bool copyAssetOrAssetFtsos
    ) external;

    function setFtsoAsset(IIFtso _ftso, IIVPToken _asset) external;

    function setFtsoAssetFtsos(IIFtso _ftso, IIFtso[] memory _assetFtsos) external;

    function setFallbackMode(bool _fallbackMode) external;

    function setFtsoFallbackMode(IIFtso _ftso, bool _fallbackMode) external;

    function notInitializedFtsos(IIFtso) external view returns (bool);

    function getRewardEpochData(uint256 _rewardEpochId) external view returns (RewardEpochData memory);

    function currentRewardEpochEnds() external view returns (uint256);

    function getLastUnprocessedPriceEpochData() external view
        returns(
            uint256 _lastUnprocessedPriceEpoch,
            uint256 _lastUnprocessedPriceEpochRevealEnds,
            bool _lastUnprocessedPriceEpochInitialized
        );

    function rewardEpochsStartTs() external view returns(uint256);

    function rewardEpochDurationSeconds() external view returns(uint256);

    function rewardEpochs(uint256 _rewardEpochId) external view 
        returns (
            uint256 _votepowerBlock,
            uint256 _startBlock,
            uint256 _startTimestamp
        );

    function getRewardExpiryOffsetSeconds() external view returns (uint256);

    /**
     * @notice Returns elastic band width in PPM (parts-per-million) for given ftso
     */
    function getElasticBandWidthPPMFtso(IIFtso _ftso) external view returns (uint256);
}
