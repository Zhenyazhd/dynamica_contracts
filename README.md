# DYNAMICA

A decentralized prediction market platform implementing the Logarithmic Market Scoring Rule (LMSR) algorithm for automated market making on blockchain networks.

## Overview

This project provides a complete implementation of prediction markets using the LMSR mechanism, featuring:

- **LMSR Market Maker**: Core contract implementing logarithmic market scoring rule pricing
- **Market Maker Factory**: Factory pattern for creating new prediction markets
- **Oracle Integration**: Support for Flare Network's FDC oracle system
- **Multi-chain Support**: Deployment scripts for Flare and Hedera networks
- **Comprehensive Testing**: Extensive test suite with gas analysis

## Architecture

### Core Contracts

#### `LMSRMarketMaker.sol`
The main market maker contract implementing the LMSR algorithm:

- **Pricing Mechanism**: Uses exponential functions for price calculation
- **Delta Calculations**: Supports both 2-outcome and multi-outcome markets
- **Gas Optimization**: Efficient fixed-point arithmetic using PRB Math library
- **Safety Features**: Overflow protection and parameter validation

Key features:
- `calcNetCost()`: Calculate trade costs using LMSR formula
- `calcMarginalPrice()`: Get current price for any outcome
- `getDelta()`: Calculate required delta to achieve target price
- `getDeltaGeneric()`: Generic delta calculation for multi-outcome markets

#### `SimpleMarketMaker.sol`
Base market maker contract providing:

- **Market Management**: Condition preparation and initialization
- **Trading Functions**: Buy/sell outcome tokens
- **Fee Handling**: Configurable trading fees
- **Payout System**: Automatic payout distribution on market resolution

#### `MarketMakerFactory.sol`
Factory contract for creating new markets:

- **Market Creation**: Standard and funded market creation
- **Registry**: Track all created markets
- **Access Control**: Creator-based market management

### Oracle Integration

#### `DynamicaFeed.sol`
Flare Network oracle integration:

- **FDC Verification**: Uses Flare's FDC for JSON API proof validation
- **Market Resolution**: Automatic market closure with oracle data
- **Data Parsing**: Handles structured data from external APIs

#### `OracleManager_flare.sol` & `OracleManager_hedera.sol`
Network-specific oracle managers for different blockchain platforms.

## Installation

### Prerequisites

- [Foundry](https://getfoundry.sh/) (latest version)
- Node.js 18+ (for package management)

### Setup

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd result_github
   ```

2. **Install dependencies**
   ```bash
   forge install
   npm install
   ```

3. **Environment setup**
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```


## Research Features

The project includes comprehensive gas analysis and stability research tools:

- **Gas Consumption Analysis**: Detailed gas usage tracking for LMSR operations
- **Parameter Stress Testing**: Tests with extreme market conditions
- **Performance Benchmarks**: Comparison across different parameter ranges
- **Formula Validation**: Mathematical correctness verification

*Note: Research tests are currently commented out due to ongoing code improvements.*

## Key Features

### LMSR Algorithm Implementation

- **Exponential Pricing**: Uses `exp()` and `ln()` functions for price calculation
- **Fixed-Point Arithmetic**: 18-decimal precision using PRB Math library
- **Overflow Protection**: Safe mathematical operations with bounds checking
- **Multi-Outcome Support**: Handles markets with 2-5 possible outcomes

### Security Features

- **Ownable Pattern**: Access control for market management
- **Parameter Validation**: Comprehensive input validation
- **Reentrancy Protection**: Safe external calls
- **Fee Controls**: Configurable and bounded fee rates

### Gas Optimization

- **Efficient Storage**: Optimized data structures
- **Batch Operations**: Reduced transaction costs
- **Minimal External Calls**: Inline calculations where possible

## Configuration

### Fee Structure

- **Maximum Fee**: 100% (10,000 basis points)
- **Default Fee**: 0 
- **Fee Collection**: Automatic fee deduction on trades

### Market Parameters

- **Maximum Outcomes**: 1-5 outcomes per market
- **Minimum Funding**: 1 token
- **Price Precision**: 18 decimals
- **Oracle Timeout**: Configurable per network

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run the test suite
6. Submit a pull request

## Acknowledgments

- **PRB Math**: For efficient fixed-point arithmetic
- **OpenZeppelin**: For secure contract patterns
- **Flare Network**: For oracle infrastructure
- **Foundry**: For development and testing framework

