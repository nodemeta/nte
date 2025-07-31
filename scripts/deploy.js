const { ethers, upgrades, network } = require("hardhat");
require("dotenv").config();

async function main() {
	try {
		const [deployer] = await ethers.getSigners();
		console.log("🚀 Deploying with address:", deployer.address);

		if (!process.env.TOKEN_NAME) throw new Error("TOKEN_NAME not set in .env");

		const provider = deployer.provider;
		const balance = await provider.getBalance(deployer.address);
		const minBalance = ethers.parseEther("0.1");
		console.log("💰 Account balance:", ethers.formatEther(balance), "MATIC");

		if (balance < minBalance) {
			throw new Error(
				`❌ Insufficient MATIC. Need at least ${ethers.formatEther(
					minBalance,
				)} MATIC for deployment`,
			);
		}

		let currentGasPrice;
		let optimizedGasPrice;

		if (network.name === "localhost" || network.name === "hardhat") {
			currentGasPrice = ethers.parseUnits("10", "gwei");
			optimizedGasPrice = currentGasPrice;
		} else {
			try {
				currentGasPrice = await ethers.provider.getGasPrice();
			} catch {
				currentGasPrice = ethers.parseUnits("10", "gwei");
			}

			let currentGasPriceBigInt;
			if (currentGasPrice._isBigNumber) {
				currentGasPriceBigInt = BigInt(currentGasPrice.toString());
			} else if (typeof currentGasPrice === "bigint") {
				currentGasPriceBigInt = currentGasPrice;
			} else {
				throw new Error("❌ Unexpected gas price type");
			}

			optimizedGasPrice = (currentGasPriceBigInt * 110n) / 100n;
			currentGasPrice = optimizedGasPrice;
		}

		console.log("\n⛓️ Deploying Token Proxy...");
		const COIN = await ethers.getContractFactory(process.env.TOKEN_NAME);

		const miningReward = Number(process.env.MINING_REWARD);
		const stakingAPY = Number(process.env.STAKING_APY);
		const taxPercent = parseInt(process.env.TAX_PERCENT);
		const miningDifficultyRaw = process.env.MINING_DIFFICULTY;
		const miningDifficulty =
			miningDifficultyRaw &&
			miningDifficultyRaw !== "null" &&
			miningDifficultyRaw !== ""
				? ethers.toBigInt(miningDifficultyRaw)
				: ethers.toBigInt("");

		const coin = await upgrades.deployProxy(
			COIN,
			[
				11000000000,
				deployer.address,
				miningReward,
				miningDifficulty,
				stakingAPY,
				deployer.address,
				taxPercent,
			],
			{
				initializer: "initialize",
				kind: "uups",
				timeout: 120000,
				gasPrice: optimizedGasPrice,
				gasLimit: 5000000,
			},
		);

		console.log("\n⏳ Waiting for deployment confirmations...");
		await coin.waitForDeployment();

		const contractAddress = await coin.getAddress();
		const deployTx = coin.deploymentTransaction();

		console.log("\n✅ Deployment Successful");
		console.log("📍 Contract address:", contractAddress);
		console.log("🔗 Transaction hash:", deployTx?.hash || "N/A");

		if (deployTx) {
			const receipt = await deployTx.wait();
			console.log("⛽ Gas used:", receipt.gasUsed.toString());

			const gasUsedNumber = Number(receipt.gasUsed);
			const gasPriceNumber = Number(optimizedGasPrice);
			const deploymentCost = gasUsedNumber * gasPriceNumber;

			console.log(
				"💸 Deployment cost:",
				ethers.formatEther(deploymentCost.toString()),
				"MATIC",
			);
		}
	} catch (error) {
		console.error("\n❌ Deployment Failed");
		console.error("⚠️ Reason:", error.message || error);
		process.exit(1);
	}
}

main();
