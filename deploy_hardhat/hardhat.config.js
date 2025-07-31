require("dotenv").config();
require("@nomicfoundation/hardhat-toolbox");

module.exports = {
  solidity: {
    version: "0.8.25",
  },
  defaultNetwork: "testnet",
  networks: {
    testnet: {
      url: process.env.RPC_URL,
      chainId: 296,
      accounts: [process.env.OPERATOR_KEY],
    }
  }
};