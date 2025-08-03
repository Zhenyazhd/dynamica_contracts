# Dynamica v2 - Perpetual Prediction Markets

## Project Essence

**Dynamica** is a platform for creating perpetual prediction markets built on blockchain. Markets offer the ability to predict the ratio of several continuous quantities and bet money on it. The project implements a modern market making system using the **Logarithmic Market Scoring Rule (LMSR)** algorithm, which ensures continuous trading and automatic price discovery.

### Core Concepts:

- **Perpetual Markets**: Markets operate continuously with automatic transitions between epochs
- **LMSR Algorithm**: Uses logarithmic scoring function for price and liquidity determination
- **Multi-Outcome Markets**: Support for up to 10 different outcomes in one market
- **Time Weights**: Reward system considering trading participation time
- **Cross-Chain Oracles**: Integration with Chainlink oracles

## Main Features and Characteristics

### 🎯 Key Capabilities

1. **Continuous Trading**
   - Automatic transitions between epochs and periods
   - Continuous liquidity without waiting for market resolution
   - Dynamic pricing based on current state

2. **Advanced Market Making**
   - LMSR algorithm for efficient price discovery
   - Automatic scaling to maintain liquidity
   - Protection against manipulation through mathematical constraints

3. **Time-based Weights and Incentives**
   - Gamma power system to encourage early predictions
   - Decreasing multipliers for later periods
   - Fair distribution of rewards

4. **Modular Oracle Architecture**
   - Chainlink support for Hedera
   - FTSO integration for Flare Network
   - Extensible system for adding new oracles

5. **Gas Efficiency**
   - Use of minimal proxies (EIP-1167)
   - Optimized mathematical computations
   - Batch processing of operations

### 🔧 Technical Features

- **Smart Contracts**: Written in Solidity 0.8.25
- **Mathematical Library**: PRB Math for precise calculations
- **Token Standards**: ERC-1155 for outcome tokens, ERC-20 for collateral
- **Security**: OpenZeppelin contracts and upgradeable proxies
- **Testing**: Complete test suite with Foundry

### 📊 Market Structure

- **Epochs**: Main time periods (configurable)
- **Periods**: Epoch subdivisions for time weights
- **Outcomes**: Up to 10 possible event results
- **Collateral**: Any ERC-20 token for trading

## System Architecture

### Main Contracts:

1. **DynamicaFactory** - Factory for creating new markets
2. **Dynamica** - Main market maker contract with LMSR
3. **MarketMaker** - Base class with common logic
4. **MarketResolutionManager** - Market resolution management
5. **Resolution Modules** - Modules for various oracles

### Workflow:

1. Market creation through factory
2. Initialization with initial funding
3. Continuous trading throughout epochs
4. Automatic resolution through oracles
5. Reward distribution to participants

## Smart Contract Functions

### DynamicaFactory

#### Main Functions:
- `createMarketMaker()` - Create new market
- `setOracleCoordinator()` - Set oracle coordinator
- `getAllMarketMakers()` - Get all created markets
- `getMarketMakersByCreator()` - Markets by specific creator

#### Events:
- `FactoryMarketMakerCreated` - New market created

### Dynamica (Main Contract)

#### Initialization and Setup:
- `initialize()` - Initialize contract with parameters
- `initializeMarket()` - Setup initial market state

#### Trading Functions:
- `makePrediction()` - Place prediction/trade
- `calcNetCost()` - Calculate trade cost
- `calcMarginalPrice()` - Calculate marginal price for outcome

#### Epoch Management:
- `closeEpoch()` - Close epoch and calculate payouts
- `redeemPayout()` - Get epoch payouts
- `updateEpochAndPeriod()` - Update time periods

#### Administrative Functions:
- `changeFee()` - Change fee
- `withdrawFee()` - Withdraw collected fees
- `emergencyExit()` - Emergency exit

#### Events:
- `MarketInitialized` - Market initialized
- `OutcomeTokenTrade` - Trade executed
- `EpochResolved` - Epoch resolved
- `PayoutRedemption` - Payout received
- `MarketScaled` - Market scaled

### MarketMaker (Base Class)

#### Additional Functions:
- `checkEpoch()` - Check epoch status
- `payoutNumerators()` - Get payout numerators
- `outcomeTokenSupplies()` - Get token supplies
- `changeExpirationEpoch()` - Change expiration time

#### Events:
- `TokenMinted` - Tokens minted
- `TokenBurned` - Tokens burned
- `FeeChanged` - Fee changed
- `FeeWithdrawal` - Fees withdrawn
- `SendMarketsSharesToOwner` - Shares sent to owner

### MarketResolutionManager

#### Management Functions:
- `registerMarket()` - Register market with oracle
- `resolveMarket()` - Resolve market through oracle
- `getCurrentMarketData()` - Get market data

#### Events:
- `MarketRegistered` - Market registered
- `MarketResolved` - Market resolved

### Resolution Modules

#### ChainlinkResolutionModule (Hedera):
- `resolveMarket()` - Resolve through Chainlink
- `getCurrentMarketData()` - Get data

#### FTSOResolutionModule (Flare):
- `resolveMarket()` - Resolve through FTSO
- `getCurrentMarketData()` - Get data

## Mathematical Foundations

### LMSR Algorithm:
- **Cost Function**: C(q) = b * ln(Σ(exp(q_i/b)))
- **Marginal Price**: p_i = exp(q_i/b) / Σ(exp(q_j/b))
- **Liquidity**: b = α * Σ(q_i)

### Time Weights:
- Gamma powers to encourage early predictions
- Decreasing multipliers across periods
- Fair reward distribution

## Security

- Overflow checks in mathematical operations
- Input parameter validation
- Protection against manipulation through mathematical constraints
- Emergency functions for owners
- Upgradeable contracts for bug fixes

## Deployment and Usage

### Requirements:
- Foundry for compilation and testing
- Solidity 0.8.25+ support
- Access to oracles (Chainlink, FTSO)

### Supported Networks:
- **Hedera**: Through Chainlink oracles
- **Flare**: Through FTSO V2
- **Other EVM-compatible**: Through custom oracles

## License

MIT License - free use and modification

