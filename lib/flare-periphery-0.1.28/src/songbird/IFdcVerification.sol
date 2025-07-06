// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

import "./IRelay.sol";
import "./IAddressValidityVerification.sol";
import "./IBalanceDecreasingTransactionVerification.sol";
import "./IConfirmedBlockHeightExistsVerification.sol";
import "./IEVMTransactionVerification.sol";
import "./IPaymentVerification.sol";
import "./IReferencedPaymentNonexistenceVerification.sol";
import "./IWeb2JsonVerification.sol";

/**
 * FdcVerification interface.
 */
interface IFdcVerification is
  IAddressValidityVerification,
  IBalanceDecreasingTransactionVerification,
  IConfirmedBlockHeightExistsVerification,
  IEVMTransactionVerification,
  IPaymentVerification,
  IReferencedPaymentNonexistenceVerification,
  IWeb2JsonVerification
{
  /**
   * The FDC protocol id.
   */
  function fdcProtocolId() external view returns (uint8 _fdcProtocolId);

  /**
   * Relay contract address.
   */
  function relay() external view returns (IRelay);
}
