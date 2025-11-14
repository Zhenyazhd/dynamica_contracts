// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IDynamica} from "./IDynamica.sol";
import {IMarketResolutionModule} from "./Oracles/IMarketResolutionModule.sol";

/**
 * @title IDynamicaFactory
 * @dev Interface for the DynamicaFactory contract that deploys Dynamica v2 prediction market makers
 * @notice This factory contract creates gas-efficient clones of the Dynamica v2 implementation using the minimal proxy pattern.
 *         It supports perpetual markets with continuous trading and automatic epoch transitions.
 *         The factory manages market creation, tracks all created markets, and handles oracle coordination.
 */
interface IDynamicaFactory {
    // ============ EVENTS ============

    /// @notice Emitted when a new market maker is created
    /// @param creator Address of the market creator
    /// @param marketMaker Address of the created market maker contract
    /// @param collateralToken Address of the collateral token used
    event FactoryMarketMakerCreated(
        address indexed creator, address indexed marketMaker, address indexed collateralToken
    );

    /// @notice Emitted when an address is granted permission to create markets
    /// @param account Address that was granted permission
    event MarketCreatorAdded(address indexed account);

    /// @notice Emitted when an address loses permission to create markets
    /// @param account Address that lost permission
    event MarketCreatorRemoved(address indexed account);

    /// @notice Emitted when a collateral token is added to the allowed list
    /// @param token Address of the collateral token that was added
    event AllowedCollateralTokenAdded(address indexed token);

    /// @notice Emitted when a collateral token is removed from the allowed list
    /// @param token Address of the collateral token that was removed
    event AllowedCollateralTokenRemoved(address indexed token);

    // ============ Errors ============

    /// @notice Thrown if the implementation address is invalid
    error InvalidImplementation();
    /// @notice Thrown if the resolution module implementation address is invalid
    error InvalidImplementationResolutionModuleChainlink();
    /// @notice Thrown if the LMSR math address is invalid
    error InvalidLMSRMathAddress();
    /// @notice Thrown if the oracle coordinator address is invalid
    error InvalidOracleCoordinator();
    /// @notice Thrown if the oracle coordinator is not set
    error OracleCoordinatorNotSet();
    /// @notice Thrown if the collateral token address is invalid
    error InvalidCollateralToken();
    /// @notice Thrown if the owner address is invalid
    error InvalidOwner();
    /// @notice Thrown if the fee is too high
    error FeeTooHigh(uint64 provided, uint64 max);
    /// @notice Thrown if funding must be positive
    error FundingMustBePositive();
    /// @notice Thrown if there must be more than one outcome
    error MustHaveMoreThanOneOutcome();
    /// @notice Thrown if outcome token amounts must be positive
    error OutcomeTokenAmountsMustBePositive();
    /// @notice Thrown if the question cannot be empty
    error QuestionCannotBeEmpty();
    /// @notice Thrown if alpha must be positive
    error AlphaMustBePositive();
    /// @notice Thrown if exp limit must be positive
    error ExpLimitMustBePositive();
    /// @notice Thrown if decimals must be at least 8
    error DecimalsMustBeAtLeast8(uint8 provided);
    /// @notice Thrown if gamma value is invalid
    error InvalidGammaValue(uint32 provided, uint64 max);
    /// @notice Thrown if epoch duration must be greater than period duration
    error EpochDurationMustBeGreaterThanPeriodDuration();
    /// @notice Thrown if period duration must be greater than 0
    error PeriodDurationMustBeGreaterThan0();
    /// @notice Thrown if the resolution module type is invalid
    error InvalidResolutionModuleType();
    /// @notice Thrown if a reentrant call is detected
    error ReentrancyGuardReentrantCall();
    /// @notice Thrown if the caller is not authorized to create markets
    error NotAuthorizedMarketCreator(address caller);
    /// @notice Thrown if the collateral token is not allowed
    error CollateralTokenNotAllowed(address token);

    /**
     * @notice Sets the oracle coordinator address (owner only)
     * @param _oracleCoordinator Address of the oracle coordinator
     */
    function setOracleCoordinator(address _oracleCoordinator) external;

    /**
     * @notice Grants permission to an address to create markets (owner only)
     * @param account Address to grant permission to
     */
    function addMarketCreator(address account) external;

    /**
     * @notice Revokes permission from an address to create markets (owner only)
     * @param account Address to revoke permission from
     */
    function removeMarketCreator(address account) external;

    /**
     * @notice Adds a collateral token to the allowed list (owner only)
     * @param token Address of the collateral token to allow
     */
    function addAllowedCollateralToken(address token) external;

    /**
     * @notice Removes a collateral token from the allowed list (owner only)
     * @param token Address of the collateral token to disallow
     */
    function removeAllowedCollateralToken(address token) external;

    // ============ EXTERNAL FUNCTIONS ============

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
    ) external returns (address cloneAddress);

    /**
     * @notice Returns all created market maker addresses
     * @return Array of market maker addresses
     */
    function getAllMarketMakers() external view returns (address[] memory);

    /**
     * @notice Returns the total number of created market makers
     * @return Number of market makers
     */
    function getMarketMakerCount() external view returns (uint256);

    /**
     * @notice Returns all market makers created by a specific address
     * @param creator Address of the creator
     * @return Array of market maker addresses created by the specified address
     */
    function getMarketMakersByCreator(address creator) external view returns (address[] memory);

    /**
     * @notice Returns the creator of a specific market maker
     * @param marketMaker Address of the market maker
     * @return Address of the market maker creator
     */
    function getMarketMakerCreator(address marketMaker) external view returns (address);

    /**
     * @notice Checks if an address is a valid market maker created by this factory
     * @param marketMaker Address to check
     * @return True if the address is a valid market maker
     */
    function isMarketMaker(address marketMaker) external view returns (bool);
}
