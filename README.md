# Dynamica - Prediction Market System

## Overview

Dynamica is a decentralized prediction market system built on blockchain. The system uses the LMSR (Logarithmic Market Scoring Rule) algorithm to provide liquidity and automatic price discovery.

## System Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   DynamicaFactory │    │ MarketResolutionManager │    │   ResolutionModules   │
│                 │    │                  │    │                 │
│ - Creates markets│◄──►│ - Manages        │◄──►│ - Chainlink     │
│ - Manages       │    │   resolution     │    │ - FTSO          │
│   proxies       │    │ - Registers      │    │ - FDC           │
└─────────────────┘    │   markets        │    └─────────────────┘
         │              └──────────────────┘
         │                       │
         ▼                       ▼
┌─────────────────┐    ┌──────────────────┐
│   Dynamica      │    │   MarketMaker    │
│   (LMSR)        │    │   (Base)         │
│                 │    │                  │
│ - Price discovery│    │ - Base logic     │
│ - Calculations  │    │ - State          │
│ - Trading       │    │   management     │
└─────────────────┘    └──────────────────┘
```

## Contracts and Their Purpose

### 1. MarketMaker.sol
**Base contract for prediction markets**
- Manages market state (tokens, balances, payouts)
- Processes trading operations
- Manages market resolution and payouts
- Contains base logic for all market types

### 2. Dynamica.sol
**LMSR (Logarithmic Market Scoring Rule) implementation**
- Extends MarketMaker with LMSR algorithm
- Provides automatic price discovery
- Uses fixed-point arithmetic with 18 decimal places
- Prevents arbitrage opportunities

### 3. DynamicaFactory.sol
**Factory for creating markets**
- Creates minimal proxy clones for gas efficiency
- Manages market registration
- Supports various resolution module types
- Handles token transfers and approvals

### 4. MarketResolutionManager.sol
**Market resolution manager**
- Coordinates market resolution through various modules
- Registers markets with specific resolution modules
- Manages market resolution state

### 5. Resolution Modules
**Modules for market resolution**

#### ChainlinkResolutionModule.sol
- Uses Chainlink oracles to fetch data
- Supports multiple price feeds
- Validates data freshness

#### FTSOResolutionModule.sol
- Uses FTSO (Flare Time Series Oracle) for Flare network
- Fetches price data and other metrics

## Contract Interactions

### Market Creation
1. **DynamicaFactory** receives market configuration
2. Creates minimal proxy clone of **Dynamica**
3. Creates corresponding **ResolutionModule**
4. Registers market in **MarketResolutionManager**
5. Initializes **Dynamica** with initial funding

### Trading
1. User calls `makePrediction()` in **Dynamica**
2. **Dynamica** calculates cost through LMSR
3. **MarketMaker** processes payments and updates state
4. `OutcomeTokenTrade` event is emitted

### Market Resolution
1. **MarketResolutionManager** calls corresponding **ResolutionModule**
2. **ResolutionModule** fetches data from oracles
3. **MarketResolutionManager** calls `closeMarket()` in **Dynamica**
4. **MarketMaker** sets payout ratios
5. Users can redeem payouts via `redeemPayout()`

## Events

### MarketMaker Events
```solidity
// Events are defined in IDynamica interface
event MarketMakerCreated(uint256 initialFunding);
event startFunding(uint256 startFunding, uint256 outcomeTokenAmounts);
event FeeChanged(uint64 newFee);
event FeeWithdrawal(uint256 fees);
event OutcomeTokenTrade(
    address indexed trader,
    int256[] outcomeTokenAmounts,
    int256 outcomeTokenNetCost,
    uint256 marketFees
);
event ConditionPreparation(
    address indexed oracle,
    string indexed question,
    uint256 outcomeSlotCount
);
event PayoutRedemption(
    address indexed redeemer,
    IERC20 indexed collateralToken,
    bytes32 indexed parentCollectionId,
    bytes32 conditionId,
    uint256[] indexSets,
    uint256 payout
);
event SendMarketsSharesToOwner(uint256 returnToOwner);
```

### DynamicaFactory Events
```solidity
event MarketMakerCreated(
    address indexed creator,
    address indexed marketMaker,
    address indexed collateralToken
);
```

### MarketResolutionManager Events
```solidity
event MarketRegistered(
    bytes32 indexed questionId, 
    address indexed marketMaker, 
    address indexed resolutionModule
);
event MarketResolved(bytes32 indexed questionId, uint256[] payouts);
```

## Function and Variable Descriptions

### MarketMaker.sol

#### Constants
- `FEE_RANGE` (uint64): Maximum fee (100% = 10,000 basis points)

#### State Variables
- `payoutNumerators[]` (uint256[]): Payout numerators for each outcome
- `payoutDenominator` (uint256): Denominator for payout calculation
- `collateralToken` (IERC20): Collateral token for trading
- `question` (string): Question that the market resolves
- `fee` (uint64): Fee rate in basis points
- `funding` (uint256): Total market funding
- `feeReceived` (uint256): Total fees received
- `outcomeTokenAmounts[]` (uint256[]): Outcome token amounts in pool
- `usersOutcomes[]` (uint256[]): Total user outcome tokens for each outcome
- `oracleManager` (address): Oracle manager address
- `userShares` (mapping): Mapping of users to their shares
- `outcomeSlotCount` (uint256): Number of possible outcomes

#### Main Functions
- `initializeMarket()`: Initializes market with funding
- `makePrediction()`: Makes prediction (buy/sell outcome tokens)
- `closeMarket()`: Closes market with payout ratios
- `redeemPayout()`: Redeems payouts for resolved market
- `calcNetCost()`: Calculates net cost of trade
- `changeFee()`: Changes fee rate
- `withdrawFee()`: Withdraws accumulated fees

### Dynamica.sol

#### Constants
- `UNIT_DEC` (int256): Decimal precision (1e18)

#### State Variables
- `EXP_LIMIT_DEC` (SD59x18): Exponential limit to prevent overflow
- `alpha` (SD59x18): Liquidity parameter controlling market depth

#### Main Functions
- `initialize()`: Initializes Dynamica with configuration
- `calcMarginalPrice()`: Calculates current marginal price for outcome
- `calcNetCost()`: Calculates net cost of trade through LMSR
- `_marginalPriceFromMemory()`: Calculates price from given state
- `getB()`: Calculates liquidity parameter b
- `sumExp()`: Computes sum of exponentials with numerical stability

### DynamicaFactory.sol

#### State Variables
- `implementationMarketMaker` (address): Dynamica implementation contract
- `implementationResolutionModuleChainlink` (address): Chainlink module implementation
- `implementationResolutionModuleFTSO` (address): FTSO module implementation
- `marketMakers[]` (address[]): Array of all created markets
- `oracleCoordinator` (address): Oracle coordinator
- `ftsoV2Address` (address): FTSO V2 contract address
- `marketMakerCreators` (mapping): Mapping of market creators
- `creatorMarketMakers` (mapping): Mapping of creators to their markets

#### Main Functions
- `createMarketMaker()`: Creates new Dynamica market
- `setOracleCoordinator()`: Sets oracle coordinator
- `_createAndInitializeResolutionModule()`: Creates and initializes resolution module
- `_registerMarketWithResolutionManager()`: Registers market in resolution manager

### MarketResolutionManager.sol

#### State Variables
- `factory` (address): Factory address
- `marketConfigs` (mapping): Market configurations

#### Main Functions
- `registerMarket()`: Registers new market
- `resolveMarket()`: Resolves market through corresponding module

### Resolution Modules

#### ChainlinkResolutionModule.sol
- `resolveMarket()`: Resolves market using Chainlink oracles
- `_validateConfig()`: Validates configuration
- `_fetchAndProcessPrices()`: Fetches and processes prices
- `_normalizePayouts()`: Normalizes payouts
- `_adjustPayoutPrecision()`: Adjusts payout precision

#### FTSOResolutionModule.sol
- `resolveMarket()`: Resolves market using FTSO

## Modifiers

### MarketMaker
- `marketNotResolved`: Market not yet resolved
- `marketResolved`: Market is resolved
- `onlyOracleManager`: Only oracle manager

### MarketResolutionManager
- `onlyFactory`: Only factory

### Resolution Modules
- `onlyMarketResolutionManager`: Only market resolution manager

## Data Structures

### IDynamica.Config
```solidity
struct Config {
    address owner;
    address collateralToken;
    address oracle;
    string question;
    uint256 outcomeSlotCount;
    uint256 startFunding;
    uint256 outcomeTokenAmounts;
    uint64 fee;
    uint256 alpha;
    uint256 expLimit;
}
```

### IMarketResolutionModule.MarketResolutionConfig
```solidity
struct MarketResolutionConfig {
    address marketMaker;
    uint256 outcomeSlotCount;
    address resolutionModule;
    bytes resolutionData;
    bool isResolved;
    ResolutionModule resolutionModuleType;
}
```

### ChainlinkConfig
```solidity
struct ChainlinkConfig {
    address[] priceFeedAddresses;
    uint256[] staleness;
    uint8[] decimals;
}
```

## LMSR Algorithm

LMSR uses the following formula for price discovery:

```
π_i = exp(q_i/b) / Σ(exp(q_j/b))
```

where:
- `π_i` - price of outcome i
- `q_i` - amount of outcome i tokens
- `b = α * Σ(q_j)` - liquidity parameter
- `α` - alpha parameter controlling market depth

Cost function:
```
C(q) = b * ln(Σ exp(q_i/b))
```

Net cost of trade:
```
netCost = C(q_new) - C(q_old)
```

## Security

- All external calls are protected with checks
- Fixed-point arithmetic prevents overflow
- Exponential limits prevent overflow
- Access modifiers protect critical functions
- Input validation in all functions

## Gas Optimization

- Use of minimal proxy clones for gas efficiency
- Optimized algorithms for numerical computations
- Efficient state management
- Use of events for indexing

