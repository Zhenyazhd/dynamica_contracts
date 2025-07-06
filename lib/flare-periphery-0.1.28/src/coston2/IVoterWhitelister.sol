// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

interface IVoterWhitelister {
    /**
     * Raised when an account is removed from the voter whitelist.
     */
    event VoterWhitelisted(address voter, uint256 ftsoIndex);
    
    /**
     * Raised when an account is removed from the voter whitelist.
     */
    event VoterRemovedFromWhitelist(address voter, uint256 ftsoIndex);

    /**
     * Raised when an account is chilled from the voter whitelist.
     */
    event VoterChilled(address voter, uint256 untilRewardEpoch);

    /**
     * Request to whitelist `_voter` account to ftso at `_ftsoIndex`. Will revert if vote power too low.
     * May be called by any address.
     */
    function requestWhitelistingVoter(address _voter, uint256 _ftsoIndex) external;

    /**
     * Request to whitelist `_voter` account to all active ftsos.
     * May be called by any address.
     * It returns an array of supported ftso indices and success flag per index.
     */
    function requestFullVoterWhitelisting(
        address _voter
    ) 
        external 
        returns (
            uint256[] memory _supportedIndices,
            bool[] memory _success
        );

    /**
     * Maximum number of voters in the whitelist for a new FTSO.
     */
    function defaultMaxVotersForFtso() external view returns (uint256);
    
    /**
     * Maximum number of voters in the whitelist for FTSO at index `_ftsoIndex`.
     */
    function maxVotersForFtso(uint256 _ftsoIndex) external view returns (uint256);

    /**
     * Get whitelisted price providers for ftso with `_symbol`
     */
    function getFtsoWhitelistedPriceProvidersBySymbol(string memory _symbol) external view returns (address[] memory);

    /**
     * Get whitelisted price providers for ftso at `_ftsoIndex`
     */
    function getFtsoWhitelistedPriceProviders(uint256 _ftsoIndex) external view returns (address[] memory);

    /**
     * In case of providing bad prices (e.g. collusion), the voter can be chilled for a few reward epochs.
     * A voter can whitelist again from a returned reward epoch onwards.
     */
    function chilledUntilRewardEpoch(address _voter) external view returns (uint256);
}
