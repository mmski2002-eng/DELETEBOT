export default {
  networks: {
    hardhat: {
      type: "edr-simulated",
      chainType: "generic",
      forking: {
        url: "https://api.mainnet.abs.xyz",
      },
    },
  },
};
