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

import {Clones} from "@openzeppelin-contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Dynamica} from "./Dynamica.sol";
import {IDynamica} from "./interfaces/IDynamica.sol";
import {IDynamicaFactory} from "./interfaces/IDynamicaFactory.sol";
import {MarketResolutionManager} from "./Oracles/MarketResolutionManager.sol";
import {ChainlinkResolutionModule} from "./Oracles/Hedera/ChainlinkResolutionModule.sol";
import {IMarketResolutionModule} from "./interfaces/Oracles/IMarketResolutionModule.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin-contracts/proxy/beacon/BeaconProxy.sol";

/**
 * @title DynamicaFactory
 * @dev Implementation of IDynamicaFactory for deploying Dynamica v2 prediction market makers
 * @notice This contract implements the factory pattern using minimal proxy clones for gas efficiency.
 *         For detailed documentation, see {IDynamicaFactory}.
 */
contract DynamicaFactory is Ownable, IDynamicaFactory {
    using SafeERC20 for IERC20;

    // ============ STATE VARIABLES ============

    /// @notice Beacon contract for Dynamica v2 market makers
    UpgradeableBeacon public immutable BEACON;

    /// @notice Address of the LMSR math contract
    address public immutable LMSR_MATH_ADDRESS;

    /// @notice Implementation contract for Chainlink resolution modules
    address public immutable IMPLEMENTATION_RESOLUTION_MODULE_CHAINLINK;

    /// @notice Maximum fee that can be set (100% = 10,000 basis points)
    uint64 public constant FEE_RANGE = 10_000;

    /// @notice Array of all created market maker addresses
    address[] public marketMakers;

    /// @notice Address of the oracle coordinator that manages market resolution
    address public oracleCoordinator;

    /// @notice Mapping from market maker address to its creator
    mapping(address => address) public marketMakerCreators;

    /// @notice Mapping from creator address to array of their created market makers
    mapping(address => address[]) public creatorMarketMakers;

    /// @notice Mapping from address to whether it is authorized to create markets
    mapping(address => bool) public authorizedMarketCreators;

    /// @notice Mapping from collateral token address to whether it is allowed
    mapping(address => bool) public allowedCollateralTokens;

    /// @notice Reentrancy guard status (1 = locked, 0 = unlocked)
    uint256 private _status;

    // ============ MODIFIERS ============

    /// @notice Prevents reentrant calls
    modifier nonReentrant() {
        if (_status == 1) {
            revert ReentrancyGuardReentrantCall();
        }
        _status = 1;
        _;
        _status = 0;
    }

    // ============ CONSTRUCTOR ============

    /**
     * @notice Initializes the factory with implementation contracts
     * @param _implementationMarketMaker Address of the Dynamica v2 implementation
     * @param _implementationResolutionModuleChainlink Address of Chainlink resolution module implementation
     * @param _owner Address of the factory owner
     * @param _lmsrMathAddress Address of the LMSR math contract
     * @dev See {IDynamicaFactory} for interface documentation
     */
    constructor(
        address _implementationMarketMaker,
        address _implementationResolutionModuleChainlink,
        address _owner,
        address _lmsrMathAddress
    ) Ownable(_owner) {
        if (_implementationMarketMaker == address(0)) {
            revert InvalidImplementation();
        }
        if (_implementationResolutionModuleChainlink == address(0)) {
            revert InvalidImplementationResolutionModuleChainlink();
        }
        if (_lmsrMathAddress == address(0)) {
            revert InvalidLMSRMathAddress();
        }

        BEACON = new UpgradeableBeacon(_implementationMarketMaker, _owner);

        IMPLEMENTATION_RESOLUTION_MODULE_CHAINLINK = _implementationResolutionModuleChainlink;
        LMSR_MATH_ADDRESS = _lmsrMathAddress;
        authorizedMarketCreators[_owner] = true;
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @notice Sets the oracle coordinator address (owner only)
     * @param _oracleCoordinator Address of the oracle coordinator
     * @dev See {IDynamicaFactory-setOracleCoordinator}
     */
    function setOracleCoordinator(address _oracleCoordinator) external onlyOwner {
        if (_oracleCoordinator == address(0)) {
            revert InvalidOracleCoordinator();
        }
        oracleCoordinator = _oracleCoordinator;
    }

    /**
     * @notice Grants permission to an address to create markets (owner only)
     * @param account Address to grant permission to
     * @dev See {IDynamicaFactory-addMarketCreator}
     */
    function addMarketCreator(address account) external onlyOwner {
        if (account == address(0)) {
            revert InvalidOwner();
        }
        if (authorizedMarketCreators[account]) {
            return;
        }
        authorizedMarketCreators[account] = true;
        emit MarketCreatorAdded(account);
    }

    /**
     * @notice Revokes permission from an address to create markets (owner only)
     * @param account Address to revoke permission from
     * @dev See {IDynamicaFactory-removeMarketCreator}
     */
    function removeMarketCreator(address account) external onlyOwner {
        if (!authorizedMarketCreators[account]) {
            return;
        }
        authorizedMarketCreators[account] = false;
        emit MarketCreatorRemoved(account);
    }

    /**
     * @notice Adds a collateral token to the allowed list (owner only)
     * @param token Address of the collateral token to allow
     * @dev See {IDynamicaFactory-addAllowedCollateralToken}
     */
    function addAllowedCollateralToken(address token) external onlyOwner {
        if (token == address(0)) {
            revert InvalidCollateralToken();
        }
        if (allowedCollateralTokens[token]) {
            return;
        }
        allowedCollateralTokens[token] = true;
        emit AllowedCollateralTokenAdded(token);
    }

    /**
     * @notice Removes a collateral token from the allowed list (owner only)
     * @param token Address of the collateral token to disallow
     * @dev See {IDynamicaFactory-removeAllowedCollateralToken}
     */
    function removeAllowedCollateralToken(address token) external onlyOwner {
        if (!allowedCollateralTokens[token]) {
            return;
        }
        allowedCollateralTokens[token] = false;
        emit AllowedCollateralTokenRemoved(token);
    }

    /**
     * @notice Checks if a collateral token is allowed
     * @param token Address of the collateral token to check
     * @return True if the token is allowed
     * @dev See {IDynamicaFactory-isAllowedCollateralToken}
     */
    function isAllowedCollateralToken(address token) external view returns (bool) {
        return allowedCollateralTokens[token];
    }

    // ============ PUBLIC FUNCTIONS ============

    /**
     * @notice Creates a new Dynamica v2 market maker with specified configuration
     * @param config Configuration for the market maker
     * @param resolutionConfig Configuration for the resolution module
     * @return market Address of the created market maker
     * @dev See {IDynamicaFactory-createMarketMaker} for detailed documentation
     */
    function createMarketMaker(
        IDynamica.Config memory config,
        IMarketResolutionModule.MarketResolutionConfig memory resolutionConfig
    ) external nonReentrant returns (address market) {
        address creator = msg.sender;
        // Validate caller is authorized to create markets
        if (!authorizedMarketCreators[creator]) revert NotAuthorizedMarketCreator(creator);

        // Validate oracle coordinator is set
        if (oracleCoordinator == address(0)) revert OracleCoordinatorNotSet();

        // Validate resolution configuration
        if (resolutionConfig.resolutionModuleType != IMarketResolutionModule.ResolutionModule.CHAINLINK) {
            revert InvalidResolutionModuleType();
        }

        // Validate market configuration
        _validateMarketConfig(config);

        IERC20(config.collateralToken).safeTransferFrom(creator, address(this), config.startFunding);

        config.oracle = oracleCoordinator;

        bytes memory initData = abi.encodeCall(Dynamica.initialize, (config, LMSR_MATH_ADDRESS));

        market = address(new BeaconProxy(address(BEACON), initData));

        IERC20(config.collateralToken).safeTransfer(market, config.startFunding);

        address resolutionModule = _createAndInitializeResolutionModule(resolutionConfig.resolutionModuleType);

        _registerMarketWithResolutionManager(
            config.question,
            market,
            config.outcomeSlotCount,
            resolutionModule,
            resolutionConfig.resolutionModuleType,
            resolutionConfig.resolutionData
        );

        marketMakers.push(market);
        marketMakerCreators[market] = creator;
        creatorMarketMakers[creator].push(market);

        emit FactoryMarketMakerCreated(creator, market, config.collateralToken);
    }

    /**
     * @notice Returns all created market maker addresses
     * @return Array of market maker addresses
     * @dev See {IDynamicaFactory-getAllMarketMakers}
     */
    function getAllMarketMakers() external view returns (address[] memory) {
        return marketMakers;
    }

    /**
     * @notice Returns the total number of created market makers
     * @return Number of market makers
     * @dev See {IDynamicaFactory-getMarketMakerCount}
     */
    function getMarketMakerCount() external view returns (uint256) {
        return marketMakers.length;
    }

    /**
     * @notice Returns all market makers created by a specific address
     * @param creator Address of the creator
     * @return Array of market maker addresses created by the specified address
     * @dev See {IDynamicaFactory-getMarketMakersByCreator}
     */
    function getMarketMakersByCreator(address creator) external view returns (address[] memory) {
        return creatorMarketMakers[creator];
    }

    /**
     * @notice Returns the creator of a specific market maker
     * @param marketMaker Address of the market maker
     * @return Address of the market maker creator
     * @dev See {IDynamicaFactory-getMarketMakerCreator}
     */
    function getMarketMakerCreator(address marketMaker) external view returns (address) {
        return marketMakerCreators[marketMaker];
    }

    /**
     * @notice Checks if an address is a valid market maker created by this factory
     * @param marketMaker Address to check
     * @return True if the address is a valid market maker
     * @dev See {IDynamicaFactory-isMarketMaker}
     */
    function isMarketMaker(address marketMaker) external view returns (bool) {
        return marketMakerCreators[marketMaker] != address(0);
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @notice Validates market configuration parameters
     * @param config The market configuration to validate
     * @dev Reverts if any parameter is invalid
     */
    function _validateMarketConfig(IDynamica.Config memory config) internal view {
        if (config.collateralToken == address(0)) {
            revert InvalidCollateralToken();
        }
        if (config.owner == address(0)) {
            revert InvalidOwner();
        }
        if (config.fee >= FEE_RANGE) {
            revert FeeTooHigh(config.fee, FEE_RANGE);
        }
        if (config.startFunding == 0) {
            revert FundingMustBePositive();
        }
        if (config.outcomeSlotCount <= 1) {
            revert MustHaveMoreThanOneOutcome();
        }
        if (config.outcomeTokenAmounts == 0) {
            revert OutcomeTokenAmountsMustBePositive();
        }
        if (bytes(config.question).length == 0) {
            revert QuestionCannotBeEmpty();
        }
        if (config.alpha <= 0) {
            revert AlphaMustBePositive();
        }
        if (config.expLimit <= 0) {
            revert ExpLimitMustBePositive();
        }
        if (config.decimals < 8) {
            revert DecimalsMustBeAtLeast8(config.decimals);
        }
        if (config.gamma == 0 || config.gamma > FEE_RANGE) {
            revert InvalidGammaValue(config.gamma, FEE_RANGE);
        }
        if (config.epochDuration <= config.periodDuration) {
            revert EpochDurationMustBeGreaterThanPeriodDuration();
        }
        if (config.periodDuration == 0) {
            revert PeriodDurationMustBeGreaterThan0();
        }
        if (!allowedCollateralTokens[config.collateralToken]) {
            revert CollateralTokenNotAllowed(config.collateralToken);
        }
    }

    /**
     * @notice Creates and initializes the appropriate resolution module based on type
     * @param resolutionModuleType Type of resolution module to create
     * @return resolutionModule Address of the created resolution module
     * @dev Supports Chainlink resolution modules
     */
    function _createAndInitializeResolutionModule(IMarketResolutionModule.ResolutionModule resolutionModuleType)
        private
        returns (address resolutionModule)
    {
        if (resolutionModuleType == IMarketResolutionModule.ResolutionModule.CHAINLINK) {
            resolutionModule = Clones.clone(IMPLEMENTATION_RESOLUTION_MODULE_CHAINLINK);
            ChainlinkResolutionModule(resolutionModule).initialize(oracleCoordinator);
        } else {
            revert InvalidResolutionModuleType();
        }
    }

    /**
     * @notice Registers the market with the resolution manager
     * @param question The market question text
     * @param marketMakerAddress Address of the market maker
     * @param outcomeSlotCount Number of possible outcomes
     * @param resolutionModule Address of the resolution module
     * @param resolutionModuleType Type of resolution module
     * @param resolutionData Encoded resolution data for the module
     * @dev This function registers the market with the oracle coordinator for resolution tracking
     */
    function _registerMarketWithResolutionManager(
        string memory question,
        address marketMakerAddress,
        uint256 outcomeSlotCount,
        address resolutionModule,
        IMarketResolutionModule.ResolutionModule resolutionModuleType,
        bytes memory resolutionData
    ) private {
        bytes32 questionHash;
        assembly {
            questionHash := keccak256(add(question, 0x20), mload(question))
        }
        MarketResolutionManager(oracleCoordinator).registerMarket(
            questionHash, marketMakerAddress, outcomeSlotCount, resolutionModule, resolutionModuleType, resolutionData
        );
    }
}
