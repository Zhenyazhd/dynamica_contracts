// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Dynamica} from "./Dynamica.sol";
import {IDynamica} from "../../src/interfaces/IDynamica.sol";
import {LMSRMath} from "../../src/LMSRMath.sol";
import {MockToken, IERC20Mock} from "../MockToken.sol";
import {BeaconProxy} from "@openzeppelin-contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC1155HolderUpgradeable} from
    "@openzeppelin-contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";

contract DynamicaTimeEchidna is Dynamica {

    UpgradeableBeacon public BEACON;
    Dynamica public dynamica_implementation;
    MockToken public collateral;
    Dynamica public dynamica;


    uint256 public initFunding;

    /// @notice Error event: when currentEpochNumber becomes 2
    event ErrorEpochNumberIs2(uint32 currentEpoch, uint256 timestamp, string context);
    
    /// @notice Error event: when currentPeriodNumber becomes 2
    event ErrorPeriodNumberIs2(uint32 currentPeriod, uint256 timestamp, string context);

    event ErrorFundingNotExceedBalance(uint256 balance, uint256 totalPayoutForRollover, uint256 totalPayout, uint256 feeReceived);
    event ErrorTrade(bytes reason);

    event GoodTrade();

    event TransferSuccess();

    event ErrorDelegatecall(bytes reason);

    event ErrorFundingNotCoversTotalPayout( uint256 funding, uint256 totalPayout);

    constructor() {
        transferOwnership(OWNER);

        lmsrMath = new LMSRMath();
        collateral = new MockToken(18);
        initFunding = 1_000 * 1e18;
        
        IDynamica.Config memory cfg = IDynamica.Config({
            owner: OWNER,
            collateralToken: address(collateral),
            oracle: address(this),
            question: "Echidna time test",
            outcomeSlotCount: 2,
            startFunding: initFunding,
            outcomeTokenAmounts: 500 * 1e10,
            fee: 100,
            alpha: 3,
            expLimit: 12_750,
            decimals: 10,
            expirationEpoch: 0,
            gamma: 9_000,
            epochDuration: 3 days,
            periodDuration: 1 days
        });
        initialize(cfg, address(lmsrMath));
        collateral.mint(address(this), initFunding);
        collateral.mint(OWNER, 1_000_000 * 1e18);
        collateral.mint(USER1, 1_000_000 * 1e18);
        collateral.mint(USER2, 1_000_000 * 1e18);
        collateral.forceApprove(OWNER, address(this ), type(uint256).max);
        collateral.forceApprove(USER1, address(this ), type(uint256).max);
        collateral.forceApprove(USER2, address(this ), type(uint256).max);
    }

    // ============ Invariants ============

    function echidna_epoch_monotonic() public view returns (bool) {
        return currentEpochNumber == lastEpoch + 1 || currentEpochNumber == lastEpoch;    
    }


    function echidna_epoch_period_consistent() public view returns (bool) {
        uint32 e = epochDuration;
        uint32 p = periodDuration;
        if (p == 0) return false;
        return e > 0 && e % p == 0;
    }

    function echidna_funding_covers_total_payout() public returns (bool) {
        if(currentEpochNumber > 1){
            IDynamica.EpochData memory epochData_ = getEpochData(currentEpochNumber);
            uint256 funding = epochData_.funding;
            if(epochData_.funding < initFunding){
                uint256 totalPayout = epochData_.totalPayout;
                funding = epochData_.funding + epochData_.fundingForRollover;
                if(funding < totalPayout){
                    emit ErrorFundingNotCoversTotalPayout(funding, totalPayout);
                    return false;
                }
                return true;
            }
        }
        return true;
    }

    function echidna_funding_non_negative() public view returns (bool) {      
        IDynamica.EpochData memory epochData_ = getEpochData(currentEpochNumber);
        uint256 funding = epochData_.funding;
        return funding >= initFunding;
        
    }

    function echidna_blocked_total_supply() public view returns (bool) {
        uint256 periods = epochDuration / periodDuration;
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            for (uint256 p = 1; p <= periods; p++) {
                uint256 id = shareId(currentEpochNumber, p, i);
                if (blockedForEpoch[id] > totalSupply(id)) return false;
            }
        }
        return true;
    }

    function echidna_outcome_supplies_match() public view returns (bool) {
        uint256 periodsPerEpoch = epochDuration / periodDuration;

        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            uint256 sum = 0;
            for (uint256 p = 1; p <= periodsPerEpoch; p++) {
                sum += totalSupply(shareId(currentEpochNumber, p, i));
            }

            if (sum != outcomeTokenSuppliesPerEpoch(currentEpochNumber, i)) {
                return false;
            }
        }
        return true;
    }

    function echidna_blocked_user_leq_blocked_epoch() public view returns (bool) {
        uint256 periodsPerEpoch = epochDuration / periodDuration;

        address[2] memory users = [USER1, USER2];

        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            for (uint256 p = 1; p <= periodsPerEpoch; p++) {
                uint256 id = shareId(currentEpochNumber, p, i);

                uint256 sumUserBlocked;
                for (uint256 u = 0; u < users.length; u++) {
                    uint256 bu = blockedForUser[users[u]][id];
                    if (bu > totalSupply(id)) return false;
                    sumUserBlocked += bu;
                }

                if (sumUserBlocked > blockedForEpoch[id]) return false;
            }
        }
        return true;
    }

    function echidna_blocked_leq_totalSupply() public view returns (bool) {
        uint256 periodsPerEpoch = epochDuration / periodDuration;

        for(uint256 i = 0; i < outcomeSlotCount; i++){
            for(uint256 p = 1; p <= periodsPerEpoch; p++){
                uint256 id = shareId(currentEpochNumber, p, i);
                if(blockedForEpoch[id] > totalSupply(id)) return false;
            }
        }
         
        return true;
    }


    function echidna_blocked_for_user_consistent() public view returns (bool) {

        address[2] memory users = [USER1, USER2];
        uint256 periodsPerEpoch = epochDuration / periodDuration;
        
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            for (uint256 o = 0; o < outcomeSlotCount; o++) {    
                for (uint256 p = 1; p <= periodsPerEpoch; p++) {
                    uint256 id = shareId(currentEpochNumber, p, o);
                    if(blockedForUser[user][id] > blockedForEpoch[id] || blockedForEpoch[id] > balanceOf(address(this), id)) return false;
                }
            }
        }
        return true;
    }


    function echidna_funding_not_exceed_balance() public returns (bool) {
        uint32 epoch = currentEpochNumber - 1;
        if(redeemForEpoch[epoch] || epoch == 0 || epoch > currentEpochNumber) return true;
        emit ErrorFundingNotExceedBalance(collateral.balanceOf(address(this)), epochData[epoch].fundingForRollover,epochData[epoch].totalPayout, feeReceived);
        return collateral.balanceOf(address(this)) >= epochData[epoch].totalPayout + epochData[epoch].fundingForRollover + feeReceived;
    }
}
