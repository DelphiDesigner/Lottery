const fs = require('fs');

const privateKey = fs.readFileSync(".secret").toString().trim();

module.exports = {
  defaultNetwork: "rinkeby",
  networks: {
    rinkeby: {
      url: "https://rinkeby.infura.io/v3/",
      accounts: [privateKey]
    }
  },
  solidity: {
    version: "0.5.10",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  paths: {
    sources: "./contracts",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  mocha: {
    timeout: 20000
  }
}