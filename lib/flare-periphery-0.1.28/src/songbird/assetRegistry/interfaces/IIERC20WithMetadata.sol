// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


/**
 * The methods of this interface are optional in ERC20 standard, so they are left out of IERC20 interface.
 * However, any sane implementation includes them, and they are mandatory for the tokens in FlareAssetRegistry.
 */
interface IIERC20WithMetadata is IERC20 {
    /**
     * Returns the name of the token.
     */
    function name() external view returns (string memory);    

    /**
     * Returns the symbol of the token, usually a shorter version of the name.
     */
    function symbol() external view returns (string memory);

    /**
     * Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei.
     *
     * NOTE: This information is only used for _display_ purposes: the methods
     * of the contract should always work with the smallest unit (e.g. wei).
     */
    function decimals() external view returns (uint8);
}
