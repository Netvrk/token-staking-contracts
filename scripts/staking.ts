import { ethers } from "hardhat";


async function main() {


    const tokenAddress = "0x9Ee1d6a13B1724803CF7EE60014E0cF9EC4b5052";
    const merkleRoot = "0xf0b1851d6151590186347cfd2e204cb37a3a3c13b125dacf5eaa1192d6de05d4";

    const stakingContract = await ethers.getContractFactory("Staking");
    const staking = await stakingContract.deploy(tokenAddress, merkleRoot);
    await staking.waitForDeployment();
    console.log("Staking contract deployed to:", await staking.getAddress());
}

main().catch(console.error);