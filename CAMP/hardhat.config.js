require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.29",
    settings: {
      optimizer: { enabled: true, runs: 200 },
      evmVersion: "cancun",
    },
  },
  networks: {
    campNetwork: {
      url: "https://rpc.basecamp.t.raas.gelato.cloud",
      chainId: 123420001114,
    },
    hardhat: {
      chainId: 123420001114,
    },
  },
};
