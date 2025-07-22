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

import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Clones} from "@openzeppelin-contracts/proxy/Clones.sol";
import {Dynamica} from "./Dynamica.sol";
import {IDynamica} from "./interfaces/IDynamica.sol";
import {MarketMaker} from "./MarketMaker.sol";
import {MarketResolutionManager} from "./Oracles/MarketResolutionManager.sol";
import {ChainlinkResolutionModule} from "./Oracles/Hedera/ChainlinkResolutionModule.sol";
import {FTSOResolutionModule} from "./Oracles/Flare/FTSOResolutionModule.sol";
import {IMarketResolutionModule} from "./interfaces/IMarketResolutionModule.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";
import {IHederaTokenService} from "hedera-smart-contracts/system-contracts/hedera-token-service/IHederaTokenService.sol";
//import {DecimalsConverter} from "@solarity/solidity-lib/libs/utils/DecimalsConverter.sol";

import {console} from "forge-std/src/console.sol";

/**
 * @title DynamicaFactory
 * @dev Factory contract for deploying Dynamica prediction market makers using minimal proxy pattern
 * @notice This contract creates gas-efficient clones of the Dynamica implementation
 *
 * Features:
 * - Deploys minimal proxy clones for gas efficiency
 * - Supports multiple resolution module types (Chainlink, FTSO)
 * - Manages market maker registration and tracking
 * - Handles collateral token transfers and approvals
 */
contract DynamicaFactory is Ownable {
    // ============ Events ============

    /**
     * @notice Emitted when a new market maker is created
     * @param creator Address of the market creator
     * @param marketMaker Address of the created market maker contract
     * @param collateralToken Address of the collateral token used
     */
    event MarketMakerCreated(address indexed creator, address indexed marketMaker, address indexed collateralToken);

    // ============ Storage ============

    /// @notice Implementation contract for Dynamica market makers
    address public immutable implementationMarketMaker;

    /// @notice Implementation contract for Chainlink resolution modules
    address public immutable implementationResolutionModuleChainlink;

    /// @notice Implementation contract for FTSO resolution modules
    address public immutable implementationResolutionModuleFTSO;

    /// @notice Maximum fee that can be set (100% = 10,000 basis points)
    uint64 public constant FEE_RANGE = 10_000;

    /// @notice Array of all created market maker addresses
    address[] public marketMakers;

    /// @notice Address of the oracle coordinator that manages market resolution
    address public oracleCoordinator;

    /// @notice Address of the FTSO V2 contract for Flare network
    address public immutable ftsoV2Address;

    /// @notice Mapping from market maker address to its creator
    mapping(address => address) public marketMakerCreators;

    /// @notice Mapping from creator address to array of their created market makers
    mapping(address => address[]) public creatorMarketMakers;

    // ============ Constructor ============

    /**
     * @notice Initializes the factory with implementation contracts
     * @param _implementationMarketMaker Address of the Dynamica implementation
     * @param _implementationResolutionModuleChainlink Address of Chainlink resolution module implementation
     * @param _implementationResolutionModuleFTSO Address of FTSO resolution module implementation
     * @param _ftsoV2Address Address of the FTSO V2 contract
     * @param _owner Address of the factory owner
     */
    constructor(
        address _implementationMarketMaker,
        address _implementationResolutionModuleChainlink,
        address _implementationResolutionModuleFTSO,
        address _ftsoV2Address,
        address _owner
    ) Ownable(_owner) {
        require(_implementationMarketMaker != address(0), "Invalid implementation");
        require(
            _implementationResolutionModuleChainlink != address(0), "Invalid implementation resolution module chainlink"
        );
        require(_implementationResolutionModuleFTSO != address(0), "Invalid implementation resolution module ftso");

        implementationMarketMaker = _implementationMarketMaker;
        implementationResolutionModuleChainlink = _implementationResolutionModuleChainlink;
        implementationResolutionModuleFTSO = _implementationResolutionModuleFTSO;
        ftsoV2Address = _ftsoV2Address;
    }

    /**
     * @notice Sets the oracle coordinator address (owner only)
     * @param _oracleCoordinator Address of the oracle coordinator
     */
    function setOracleCoordinator(address _oracleCoordinator) external onlyOwner {
        require(_oracleCoordinator != address(0), "Invalid oracle coordinator");
        oracleCoordinator = _oracleCoordinator;
    }

    // ============ External Functions ============

    /**
     * @notice Creates a new Dynamica market maker with specified configuration
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
        IMarketResolutionModule.MarketResolutionConfig memory resolutionConfig,
        IHederaTokenService.HederaToken[] memory tokens
    ) external payable returns (address payable cloneAddress) {
        // Validate input parameters
        require(config.collateralToken != address(0), "Invalid token");
        require(config.owner != address(0), "Invalid owner");
        require(config.fee < FEE_RANGE, "Fee too high");
        require(config.oracle != address(0), "Invalid oracle address");
        require(config.startFunding != 0, "Funding change must be non-zero");
        require(config.outcomeSlotCount > 1, "Must have more than one outcome slot");
        require(config.outcomeTokenAmounts != 0, "Outcome token amounts must be non-zero");
        require(bytes(config.question).length > 0, "Question cannot be empty");
        require(config.alpha > 0, "Alpha must be positive");
        require(config.expLimit > 0, "Exp limit must be positive");

        require(tokens.length == config.outcomeSlotCount, "Tokens length must match outcomeSlotCount");
        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i].expiry.autoRenewAccount = config.owner;
            tokens[i].expiry.autoRenewPeriod = 5184000;
        }

        // Transfer collateral tokens from creator to factory
        require(
            IERC20(config.collateralToken).transferFrom(msg.sender, address(this), config.startFunding),
            "Transfer failed"
        );

        // Create minimal proxy clone
        cloneAddress = payable(Clones.clone(implementationMarketMaker));

        // Approve collateral tokens for the new market maker
        IERC20(config.collateralToken).approve(cloneAddress, config.startFunding);

        // Create and initialize the appropriate resolution module
        address resolutionModule = _createAndInitializeResolutionModule(resolutionConfig.resolutionModuleType);

        // Register market with resolution manager
        _registerMarketWithResolutionManager(
            config.question,
            cloneAddress,
            config.outcomeSlotCount,
            resolutionModule,
            resolutionConfig.resolutionModuleType,
            resolutionConfig.resolutionData
        );

        // Set oracle coordinator as the oracle for the market
        config.oracle = oracleCoordinator;

        // Initialize the market maker
        Dynamica(payable(cloneAddress)).initialize{value: msg.value}(config, tokens);

        // Record the creation
        marketMakers.push(cloneAddress);
        marketMakerCreators[cloneAddress] = msg.sender;
        creatorMarketMakers[msg.sender].push(cloneAddress);

        emit MarketMakerCreated(msg.sender, cloneAddress, config.collateralToken);
    }

    // ============ View Functions ============

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

    // ============ Private Functions ============

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
            // Create Chainlink resolution module clone
            resolutionModule = Clones.clone(implementationResolutionModuleChainlink);
            ChainlinkResolutionModule(resolutionModule).initialize(oracleCoordinator);
        } else if (resolutionModuleType == IMarketResolutionModule.ResolutionModule.FTSO) {
            // Create FTSO resolution module clone
            resolutionModule = Clones.clone(implementationResolutionModuleFTSO);
            FTSOResolutionModule(resolutionModule).initialize(ftsoV2Address, oracleCoordinator);
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
        MarketResolutionManager(oracleCoordinator).registerMarket(
            keccak256(bytes(question)),
            marketMakerAddress,
            outcomeSlotCount,
            resolutionModule,
            resolutionModuleType,
            resolutionData
        );
    }
}
