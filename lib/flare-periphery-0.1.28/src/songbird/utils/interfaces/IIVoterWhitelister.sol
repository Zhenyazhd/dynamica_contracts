// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

import "../../IVoterWhitelister.sol";


interface IIVoterWhitelister is IVoterWhitelister {
    /**
     * @notice Used to chill voter - remove from whitelist for a specified number of reward epochs
     * @dev Only governance can call this method.
     */
    function chillVoter(
        address _voter,
        uint256 _noOfRewardEpochs,
        uint256[] memory _ftsoIndices
    ) 
        external
        returns(
            bool[] memory _removed,
            uint256 _untilRewardEpoch
        );

    /**
     * Set the maximum number of voters in the whitelist for FTSO at index `_ftsoIndex`.
     * Possibly removes several voters with the least votepower from the whitelist.
     * Only governance can call this method.
     */
    function setMaxVotersForFtso(uint256 _ftsoIndex, uint256 _newMaxVoters) external;

    /**
     * Set the maximum number of voters in the whitelist for a new FTSO.
     * Only governance can call this method.
     */
    function setDefaultMaxVotersForFtso(uint256 _defaultMaxVotersForFtso) external;

    /**
     * Create whitelist with default size for ftso.
     * Only ftso manager can call this method.
     */
    function addFtso(uint256 _ftsoIndex) external;
    
    /**
     * Clear whitelist for ftso at `_ftsoIndex`.
     * Only ftso manager can call this method.
     */
    function removeFtso(uint256 _ftsoIndex) external;

    /**
     * Remove `_trustedAddress` from whitelist for ftso at `_ftsoIndex`.
     */
    function removeTrustedAddressFromWhitelist(address _trustedAddress, uint256 _ftsoIndex) external;
}
