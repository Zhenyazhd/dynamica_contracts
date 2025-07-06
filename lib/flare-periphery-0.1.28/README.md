# Flare periphery package for smart contract development

This package contains a collection of smart contracts deployed on the **Flare**, Coston2 (test network for Flare), **Songbird** and Coston (test network for Songbird) networks.

The intention of this package is to provide a set of **interfaces** for easier integration and development of smart contracts on Flare based networks.
Interfaces in the most recent version of this package are the same as the ones deployed on the networks. This package exposes all public and most of the internal interfaces but **does not** expose any of the implementations. If you want to access the implementations, you can use the official [flare smart contracts repo](https://gitlab.com/flarenetwork/flare-smart-contracts).

The package functions similar to openzeppelin library packages and can easily be imported in `nodejs` based projects as well as directly in remix IDE.

Basic familiarity with the Flare network and EVM is assumed for use. For more information, please refer to the [Flare documentation](https://docs.flare.network/). If you want a guided tutorial on EVM development and Flare focused smart contract development with this package, please refer to the [Flare developer blogpost series](https://medium.com/@j0-0sko/setting-up-the-environment-3c9f20dcac7c).

## Package structure

Each of the networks has its own folder and subfolders for interfaces of specific flare based technologies. The folder structure is as follows:

```
├── coston
│   ├── distribution
│   ├── ftso
│   ├── governance
│   ├── inflation
│   ├── mockContracts
│   ├── stateConnector
│   └── util-contracts
├── coston2
│   ├── distribution
│   ├── ftso
│   ├── governance
│   ├── mockContracts
│   ├── stateConnector
│   └── util-contracts
├── examples
│   ├── coston
│   ├── coston2
│   ├── flare
│   └── songbird
├── flare
│   ├── distribution
│   ├── ftso
│   ├── governance
│   ├── mockContracts
│   ├── stateConnector
│   └── util-contracts
└── songbird
    ├── distribution
    ├── ftso
    ├── governance
    ├── inflation
    ├── mockContracts
    ├── stateConnector
    └── util-contracts
```

## Example usages

### I want to use the FTSO prices in my contract

You should use `IFtsoRegistry` (or `IIFtsoRegistry`) for simple price queries or
`IFtso` (or `IIFtso`) for more advanced queries.
The `IFtsoRegistry` interface is available in
`contracts/userInterfaces/IFtsoRegistry.sol` and the
`IFtso` interface is available in `contracts/userInterfaces/IFtso.sol`.

To use the interfaces deployed on `Flare` network, just import them in your contract source:

```solidity
import { IPriceSubmitter } from "@flarenetwork/flare-periphery-contracts/flare/ftso/userInterfaces/IPriceSubmitter.sol";
import { IFtsoRegistry } from "@flarenetwork/flare-periphery-contracts/flare/ftso/userInterfaces/IFtsoRegistry.sol";
```

If you are using Foundry, you can install the interfaces with Forge and import them in your contract source:

```solidity
import { IPriceSubmitter } from "flare-periphery-contracts/flare/ftso/userInterfaces/IPriceSubmitter.sol";
import { IFtsoRegistry } from "flare-periphery-contracts/flare/ftso/userInterfaces/IFtsoRegistry.sol";
```

Very simple contract that can consume the FTSO prices is shown in `examples/networkName/SimpleFtsoExample.sol`.

An example usage of the FTSO system to dynamically price token in a contract is showcased in
`examples/network/DynamicToken.sol` with a more detailed explanation in the [blogpost](https://medium.com/@j0-0sko/taking-it-up-to-11-74dd91c39c2b).


### I want to confirm something using the attestation client

Coming soon.

------

**You've got the tools, turn on your imagination and go, go and build something awesome**

If you find any mistake or have any suggestions, please open an issue or contact us are directly.

**Package is provided as is, without any warranty.**
