// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;


/*
██████╗ ██╗   ██╗███╗   ██╗ █████╗ ███╗   ███╗██╗ ██████╗ █████╗ 
██╔══██╗╚██╗ ██╔╝████╗  ██║██╔══██╗████╗ ████║██║██╔════╝██╔══██╗
██║  ██║ ╚████╔╝ ██╔██╗ ██║███████║██╔████╔██║██║██║     ███████║
██║  ██║  ╚██╔╝  ██║╚██╗██║██╔══██║██║╚██╔╝██║██║██║     ██╔══██║
██████╔╝   ██║   ██║ ╚████║██║  ██║██║ ╚═╝ ██║██║╚██████╗██║  ██║
╚═════╝    ╚═╝   ╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝ ╚═════╝╚═╝  ╚═╝
*/

import {IERC20} from "../interfaces/IERC20.sol";
import {IDynamica} from "../interfaces/IDynamica.sol";
import {IHederaTokenService} from "hedera-smart-contracts/system-contracts/hedera-token-service/IHederaTokenService.sol";
import {HederaTokenService} from "@hashgraph/hedera-smart-contracts/contracts/system-contracts/hedera-token-service/HederaTokenService.sol";
import {HederaResponseCodes} from "@hashgraph/hedera-smart-contracts/contracts/system-contracts/HederaResponseCodes.sol";
import {KeyHelper} from "@hashgraph/hedera-smart-contracts/contracts/system-contracts/hedera-token-service/KeyHelper.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "forge-std/src/console.sol";
import "forge-std/src/Test.sol";
/**
 * @title MarketMaker
 * @dev A simple prediction market maker contract that allows users to buy and sell outcome tokens.
 *      Implements basic market making logic for binary and multi-outcome prediction markets.
 *      Integrates with Hedera Token Service for outcome token management.
 */
contract MarketMaker is Initializable, OwnableUpgradeable, HederaTokenService, IDynamica {
    /// @notice Maximum fee that can be set (100% in basis points)
    uint64 public constant FEE_RANGE = 10_000;

    /// @notice Array of payout numerators for each outcome
    uint256[] public payoutNumerators;
    /// @notice Payout denominator for calculating final payouts
    uint256 public payoutDenominator;
    /// @notice Address of the ERC20 collateral token
    address public collateralToken;
    /// @notice The question that this prediction market resolves
    string public question;
    /// @notice The fee rate in basis points (e.g., 300 = 3%)
    uint64 public fee;
    /// @notice Total fees received from trades
    uint256 public feeReceived;
    /// @notice Array of addresses for created outcome tokens
    address[] public outcomeTokenAddresses;
    /// @notice Array of supplies for each outcome token
    int256[] public outcomeTokenSupplies;
    /// @notice Decimals for outcome tokens
    int32 public decimals;
    /// @notice Address of the oracle manager that can resolve the market
    address public oracleManager;
    /// @notice Number of possible outcomes in the market
    uint256 public outcomeSlotCount;
    /// @notice Expiration time of the market
    uint32 public expirationTime;

    /// @notice Ensures the market is not yet resolved
    modifier marketNotResolved() {
        if (payoutDenominator != 0) {
            revert MarketAlreadyResolved();
        }
        _;
    }

    /// @notice Ensures the market is resolved
    modifier marketResolved() {
        if (payoutDenominator == 0) {
            revert MarketNotResolved();
        }
        _;
    }

    /// @notice Ensures only the oracle manager can call the function
    modifier onlyOracleManager() {
        if (oracleManager != msg.sender) {
            revert OnlyOracleManager(msg.sender);
        }
        _;
    }

    /**
     * @notice Initializes the market with funding and outcome configuration
     * @param oracle The oracle address that will resolve the condition
     * @param _question The question text that this market resolves
     * @param _outcomeSlotCount The number of possible outcomes
     * @param _startFunding The amount of funding to add to the market
     * @param _outcomeTokenAmounts The initial token amounts for each outcome
     * @param _decimals The decimals for the outcome tokens
     * @param tokens Array of HederaToken structs for each outcome
     * @dev Emits MarketInitialized and TokenCreated events
     */
    function initializeMarket(
        address oracle,
        string calldata _question,
        uint256 _outcomeSlotCount,
        uint256 _startFunding,
        int64 _outcomeTokenAmounts,
        int32 _decimals,
        IHederaTokenService.HederaToken[] memory tokens
    ) internal {
        oracleManager = oracle;
        question = _question;
        outcomeSlotCount = _outcomeSlotCount;
        payoutNumerators = new uint256[](_outcomeSlotCount);
        outcomeTokenAddresses = new address[](_outcomeSlotCount);
        outcomeTokenSupplies = new int256[](_outcomeSlotCount);
        if (!IERC20(collateralToken).transferFrom(msg.sender, address(this), _startFunding)) {
            revert TransferFailed();
        }
        decimals = _decimals;
        uint256 valuePerToken = msg.value / _outcomeSlotCount;
        address tokenAddress;
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            (, tokenAddress) = this.createToken{value: valuePerToken}(tokens[i], _outcomeTokenAmounts);
            outcomeTokenAddresses[i] = tokenAddress;
            outcomeTokenSupplies[i] = int256(_outcomeTokenAmounts);
            emit TokenCreated(tokenAddress, uint8(i));
        }
        emit MarketInitialized(msg.value, _question, _outcomeTokenAmounts);
    }

    /**
     * @notice Creates a new outcome token using Hedera Token Service
     * @param token HederaToken struct for the outcome
     * @param initialSupply Initial supply for the outcome token
     * @return responseCode Hedera response code
     * @return tokenAddress Address of the created token
     * @dev Emits TokenCreated event
     */
    function createToken(IHederaTokenService.HederaToken memory token, int64 initialSupply)
        public
        payable
        onlyInitializing
        returns (int256 responseCode, address tokenAddress)
    {
        token.treasury = address(this);
        token.expiry.autoRenewAccount = address(this);
        token.tokenKeys = new IHederaTokenService.TokenKey[](1);
        IHederaTokenService.TokenKey memory supplyKey = IHederaTokenService.TokenKey({
            keyType: 16,
            key: IHederaTokenService.KeyValue({
                inheritAccountKey: false,
                contractId: address(this),
                ed25519: "",
                ECDSA_secp256k1: "",
                delegatableContractId: address(0)
            })
        });
        token.tokenKeys[0] = supplyKey;
        (responseCode, tokenAddress) = createFungibleToken(token, initialSupply, decimals);
        if (responseCode != HederaResponseCodes.SUCCESS) {
            revert FailedToCreateToken();
        }
    }

    /**
     * @notice Makes a prediction by buying or selling outcome tokens
     * @param deltaOutcomeAmounts_ Array of token amount changes for each outcome
     *        Positive values = buying tokens, Negative values = selling tokens
     * @dev Emits OutcomeTokenTrade event
     */
    function makePrediction(int64[] calldata deltaOutcomeAmounts_) external marketNotResolved {
        if (deltaOutcomeAmounts_.length != outcomeSlotCount) {
            revert InvalidDeltaOutcomeAmountsLength(deltaOutcomeAmounts_.length, outcomeSlotCount);
        }
        _validateSellAmounts(deltaOutcomeAmounts_);
        int256 netCost = calcNetCost(deltaOutcomeAmounts_);
        bool isBuy = netCost > 0;
        uint256 cost = isBuy ? uint256(netCost) : uint256(-netCost);
        uint256 feeAmount = _handleTradePayment(cost, isBuy);
        _updateUserShares(deltaOutcomeAmounts_);
        emit OutcomeTokenTrade(msg.sender, deltaOutcomeAmounts_, netCost, feeAmount);
    }

    /**
     * @notice Closes the market by resolving the condition with payout ratios
     * @param payouts Array of payout numerators for each outcome
     * @dev Only callable by the oracle manager. Emits MarketResolved event.
     */
    function closeMarket(uint256[] calldata payouts) external onlyOracleManager marketNotResolved {
        uint256 _outcomeSlotCount = payouts.length;
        if (_outcomeSlotCount != outcomeSlotCount) {
            revert MustHaveExactlyOutcomeSlotCount(_outcomeSlotCount, outcomeSlotCount);
        }
        if (payoutNumerators.length != _outcomeSlotCount) {
            revert ConditionNotPreparedOrFound();
        }
        payoutDenominator = _calculatePayoutDenominator(payouts);
        if (payoutDenominator == 0) {
            revert PayoutIsAllZeroes();
        }
        uint256 totalPayout = 0;
        uint256 usersOutcomes = 0;
        for (uint256 i = 0; i < _outcomeSlotCount; i++) {
            if (payoutNumerators[i] != 0) {
                revert PayoutNumeratorAlreadySet(i);
            }
            payoutNumerators[i] = payouts[i];
            usersOutcomes = IERC20(outcomeTokenAddresses[i]).totalSupply()
                - getHtsBalanceERC20(outcomeTokenAddresses[i], address(this));
            totalPayout += (usersOutcomes * payoutNumerators[i]) / payoutDenominator;
        }
        _sendMarketsSharesToOwner(totalPayout);
        emit MarketResolved(msg.sender, payouts, payoutDenominator);
    }

    /**
     * @notice Redeems payout for resolved condition
     * @dev Calculates payout based on user's shares and resolved outcome ratios. Emits PayoutRedemption event.
     */
    function redeemPayout() external marketResolved {
        uint256 denominator = payoutDenominator;
        uint256[] memory shares = new uint256[](outcomeSlotCount);
        uint256 totalPayout = 0;
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            shares[i] = getHtsBalanceERC20(outcomeTokenAddresses[i], msg.sender);
            if (shares[i] == 0 || payoutNumerators[i] == 0) continue;
            if (shares[i] > 0 && payoutNumerators[i] > 0) {
                _burnToken(outcomeTokenAddresses[i], int64(uint64(shares[i])), msg.sender);
            }
            totalPayout += (shares[i] * payoutNumerators[i]) / denominator;
            shares[i] = 0;
        }
        if (totalPayout == 0) {
            revert NothingToRedeem();
        }
        if (!IERC20(collateralToken).transfer(msg.sender, totalPayout)) {
            revert TransferFailed();
        }
        emit PayoutRedemption(msg.sender, collateralToken, question, totalPayout);
    }

    /**
     * @notice Calculates the net cost for a trade
     * @param outcomeTokenAmounts Array of token amount changes
     * @return netCost The net cost of the trade (positive = user pays, negative = user receives)
     */
    function calcNetCost(int64[] memory outcomeTokenAmounts) public view virtual returns (int256) {
        // This function should be implemented by derived contracts
    }

    /**
     * @notice Changes the fee rate
     * @param _fee The new fee rate in basis points
     * @dev Only callable by owner. Emits FeeChanged event.
     */
    function changeFee(uint64 _fee) external onlyOwner {
        if (_fee >= FEE_RANGE) {
            revert FeeMustBeLessThanRange(_fee, FEE_RANGE);
        }
        fee = _fee;
        emit FeeChanged(block.timestamp, _fee);
    }

    /**
     * @notice Withdraws accumulated fees to the owner
     * @dev Only callable by owner. Emits FeeWithdrawal event.
     */
    function withdrawFee() external onlyOwner {
        if (feeReceived == 0) {
            revert NoFeesToWithdraw();
        }
        uint256 amount = feeReceived;
        feeReceived = 0;
        if (!IERC20(collateralToken).transfer(owner(), amount)) {
            revert FeeTransferFailed();
        }
        emit FeeWithdrawal(block.timestamp, amount);
    }

    /**
     * @notice Validates that user has enough shares to sell
     * @param deltaOutcomeAmounts_ Array of token amount changes
     * @dev Reverts if user does not have enough shares
     */
    function _validateSellAmounts(int64[] calldata deltaOutcomeAmounts_) private view {
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            if (deltaOutcomeAmounts_[i] < 0) {
                uint256 balance = getHtsBalanceERC20(outcomeTokenAddresses[i], msg.sender);
                uint256 amount = uint256(uint64(-deltaOutcomeAmounts_[i]));
                if (balance < amount) {
                    revert InsufficientSharesToSell(msg.sender, amount, balance);
                }
            }
        }
    }

    /**
     * @notice Handles payment processing for trades including fee calculation
     * @param netCost The net cost of the trade
     * @param isBuy True if the user is buying, false if selling
     * @return feeAmount The fee amount charged
     */
    function _handleTradePayment(uint256 netCost, bool isBuy) private returns (uint256 feeAmount) {
        if (isBuy) {
            uint256 shouldPay = (netCost * FEE_RANGE) / (FEE_RANGE - fee);
            feeAmount = shouldPay - netCost;
            feeReceived += feeAmount;
            if (!IERC20(collateralToken).transferFrom(msg.sender, address(this), netCost)) {
                revert TransferFailed();
            }
        } else {
            feeAmount = (netCost * fee) / FEE_RANGE;
            feeReceived += feeAmount;
            uint256 payoutAmount = netCost - feeAmount;
            if (!IERC20(collateralToken).transfer(msg.sender, payoutAmount)) {
                revert TransferFailed();
            }
        }
    }

    /**
     * @notice Updates user shares for each outcome
     * @param deltaOutcomeAmounts_ Array of token amount changes
     * @dev Mints or burns outcome tokens as needed
     */
    function _updateUserShares(int64[] calldata deltaOutcomeAmounts_) private {
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            if (deltaOutcomeAmounts_[i] > 0) {
                int64 mintAmount = deltaOutcomeAmounts_[i];
                outcomeTokenSupplies[i] += int256(mintAmount);
                _mintToken(outcomeTokenAddresses[i], mintAmount, msg.sender);
            } else if (deltaOutcomeAmounts_[i] < 0) {
                int64 burnAmount = -deltaOutcomeAmounts_[i];
                outcomeTokenSupplies[i] -= int256(burnAmount);
                _burnToken(outcomeTokenAddresses[i], burnAmount, msg.sender);
            }
        }
    }

    /**
     * @notice Burns tokens from a user
     * @param tokenAddress Address of the token
     * @param burnAmount Amount to burn
     * @param from Address to burn from
     * @dev Emits TokenBurned event
     */
    function _burnToken(address tokenAddress, int64 burnAmount, address from) internal {
        int64[] memory serialNumbersBytes = new int64[](0);
        int256 response = transferToken(tokenAddress, from, address(this), burnAmount);
        if (response != HederaResponseCodes.SUCCESS) {
            revert FailedToTransferToken();
        }
        (int256 responseCode,) = burnToken(tokenAddress, burnAmount, serialNumbersBytes);
        if (responseCode != HederaResponseCodes.SUCCESS) {
            revert FailedToBurnToken();
        }
        emit TokenBurned(from, tokenAddress, burnAmount);
    }

    /**
     * @notice Mints tokens to a user
     * @param tokenAddress Address of the token
     * @param mintAmount Amount to mint
     * @param to Address to mint to
     * @dev Emits TokenMinted event
     */
    function _mintToken(address tokenAddress, int64 mintAmount, address to) internal {
        bytes[] memory serialNumbersBytes = new bytes[](0);
        (int256 responseCode,,) = mintToken(tokenAddress, mintAmount, serialNumbersBytes);
        if (responseCode != HederaResponseCodes.SUCCESS) {
            revert FailedToMintToken();
        }
        int256 response = transferToken(tokenAddress, address(this), to, mintAmount);
        if (response != HederaResponseCodes.SUCCESS) {
            revert FailedToTransferToken();
        }
        emit TokenMinted(to, tokenAddress, mintAmount);
    }

    /**
     * @notice Calculates the payout denominator from payout numerators
     * @param payouts Array of payout numerators
     * @return denominator The calculated denominator
     */
    function _calculatePayoutDenominator(uint256[] calldata payouts) private pure returns (uint256 denominator) {
        for (uint256 i = 0; i < payouts.length; i++) {
            denominator += payouts[i];
        }
    }

    /**
     * @notice Sends remaining market shares to the owner after resolution
     * @param totalPayout The total payout amount
     * @dev Emits SendMarketsSharesToOwner event
     */
    function _sendMarketsSharesToOwner(uint256 totalPayout) private {
        uint256 returnToOwner = getHtsBalanceERC20(collateralToken, address(this)) - totalPayout;
        if (!IERC20(collateralToken).transfer(owner(), returnToOwner)) {
            revert TransferFailed();
        }
        emit SendMarketsSharesToOwner(block.timestamp, returnToOwner);
    }

    /**
     * @notice Returns the ERC20 balance for a given token and address
     * @param token Address of the token
     * @param to Address to check balance for
     * @return Balance of the token for the address
     */
    function getHtsBalanceERC20(address token, address to) public view returns (uint256) {
        return IERC20(token).balanceOf(to);
    }
}