// deploy_hardhat/marketMaker.config.js
const { ethers } = require("ethers");       // ← вот это
require("dotenv").config();

module.exports = {
  owner: process.env.OWNER_ADDRESS,
  deployerKey: process.env.PRIVATE_KEY,
  rpcUrl: process.env.TESTNET_RPC_URL,

  // Параметры для фабрики
  implementations: {
    dynamica:  "0x9880f30c3EcdeC97263F3b2f4bd37236201B3638",
    chainlinkModule: "0xAE079AB2DD64C4F1D16AF8262a25dC2041EFe2B6",
    ftsoModule:      "0x463b77B14868cc9387CF15E84bBc530ABAfA587a",
    ftsoV2:          "0x5f0154EB02702E00a2A145937C05c6Fbb2368271",
    factory:        "0x1B6aAe0A32dD1A95C85E3DB9a8F1F30dF7d02FeF",
    resolutionMgr:  "0x24b1383Ae14FcBe5648074E8b84694D03A13F260",
  },

  // Оракулы и коллатерал
  oracles: {
    ethUsd: "0x2e5973fADbc8C47cF65216FBFbaDDd90902002fa",
    btcUsd: "0x095093902334557C22C0a2cc7964d20eb1d4Ab0B",
  },
  collateralToken: "0x400d10951Cc2a47a81212c0f207D0362A7d98964",

  // Параметры рынка
  marketParams: {
    question:        "ETH/BTC_v1_on_hedera",
    outcomeSlotCount: 2,
    startFunding:    ethers.parseUnits("1000", 18),
    outcomeTokenAmounts:   1_000n * 10n ** 10n,    // int64(int256(1000 * 10**decimals))
    fee:             0,
    alpha:           3,
    expLimit:        12750,
    decimals:        10,
    expirationTime:  Math.floor(Date.now()/1000) + 60*24*3600, // +60 дней
  }
};