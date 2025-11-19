# Dynamica - Perpetual Prediction Market System

> **Hackathon Project** - This project was developed for hackathon.

## About the Project

Dynamica is a decentralized perpetual prediction market platform built on Ethereum-compatible blockchains. The system enables users to create and participate in continuous prediction markets where they can bet on the evolution of various metrics over time (e.g., cryptocurrency price ratios, market indices, etc.).

Unlike traditional prediction markets with fixed end dates, Dynamica operates on an **epoch-based system** where markets automatically resolve and restart, creating a perpetual trading environment.

## Key Features

### Perpetual Markets
Markets run continuously without fixed expiration dates. Each epoch automatically resolves and a new one begins, allowing for ongoing trading.

### LMSR Pricing
Uses the **Logarithmic Market Scoring Rule (LMSR)** for automatic price determination and liquidity provision. Prices adjust automatically based on trading activity.

### Time-Weighted Rewards
Early predictions are rewarded more than later ones. The system uses a gamma-based weighting mechanism where:
- **Period 1**: 100% weight (full reward)
- **Period 2**: 90% weight
- **Period 3**: 81% weight
- And so on...

This incentivizes early participation and more confident predictions.

### Multi-Oracle Support
Integrates with Chainlink oracles for reliable price feeds and market resolution. Supports multiple oracle types for different blockchain networks.

### Gas-Efficient Architecture
Uses minimal proxy pattern (EIP-1167) for market creation, significantly reducing deployment costs.

### Rollover Feature
Allows users to automatically carry forward their positions to the next epoch. When trading with rollover enabled:
- Tokens are **blocked** on the contract instead of being transferred directly to the user
- **Full weight**: Rollover predictions are not affected by gamma weighting - they always receive 100% weight regardless of when they were made
- At epoch resolution, blocked tokens are converted to collateral based on outcome prices (without gamma reduction)
- Users can redeem their blocked tokens to receive **collateral** (not new epoch tokens), which they can then reinvest manually

**Benefits**:
- **Full reward**: Rollover predictions get full weight, unlike regular predictions that are weighted by period
- **Flexible reinvestment**: Receive collateral that can be used for any outcome in the next epoch
- **No time penalty**: Make rollover predictions at any time without worrying about period-based weighting

## How It Works

### Market Structure

Each market is organized into:
- **Epochs**: Main time intervals (e.g., 10 days) that automatically resolve
- **Periods**: Subdivisions of epochs (e.g., 1 day each) with different reward weights
- **Outcomes**: Different possible results users can bet on (e.g., "ETH/BTC > 0.05" or "ETH/BTC ≤ 0.05")

### Trading Flow

1. **Market Creation**: Anyone can create a market through the factory contract
2. **Trading**: Users buy/sell outcome tokens representing their predictions
3. **Automatic Resolution**: At the end of each epoch, oracles provide results
4. **Payouts**: Users redeem their rewards based on:
   - Which outcome won
   - How many tokens they hold
   - When they made their prediction (earlier = higher weight)
5. **New Epoch**: A new epoch starts immediately, and trading continues

### Rollover Mechanism

Users can opt for **rollover trading** when making predictions. Instead of receiving tokens directly, tokens are blocked on the contract:

1. **Rollover Trade**: User makes a prediction with `isRollover = true`
   - Tokens are minted to the contract address (blocked)
   - User's blocked balance is tracked separately
   - **Important**: Gamma weighting does NOT apply to rollover predictions - they always have 100% weight

2. **Epoch Resolution**: When the epoch closes:
   - Blocked tokens are converted to collateral based on outcome prices
   - Conversion uses **full weight** (100%) - no gamma reduction applied
   - The collateral is used to create new epoch tokens that are blocked on the contract

3. **Redemption**: User calls `redeemBlockedTokens(epoch)` to claim their collateral
   - Receives **collateral tokens** (not new epoch tokens)
   - Can manually reinvest the collateral in any outcome for the new epoch
   - Provides flexibility to change strategy between epochs

**Example**: 
- You make a rollover prediction with 100 tokens for outcome A in period 5 of epoch 1
- At epoch resolution, outcome A wins with base price of 0.6
- Your 100 tokens are converted to 60 collateral units (100 × 0.6) with **full weight** (not reduced by period 5's gamma)
- You call `redeemBlockedTokens(1)` and receive 60 collateral tokens
- You can then use this collateral to buy tokens for any outcome in epoch 2

### Example Use Case

**Market Question**: "Which ETH:BTC ratio will be at the end of this epoch?"



Users buy tokens for the outcome they believe will happen. At epoch end:
- Chainlink oracle provides current ETH/USD and BTC/USD prices
- System calculates the ratio and determines the winning outcome
- Users who bet correctly receive payouts proportional to their holdings and prediction timing

## Technical Architecture

### Core Contracts

- **`Dynamica.sol`**: Main market contract implementing LMSR pricing and epoch management
- **`DynamicaFactory.sol`**: Factory for creating new markets using minimal proxies
- **`MarketResolutionManager.sol`**: Coordinates oracle data and market resolution
- **`ChainlinkResolutionModule.sol`**: Chainlink oracle integration module

### Key Technologies

- **Solidity ^0.8.25**: Smart contract language
- **OpenZeppelin Contracts**: Battle-tested security libraries
- **PRB-Math**: Fixed-point arithmetic for precise calculations
- **Chainlink**: Decentralized oracle network

## Getting Started

### Prerequisites

- Node.js and npm/yarn
- Foundry (for development and testing)
- Access to an Ethereum-compatible network

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd dynamica_contracts

# Install dependencies
forge install

# Run tests
forge test
```

### Deployment

See `script/deploy.s.sol` for deployment script. Example:

```bash
export PRIVATE_KEY=0x...
forge script script/deploy.s.sol:Deploy \
  --rpc-url <RPC_URL> \
  --broadcast \
  --verify
```

## Project Structure

```
dynamica_contracts/
├── src/
│   ├── Dynamica.sol              # Main market contract
│   ├── DynamicaFactory.sol       # Market factory
│   ├── LMSRMath.sol             # LMSR pricing logic
│   ├── Oracles/                  # Oracle integration modules
│   └── interfaces/              # Contract interfaces
├── test/                         # Test files
├── script/                       # Deployment scripts
└── README.md                     # This file
```

## Security

The project includes:
- Comprehensive test coverage
- Static analysis with Slither
- Reentrancy guards
- Access control mechanisms
- Numerical stability safeguards

## License

MIT License

