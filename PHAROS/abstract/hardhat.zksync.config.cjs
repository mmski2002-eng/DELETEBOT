require("@matterlabs/hardhat-zksync-node");

module.exports = {
  zksolc: {
    version: "latest",
    settings: {},
  },
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      zksync: true,
    },
  },
  solidity: "0.8.24",
};
