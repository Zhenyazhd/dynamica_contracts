// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

import "./genesis/interfaces/IFtsoGenesis.sol";
import "./genesis/interfaces/IFtsoRegistryGenesis.sol";

interface IPriceSubmitter {
    /**
     * Event emitted when price hashes were submitted through PriceSubmitter.
     * @param submitter the address of the sender
     * @param epochId current price epoch id
     * @param ftsos array of ftsos that correspond to the indexes in call
     * @param hashes the submitted hashes
     * @param timestamp current block timestamp
     */
    event PriceHashesSubmitted(
        address indexed submitter,
        uint256 indexed epochId,
        IFtsoGenesis[] ftsos,
        bytes32[] hashes,
        uint256 timestamp
    );

    /**
     * Event emitted when prices were revealed through PriceSubmitter.
     * @param voter the address of the sender
     * @param epochId id of the epoch in which the price hash was submitted
     * @param ftsos array of ftsos that correspond to the indexes in the call
     * @param prices the submitted prices
     * @param timestamp current block timestamp
     */
    event PricesRevealed(
        address indexed voter,
        uint256 indexed epochId,
        IFtsoGenesis[] ftsos,
        uint256[] prices,
        uint256[] randoms,
        uint256 timestamp
    );
    
    /**
     * @notice Submits price hashes for current epoch
     * @param _epochId              Target epoch id to which hashes are submitted
     * @param _ftsoIndices          List of ftso indices
     * @param _hashes               List of hashed price and random number
     * @notice Emits PriceHashesSubmitted event
     */
    function submitPriceHashes(
        uint256 _epochId,
        uint256[] memory _ftsoIndices,
        bytes32[] memory _hashes
    ) external;

    /**
     * @notice Reveals submitted prices during epoch reveal period
     * @param _epochId              Id of the epoch in which the price hashes was submitted
     * @param _ftsoIndices          List of ftso indices
     * @param _prices               List of submitted prices in USD
     * @param _randoms              List of submitted random numbers
     * @notice The hash of _price and _random must be equal to the submitted hash
     * @notice Emits PricesRevealed event
     */
    function revealPrices(
        uint256 _epochId,
        uint256[] memory _ftsoIndices,
        uint256[] memory _prices,
        uint256[] memory _randoms
    ) external;

    /**
     * Returns bitmap of all ftso's for which `_voter` is allowed to submit prices/hashes.
     * If voter is allowed to vote for ftso at index (see *_FTSO_INDEX), the corrsponding
     * bit in the result will be 1.
     */    
    function voterWhitelistBitmap(address _voter) external view returns (uint256);

    function getVoterWhitelister() external view returns (address);
    function getFtsoRegistry() external view returns (IFtsoRegistryGenesis);
    function getFtsoManager() external view returns (address);
}
