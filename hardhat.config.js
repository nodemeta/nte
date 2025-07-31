require("@nomicfoundation/hardhat-toolbox");
require("@openzeppelin/hardhat-upgrades");
require("dotenv").config();

module.exports = {
	solidity: "0.8.22",
	networks: {
		localhost: {
			url: "http://127.0.0.1:8545",
			accounts: [process.env.PRIVATE_KEY],
		},
		bnb: {
			url: process.env.RPC_URL,
			accounts: [process.env.PRIVATE_KEY],
		},
		bnbTestnet: {
			url: process.env.BSC_TESTNET_RPC,
			accounts: [process.env.PRIVATE_KEY],
		},
	},
};
