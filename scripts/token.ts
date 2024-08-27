import { ethers } from "hardhat";


async function main() {
    const tokenContract = await ethers.getContractFactory("Token");
    const token = await tokenContract.deploy();
    await token.waitForDeployment();
    console.log("Token deployed to:", await token.getAddress());
}

main().catch(console.error);