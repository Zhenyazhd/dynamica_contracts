// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/src/Test.sol";
import {DataLayoutLibrary as DL} from "../src/libraries/DataLayoutLibrary.sol";

/**
 * @title DataTest
 * @dev Test contract for DataLayoutLibrary packing/unpacking functions
 * @notice Tests bit manipulation functions for epoch, period, and config data
 */
contract DataTest is Test {
    // Test contract that uses DataLayoutLibrary
    DataTestContract public dataContract;

    function setUp() public {
        dataContract = new DataTestContract();
    }

    // ============ Getter Tests ============

    function testGetCurrentEpoch() public {
        DL.TimeUpdate memory update = DL.TimeUpdate({
            currentEpoch: 123,
            currentPeriod: 0,
            expirationEpoch: 0,
            epochDuration: 0,
            periodDuration: 0,
            periodStart: 0,
            epochStart: 0
        });
        dataContract.batchUpdateTimeInfo(update, DL.FLAG_UPDATE_CURRENT_EPOCH);
        
        (uint32 currentEpoch,, , , , , ) = dataContract.getTimeInfo();
        assertEq(currentEpoch, 123);
    }

    function testGetCurrentPeriod() public {
        DL.TimeUpdate memory update = DL.TimeUpdate({
            currentEpoch: 0,
            currentPeriod: 456,
            expirationEpoch: 0,
            epochDuration: 0,
            periodDuration: 0,
            periodStart: 0,
            epochStart: 0
        });
        dataContract.batchUpdateTimeInfo(update, DL.FLAG_UPDATE_CURRENT_PERIOD);
        
        (, uint32 currentPeriod, , , , , ) = dataContract.getTimeInfo();
        assertEq(currentPeriod, 456);
    }

    function testGetExpirationEpoch() public {
        DL.TimeUpdate memory update = DL.TimeUpdate({
            currentEpoch: 0,
            currentPeriod: 0,
            expirationEpoch: 789,
            epochDuration: 0,
            periodDuration: 0,
            periodStart: 0,
            epochStart: 0
        });
        dataContract.batchUpdateTimeInfo(update, DL.FLAG_UPDATE_EXPIRATION_EPOCH);
        
        (, , uint32 expirationEpoch, , , , ) = dataContract.getTimeInfo();
        assertEq(expirationEpoch, 789);
    }

    function testGetEpochDuration() public {
        DL.TimeUpdate memory update = DL.TimeUpdate({
            currentEpoch: 0,
            currentPeriod: 0,
            expirationEpoch: 0,
            epochDuration: 1000,
            periodDuration: 0,
            periodStart: 0,
            epochStart: 0
        });
        dataContract.batchUpdateTimeInfo(update, DL.FLAG_UPDATE_EPOCH_DURATION);
        
        (, , , uint32 epochDuration, , , ) = dataContract.getTimeInfo();
        assertEq(epochDuration, 1000);
    }

    function testGetPeriodDuration() public {
        DL.TimeUpdate memory update = DL.TimeUpdate({
            currentEpoch: 0,
            currentPeriod: 0,
            expirationEpoch: 0,
            epochDuration: 0,
            periodDuration: 2000,
            periodStart: 0,
            epochStart: 0
        });
        dataContract.batchUpdateTimeInfo(update, DL.FLAG_UPDATE_PERIOD_DURATION);
        
        (, , , , uint32 periodDuration, , ) = dataContract.getTimeInfo();
        assertEq(periodDuration, 2000);
    }

    function testGetFee() public {
        DL.ConfigUpdate memory update = DL.ConfigUpdate({
            version: 0,
            fee: 12345,
            gamma: 0,
            decimals: 0,
            outcomeSlotCount: 0,
            feeReceived: 0
        });
        dataContract.batchUpdateConfigInfo(update, DL.FLAG_UPDATE_FEE);
        
        (, uint64 fee, , , , ) = dataContract.getConfigInfo();
        assertEq(fee, 12345);
    }

    function testGetGamma() public {
        DL.ConfigUpdate memory update = DL.ConfigUpdate({
            version: 0,
            fee: 0,
            gamma: 9000,
            decimals: 0,
            outcomeSlotCount: 0,
            feeReceived: 0
        });
        dataContract.batchUpdateConfigInfo(update, DL.FLAG_UPDATE_GAMMA);
        
        (, , uint32 gamma, , , ) = dataContract.getConfigInfo();
        assertEq(gamma, 9000);
    }

    function testGetDecimals() public {
        DL.ConfigUpdate memory update = DL.ConfigUpdate({
            version: 0,
            fee: 0,
            gamma: 0,
            decimals: 18,
            outcomeSlotCount: 0,
            feeReceived: 0
        });
        dataContract.batchUpdateConfigInfo(update, DL.FLAG_UPDATE_DECIMALS);
        
        (, , , uint8 decimals, , ) = dataContract.getConfigInfo();
        assertEq(decimals, 18);
    }

    function testGetOutcomeSlotCount() public {
        DL.ConfigUpdate memory update = DL.ConfigUpdate({
            version: 0,
            fee: 0,
            gamma: 0,
            decimals: 0,
            outcomeSlotCount: 5,
            feeReceived: 0
        });
        dataContract.batchUpdateConfigInfo(update, DL.FLAG_UPDATE_OUTCOME_SLOT_COUNT);
        
        (, , , , uint8 outcomeSlotCount, ) = dataContract.getConfigInfo();
        assertEq(outcomeSlotCount, 5);
    }

    // ============ Batch Update Tests ============

    function testSetMultipleTimeValues() public {
        DL.TimeUpdate memory update = DL.TimeUpdate({
            currentEpoch: 1,
            currentPeriod: 2,
            expirationEpoch: 3,
            epochDuration: 4,
            periodDuration: 5,
            periodStart: 0,
            epochStart: 0
        });
        uint8 flags = DL.FLAG_UPDATE_CURRENT_EPOCH 
                    | DL.FLAG_UPDATE_CURRENT_PERIOD 
                    | DL.FLAG_UPDATE_EXPIRATION_EPOCH
                    | DL.FLAG_UPDATE_EPOCH_DURATION
                    | DL.FLAG_UPDATE_PERIOD_DURATION;
        dataContract.batchUpdateTimeInfo(update, flags);
        
        (uint32 currentEpoch, uint32 currentPeriod, uint32 expirationEpoch, uint32 epochDuration, uint32 periodDuration, uint32 periodStart, uint32 epochStart) = dataContract.getTimeInfo();
        assertEq(currentEpoch, 1);
        assertEq(currentPeriod, 2);
        assertEq(expirationEpoch, 3);
        assertEq(epochDuration, 4);
        assertEq(periodDuration, 5);
        assertEq(periodStart, 0);
        assertEq(epochStart, 0);
    }

    function testSetMultipleConfigValues() public {
        DL.ConfigUpdate memory update = DL.ConfigUpdate({
            version: 1,
            fee: 1000,
            gamma: 9000,
            decimals: 18,
            outcomeSlotCount: 5,
            feeReceived: 0
        });
        uint8 flags = DL.FLAG_UPDATE_VERSION 
                    | DL.FLAG_UPDATE_FEE 
                    | DL.FLAG_UPDATE_GAMMA
                    | DL.FLAG_UPDATE_DECIMALS
                    | DL.FLAG_UPDATE_OUTCOME_SLOT_COUNT;
        dataContract.batchUpdateConfigInfo(update, flags);
        
        (uint16 version, uint64 fee, uint32 gamma, uint8 decimals, uint8 outcomeSlotCount, uint128 feeReceived) = dataContract.getConfigInfo();
        assertEq(version, 1);
        assertEq(fee, 1000);
        assertEq(gamma, 9000);
        assertEq(decimals, 18);
        assertEq(outcomeSlotCount, 5);
        assertEq(feeReceived, 0);
    }

    function testUpdateSingleTimeValue() public {
        // Set all values
        DL.TimeUpdate memory update1 = DL.TimeUpdate({
            currentEpoch: 10,
            currentPeriod: 20,
            expirationEpoch: 30,
            epochDuration: 40,
            periodDuration: 50,
            periodStart: 0,
            epochStart: 0
        });
        uint8 flags1 = DL.FLAG_UPDATE_CURRENT_EPOCH 
                     | DL.FLAG_UPDATE_CURRENT_PERIOD 
                     | DL.FLAG_UPDATE_EXPIRATION_EPOCH
                     | DL.FLAG_UPDATE_EPOCH_DURATION
                     | DL.FLAG_UPDATE_PERIOD_DURATION;
        dataContract.batchUpdateTimeInfo(update1, flags1);
        
        // Update only currentEpoch
        DL.TimeUpdate memory update2 = DL.TimeUpdate({
            currentEpoch: 100,
            currentPeriod: 0,
            expirationEpoch: 0,
            epochDuration: 0,
            periodDuration: 0,
            periodStart: 0,
            epochStart: 0
        });
        dataContract.batchUpdateTimeInfo(update2, DL.FLAG_UPDATE_CURRENT_EPOCH);
        
        (uint32 currentEpoch, uint32 currentPeriod, uint32 expirationEpoch, uint32 epochDuration, uint32 periodDuration, , ) = dataContract.getTimeInfo();
        assertEq(currentEpoch, 100);
        assertEq(currentPeriod, 20);
        assertEq(expirationEpoch, 30);
        assertEq(epochDuration, 40);
        assertEq(periodDuration, 50);
    }

    function testUpdateMultipleTimeValues() public {
        // Set initial values
        DL.TimeUpdate memory update1 = DL.TimeUpdate({
            currentEpoch: 1,
            currentPeriod: 2,
            expirationEpoch: 3,
            epochDuration: 0,
            periodDuration: 0,
            periodStart: 0,
            epochStart: 0
        });
        uint8 flags1 = DL.FLAG_UPDATE_CURRENT_EPOCH 
                     | DL.FLAG_UPDATE_CURRENT_PERIOD 
                     | DL.FLAG_UPDATE_EXPIRATION_EPOCH;
        dataContract.batchUpdateTimeInfo(update1, flags1);
        
        // Update some values
        DL.TimeUpdate memory update2 = DL.TimeUpdate({
            currentEpoch: 10,
            currentPeriod: 20,
            expirationEpoch: 0,
            epochDuration: 0,
            periodDuration: 0,
            periodStart: 0,
            epochStart: 0
        });
        uint8 flags2 = DL.FLAG_UPDATE_CURRENT_EPOCH | DL.FLAG_UPDATE_CURRENT_PERIOD;
        dataContract.batchUpdateTimeInfo(update2, flags2);
        
        (uint32 currentEpoch, uint32 currentPeriod, uint32 expirationEpoch, , , , ) = dataContract.getTimeInfo();
        assertEq(currentEpoch, 10);
        assertEq(currentPeriod, 20);
        assertEq(expirationEpoch, 3);
    }

    function testUpdateSingleConfigValue() public {
        // Set all config values
        DL.ConfigUpdate memory update1 = DL.ConfigUpdate({
            version: 1,
            fee: 1000,
            gamma: 9000,
            decimals: 18,
            outcomeSlotCount: 5,
            feeReceived: 0
        });
        uint8 flags1 = DL.FLAG_UPDATE_VERSION 
                     | DL.FLAG_UPDATE_FEE 
                     | DL.FLAG_UPDATE_GAMMA
                     | DL.FLAG_UPDATE_DECIMALS
                     | DL.FLAG_UPDATE_OUTCOME_SLOT_COUNT;
        dataContract.batchUpdateConfigInfo(update1, flags1);
        
        // Update only fee
        DL.ConfigUpdate memory update2 = DL.ConfigUpdate({
            version: 0,
            fee: 2000,
            gamma: 0,
            decimals: 0,
            outcomeSlotCount: 0,
            feeReceived: 0
        });
        dataContract.batchUpdateConfigInfo(update2, DL.FLAG_UPDATE_FEE);
        
        (uint16 version, uint64 fee, uint32 gamma, uint8 decimals, uint8 outcomeSlotCount, ) = dataContract.getConfigInfo();
        assertEq(version, 1);
        assertEq(fee, 2000);
        assertEq(gamma, 9000);
        assertEq(decimals, 18);
        assertEq(outcomeSlotCount, 5);
    }

    function testUpdateMultipleConfigValues() public {
        // Set initial values
        DL.ConfigUpdate memory update1 = DL.ConfigUpdate({
            version: 1,
            fee: 1000,
            gamma: 8000,
            decimals: 10,
            outcomeSlotCount: 0,
            feeReceived: 0
        });
        uint8 flags1 = DL.FLAG_UPDATE_VERSION 
                     | DL.FLAG_UPDATE_FEE 
                     | DL.FLAG_UPDATE_GAMMA
                     | DL.FLAG_UPDATE_DECIMALS;
        dataContract.batchUpdateConfigInfo(update1, flags1);
        
        // Update some values
        DL.ConfigUpdate memory update2 = DL.ConfigUpdate({
            version: 0,
            fee: 2000,
            gamma: 9000,
            decimals: 0,
            outcomeSlotCount: 0,
            feeReceived: 0
        });
        uint8 flags2 = DL.FLAG_UPDATE_FEE | DL.FLAG_UPDATE_GAMMA;
        dataContract.batchUpdateConfigInfo(update2, flags2);
        
        (uint16 version, uint64 fee, uint32 gamma, uint8 decimals, , ) = dataContract.getConfigInfo();
        assertEq(version, 1);
        assertEq(fee, 2000);
        assertEq(gamma, 9000);
        assertEq(decimals, 10);
    }

    // ============ Edge Cases Tests ============

    function testMaxUint32Values() public {    
        uint32 maxValue = type(uint32).max;
        
        DL.TimeUpdate memory update = DL.TimeUpdate({
            currentEpoch: maxValue,
            currentPeriod: maxValue,
            expirationEpoch: maxValue,
            epochDuration: maxValue,
            periodDuration: maxValue,
            periodStart: 0,
            epochStart: 0
        });
        uint8 flags = DL.FLAG_UPDATE_CURRENT_EPOCH 
                    | DL.FLAG_UPDATE_CURRENT_PERIOD 
                    | DL.FLAG_UPDATE_EXPIRATION_EPOCH
                    | DL.FLAG_UPDATE_EPOCH_DURATION
                    | DL.FLAG_UPDATE_PERIOD_DURATION;
        dataContract.batchUpdateTimeInfo(update, flags);
        
        (uint32 currentEpoch, uint32 currentPeriod, uint32 expirationEpoch, uint32 epochDuration, uint32 periodDuration, , ) = dataContract.getTimeInfo();
        assertEq(currentEpoch, maxValue);
        assertEq(currentPeriod, maxValue);
        assertEq(expirationEpoch, maxValue);
        assertEq(epochDuration, maxValue);
        assertEq(periodDuration, maxValue);
    }

    function testMaxConfigValues() public {
        uint64 maxFee = type(uint64).max;
        uint32 maxGamma = type(uint32).max;
        uint8 maxDecimals = type(uint8).max;
        uint8 maxOutcomeSlotCount = type(uint8).max;
        
        DL.ConfigUpdate memory update = DL.ConfigUpdate({
            version: 0,
            fee: maxFee,
            gamma: maxGamma,
            decimals: maxDecimals,
            outcomeSlotCount: maxOutcomeSlotCount,
            feeReceived: 0
        });
        uint8 flags = DL.FLAG_UPDATE_FEE 
                    | DL.FLAG_UPDATE_GAMMA
                    | DL.FLAG_UPDATE_DECIMALS
                    | DL.FLAG_UPDATE_OUTCOME_SLOT_COUNT;
        dataContract.batchUpdateConfigInfo(update, flags);
        
        (, uint64 fee, uint32 gamma, uint8 decimals, uint8 outcomeSlotCount, ) = dataContract.getConfigInfo();
        assertEq(fee, maxFee);
        assertEq(gamma, maxGamma);
        assertEq(decimals, maxDecimals);
        assertEq(outcomeSlotCount, maxOutcomeSlotCount);
    }

    function testZeroValues() public {
        DL.TimeUpdate memory update = DL.TimeUpdate({
            currentEpoch: 0,
            currentPeriod: 0,
            expirationEpoch: 0,
            epochDuration: 0,
            periodDuration: 0,
            periodStart: 0,
            epochStart: 0
        });
        uint8 flags = DL.FLAG_UPDATE_CURRENT_EPOCH 
                    | DL.FLAG_UPDATE_CURRENT_PERIOD 
                    | DL.FLAG_UPDATE_EXPIRATION_EPOCH
                    | DL.FLAG_UPDATE_EPOCH_DURATION
                    | DL.FLAG_UPDATE_PERIOD_DURATION;
        dataContract.batchUpdateTimeInfo(update, flags);
        
        (uint32 currentEpoch, uint32 currentPeriod, uint32 expirationEpoch, uint32 epochDuration, uint32 periodDuration, , ) = dataContract.getTimeInfo();
        assertEq(currentEpoch, 0);
        assertEq(currentPeriod, 0);
        assertEq(expirationEpoch, 0);
        assertEq(epochDuration, 0);
        assertEq(periodDuration, 0);
    }

    function testZeroConfigValues() public {
        DL.ConfigUpdate memory update = DL.ConfigUpdate({
            version: 0,
            fee: 0,
            gamma: 0,
            decimals: 0,
            outcomeSlotCount: 0,
            feeReceived: 0
        });
        uint8 flags = DL.FLAG_UPDATE_FEE 
                    | DL.FLAG_UPDATE_GAMMA
                    | DL.FLAG_UPDATE_DECIMALS
                    | DL.FLAG_UPDATE_OUTCOME_SLOT_COUNT;
        dataContract.batchUpdateConfigInfo(update, flags);
        
        (, uint64 fee, uint32 gamma, uint8 decimals, uint8 outcomeSlotCount, ) = dataContract.getConfigInfo();
        assertEq(fee, 0);
        assertEq(gamma, 0);
        assertEq(decimals, 0);
        assertEq(outcomeSlotCount, 0);
    }

    function testSetToZeroAfterNonZero() public {
        // Set to non-zero values
        DL.TimeUpdate memory update1 = DL.TimeUpdate({
            currentEpoch: 100,
            currentPeriod: 200,
            expirationEpoch: 0,
            epochDuration: 0,
            periodDuration: 0,
            periodStart: 0,
            epochStart: 0
        });
        uint8 flags1 = DL.FLAG_UPDATE_CURRENT_EPOCH | DL.FLAG_UPDATE_CURRENT_PERIOD;
        dataContract.batchUpdateTimeInfo(update1, flags1);
        
        // Set back to zero
        DL.TimeUpdate memory update2 = DL.TimeUpdate({
            currentEpoch: 0,
            currentPeriod: 0,
            expirationEpoch: 0,
            epochDuration: 0,
            periodDuration: 0,
            periodStart: 0,
            epochStart: 0
        });
        dataContract.batchUpdateTimeInfo(update2, flags1);
        
        (uint32 currentEpoch, uint32 currentPeriod, , , , , ) = dataContract.getTimeInfo();
        assertEq(currentEpoch, 0);
        assertEq(currentPeriod, 0);
    }

    function testSetConfigToZeroAfterNonZero() public {
        // Set to non-zero values
        DL.ConfigUpdate memory update1 = DL.ConfigUpdate({
            version: 0,
            fee: 1000,
            gamma: 9000,
            decimals: 18,
            outcomeSlotCount: 0,
            feeReceived: 0
        });
        uint8 flags1 = DL.FLAG_UPDATE_FEE 
                     | DL.FLAG_UPDATE_GAMMA
                     | DL.FLAG_UPDATE_DECIMALS;
        dataContract.batchUpdateConfigInfo(update1, flags1);
        
        // Set back to zero
        DL.ConfigUpdate memory update2 = DL.ConfigUpdate({
            version: 0,
            fee: 0,
            gamma: 0,
            decimals: 0,
            outcomeSlotCount: 0,
            feeReceived: 0
        });
        dataContract.batchUpdateConfigInfo(update2, flags1);
        
        (, uint64 fee, uint32 gamma, uint8 decimals, , ) = dataContract.getConfigInfo();
        assertEq(fee, 0);
        assertEq(gamma, 0);
        assertEq(decimals, 0);
    }

    // ============ Bit Isolation Tests ============

    function testBitsDoNotOverlap() public {
        DL.TimeUpdate memory update = DL.TimeUpdate({
            currentEpoch: 0x11111111,
            currentPeriod: 0x22222222,
            expirationEpoch: 0x33333333,
            epochDuration: 0x44444444,
            periodDuration: 0x55555555,
            periodStart: 0,
            epochStart: 0
        });
        uint8 flags = DL.FLAG_UPDATE_CURRENT_EPOCH 
                    | DL.FLAG_UPDATE_CURRENT_PERIOD 
                    | DL.FLAG_UPDATE_EXPIRATION_EPOCH
                    | DL.FLAG_UPDATE_EPOCH_DURATION
                    | DL.FLAG_UPDATE_PERIOD_DURATION;
        dataContract.batchUpdateTimeInfo(update, flags);
        
        (uint32 currentEpoch, uint32 currentPeriod, uint32 expirationEpoch, uint32 epochDuration, uint32 periodDuration, , ) = dataContract.getTimeInfo();
        assertEq(currentEpoch, 0x11111111);
        assertEq(currentPeriod, 0x22222222);
        assertEq(expirationEpoch, 0x33333333);
        assertEq(epochDuration, 0x44444444);
        assertEq(periodDuration, 0x55555555);
    }

    function testConfigBitsDoNotOverlap() public {
        DL.ConfigUpdate memory update = DL.ConfigUpdate({
            version: 0,
            fee: 0x1111111111111111,
            gamma: 0x22222222,
            decimals: 0x33,
            outcomeSlotCount: 0x44,
            feeReceived: 0
        });
        uint8 flags = DL.FLAG_UPDATE_FEE 
                    | DL.FLAG_UPDATE_GAMMA
                    | DL.FLAG_UPDATE_DECIMALS
                    | DL.FLAG_UPDATE_OUTCOME_SLOT_COUNT;
        dataContract.batchUpdateConfigInfo(update, flags);
        
        (, uint64 fee, uint32 gamma, uint8 decimals, uint8 outcomeSlotCount, ) = dataContract.getConfigInfo();
        assertEq(fee, 0x1111111111111111);
        assertEq(gamma, 0x22222222);
        assertEq(decimals, 0x33);
        assertEq(outcomeSlotCount, 0x44);
    }

    function testRandomValues() public {
        DL.TimeUpdate memory update = DL.TimeUpdate({
            currentEpoch: 12345,
            currentPeriod: 67890,
            expirationEpoch: 54321,
            epochDuration: 98765,
            periodDuration: 13579,
            periodStart: 0,
            epochStart: 0
        });
        uint8 flags = DL.FLAG_UPDATE_CURRENT_EPOCH 
                    | DL.FLAG_UPDATE_CURRENT_PERIOD 
                    | DL.FLAG_UPDATE_EXPIRATION_EPOCH
                    | DL.FLAG_UPDATE_EPOCH_DURATION
                    | DL.FLAG_UPDATE_PERIOD_DURATION;
        dataContract.batchUpdateTimeInfo(update, flags);
        
        (uint32 currentEpoch, uint32 currentPeriod, uint32 expirationEpoch, uint32 epochDuration, uint32 periodDuration, uint32 periodStart, uint32 epochStart) = dataContract.getTimeInfo();
        assertEq(currentEpoch, 12345);
        assertEq(currentPeriod, 67890);
        assertEq(expirationEpoch, 54321);
        assertEq(epochDuration, 98765);
        assertEq(periodDuration, 13579);
        assertEq(periodStart, 0);
        assertEq(epochStart, 0);
    }

    function testRandomConfigValues() public {
        DL.ConfigUpdate memory update = DL.ConfigUpdate({
            version: 0,
            fee: 123456789,
            gamma: 9000,
            decimals: 10,
            outcomeSlotCount: 5,
            feeReceived: 0
        });
        uint8 flags = DL.FLAG_UPDATE_FEE 
                    | DL.FLAG_UPDATE_GAMMA
                    | DL.FLAG_UPDATE_DECIMALS
                    | DL.FLAG_UPDATE_OUTCOME_SLOT_COUNT;
        dataContract.batchUpdateConfigInfo(update, flags);
        
        (, uint64 fee, uint32 gamma, uint8 decimals, uint8 outcomeSlotCount, ) = dataContract.getConfigInfo();
        assertEq(fee, 123456789);
        assertEq(gamma, 9000);
        assertEq(decimals, 10);
        assertEq(outcomeSlotCount, 5);
    }

    // ============ FeeReceived Tests ============

    function testAddFeeReceived() public {
        DL.ConfigUpdate memory update1 = DL.ConfigUpdate({
            version: 0,
            fee: 0,
            gamma: 0,
            decimals: 0,
            outcomeSlotCount: 0,
            feeReceived: 1000
        });
        dataContract.batchUpdateConfigInfo(update1, DL.FLAG_UPDATE_FEE_RECEIVED);
        
        (, , , , , uint128 feeReceived) = dataContract.getConfigInfo();
        assertEq(feeReceived, 1000);
        
        // Add more
        DL.ConfigUpdate memory update2 = DL.ConfigUpdate({
            version: 0,
            fee: 0,
            gamma: 0,
            decimals: 0,
            outcomeSlotCount: 0,
            feeReceived: 500
        });
        dataContract.batchUpdateConfigInfo(update2, DL.FLAG_UPDATE_FEE_RECEIVED);
        
        (, , , , , feeReceived) = dataContract.getConfigInfo();
        assertEq(feeReceived, 1500);
    }

    function testSubFeeReceived() public {
        // Set initial fee
        DL.ConfigUpdate memory update1 = DL.ConfigUpdate({
            version: 0,
            fee: 0,
            gamma: 0,
            decimals: 0,
            outcomeSlotCount: 0,
            feeReceived: 2000
        });
        dataContract.batchUpdateConfigInfo(update1, DL.FLAG_UPDATE_FEE_RECEIVED);
        
        // Subtract
        DL.ConfigUpdate memory update2 = DL.ConfigUpdate({
            version: 0,
            fee: 0,
            gamma: 0,
            decimals: 0,
            outcomeSlotCount: 0,
            feeReceived: -500
        });
        dataContract.batchUpdateConfigInfo(update2, DL.FLAG_UPDATE_FEE_RECEIVED);
        
        (, , , , , uint128 feeReceived) = dataContract.getConfigInfo();
        assertEq(feeReceived, 1500);
    }

    // ============ Fuzz Tests ============

    function testFuzzGetSetCurrentEpoch(uint32 value) public {
        DL.TimeUpdate memory update = DL.TimeUpdate({
            currentEpoch: value,
            currentPeriod: 0,
            expirationEpoch: 0,
            epochDuration: 0,
            periodDuration: 0,
            periodStart: 0,
            epochStart: 0
        });
        dataContract.batchUpdateTimeInfo(update, DL.FLAG_UPDATE_CURRENT_EPOCH);
        
        (uint32 currentEpoch, , , , , , ) = dataContract.getTimeInfo();
        assertEq(currentEpoch, value);
    }

    function testFuzzGetSetCurrentPeriod(uint32 value) public {
        DL.TimeUpdate memory update = DL.TimeUpdate({
            currentEpoch: 0,
            currentPeriod: value,
            expirationEpoch: 0,
            epochDuration: 0,
            periodDuration: 0,
            periodStart: 0,
            epochStart: 0
        });
        dataContract.batchUpdateTimeInfo(update, DL.FLAG_UPDATE_CURRENT_PERIOD);
        
        (, uint32 currentPeriod, , , , , ) = dataContract.getTimeInfo();
        assertEq(currentPeriod, value);
    }

    function testFuzzGetSetExpirationEpoch(uint32 value) public {
        DL.TimeUpdate memory update = DL.TimeUpdate({
            currentEpoch: 0,
            currentPeriod: 0,
            expirationEpoch: value,
            epochDuration: 0,
            periodDuration: 0,
            periodStart: 0,
            epochStart: 0
        });
        dataContract.batchUpdateTimeInfo(update, DL.FLAG_UPDATE_EXPIRATION_EPOCH);
        
        (, , uint32 expirationEpoch, , , , ) = dataContract.getTimeInfo();
        assertEq(expirationEpoch, value);
    }

    function testFuzzGetSetEpochDuration(uint32 value) public {
        DL.TimeUpdate memory update = DL.TimeUpdate({
            currentEpoch: 0,
            currentPeriod: 0,
            expirationEpoch: 0,
            epochDuration: value,
            periodDuration: 0,
            periodStart: 0,
            epochStart: 0
        });
        dataContract.batchUpdateTimeInfo(update, DL.FLAG_UPDATE_EPOCH_DURATION);
        
        (, , , uint32 epochDuration, , , ) = dataContract.getTimeInfo();
        assertEq(epochDuration, value);
    }

    function testFuzzGetSetPeriodDuration(uint32 value) public {
        DL.TimeUpdate memory update = DL.TimeUpdate({
            currentEpoch: 0,
            currentPeriod: 0,
            expirationEpoch: 0,
            epochDuration: 0,
            periodDuration: value,
            periodStart: 0,
            epochStart: 0
        });
        dataContract.batchUpdateTimeInfo(update, DL.FLAG_UPDATE_PERIOD_DURATION);
        
        (, , , , uint32 periodDuration, , ) = dataContract.getTimeInfo();
        assertEq(periodDuration, value);
    }

    function testFuzzGetSetFee(uint64 value) public {
        DL.ConfigUpdate memory update = DL.ConfigUpdate({
            version: 0,
            fee: value,
            gamma: 0,
            decimals: 0,
            outcomeSlotCount: 0,
            feeReceived: 0
        });
        dataContract.batchUpdateConfigInfo(update, DL.FLAG_UPDATE_FEE);
        
        (, uint64 fee, , , , ) = dataContract.getConfigInfo();
        assertEq(fee, value);
    }

    function testFuzzGetSetGamma(uint32 value) public {
        DL.ConfigUpdate memory update = DL.ConfigUpdate({
            version: 0,
            fee: 0,
            gamma: value,
            decimals: 0,
            outcomeSlotCount: 0,
            feeReceived: 0
        });
        dataContract.batchUpdateConfigInfo(update, DL.FLAG_UPDATE_GAMMA);
        
        (, , uint32 gamma, , , ) = dataContract.getConfigInfo();
        assertEq(gamma, value);
    }

    function testFuzzGetSetDecimals(uint8 value) public {
        DL.ConfigUpdate memory update = DL.ConfigUpdate({
            version: 0,
            fee: 0,
            gamma: 0,
            decimals: value,
            outcomeSlotCount: 0,
            feeReceived: 0
        });
        dataContract.batchUpdateConfigInfo(update, DL.FLAG_UPDATE_DECIMALS);
        
        (, , , uint8 decimals, , ) = dataContract.getConfigInfo();
        assertEq(decimals, value);
    }

    function testFuzzGetSetOutcomeSlotCount(uint8 value) public {
        DL.ConfigUpdate memory update = DL.ConfigUpdate({
            version: 0,
            fee: 0,
            gamma: 0,
            decimals: 0,
            outcomeSlotCount: value,
            feeReceived: 0
        });
        dataContract.batchUpdateConfigInfo(update, DL.FLAG_UPDATE_OUTCOME_SLOT_COUNT);
        
        (, , , , uint8 outcomeSlotCount, ) = dataContract.getConfigInfo();
        assertEq(outcomeSlotCount, value);
    }

    function testFuzzAllTimeFields(
        uint32 epoch,
        uint32 period,
        uint32 expirationEpoch,
        uint32 epochDuration,
        uint32 periodDuration
    ) public {
        DL.TimeUpdate memory update = DL.TimeUpdate({
            currentEpoch: epoch,
            currentPeriod: period,
            expirationEpoch: expirationEpoch,
            epochDuration: epochDuration,
            periodDuration: periodDuration,
            periodStart: 0,
            epochStart: 0
        });
        uint8 flags = DL.FLAG_UPDATE_CURRENT_EPOCH 
                    | DL.FLAG_UPDATE_CURRENT_PERIOD 
                    | DL.FLAG_UPDATE_EXPIRATION_EPOCH
                    | DL.FLAG_UPDATE_EPOCH_DURATION
                    | DL.FLAG_UPDATE_PERIOD_DURATION;
        dataContract.batchUpdateTimeInfo(update, flags);
        
        (uint32 currentEpoch, uint32 currentPeriod, uint32 expEpoch, uint32 epDuration, uint32 perDuration, , ) = dataContract.getTimeInfo();
        assertEq(currentEpoch, epoch);
        assertEq(currentPeriod, period);
        assertEq(expEpoch, expirationEpoch);
        assertEq(epDuration, epochDuration);
        assertEq(perDuration, periodDuration);
    }

    function testFuzzAllConfigFields(
        uint64 fee,
        uint32 gamma,
        uint8 decimals,
        uint8 outcomeSlotCount
    ) public {
        DL.ConfigUpdate memory update = DL.ConfigUpdate({
            version: 0,
            fee: fee,
            gamma: gamma,
            decimals: decimals,
            outcomeSlotCount: outcomeSlotCount,
            feeReceived: 0
        });
        uint8 flags = DL.FLAG_UPDATE_FEE 
                    | DL.FLAG_UPDATE_GAMMA
                    | DL.FLAG_UPDATE_DECIMALS
                    | DL.FLAG_UPDATE_OUTCOME_SLOT_COUNT;
        dataContract.batchUpdateConfigInfo(update, flags);
        
        (, uint64 feeResult, uint32 gammaResult, uint8 decimalsResult, uint8 outcomeSlotCountResult, ) = dataContract.getConfigInfo();
        assertEq(feeResult, fee);
        assertEq(gammaResult, gamma);
        assertEq(decimalsResult, decimals);
        assertEq(outcomeSlotCountResult, outcomeSlotCount);
    }
}

/**
 * @title DataTestContract
 * @dev Test contract that wraps DataLayoutLibrary functions for testing
 */
contract DataTestContract {
    function getTimeInfo() public view returns (uint32 currentEpoch, uint32 currentPeriod, uint32 expirationEpoch, uint32 epochDuration, uint32 periodDuration, uint32 periodStart, uint32 epochStart) {
        return DL.getTimeInfo();
    }

    function getConfigInfo() public view returns (uint16 version, uint64 fee, uint32 gamma, uint8 decimals, uint8 outcomeSlotCount, uint128 feeReceived) {
        return DL.getConfigInfo();
    }

    function batchUpdateTimeInfo(DL.TimeUpdate memory update, uint8 flags) public {
        DL.batchUpdateTimeInfo(update, flags);
    }

    function batchUpdateConfigInfo(DL.ConfigUpdate memory update, uint8 flags) public {
        DL.batchUpdateConfigInfo(update, flags);
    }
}
