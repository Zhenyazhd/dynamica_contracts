// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

import "./IDelegationAccount.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IClaimSetupManager {

    event DelegationAccountCreated(address owner, IDelegationAccount delegationAccount);
    event DelegationAccountUpdated(address owner, IDelegationAccount delegationAccount, bool enabled);
    event ClaimExecutorsChanged(address owner, address[] executors);
    event AllowedClaimRecipientsChanged(address owner, address[] recipients);
    event ClaimExecutorFeeValueChanged(address executor, uint256 validFromRewardEpoch, uint256 feeValueWei);
    event ExecutorRegistered(address executor);
    event ExecutorUnregistered(address executor, uint256 validFromRewardEpoch);
    event MinFeeSet(uint256 minFeeValueWei);
    event MaxFeeSet(uint256 maxFeeValueWei);
    event RegisterExecutorFeeSet(uint256 registerExecutorFeeValueWei);
    event SetExecutorsExcessAmountRefunded(address owner, uint256 excessAmount);

    /**
     * @notice Sets the addresses of executors and optionally enables (creates) delegation account.
     * @notice If setting registered executors some fee must be paid to them.
     * @param _executors        The new executors. All old executors will be deleted and replaced by these.
     */
    function setAutoClaiming(address[] memory _executors, bool _enableDelegationAccount) external payable;

    /**
     * @notice Sets the addresses of executors.
     * @notice If setting registered executors some fee must be paid to them.
     * @param _executors        The new executors. All old executors will be deleted and replaced by these.
     */ 
    function setClaimExecutors(address[] memory _executors) external payable;

    /**
     * Set the addresses of allowed recipients.
     * Apart from these, the owner is always an allowed recipient.
     * @param _recipients The new allowed recipients. All old recipients will be deleted and replaced by these.
     */    
    function setAllowedClaimRecipients(address[] memory _recipients) external;

    /**
     * @notice Enables (creates) delegation account contract,
     * i.e. all airdrop and ftso rewards will be send to delegation account when using automatic claiming.
     * @return Address of delegation account contract.
     */
    function enableDelegationAccount() external returns (IDelegationAccount);

    /**
     * @notice Disables delegation account contract,
     * i.e. all airdrop and ftso rewards will be send to owner's account when using automatic claiming.
     * @notice Automatic claiming will not claim airdrop and ftso rewards for delegation account anymore.
     * @dev Reverts if there is no delegation account
     */
    function disableDelegationAccount() external;

    /**
     * @notice Allows executor to register and set initial fee value.
     * If executor was already registered before (has fee set), only update fee after `feeValueUpdateOffset`.
     * @notice Executor must pay fee in order to register - `registerExecutorFeeValueWei`.
     * @param _feeValue    number representing fee value
     * @return Returns the reward epoch number when the setting becomes effective.
     */
    function registerExecutor(uint256 _feeValue) external payable returns (uint256);

    /**
     * @notice Allows executor to unregister.
     * @return Returns the reward epoch number when the setting becomes effective.
     */
    function unregisterExecutor() external returns (uint256);

    /**
     * @notice Allows registered executor to set (or update last scheduled) fee value.
     * @param _feeValue    number representing fee value
     * @return Returns the reward epoch number when the setting becomes effective.
     */
    function updateExecutorFeeValue(uint256 _feeValue) external returns(uint256);

    /**
     * @notice Delegate `_bips` of voting power to `_to` from msg.sender's delegation account
     * @param _to The address of the recipient
     * @param _bips The percentage of voting power to be delegated expressed in basis points (1/100 of one percent).
     *   Not cumulative - every call resets the delegation value (and value of 0 revokes delegation).
     */
    function delegate(address _to, uint256 _bips) external;

    /**
     * @notice Undelegate all percentage delegations from the msg.sender's delegation account and then delegate 
     *   corresponding `_bips` percentage of voting power to each member of `_delegatees`.
     * @param _delegatees The addresses of the new recipients.
     * @param _bips The percentages of voting power to be delegated expressed in basis points (1/100 of one percent).
     *   Total of all `_bips` values must be at most 10000.
     */
    function batchDelegate(address[] memory _delegatees, uint256[] memory _bips) external;

    /**
     * @notice Undelegate all voting power for delegates of msg.sender's delegation account
     */
    function undelegateAll() external;

    /**
     * @notice Revoke all delegation from msg.sender's delegation account to `_who` at given block. 
     *    Only affects the reads via `votePowerOfAtCached()` in the block `_blockNumber`.
     *    Block `_blockNumber` must be in the past. 
     *    This method should be used only to prevent rogue delegate voting in the current voting block.
     *    To stop delegating use delegate with value of 0 or undelegateAll.
     */
    function revokeDelegationAt(address _who, uint256 _blockNumber) external;

    /**
     * @notice Delegate all governance vote power of msg.sender's delegation account to `_to`.
     * @param _to The address of the recipient
     */
    function delegateGovernance(address _to) external;

    /**
     * @notice Undelegate governance vote power for delegate of msg.sender's delegation account
     */
    function undelegateGovernance() external;

    /**
     * @notice Allows user to transfer WNat to owner's account.
     * @param _amount           Amount of tokens to transfer
     */
    function withdraw(uint256 _amount) external;

    /**
     * @notice Allows user to transfer balance of ERC20 tokens owned by the personal delegation contract.
     The main use case is to transfer tokens/NFTs that were received as part of an airdrop or register 
     as participant in such airdrop.
     * @param _token            Target token contract address
     * @param _amount           Amount of tokens to transfer
     * @dev Reverts if target token is WNat contract - use method `withdraw` for that
     */
    function transferExternalToken(IERC20 _token, uint256 _amount) external;

    /**
     * @notice Gets the delegation account of the `_owner`. Returns address(0) if not created yet.
     */
    function accountToDelegationAccount(address _owner) external view returns (address);

    /**
     * @notice Gets the delegation account data for the `_owner`. Returns address(0) if not created yet.
     * @param _owner                        owner's address
     * @return _delegationAccount           owner's delegation account address - could be address(0)
     * @return _enabled                     indicates if delegation account is enabled
     */
    function getDelegationAccountData(
        address _owner
    )
        external view
        returns (IDelegationAccount _delegationAccount, bool _enabled);

    /**
     * @notice Get the addresses of executors.
     */    
    function claimExecutors(address _owner) external view returns (address[] memory);

    /**
     * Get the addresses of allowed recipients.
     * Apart from these, the owner is always an allowed recipient.
     */    
    function allowedClaimRecipients(address _rewardOwner) external view returns (address[] memory);

    /**
     * @notice Returns info if `_executor` is allowed to execute calls for `_owner`
     */
    function isClaimExecutor(address _owner, address _executor) external view returns(bool);

    /**
     * @notice Get registered executors
     */
    function getRegisteredExecutors(
        uint256 _start, 
        uint256 _end
    ) 
        external view
        returns (address[] memory _registeredExecutors, uint256 _totalLength);

    /**
     * @notice Returns some info about the `_executor`
     * @param _executor             address representing executor
     * @return _registered          information if executor is registered
     * @return _currentFeeValue     executor's current fee value
     */
    function getExecutorInfo(address _executor) external view returns (bool _registered, uint256 _currentFeeValue);

    /**
     * @notice Returns the current fee value of `_executor`
     * @param _executor             address representing executor
     */
    function getExecutorCurrentFeeValue(address _executor) external view  returns (uint256);

    /**
     * @notice Returns the fee value of `_executor` at `_rewardEpoch`
     * @param _executor             address representing executor
     * @param _rewardEpoch          reward epoch number
     */
    function getExecutorFeeValue(address _executor, uint256 _rewardEpoch) external view returns (uint256);

    /**
     * @notice Returns the scheduled fee value changes of `_executor`
     * @param _executor             address representing executor
     * @return _feeValue            positional array of fee values
     * @return _validFromEpoch      positional array of reward epochs the fee settings are effective from
     * @return _fixed               positional array of boolean values indicating if settings are subjected to change
     */
    function getExecutorScheduledFeeValueChanges(address _executor)
        external view
        returns (
            uint256[] memory _feeValue,
            uint256[] memory _validFromEpoch,
            bool[] memory _fixed
        );
}
