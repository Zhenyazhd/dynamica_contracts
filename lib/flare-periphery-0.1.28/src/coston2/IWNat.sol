// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

interface IWNat {
    /**
     * @notice Deposit native token and mint WNAT ERC20.
     */
    function deposit() external payable;

    /**
     * @notice Withdraw native token and burn WNAT ERC20.
     * @param _amount The amount to withdraw.
     */
    function withdraw(uint256 _amount) external;
    
    /**
     * @notice Deposit native token from msg.sender and mint WNAT ERC20.
     * @param _recipient An address to receive minted WNAT.
     */
    function depositTo(address _recipient) external payable;
    
    /**
     * @notice Withdraw WNAT from an owner and send NAT to msg.sender given an allowance.
     * @param _owner An address spending the native tokens.
     * @param _amount The amount to spend.
     *
     * Requirements:
     *
     * - `_owner` must have a balance of at least `_amount`.
     * - the caller must have allowance for `_owners`'s tokens of at least
     * `_amount`.
     */
    function withdrawFrom(address _owner, uint256 _amount) external;
}
