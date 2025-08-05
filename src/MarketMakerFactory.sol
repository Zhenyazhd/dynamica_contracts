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

import {IERC20} from "./interfaces/IERC20.sol";
import {Clones} from "@openzeppelin-contracts/proxy/Clones.sol";
import {Dynamica} from "./Dynamica.sol";
import {IDynamica} from "./interfaces/IDynamica.sol";
import {MarketResolutionManager} from "./Oracles/MarketResolutionManager.sol";
import {ChainlinkResolutionModule} from "./Oracles/Hedera/ChainlinkResolutionModule.sol";
import {FTSOResolutionModule} from "./Oracles/Flare/FTSOResolutionModule.sol";
import {IMarketResolutionModule} from "./interfaces/IMarketResolutionModule.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";

/**
 * @title DynamicaFactory v2
 * @dev Factory contract for deploying Dynamica v2 prediction market makers using minimal proxy pattern
 * @notice This contract creates gas-efficient clones of the Dynamica v2 implementation.
 *         Supports perpetual markets with continuous trading and automatic epoch transitions.
 */
contract DynamicaFactory is Ownable, ReentrancyGuard {
    // ============ EVENTS ============

    /// @notice Emitted when a new market maker is created
    /// @param creator Address of the market creator
    /// @param marketMaker Address of the created market maker contract
    /// @param collateralToken Address of the collateral token used
    event FactoryMarketMakerCreated(
        address indexed creator, address indexed marketMaker, address indexed collateralToken
    );

    // ============ STATE VARIABLES ============

    /// @notice Implementation contract for Dynamica v2 market makers
    address public immutable IMPLEMENTATION_MARKET_MAKER;

    /// @notice Implementation contract for Chainlink resolution modules
    address public immutable IMPLEMENTATION_RESOLUTION_MODULE_CHAINLINK;

    /// @notice Implementation contract for FTSO resolution modules
    address public immutable IMPLEMENTATION_RESOLUTION_MODULE_FTSO;

    /// @notice Maximum fee that can be set (100% = 10,000 basis points)
    uint64 public constant FEE_RANGE = 10_000;

    /// @notice Array of all created market maker addresses
    address[] public marketMakers;

    /// @notice Address of the oracle coordinator that manages market resolution
    address public oracleCoordinator;

    /// @notice Address of the FTSO V2 contract for Flare network
    address public immutable FTSO_V2_ADDRESS;

    /// @notice Mapping from market maker address to its creator
    mapping(address => address) public marketMakerCreators;

    /// @notice Mapping from creator address to array of their created market makers
    mapping(address => address[]) public creatorMarketMakers;

    /// @notice Mapping from token address to boolean indicating if it is allowed
    mapping(address => bool) public allowedTokens;

    // ============ CONSTRUCTOR ============

    /**
     * @notice Initializes the factory with implementation contracts
     * @param _implementationMarketMaker Address of the Dynamica v2 implementation
     * @param _implementationResolutionModuleChainlink Address of Chainlink resolution module implementation
     * @param _implementationResolutionModuleFtso Address of FTSO resolution module implementation
     * @param _ftsoV2Address Address of the FTSO V2 contract
     * @param _owner Address of the factory owner
     */
    constructor(
        address _implementationMarketMaker,
        address _implementationResolutionModuleChainlink,
        address _implementationResolutionModuleFtso,
        address _ftsoV2Address,
        address _owner
    ) Ownable(_owner) {
        require(_implementationMarketMaker != address(0), "Invalid implementation");
        require(
            _implementationResolutionModuleChainlink != address(0), "Invalid implementation resolution module chainlink"
        );
        require(_implementationResolutionModuleFtso != address(0), "Invalid implementation resolution module ftso");
        require(_ftsoV2Address != address(0), "Invalid FTSO V2 address");

        IMPLEMENTATION_MARKET_MAKER = _implementationMarketMaker;
        IMPLEMENTATION_RESOLUTION_MODULE_CHAINLINK = _implementationResolutionModuleChainlink;
        IMPLEMENTATION_RESOLUTION_MODULE_FTSO = _implementationResolutionModuleFtso;
        FTSO_V2_ADDRESS = _ftsoV2Address;
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @notice Sets the oracle coordinator address (owner only)
     * @param _oracleCoordinator Address of the oracle coordinator
     */
    function setOracleCoordinator(address _oracleCoordinator) external onlyOwner {
        require(_oracleCoordinator != address(0), "Invalid oracle coordinator");
        oracleCoordinator = _oracleCoordinator;
    }

    // ============ PUBLIC FUNCTIONS ============

    /**
     * @notice Creates a new Dynamica v2 market maker with specified configuration
     * @param config Configuration for the market maker
     * @param resolutionConfig Configuration for the resolution module
     * @return cloneAddress Address of the created market maker clone
     * @dev This function:
     * 1. Validates all input parameters
     * 2. Transfers collateral tokens from creator to factory
     * 3. Creates a minimal proxy clone of the implementation
     * 4. Creates and initializes the appropriate resolution module
     * 5. Registers the market with the resolution manager
     * 6. Initializes the market maker with the provided configuration
     * 7. Records the creation for tracking purposes
     */
    function createMarketMaker(
        IDynamica.Config memory config,
        IMarketResolutionModule.MarketResolutionConfig memory resolutionConfig
    ) external onlyOwner nonReentrant returns (address cloneAddress) {
        // Validate market configuration
        _validateMarketConfig(config);

        // Validate resolution configuration
        _validateResolutionConfig(resolutionConfig);

        // Validate oracle coordinator is set
        require(oracleCoordinator != address(0), "Oracle coordinator not set");

        // Transfer collateral tokens from creator to factory
        require(
            IERC20(config.collateralToken).transferFrom(msg.sender, address(this), config.startFunding),
            "Transfer failed"
        );

        // Create minimal proxy clone
        cloneAddress = Clones.clone(IMPLEMENTATION_MARKET_MAKER);

        // Approve collateral tokens for the new market maker
        bool success = IERC20(config.collateralToken).approve(cloneAddress, config.startFunding);
        require(success, "Approval failed");

        // Create and initialize resolution module
        address resolutionModule = _createAndInitializeResolutionModule(resolutionConfig.resolutionModuleType);

        uint256[] memory interval;

        if (resolutionConfig.minPrice == resolutionConfig.maxPrice) {
            interval = new uint256[](0);
        } else {
            interval = new uint256[](2);
            interval[0] = resolutionConfig.minPrice;
            interval[1] = resolutionConfig.maxPrice;
        }

        // Register market with resolution manager
        _registerMarketWithResolutionManager(
            config.question,
            cloneAddress,
            config.outcomeSlotCount,
            resolutionModule,
            resolutionConfig.resolutionModuleType,
            resolutionConfig.resolutionData,
            interval
        );

        // Set oracle and initialize market maker
        config.oracle = oracleCoordinator;
        Dynamica(cloneAddress).initialize(config);

        // Record creation for tracking
        marketMakers.push(cloneAddress);
        marketMakerCreators[cloneAddress] = msg.sender;
        creatorMarketMakers[msg.sender].push(cloneAddress);

        emit FactoryMarketMakerCreated(msg.sender, cloneAddress, config.collateralToken);
    }

    /**
     * @notice Sets the allowed status for a token
     * @param token Address of the token
     * @param allowed Boolean indicating if the token is allowed
     */
    function setAllowedToken(address token, bool allowed) external onlyOwner {
        allowedTokens[token] = allowed;
    }

    /**
     * @notice Returns all created market maker addresses
     * @return Array of market maker addresses
     */
    function getAllMarketMakers() external view returns (address[] memory) {
        return marketMakers;
    }

    /**
     * @notice Returns the total number of created market makers
     * @return Number of market makers
     */
    function getMarketMakerCount() external view returns (uint256) {
        return marketMakers.length;
    }

    /**
     * @notice Returns all market makers created by a specific address
     * @param creator Address of the creator
     * @return Array of market maker addresses created by the specified address
     */
    function getMarketMakersByCreator(address creator) external view returns (address[] memory) {
        return creatorMarketMakers[creator];
    }

    /**
     * @notice Returns the creator of a specific market maker
     * @param marketMaker Address of the market maker
     * @return Address of the market maker creator
     */
    function getMarketMakerCreator(address marketMaker) external view returns (address) {
        return marketMakerCreators[marketMaker];
    }

    /**
     * @notice Checks if an address is a valid market maker created by this factory
     * @param marketMaker Address to check
     * @return True if the address is a valid market maker
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
        require(allowedTokens[config.collateralToken], "Invalid collateral token");
        require(config.owner != address(0), "Invalid owner");
        require(config.fee < FEE_RANGE, "Fee too high");
        require(config.startFunding > 0, "Funding must be positive");
        require(config.outcomeSlotCount > 1, "Must have more than one outcome");
        require(config.outcomeTokenAmounts > 0, "Outcome token amounts must be positive");
        require(bytes(config.question).length > 0, "Question cannot be empty");
        require(config.alpha > 0, "Alpha must be positive");
        require(config.expLimit > 0, "Exp limit must be positive");
        require(config.decimals >= 8, "Decimals must be at least 8");
        require(config.gamma > 0 && config.gamma <= FEE_RANGE, "Invalid gamma value");
        require(config.epochDuration > config.periodDuration, "Epoch duration must be greater than period duration");
        require(config.periodDuration > 0, "Period duration must be greater than 0");
    }

    /**
     * @notice Validates resolution configuration parameters
     * @param resolutionConfig The resolution configuration to validate
     * @dev Reverts if any parameter is invalid
     */
    function _validateResolutionConfig(IMarketResolutionModule.MarketResolutionConfig memory resolutionConfig)
        internal
        pure
    {
        require(
            resolutionConfig.resolutionModuleType == IMarketResolutionModule.ResolutionModule.CHAINLINK
                || resolutionConfig.resolutionModuleType == IMarketResolutionModule.ResolutionModule.FTSO,
            "Invalid resolution module type"
        );
    }

    /**
     * @notice Creates and initializes the appropriate resolution module based on type
     * @param resolutionModuleType Type of resolution module to create
     * @return resolutionModule Address of the created resolution module
     * @dev Supports Chainlink and FTSO resolution modules
     */
    function _createAndInitializeResolutionModule(IMarketResolutionModule.ResolutionModule resolutionModuleType)
        private
        returns (address resolutionModule)
    {
        if (resolutionModuleType == IMarketResolutionModule.ResolutionModule.CHAINLINK) {
            resolutionModule = Clones.clone(IMPLEMENTATION_RESOLUTION_MODULE_CHAINLINK);
            ChainlinkResolutionModule(resolutionModule).initialize(oracleCoordinator);
        } else if (resolutionModuleType == IMarketResolutionModule.ResolutionModule.FTSO) {
            resolutionModule = Clones.clone(IMPLEMENTATION_RESOLUTION_MODULE_FTSO);
            FTSOResolutionModule(resolutionModule).initialize(FTSO_V2_ADDRESS, oracleCoordinator);
        } else {
            revert("Invalid resolution module type");
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
     * @param interval Interval for the resolution module
     * @dev This function registers the market with the oracle coordinator for resolution tracking
     */
    function _registerMarketWithResolutionManager(
        string memory question,
        address marketMakerAddress,
        uint256 outcomeSlotCount,
        address resolutionModule,
        IMarketResolutionModule.ResolutionModule resolutionModuleType,
        bytes memory resolutionData,
        uint256[] memory interval
    ) private {
        MarketResolutionManager(oracleCoordinator).registerMarket(
            keccak256(bytes(question)),
            marketMakerAddress,
            outcomeSlotCount,
            resolutionModule,
            resolutionModuleType,
            resolutionData,
            interval
        );
    }
}
