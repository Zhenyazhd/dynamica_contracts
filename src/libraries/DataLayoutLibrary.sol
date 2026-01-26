// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

library DataLayoutLibrary {

    bytes32 constant _TIME_SLOT = bytes32(uint256(keccak256("dynamica.data.time")) - 1);
    bytes32 constant _CONFIG_SLOT = bytes32(uint256(keccak256("dynamica.data.config")) - 1);
    bytes32 constant _END_EPOCH_FUNDING_SLOT = bytes32(uint256(keccak256("dynamica.data.endEpochFunding")) - 1);

    uint256 internal constant MASK_8  = type(uint8).max; 
    uint256 internal constant MASK_16 = type(uint16).max; 
    uint256 internal constant MASK_32 = type(uint32).max; 
    uint256 internal constant MASK_64 = type(uint64).max; 
    uint256 internal constant MASK_128 = type(uint128).max; 

    /*
        | bits 0–31     | currentEpoch     (uint32)  |
        | bits 32–63    | currentPeriod    (uint32)  |
        | bits 64–95    | expirationEpoch  (uint32)  |
        | bits 96–127   | epochDuration    (uint32)  |
        | bits 128–159  | periodDuration   (uint32)  |
        | bits 160–191  | periodStart      (uint32)  |
        | bits 192–223  | epochStart       (uint32)  |
    */
   
    uint256 internal constant SHIFT_EPOCH            = 0;
    uint256 internal constant SHIFT_PERIOD           = 32;
    uint256 internal constant SHIFT_EXPIRATION_EPOCH = 64;
    uint256 internal constant SHIFT_EPOCH_DURATION   = 96;
    uint256 internal constant SHIFT_PERIOD_DURATION  = 128;
    uint256 internal constant SHIFT_PERIOD_START     = 160;
    uint256 internal constant SHIFT_EPOCH_START      = 192;

    uint256 internal constant MASK_CURRENT_EPOCH      = MASK_32 << SHIFT_EPOCH;
    uint256 internal constant MASK_CURRENT_PERIOD     = MASK_32 << SHIFT_PERIOD;
    uint256 internal constant MASK_EXPIRATION_EPOCH   = MASK_32 << SHIFT_EXPIRATION_EPOCH;
    uint256 internal constant MASK_EPOCH_DURATION     = MASK_32 << SHIFT_EPOCH_DURATION;
    uint256 internal constant MASK_PERIOD_DURATION    = MASK_32 << SHIFT_PERIOD_DURATION;
    uint256 internal constant MASK_PERIOD_START       = MASK_32 << SHIFT_PERIOD_START;
    uint256 internal constant MASK_EPOCH_START        = MASK_32 << SHIFT_EPOCH_START;

    // Bit flags for batch update control
    uint8 internal constant FLAG_UPDATE_CURRENT_EPOCH     = 1 << 0; // 0x01
    uint8 internal constant FLAG_UPDATE_CURRENT_PERIOD    = 1 << 1; // 0x02
    uint8 internal constant FLAG_UPDATE_EXPIRATION_EPOCH  = 1 << 2; // 0x04
    uint8 internal constant FLAG_UPDATE_EPOCH_DURATION    = 1 << 3; // 0x08
    uint8 internal constant FLAG_UPDATE_PERIOD_DURATION   = 1 << 4; // 0x10
    uint8 internal constant FLAG_UPDATE_PERIOD_START      = 1 << 5; // 0x20
    uint8 internal constant FLAG_UPDATE_EPOCH_START       = 1 << 6; // 0x40

    // Structure for batch time updates
    struct TimeUpdate {
        uint32 currentEpoch;
        uint32 currentPeriod;
        uint32 expirationEpoch;
        uint32 epochDuration;
        uint32 periodDuration;
        uint32 periodStart;
        uint32 epochStart;
    }

    // Bit flags for batch config update control
    uint8 internal constant FLAG_UPDATE_VERSION            = 1 << 0; // 0x01
    uint8 internal constant FLAG_UPDATE_FEE                = 1 << 1; // 0x02
    uint8 internal constant FLAG_UPDATE_GAMMA              = 1 << 2; // 0x04
    uint8 internal constant FLAG_UPDATE_DECIMALS           = 1 << 3; // 0x08
    uint8 internal constant FLAG_UPDATE_OUTCOME_SLOT_COUNT = 1 << 4; // 0x10
    uint8 internal constant FLAG_UPDATE_FEE_RECEIVED       = 1 << 5; // 0x20
    uint8 internal constant FLAG_UPDATE_ALPHA              = 1 << 6; // 0x40

    // Structure for batch config updates
    struct ConfigUpdate {
        uint8 version;
        uint8 alpha;
        uint64 fee;
        uint32 gamma;
        uint8 decimals;
        uint8 outcomeSlotCount;
        int128 feeReceived;
    }

    /*  
        | bits 0–7      | version          (uint8)   |
        | bits 8–15     | alpha            (uint8)   |
        | bits 16–23    | decimals         (uint8)   |
        | bits 24–31    | outcomeSlotCount (uint8)   |
        | bits 32–95    | fee              (uint64)  |
        | bits 96–127   | gamma            (uint32)  |
        | bits 128–255  | feeReceived      (uint128) |
    */

    uint256 internal constant SHIFT_VERSION            = 0;
    uint256 internal constant SHIFT_ALPHA              = 8;
    uint256 internal constant SHIFT_DECIMALS           = 16;
    uint256 internal constant SHIFT_OUTCOME_SLOT_COUNT = 24;
    uint256 internal constant SHIFT_FEE                = 32;
    uint256 internal constant SHIFT_GAMMA              = 96;
    uint256 internal constant SHIFT_FEE_RECIEVED       = 128;

    uint256 internal constant MASK_VERSION            = MASK_8 << SHIFT_VERSION;
    uint256 internal constant MASK_ALPHA              = MASK_8 << SHIFT_ALPHA;
    uint256 internal constant MASK_DECIMALS           = MASK_8 << SHIFT_DECIMALS;
    uint256 internal constant MASK_OUTCOME_SLOT_COUNT = MASK_8 << SHIFT_OUTCOME_SLOT_COUNT;
    uint256 internal constant MASK_FEE                = MASK_64 << SHIFT_FEE;
    uint256 internal constant MASK_GAMMA              = MASK_32 << SHIFT_GAMMA;  
    uint256 internal constant MASK_FEE_RECIEVED       = MASK_128 << SHIFT_FEE_RECIEVED;

    uint256 internal constant SHIFT_TOTAL_PAYOUT         = 0;
    uint256 internal constant SHIFT_FUNDING_FOR_ROLLOVER = 128;

    uint256 internal constant MASK_TOTAL_PAYOUT         = MASK_128 << SHIFT_TOTAL_PAYOUT;
    uint256 internal constant MASK_FUNDING_FOR_ROLLOVER = MASK_128 << SHIFT_FUNDING_FOR_ROLLOVER;


    // ============== Mapping ==============    
    /*
        | bits 0–127    | totalPayout         (uint128)  |
        | bits 128–255  | fundingForRollover  (uint128)  |
    */
    
    //mapping(uint256 => uint256) public packedEndEpochFunding;

    // ============ State Variables ============
   
    function _getStorageData(bytes32 slot) internal view returns (uint256 data) {
        assembly {
            data := sload(slot)
        }
    }

    function _setStorageData(bytes32 slot, uint256 data) internal {
        assembly {
            sstore(slot, data)
        }
    }

    function _getStorageDataWithMask(bytes32 slot, uint256 mask, uint256 shift) internal view returns (uint256 data) {
        assembly {
            data := and(sload(slot), mask)
            data := shr(shift, data)
        }
    }

    /// @notice Sets a field in packed storage data
    /// @param slot Storage slot to update
    /// @param fieldMask Mask of the field to update (bits that belong to this field)
    /// @param shift Shift amount for the field
    /// @param data New value for the field
    /// @dev This function clears the field (using ~fieldMask) and sets the new value
    function _setStorageDataWithMask(bytes32 slot, uint256 fieldMask, uint256 shift, uint256 data) internal {
        assembly {
            let packedData := sload(slot)
            packedData := and(packedData, not(fieldMask))
            packedData := or(packedData, shl(shift, data))
            sstore(slot, packedData)
        }
    }


    /// @notice Calculating the slot ID for Dex contract for single mapping at `slot_` for `key_`
    function calculateMapPackedEndEpochFundingSlot(bytes32 slot_, uint256 epoch) internal pure returns (bytes32) {
        return keccak256(abi.encode(epoch, slot_));
    }

    function getTimeInfo() public view returns (uint32 currentEpoch, uint32 currentPeriod, uint32 expirationEpoch, uint32 epochDuration, uint32 periodDuration, uint32 periodStart, uint32 epochStart) {
        uint256 packedTime = _getStorageData(_TIME_SLOT);
        return(
            uint32((packedTime & MASK_CURRENT_EPOCH) >> SHIFT_EPOCH),
            uint32((packedTime & MASK_CURRENT_PERIOD) >> SHIFT_PERIOD),
            uint32((packedTime & MASK_EXPIRATION_EPOCH) >> SHIFT_EXPIRATION_EPOCH),
            uint32((packedTime & MASK_EPOCH_DURATION) >> SHIFT_EPOCH_DURATION),
            uint32((packedTime & MASK_PERIOD_DURATION) >> SHIFT_PERIOD_DURATION),
            uint32((packedTime & MASK_PERIOD_START) >> SHIFT_PERIOD_START),
            uint32((packedTime & MASK_EPOCH_START) >> SHIFT_EPOCH_START)
        );
    }

    function getConfigInfo() public view returns (uint16 version, uint64 fee, uint32 gamma, uint8 decimals, uint8 outcomeSlotCount, uint128 feeReceived) {
        uint256 packedConfig = _getStorageData(_CONFIG_SLOT);
        return(
            uint16((packedConfig & MASK_VERSION) >> SHIFT_VERSION),
            uint64((packedConfig & MASK_FEE) >> SHIFT_FEE),
            uint32((packedConfig & MASK_GAMMA) >> SHIFT_GAMMA),
            uint8((packedConfig & MASK_DECIMALS) >> SHIFT_DECIMALS),
            uint8((packedConfig & MASK_OUTCOME_SLOT_COUNT) >> SHIFT_OUTCOME_SLOT_COUNT),
            uint128((packedConfig & MASK_FEE_RECIEVED) >> SHIFT_FEE_RECIEVED)
        );
    }

    function getEndEpochFundingInfo(uint256 epoch) public view returns (uint128 totalPayout, uint128 fundingForRollover) {
        bytes32 slot = calculateMapPackedEndEpochFundingSlot(_END_EPOCH_FUNDING_SLOT, epoch);
        uint256 packedEndEpochFunding = _getStorageData(slot);
        return(
            uint128((packedEndEpochFunding & MASK_TOTAL_PAYOUT) >> SHIFT_TOTAL_PAYOUT),
            uint128((packedEndEpochFunding & MASK_FUNDING_FOR_ROLLOVER) >> SHIFT_FUNDING_FOR_ROLLOVER)
        );
    }

    /**
     * @notice Batch update multiple time fields at once
     * @param update Struct containing values to update (unused fields are ignored)
     * @param flags Bitmask indicating which fields to update
     *        Use FLAG_UPDATE_* constants combined with bitwise OR (|)
     *        Example: FLAG_UPDATE_CURRENT_EPOCH | FLAG_UPDATE_CURRENT_PERIOD
     * @dev Only fields specified in flags will be updated, others remain unchanged
     */
    function batchUpdateTimeInfo(TimeUpdate memory update, uint8 flags) internal {
        uint256 packedTime = _getStorageData(_TIME_SLOT);
        
        if ((flags & FLAG_UPDATE_CURRENT_EPOCH) != 0) {
            packedTime = (packedTime & ~MASK_CURRENT_EPOCH) | (uint256(update.currentEpoch) << SHIFT_EPOCH);
        }
        
        if ((flags & FLAG_UPDATE_CURRENT_PERIOD) != 0) {
            packedTime = (packedTime & ~MASK_CURRENT_PERIOD) | (uint256(update.currentPeriod) << SHIFT_PERIOD);
        }
        
        if ((flags & FLAG_UPDATE_EXPIRATION_EPOCH) != 0) {
            packedTime = (packedTime & ~MASK_EXPIRATION_EPOCH) | (uint256(update.expirationEpoch) << SHIFT_EXPIRATION_EPOCH);
        }
        
        if ((flags & FLAG_UPDATE_EPOCH_DURATION) != 0) {
            packedTime = (packedTime & ~MASK_EPOCH_DURATION) | (uint256(update.epochDuration) << SHIFT_EPOCH_DURATION);
        }
        
        if ((flags & FLAG_UPDATE_PERIOD_DURATION) != 0) {
            packedTime = (packedTime & ~MASK_PERIOD_DURATION) | (uint256(update.periodDuration) << SHIFT_PERIOD_DURATION);
        }
        
        if ((flags & FLAG_UPDATE_PERIOD_START) != 0) {
            packedTime = (packedTime & ~MASK_PERIOD_START) | (uint256(update.periodStart) << SHIFT_PERIOD_START);
        }
        
        if ((flags & FLAG_UPDATE_EPOCH_START) != 0) {
            packedTime = (packedTime & ~MASK_EPOCH_START) | (uint256(update.epochStart) << SHIFT_EPOCH_START);
        }
        
        _setStorageData(_TIME_SLOT, packedTime);
    }

    /**
     * @notice Batch update multiple config fields at once
     * @param update Struct containing values to update (unused fields are ignored)
     * @param flags Bitmask indicating which fields to update
     *        Use FLAG_UPDATE_* constants combined with bitwise OR (|)
     *        Example: FLAG_UPDATE_VERSION | FLAG_UPDATE_FEE | FLAG_UPDATE_GAMMA
     * @dev Only fields specified in flags will be updated, others remain unchanged
     */
    function batchUpdateConfigInfo(ConfigUpdate memory update, uint8 flags) internal {
        uint256 packedConfig = _getStorageData(_CONFIG_SLOT);
        
        if ((flags & FLAG_UPDATE_VERSION) != 0) {
            packedConfig = (packedConfig & ~MASK_VERSION) | (uint256(update.version) << SHIFT_VERSION);
        }
        
        if ((flags & FLAG_UPDATE_FEE) != 0) {
            packedConfig = (packedConfig & ~MASK_FEE) | (uint256(update.fee) << SHIFT_FEE);
        }
        
        if ((flags & FLAG_UPDATE_GAMMA) != 0) {
            packedConfig = (packedConfig & ~MASK_GAMMA) | (uint256(update.gamma) << SHIFT_GAMMA);
        }
        
        if ((flags & FLAG_UPDATE_DECIMALS) != 0) {
            packedConfig = (packedConfig & ~MASK_DECIMALS) | (uint256(update.decimals) << SHIFT_DECIMALS);
        }
        
        if ((flags & FLAG_UPDATE_OUTCOME_SLOT_COUNT) != 0) {
            packedConfig = (packedConfig & ~MASK_OUTCOME_SLOT_COUNT) | (uint256(update.outcomeSlotCount) << SHIFT_OUTCOME_SLOT_COUNT);
        }
        
        if ((flags & FLAG_UPDATE_ALPHA) != 0) {
            packedConfig = (packedConfig & ~MASK_ALPHA) | (uint256(update.alpha) << SHIFT_ALPHA);
        }
        
        if ((flags & FLAG_UPDATE_FEE_RECEIVED) != 0) {
            uint128 current = uint128((packedConfig & MASK_FEE_RECIEVED) >> SHIFT_FEE_RECIEVED);
            if (update.feeReceived > 0) {
                current += uint128(update.feeReceived);
                packedConfig = (packedConfig & ~MASK_FEE_RECIEVED) | (uint256(current) << SHIFT_FEE_RECIEVED);
            } else {
                current -= uint128(-update.feeReceived);
                packedConfig = (packedConfig & ~MASK_FEE_RECIEVED) | (uint256(current) << SHIFT_FEE_RECIEVED);
            }
        }
        _setStorageData(_CONFIG_SLOT, packedConfig);
    }

    function setTotalPayout(uint256 epoch, uint128 value) internal {
        bytes32 slot = calculateMapPackedEndEpochFundingSlot(_END_EPOCH_FUNDING_SLOT, epoch);
        uint256 packedEndEpochFunding = _getStorageData(slot);
        packedEndEpochFunding = (packedEndEpochFunding & ~MASK_TOTAL_PAYOUT) | (uint256(value) << SHIFT_TOTAL_PAYOUT);
        _setStorageData(slot, packedEndEpochFunding);
    }

    function setFundingForRollover(uint256 epoch, uint128 value) internal {
        bytes32 slot = calculateMapPackedEndEpochFundingSlot(_END_EPOCH_FUNDING_SLOT, epoch);
        uint256 packedEndEpochFunding = _getStorageData(slot);
        packedEndEpochFunding = (packedEndEpochFunding & ~MASK_FUNDING_FOR_ROLLOVER) | (uint256(value) << SHIFT_FUNDING_FOR_ROLLOVER);
        _setStorageData(slot, packedEndEpochFunding);
    }
}