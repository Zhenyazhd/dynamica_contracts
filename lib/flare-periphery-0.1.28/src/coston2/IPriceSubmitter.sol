// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

import "./genesis/interfaces/IFtsoGenesis.sol";
import "./genesis/interfaces/IFtsoRegistryGenesis.sol";
import "./genesis/interfaces/IFtsoManagerGenesis.sol";

interface IPriceSubmitter {
    /**
     * Event emitted when hash was submitted through PriceSubmitter.
     * @param submitter the address of the sender
     * @param epochId current price epoch id
     * @param hash the submitted hash
     * @param timestamp current block timestamp
     */
    event HashSubmitted(
        address indexed submitter,
        uint256 indexed epochId,
        bytes32 hash,
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
        uint256 random,
        uint256 timestamp
    );
    
    /**
     * @notice Submits hash for current epoch
     * @param _epochId              Target epoch id to which hash is submitted
     * @param _hash                 Hash of ftso indices, prices, random number and voter address
     * @notice Emits HashSubmitted event
     */
    function submitHash(
        uint256 _epochId,
        bytes32 _hash
    ) external;

    /**
     * @notice Reveals submitted prices during epoch reveal period
     * @param _epochId              Id of the epoch in which the price hashes was submitted
     * @param _ftsoIndices          List of increasing ftso indices
     * @param _prices               List of submitted prices in USD
     * @param _random               Submitted random number
     * @notice The hash of ftso indices, prices, random number and voter address must be equal to the submitted hash
     * @notice Emits PricesRevealed event
     */
    function revealPrices(
        uint256 _epochId,
        uint256[] memory _ftsoIndices,
        uint256[] memory _prices,
        uint256 _random
    ) external;

    /**
     * Returns bitmap of all ftso's for which `_voter` is allowed to submit prices/hashes.
     * If voter is allowed to vote for ftso at index (see *_FTSO_INDEX), the corrsponding
     * bit in the result will be 1.
     */    
    function voterWhitelistBitmap(address _voter) external view returns (uint256);

    function getVoterWhitelister() external view returns (address);
    function getFtsoRegistry() external view returns (IFtsoRegistryGenesis);
    function getFtsoManager() external view returns (IFtsoManagerGenesis);

    /**
     * @notice Returns current random number
     */
    function getCurrentRandom() external view returns (uint256);
    
    /**
     * @notice Returns random number of the specified epoch
     * @param _epochId              Id of the epoch
     */
    function getRandom(uint256 _epochId) external view returns (uint256);
}
