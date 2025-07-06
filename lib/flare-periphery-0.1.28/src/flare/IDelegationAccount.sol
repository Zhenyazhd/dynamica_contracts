// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

import "./IClaimSetupManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IDelegationAccount {

    event DelegateFtso(address to, uint256 bips);
    event RevokeFtso(address to, uint256 blockNumber);
    event UndelegateAllFtso();
    event DelegateGovernance(address to);
    event UndelegateGovernance();
    event WithdrawToOwner(uint256 amount);
    event ExternalTokenTransferred(IERC20 token, uint256 amount);
    event ExecutorFeePaid(address executor, uint256 amount);
    event Initialize(address owner, IClaimSetupManager manager);
}
