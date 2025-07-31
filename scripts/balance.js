const hre = require("hardhat");

async function main() {
	const tokenAddress = process.env.CONTRACT_ADDRESS;
	const walletAddress = process.env.WALLET_ADDRESS;

	const decimals = 18;

	const coin = await hre.ethers.getContractAt(
		process.env.TOKEN_NAME,
		tokenAddress,
	);

	const code = await hre.ethers.provider.getCode(tokenAddress);
	if (code === "0x") {
		console.error(`❌ No contract deployed at address: ${tokenAddress}`);
		process.exit(1);
	}

	const balance = await coin.balanceOf(walletAddress);

	const formattedBalance = hre.ethers.formatUnits(balance, decimals);

	console.log(`💰 Balance of ${walletAddress}: ${formattedBalance}`);
}

main().catch((error) => {
	console.error("❌ Error:", error);
	process.exit(1);
});
