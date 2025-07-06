// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;
pragma abicoder v2;

import "./IIInflationReceiver.sol";


// interface for the first version of inflation (V1 = oldest version) - last version is always without any Vx
interface IIInflationV1 {

    struct RewardServiceState {
        IIInflationReceiver inflationReceiver;          // The target rewarding contract
        uint256 authorizedInflationWei;                 // Total authorized inflation for this reward service
        uint256 lastDailyAuthorizedInflationWei;        // Last daily authorized inflation amount
        uint256 inflationTopupRequestedWei;             // Total inflation topup requested to be minted
        uint256 inflationTopupReceivedWei;              // Total inflation minting received
        uint256 inflationTopupWithdrawnWei;             // Total inflation minting sent to rewarding service contract
    }

    struct RewardServicesState {
        // Collection of annums
        RewardServiceState[] rewardServices;
        // Balances
        uint256 totalAuthorizedInflationWei;
        uint256 totalInflationTopupRequestedWei;
        uint256 totalInflationTopupReceivedWei;
        uint256 totalInflationTopupWithdrawnWei;
    }

    struct InflationAnnumState {
        uint256 recognizedInflationWei;
        uint16 daysInAnnum;
        uint256 startTimeStamp;
        uint256 endTimeStamp;
        RewardServicesState rewardServices;
    }


    function lastAuthorizationTs() external returns(uint256);
    function rewardEpochStartedTs() external returns(uint256);
    function getAnnum(uint256 _index) external view returns(InflationAnnumState memory);

}
