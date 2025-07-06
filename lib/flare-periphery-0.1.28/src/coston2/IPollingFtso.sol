// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;
pragma abicoder v2;


interface IPollingFtso {

    /**
     * @notice Struct holding the information about proposal properties
     */
    struct Proposal {
        string description;                // description of the proposal
        address proposer;                  // address of the proposer
        bool canceled;                     // flag indicating if proposal has been canceled
        uint256 voteStartTime;             // start time of voting window (in seconds from epoch)
        uint256 voteEndTime;               // end time of voting window (in seconds from epoch)
        uint256 thresholdConditionBIPS;    // percentage in BIPS of the total vote power required for proposal "quorum"
        uint256 majorityConditionBIPS;     // percentage in BIPS of the proper relation between FOR and AGAINST votes
        mapping(address => bool) isEligible; // flag if an address is eligible to cast a vote in a proposal
        uint256 noOfEligibleMembers;       // number of addresses that can vote in the proposal
    }

    /**
     * @notice Struct holding the information about proposal voting
     */
    struct ProposalVoting {
        uint256 againstVotePower;           // accumulated vote power against the proposal
        uint256 forVotePower;               // accumulated vote power for the proposal
        mapping(address => bool) hasVoted;  // flag if a voter has cast a vote
    }

    /**
     * @notice Enum describing a proposal state
     */
    enum ProposalState {
        Canceled,
        Pending,
        Active,
        Defeated,
        Succeeded
    }

    /**
     * @notice Enum that determines vote (support) type
     * @dev 0 = Against, 1 = For
     */
    enum VoteType {
        Against,
        For
    }

    /**
     * @notice Event emitted when a proposal is created
     */
    event FtsoProposalCreated(
        uint256 indexed proposalId,
        address proposer,
        string description,
        uint256 voteStartTime,
        uint256 voteEndTime,
        uint256 thresholdConditionBIPS,
        uint256 majorityConditionBIPS,
        address[] eligibleMembers
    );

    /**
     * @notice Event emitted when a vote is cast
     */
    event VoteCast(
        address indexed voter,
        uint256 indexed proposalId,
        uint8 support,
        uint256 forVotePower,
        uint256 againstVotePower
    );

    /**
     * @notice Event emitted when a proposal is canceled
     */
    event ProposalCanceled(uint256 indexed proposalId);

    /**
     * @notice Event emitted when parameters are set
     */
    event ParametersSet(
        uint256 votingDelaySeconds,
        uint256 votingPeriodSeconds,
        uint256 thresholdConditionBIPS,
        uint256 majorityConditionBIPS,
        uint256 proposalFeeValueWei,
        uint256 addAfterRewardedEpochs,
        uint256 addAfterNotChilledEpochs,
        uint256 removeAfterNotRewardedEpochs,
        uint256 removeAfterEligibleProposals,
        uint256 removeAfterNonParticipatingProposals,
        uint256 removeForDays
    );

    /**
     * @notice Event emitted when management group member is added
     */
    event ManagementGroupMemberAdded(address addedMember);

    /**
     * @notice Event emitted when management group member is removed
     */
    event ManagementGroupMemberRemoved(address removedMember);

    /**
     * @notice Event emitted when maintainer is set
     */
    event MaintainerSet(address newMaintainer);

    /**
     * @notice Event emitted when proxy voter is set
     */
    event ProxyVoterSet(address account, address proxyVoter);

    /**
     * @notice Sets (or changes) contract's parameters. It is called after deployment of the contract
     * and every time one of the parameters changes.
     */
    function setParameters(
        uint256 _votingDelaySeconds,
        uint256 _votingPeriodSeconds,
        uint256 _thresholdConditionBIPS,
        uint256 _majorityConditionBIPS,
        uint256 _proposalFeeValueWei,
        uint256 _addAfterRewardedEpochs,
        uint256 _addAfterNotChilledEpochs,
        uint256 _removeAfterNotRewardedEpochs,
        uint256 _removeAfterEligibleProposals,
        uint256 _removeAfterNonParticipatingProposals,
        uint256 _removeForDays
    )
    external;

    /**
     * @notice Cancels an existing proposal
     * @param _proposalId           Unique identifier of a proposal
     * @notice Emits a ProposalCanceled event
     */
    function cancel(uint256 _proposalId) external;

    /**
     * @notice Creates a new proposal
     * @param _description          String description of the proposal
     * @return _proposalId          Unique identifier of the proposal
     * @notice Emits a FtsoProposalCreated event
     */
    function propose(
        string memory _description
    ) external payable returns (uint256);

    /**
     * @notice Casts a vote on a proposal
     * @param _proposalId           Id of the proposal
     * @param _support              A value indicating vote type (against, for)
     * @notice Emits a VoteCast event
     */
    function castVote(uint256 _proposalId, uint8 _support) external;

    /**
     * @notice Changes list of management group members
     * @param _providersToAdd       Array of addresses to add to the list
     * @param _providersToRemove    Array of addresses to remove from the list
     * @notice This operation can only be performed through a maintainer
     * (mostly used for manually adding KYCed providers)
     */
    function changeManagementGroupMembers(
        address[] memory _providersToAdd,
        address[] memory _providersToRemove
    ) external;

    /**
     * @notice Sets a proxy voter for data provider (i.e. address that can vote in his name)
     * @param _proxyVoter           Address to register as a proxy (use address(0) to remove proxy)
     * @notice Emits a ProxyVoterSet event
     */
    function setProxyVoter(address _proxyVoter) external;

    /**
     * @notice Adds msg.sender to the management group
     */
    function addMember() external;

    /**
     * @notice Removes member from the management group
     * @param _account              Account to remove from the management group
     */
    function removeMember(address _account) external;

    /**
     * @notice Returns the current state of a proposal
     * @param _proposalId           Id of the proposal
     * @return ProposalState enum
     */
    function state(uint256 _proposalId) external view returns (ProposalState);

    /**
     * @notice Returns whether a voter has cast a vote on a specific proposal
     * @param _proposalId           Id of the proposal
     * @param _voter                Address of the voter
     * @return True if the voter has cast a vote on the proposal, and false otherwise
     */
    function hasVoted(uint256 _proposalId, address _voter) external view returns (bool);

    /**
     * @notice Returns information about the specified proposal
     * @param _proposalId               Id of the proposal
     * @return _description             Description of the proposal
     * @return _proposer                Address of the proposal submitter
     * @return _voteStartTime           Start time (in seconds from epoch) of the proposal voting
     * @return _voteEndTime             End time (in seconds from epoch) of the proposal voting
     * @return _thresholdConditionBIPS  Total number of cast votes, as a percentage in BIPS of the
     total vote power, required for the proposal to pass (quorum)
     * @return _majorityConditionBIPS   Number of FOR votes, as a percentage in BIPS of the
     total cast votes, requires for the proposal to pass
     * @return _noOfEligibleMembers     Number of members that are eligible to vote in the specified proposal
     */
    function getProposalInfo(
        uint256 _proposalId
    )
        external view
        returns (
            string memory _description,
            address _proposer,
            uint256 _voteStartTime,
            uint256 _voteEndTime,
            uint256 _thresholdConditionBIPS,
            uint256 _majorityConditionBIPS,
            uint256 _noOfEligibleMembers
        );

    /**
     * @notice Returns the description string that was supplied when the specified proposal was created
     * @param _proposalId           Id of the proposal
     * @return _description         Description of the proposal
     */
    function getProposalDescription(uint256 _proposalId) external view
        returns (string memory _description);

    /**
     * @notice Returns id and description of the last created proposal
     * @return _proposalId          Id of the last proposal
     * @return _description         Description of the last proposal
     */
    function getLastProposal() external view
        returns ( uint256 _proposalId, string memory _description);

    /**
     * @notice Returns number of votes for and against the specified proposal
     * @param _proposalId           Id of the proposal
     * @return _for                 Accumulated vote power for the proposal
     * @return _against             Accumulated vote power against the proposal
     */
    function getProposalVotes(
        uint256 _proposalId
    )
        external view
        returns (
            uint256 _for,
            uint256 _against
        );

    /**
     * @notice Returns list of current management group members
     * @return _list                List of management group members
     */
    function getManagementGroupMembers() external view returns (address[] memory _list);

    /**
     * @notice Returns whether an account can create proposals
     * @notice An address can make proposals if it is a member of the management group,
     * one of their proxies or the maintainer of the contract
     * @param _account              Address of a queried account
     * @return True if a queried account can propose, false otherwise
     */
    function canPropose(address _account) external view returns (bool);

    /**
     * @notice Returns whether an account can vote for a given proposal
     * @param _account              Address of the queried account
     * @param _proposalId           Id of the queried proposal
     * @return True if account is eligible to vote, and false otherwise
     */
    function canVote(address _account, uint256 _proposalId) external view returns (bool);

    /**
     * @notice Returns whether an account is member of the management group
     * @param _account              Address of the queried account
     * @return True if the queried account is member, false otherwise
     */
    function isMember(address _account) external view  returns (bool);
}
