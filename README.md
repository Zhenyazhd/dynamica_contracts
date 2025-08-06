# Dynamica - Perpetual Prediction Market System

## System Overview

Dynamica is a decentralized prediction market system built on the Ethereum blockchain. It uses the Logarithmic Market Scoring Rule (LMSR) for automatic price determination, supports continuous trading with automatic transitions between epochs, and enables participants to place bets on how the ratio between various continuous quantities evolves over time.

### Key Features:
- **Perpetual Markets**: Continuous markets without fixed end dates
- **LMSR Pricing**: Automatic price determination based on liquidity
- **Multi-Oracle Support**: Chainlink oracle support
- **Epoch-Based Trading**: Trading organized by epochs with automatic resolution at the end of each epoch
- **Time-Weighted Rewards**: Reward system based on prediction timing (early periods = higher weight)
- **Gas-Efficient**: Use of minimal proxies for gas optimization

## System Architecture

### Main Components:

```
Dynamica System
├── MarketMakerFactory.sol     # Factory for creating markets
├── Dynamica.sol              # Main market contract (LMSR)
├── MarketMaker.sol           # Base market contract
├── Interfaces/               # Interfaces and data structures
├── Oracles/                  # Oracle integration modules
│   ├── MarketResolutionManager.sol
│   ├── Hedera/ChainlinkResolutionModule.sol
│   └── Flare/FTSOResolutionModule.sol
└── MockTokenNew.sol          # Test token
```

## Detailed Contract Description

### 1. MarketMakerFactory.sol

**Purpose**: Factory for creating new prediction markets using the minimal proxy pattern.

**Key Functions**:

#### Market Creation
```solidity
function createMarketMaker(
    IDynamica.Config memory config,
    IMarketResolutionModule.MarketResolutionConfig memory resolutionConfig
) external onlyOwner nonReentrant returns (address cloneAddress)
```

**Configuration Parameters**:
- `owner`: Market owner
- `collateralToken`: Collateral token address (ERC20)
- `oracle`: Oracle address
- `question`: Market question
- `outcomeSlotCount`: Number of possible outcomes
- `startFunding`: Initial funding
- `outcomeTokenAmounts`: Number of tokens per outcome
- `fee`: Fee in basis points
- `alpha`: LMSR liquidity parameter
- `expLimit`: Exponent limit for numerical stability
- `expirationEpoch`: Expiration epoch (0 = perpetual)
- `gamma`: Time weighting parameter
- `epochDuration`: Epoch duration
- `periodDuration`: Period duration

#### Token Management
```solidity
function setAllowedToken(address token, bool allowed) external onlyOwner
```

#### Queries
```solidity
function getAllMarketMakers() external view returns (address[] memory)
function getMarketMakerCount() external view returns (uint256)
function getMarketMakersByCreator(address creator) external view returns (address[] memory)
function getMarketMakerCreator(address marketMaker) external view returns (address)
function isMarketMaker(address marketMaker) external view returns (bool)
```

### 2. Dynamica.sol

**Purpose**: Main prediction market contract implementing LMSR (Logarithmic Market Scoring Rule).

**Key Mathematical Functions**:

#### Marginal Price Calculation
```solidity
function calcMarginalPrice(uint256 outcomeTokenIndex) external view returns (int256)
```

**LMSR Algorithm**:
1. Quantity normalization: `q_i / b`, where `b = α * Σ(q_i)`
2. Offset calculation for numerical stability
3. Exponential calculation: `exp(q_i - offset)`
4. Normalization: `p_i = exp(q_i - offset) / Σ(exp(q_j - offset))`

#### Net Cost Calculation
```solidity
function calcNetCost(int256[] memory deltaOutcomeAmounts) external view returns (int256)
```

**LMSR Cost Formula**:
```
C(q) = b * ln(Σ(exp(q_i / b)))
ΔC = C(q_new) - C(q_old)
```

#### LMSR Parameters
- `alpha`: Liquidity parameter (controls market depth)
- `expLimitDec`: Exponent limit to prevent overflow

### 3. MarketMaker.sol

**Purpose**: Base contract for all types of prediction markets.

**Temporal Structure**:
- **Epoch**: Main time interval (e.g., 10 days) with automatic resolution at the end
- **Period**: Epoch subdivision (e.g., 1 day) with different reward weights
- **Tokens**: ERC1155 tokens for each outcome in each period
- **Oracle**: Provides results at the end of each epoch

#### Trading Management
```solidity
function makePrediction(int256[] memory deltaOutcomeAmounts_) 
    external nonReentrant epochNotResolved(currentEpochNumber)
```

**Trading Logic**:
1. Update epoch/period if necessary
2. Validate input data
3. Calculate net cost
4. Update user balances
5. Handle payments and fees

#### Reward System
```solidity
function _initializeGammaPowers(uint32 gamma) private
```

**Time Weighting**:
- **Early periods = higher weight**: Predictions made at the beginning of an epoch receive higher rewards
- **Decreasing weight**: Each subsequent period has a lower weight than the previous one
- **Formula**: `gammaPow[i] = gammaPow[i-1] * gamma / RANGE`
- **First period**: Receives full reward (100%)
- **Motivation**: Encourages early and more risky predictions

#### Epoch Resolution
```solidity
function closeEpoch(uint256[] calldata payouts) 
    external onlyOracleManager epochNotResolved(currentEpochNumber) returns (bool)
```

**Epoch Resolution Process**:
1. **Automatic trigger**: At the end of each epoch, the oracle automatically provides results
2. **Payout validation**: Verification of oracle data correctness
3. **Payout denominator calculation**: Result normalization
4. **Base price calculation**: Price determination for each outcome
5. **Fund transfer to next epoch**: Automatic creation of new epoch
6. **Timestamp update**: Transition to next trading cycle

**Features**:
- Each epoch ends with automatic resolution
- Oracle results determine payouts for all participants
- New epoch starts immediately after previous resolution
- System supports continuous trading without interruptions

#### Payout Redemption
```solidity
function redeemPayout(uint32 epoch) external nonReentrant epochResolved(epoch)
```

**Payout Calculation**:
```
payout = Σ(balance * gammaPow[period] * basePrice[outcome] / decQ) / RANGE
```

**Formula Components**:
- `balance`: User's outcome token quantity
- `gammaPow[period]`: Period weight (early periods = higher weight)
- `basePrice[outcome]`: Outcome base price from oracle
- `decQ`: Denominator for normalization
- `RANGE`: Scaling constant (10,000)

**Period Weight Example** (for 10-day epoch with gamma = 9000):
- Period 1: 100% (full weight)
- Period 2: 90% 
- Period 3: 81%
- Period 4: 72.9%
- ...
- Period 10: 43% (lowest weight)

### 4. Oracle Integration

#### MarketResolutionManager.sol
**Purpose**: Coordinator for managing market resolution by epochs.

```solidity
function resolveMarket(bytes32 questionId) external onlyOwner
function getCurrentMarketData(bytes32 questionId) external returns (uint256[] memory payouts)
```

**Functions**:
- **Automatic resolution**: Automatically requests oracle data at the end of each epoch
- **Oracle coordination**: Manages different oracle types (Chainlink, FTSO)
- **Data validation**: Verifies correctness and relevance of oracle data
- **Result distribution**: Passes resolution results to corresponding markets

#### ChainlinkResolutionModule.sol
**Purpose**: Integration with Chainlink oracles.

**Supported Pairs**:
- ETH/USD
- BTC/USD
- Other pairs via Chainlink Price Feeds

#### FTSOResolutionModule.sol
**Purpose**: Integration with Flare Time Series Oracle (FTSO).

**Features**:
- Flare Network support
- Automatic price updates
- FTSO V2 integration

## Mathematical Foundations

### LMSR (Logarithmic Market Scoring Rule)

LMSR is an automated market maker that provides liquidity and automatic price determination.

#### Basic Formulas:

**Cost Function**:
```
C(q) = b * ln(Σ(exp(q_i / b)))
```
where:
- `q_i` - quantity of outcome i tokens
- `b = α * Σ(q_i)` - liquidity parameter
- `α` - LMSR parameter

**Marginal Price**:
```
p_i = exp(q_i / b) / Σ(exp(q_j / b))
```

**Trading Cost**:
```
ΔC = C(q_new) - C(q_old)
```

### Numerical Stability

To prevent overflow, offset technique is used:

```solidity
offset = max(q_i / b) - EXP_LIMIT_DEC
p_i = exp((q_i / b) - offset) / Σ(exp((q_j / b) - offset))
```

### Limitations

- Maximum number of outcomes: 10
- Maximum fee: 100% (10,000 basis points)
- Trading size limits to prevent manipulation

## Testing and Security Analysis

### Test Files
- `LMSRMarketMakerSimple.t.sol`: LMSR functionality tests and obtaining values for comparison with our Python model
- `RangedMarketMakerSimple.t.sol`: Range market tests (implementation just started)
- `DynamicaCoverageTests.t.sol`: Code coverage tests
- `DynamicaRevertTests.t.sol`: Error and revert condition tests

### Mock Contracts
- `MockTokenNew.sol`: Test ERC20 token
- `MockAggregator.sol`: Mock Chainlink aggregator
- `MockFtsoV2.sol`: Mock FTSO V2 contract

### Security Analysis and Code Coverage

#### Slither Analysis
- `slither-report.json`: Detailed static security analysis report
- Includes vulnerability analysis, optimization recommendations, and best practices
- Checks for reentrancy, access control, arithmetic issues, and other security problems

#### Code Coverage
- `coverage/`: Directory with code coverage reports
- `coverage/html/`: HTML reports for visual coverage analysis
- Shows percentage coverage of each function and code line
- Helps identify untested code sections

## Deployment

### Requirements
- Solidity ^0.8.25
- OpenZeppelin Contracts
- PRB-Math for fixed-point arithmetic
- Chainlink for oracles

### Deployment Order
1. Deploy implementation contracts
2. Deploy MarketMakerFactory
3. Configure oracles
4. Create first markets

## Usage

### Market Creation
```solidity
// 1. Prepare configuration
IDynamica.Config memory config = IDynamica.Config({
    owner: msg.sender,
    collateralToken: address(token),
    oracle: oracleAddress,
    question: "Will ETH be above $3000 on Dec 31?",
    outcomeSlotCount: 2,
    startFunding: 1000e18,
    outcomeTokenAmounts: 500e18,
    fee: 300, // 3%
    alpha: 3,
    expLimit: 12750,
    decimals: 18,
    expirationEpoch: 0, // perpetual
    gamma: 9000,        // Time weighting parameter (90%)
    epochDuration: 10 days,  // Epoch = 10 days
    periodDuration: 1 days   // Period = 1 day
});

// 2. Create via factory
factory.createMarketMaker(config, resolutionConfig);
```

**Market Temporal Structure**:
- **Epoch**: 10 days with automatic resolution at the end
- **Periods**: 10 periods of 1 day each
- **Weighting**: Early periods receive higher weight (90% of previous)
- **Oracle**: Automatically provides results at the end of each epoch

### Period-Based Trading
```solidity
// Buy outcome 0 tokens in current period
int256[] memory amounts = new int256[](2);
amounts[0] = 100e18; // buy 100 outcome 0 tokens
amounts[1] = 0;      // don't touch outcome 1

marketMaker.makePrediction(amounts);
```

**Trading Features**:
- **Period-based trading**: Each period has its own tokens and weights
- **Time weighting**: Early periods = higher weight in payouts
- **Automatic transitions**: System automatically transitions to next period
- **Continuity**: Trading continues without breaks between epochs

### Epoch Resolution
```solidity
// Oracle automatically resolves epoch at period end
uint256[] memory payouts = new uint256[](2);
payouts[0] = 30e18;    // outcome 0 data
payouts[1] = 4000e18; // outcome 1 data

marketMaker.closeEpoch(payouts);
```

**Resolution Process**:
1. **Automatic trigger**: At epoch end, oracle automatically provides results
2. **Payout calculation**: System accounts for weights of all epoch periods
3. **Distribution**: Users receive payouts proportional to their tokens and period weights
4. **New epoch**: New epoch with new periods starts immediately
---

*This document describes the current version of the Dynamica system. For the latest updates, follow the repository.* 
