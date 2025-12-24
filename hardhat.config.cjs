require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    solidity: {
        version: "0.8.28",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
            viaIR: true,
        },
    },
    networks: {
        // BSC Testnet
        testnet: {
            url: "https://data-seed-prebsc-1-s1.binance.org:8545",
            chainId: 97,
            accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
            gasPrice: 10000000000, // 10 gwei
        },
        // BSC Mainnet
        mainnet: {
            url: "https://bsc-dataseed1.binance.org",
            chainId: 56,
            accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
            gasPrice: 5000000000, // 5 gwei
        },
        // Local Hardhat Network (for testing)
        hardhat: {
            chainId: 31337
        }
    },
    etherscan: {
        apiKey: process.env.BSCSCAN_API_KEY || "",
        customChains: [
            {
                network: "bscTestnet",
                chainId: 97,
                urls: {
                    apiURL: "https://api-testnet.bscscan.com/api",
                    browserURL: "https://testnet.bscscan.com"
                }
            },
            {
                network: "bsc",
                chainId: 56,
                urls: {
                    apiURL: "https://api.bscscan.com/api",
                    browserURL: "https://bscscan.com"
                }
            }
        ]
    },
    paths: {
        sources: "./contracts",
        tests: "./test",
        cache: "./cache",
        artifacts: "./artifacts"
    }
};