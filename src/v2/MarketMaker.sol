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
import {IMarketResolutionModule} from "../interfaces/IMarketResolutionModule.sol";
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
    uint256 public constant MAX_SLOT_COUNT = 10;
    /// @notice Maximum fee that can be set (100% in basis points)
    uint64 public constant FEE_RANGE = 10_000;
    
    /// @notice Gamma unit for calculations
    uint32 public constant GAMMA_UNIT = 10_000;
    
    /// @notice Unit decimal for calculations
    int256 public constant UNIT_DEC = 1e18;

    uint32 public epochDuration = 10 days;
    uint32 public periodDuration = 1 days;
    uint32 public currentPeriodNumber = 1;
    uint32 public currentEpochNumber = 1;
    
    /// @notice Collateral token decimals
    int256 public DEC_COLLATERAL;
    
    /// @notice Outcome token decimals
    int256 public DEC_Q;

    uint32[] public gammaPow;
  

    struct EpochData {
        uint32 epochStart;
        uint256 payoutDenominator;
        uint256[MAX_SLOT_COUNT] basePrice;
        uint256[MAX_SLOT_COUNT] payoutNumerators;
        int256[MAX_SLOT_COUNT] outcomeTokenSupplies; 
    }

    struct PeriodData {
        uint32 epochNumber;
        uint32 periodStart;
        int64[MAX_SLOT_COUNT] outcomeTokenAmounts;
        mapping(address => int64[MAX_SLOT_COUNT]) stakesByPeriod;
    }

    mapping(uint256 => EpochData) public epochData;
    // periodData[epochNumber][periodNumber]
    mapping(uint256 => mapping(uint256 => PeriodData)) public periodData;
       
    /// @notice Address of the ERC20 collateral token
    address public collateralToken;
    /// @notice The question that this prediction market resolves
    string public question;
    /// @notice The fee rate in basis points (e.g., 300 = 3%)
    uint64 public fee;
    /// @notice Total fees received from trades
    uint256 public feeReceived;
    /// @notice Array of addresses for created outcome tokens
    address[MAX_SLOT_COUNT] public outcomeTokenAddresses;
    /// @notice Array of supplies for each outcome token
    //int256[MAX_SLOT_COUNT] public outcomeTokenSupplies; // переносить из эпохи в эпоху? но сохранять награды юзера? 
    /// @notice Decimals for outcome tokens
    int32 public decimals;
    /// @notice Address of the oracle manager that can resolve the market
    address public oracleManager;
    /// @notice Number of possible outcomes in the market
    uint256 public outcomeSlotCount;
    /// @notice Expiration time of the market
    uint32 public expirationTime;

    /// @notice Ensures the market is not yet resolved
    modifier epochNotResolved(uint256 epoch) {
        if (epochData[epoch].payoutDenominator != 0) {
            revert MarketAlreadyResolved();
        }
        _;
    }

    /// @notice Ensures the market is resolved
    modifier epochResolved(uint256 epoch) {
        if (epochData[epoch].payoutDenominator == 0) {
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

        epochData[currentEpochNumber].epochStart = uint32(block.timestamp);
        periodData[currentPeriodNumber][currentEpochNumber].epochNumber = currentEpochNumber;
        periodData[currentPeriodNumber][currentEpochNumber].periodStart = uint32(block.timestamp);
     
        if (!IERC20(collateralToken).transferFrom(msg.sender, address(this), _startFunding)) {
            revert TransferFailed();
        }
        decimals = _decimals;
        
        // Initialize decimal constants
        uint8 collateralTokenDecimals = IERC20(collateralToken).decimals();
        DEC_COLLATERAL = int256(10 ** collateralTokenDecimals);
        DEC_Q = int256(10 ** uint32(_decimals));
        
        uint256 valuePerToken = msg.value / _outcomeSlotCount;
        address tokenAddress;
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            (, tokenAddress) = this.createToken{value: valuePerToken}(tokens[i], _outcomeTokenAmounts);
            outcomeTokenAddresses[i] = tokenAddress;
            epochData[currentEpochNumber].outcomeTokenSupplies[i] = int256(_outcomeTokenAmounts);
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
    function makePrediction(int64[] memory deltaOutcomeAmounts_) external epochNotResolved(currentEpochNumber) {
        PeriodData storage pd = periodData[currentEpochNumber][currentPeriodNumber];
        _updateEpochAndPeriod();
        if (deltaOutcomeAmounts_.length != outcomeSlotCount) {
            revert InvalidDeltaOutcomeAmountsLength(deltaOutcomeAmounts_.length, outcomeSlotCount);
        }
        _validateSellAmounts(pd, deltaOutcomeAmounts_);
        int256 netCost = calcNetCost(deltaOutcomeAmounts_);
        bool isBuy = netCost > 0;
        uint256 cost = isBuy ? uint256(netCost) : uint256(-netCost);
        _updateUserShares(pd,deltaOutcomeAmounts_);
        uint256 feeAmount = _handleTradePayment(cost, isBuy);
        emit OutcomeTokenTrade(msg.sender, deltaOutcomeAmounts_, netCost, feeAmount);
    }

    function payoutNumerators(uint256 i) external view returns (uint256) {
        return epochData[currentEpochNumber-1].payoutNumerators[i];
    }

    function payoutDenominator() external view returns (uint256) {
        return epochData[currentEpochNumber-1].payoutDenominator;
    }

    function outcomeTokenSupplies(uint256 i) external view returns (int256) {
        return epochData[currentEpochNumber].outcomeTokenSupplies[i];
    }

    /**
     * @notice Closes the market by resolving the condition with payout ratios
     * @param payouts Array of payout numerators for each outcome
     * @dev Only callable by the oracle manager. Emits epochResolved event.
     */
    function closeMarket(uint256[] calldata payouts) external onlyOracleManager epochNotResolved(currentEpochNumber) {
        uint256 _outcomeSlotCount = payouts.length;
        if (_outcomeSlotCount != outcomeSlotCount) {
            revert MustHaveExactlyOutcomeSlotCount(_outcomeSlotCount, outcomeSlotCount);
        }
        if (epochData[currentEpochNumber].payoutNumerators.length != _outcomeSlotCount) {
            revert ConditionNotPreparedOrFound();
        }
        uint256 payoutDenominator_ = _calculatePayoutDenominator(payouts);
        if (epochData[currentEpochNumber].payoutDenominator == 0) {
            revert PayoutIsAllZeroes();
        }
        epochData[currentEpochNumber].payoutDenominator = payoutDenominator_;


        uint256[] memory totalWeightedShares = new uint256[](_outcomeSlotCount);
        uint256 l = epochDuration/periodDuration;
        for (uint256 i = 1; i <= l; i++) {
            for (uint256 j = 0; j < outcomeSlotCount; j++) {
                if(periodData[currentEpochNumber][i].outcomeTokenAmounts.length != 0){
                    totalWeightedShares[j] += ((uint64(periodData[currentEpochNumber][i].outcomeTokenAmounts[j])*gammaPow[i-1]) / GAMMA_UNIT);
                }
            }
        }

        uint256 totalPayout = 0;
        for (uint256 i = 0; i < _outcomeSlotCount; i++) {
            if (epochData[currentEpochNumber].payoutNumerators[i] != 0) {
                revert PayoutNumeratorAlreadySet(i);
            }
            epochData[currentEpochNumber].payoutNumerators[i] = payouts[i];
            if(totalWeightedShares[i] != 0){
                uint256 totalPayout_i = (totalWeightedShares[i] * payouts[i]) / payoutDenominator_;
                totalPayout += totalPayout_i;
                if(totalWeightedShares[i] != 0) {
                    epochData[currentEpochNumber].basePrice[i] = (totalPayout_i * uint256(DEC_COLLATERAL))/ totalWeightedShares[i];
                }
            }
        }
        //_sendMarketsSharesToOwner(totalPayout);
        emit MarketResolved(msg.sender, payouts, epochData[currentEpochNumber].payoutDenominator);
    }

    /**
     * @notice Redeems payout for resolved condition
     * @dev Calculates payout based on user's shares and resolved outcome ratios. Emits PayoutRedemption event.
     */
    function redeemPayout() external epochResolved(currentEpochNumber) {
        uint256 totalPayout = 0;
        int64 shares = 0;
        uint256 l = epochDuration/periodDuration;
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            shares = 0;
            for (uint256 j = 1; j <= l; j++) {
                if(periodData[currentEpochNumber][j].stakesByPeriod[msg.sender].length > 0){
                    shares += periodData[currentEpochNumber][j].stakesByPeriod[msg.sender][i];
                    totalPayout += (uint64(periodData[currentEpochNumber][j].stakesByPeriod[msg.sender][i])*gammaPow[j-1]*epochData[currentEpochNumber].basePrice[i] / uint256(DEC_Q)) / GAMMA_UNIT;
                }
            }
            if (shares > 0) {
                _burnToken(outcomeTokenAddresses[i], int64(uint64(shares)), msg.sender);
            }
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
    function _validateSellAmounts(PeriodData storage pd, int64[] memory deltaOutcomeAmounts_) private view {
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            if (deltaOutcomeAmounts_[i] < 0) {
                int64 balance = pd.stakesByPeriod[msg.sender][i];
                int64 amount = -deltaOutcomeAmounts_[i];
                if (balance < amount) {
                    revert InsufficientSharesToSell_(msg.sender, amount, balance);
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
    function _updateUserShares(PeriodData storage pd, int64[] memory deltaOutcomeAmounts_) private {
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            int64 deltaOutcomeAmount = deltaOutcomeAmounts_[i];
            epochData[currentEpochNumber].outcomeTokenSupplies[i] += int256(deltaOutcomeAmount);
            pd.outcomeTokenAmounts[i] += deltaOutcomeAmount;
            pd.stakesByPeriod[msg.sender][i] += deltaOutcomeAmount;
            if (deltaOutcomeAmounts_[i] > 0) {
                _mintToken(outcomeTokenAddresses[i], deltaOutcomeAmounts_[i], msg.sender);
            } else if (deltaOutcomeAmounts_[i] < 0) {
                _burnToken(outcomeTokenAddresses[i], -deltaOutcomeAmounts_[i], msg.sender);
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

    function _updateEpochAndPeriod() public {       
        uint32 now32 = uint32(block.timestamp);
        uint32 newEpoch = 0;
        if (now32 >= epochData[currentEpochNumber].epochStart + epochDuration) {
            newEpoch = (now32 - epochData[currentEpochNumber].epochStart) / epochDuration;
            currentEpochNumber += newEpoch;
            epochData[currentEpochNumber].epochStart = now32;
            currentPeriodNumber = 1; 
            periodData[currentEpochNumber][currentPeriodNumber].periodStart = now32;
            periodData[currentPeriodNumber][currentEpochNumber].epochNumber = currentEpochNumber;
        }
        if(newEpoch == 0 && now32 >= periodData[currentEpochNumber][currentPeriodNumber].periodStart + periodDuration) {
            uint32 currentPeriod = (now32 - periodData[currentEpochNumber][currentPeriodNumber].periodStart) / periodDuration;
            currentPeriodNumber += currentPeriod;
            periodData[currentEpochNumber][currentPeriodNumber].periodStart = now32;
            periodData[currentPeriodNumber][currentEpochNumber].epochNumber = currentEpochNumber;
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