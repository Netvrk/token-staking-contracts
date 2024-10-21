import { ethers, upgrades } from "hardhat";

async function main() {
    const tokenAddress = "0x9Ee1d6a13B1724803CF7EE60014E0cF9EC4b5052";
    const managerAddress = "0x57291FE9b6dC5bBeF1451c4789d4e578ce956219";

    const rrStakingContract = await ethers.getContractFactory("RRStaking");
    const rrStaking = await upgrades.deployProxy(rrStakingContract, [tokenAddress, managerAddress], {
        kind: "uups"
    });
    await rrStaking.waitForDeployment();
    console.log("RRStaking contract deployed to:", await rrStaking.getAddress());
}

main().catch(console.error);