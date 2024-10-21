import { time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import hre, { ethers } from "hardhat";

describe("RRStaking", function () {
    let rrStaking: any;
    let token: any;
    let owner: any;
    let manager: any;
    let user1: any;
    let user2: any;
    let user3: any;
    let user4: any;

    let ownerAddress: string;
    let managerAddress: string;
    let user1Address: string;
    let user2Address: string;
    let user3Address: string;
    let user4Address: string;

    let tokenAddress: string;
    let rrStakingAddress: string;

    before(async function () {
        [owner, manager, user1, user2, user3, user4] = await hre.ethers.getSigners();

        ownerAddress = await owner.getAddress();
        managerAddress = await manager.getAddress();
        user1Address = await user1.getAddress();
        user2Address = await user2.getAddress();
        user3Address = await user3.getAddress();
        user4Address = await user4.getAddress();
    });

    describe("Deployment and updates", async function () {
        it("Deploy token & RRStaking contract", async function () {
            const tokenContract = await hre.ethers.getContractFactory("Token");
            token = await tokenContract.deploy();
            tokenAddress = await token.getAddress();

            const rrStakingContract = await hre.ethers.getContractFactory("RRStaking");
            rrStaking = await hre.upgrades.deployProxy(rrStakingContract, [tokenAddress, managerAddress]);
            rrStakingAddress = await rrStaking.getAddress();
        });

        it("Approve token", async function () {
            await token.approve(rrStakingAddress, ethers.parseEther("10000"));
        });

        it("Update staking program", async function () {
            const now = (await time.latest()) + 86400;
            const endTime = now + 86400;

            await expect(rrStaking.updateStakingProgram(ethers.parseEther("0.1"), ethers.parseEther("100"), now, endTime)).to.be.reverted;
            await expect(rrStaking.connect(manager).updateStakingProgram(ethers.parseEther("0.1"), ethers.parseEther("100"), now - 2 * 86400, endTime)).to.be.revertedWithCustomError(rrStaking, "STAKING_START_IN_PAST");

            await expect(rrStaking.connect(manager).updateStakingProgram(ethers.parseEther("0.1"), ethers.parseEther("100"), now, now - 86400)).to.be.revertedWithCustomError(rrStaking, "STAKING_RANGE_INVALID");

            await expect(rrStaking.connect(manager).updateStakingProgram(ethers.parseEther("100"), ethers.parseEther("1"), now, endTime)).to.be.revertedWithCustomError(rrStaking, "MIN_STAKING_GREATER_THAN_MAX");

            await rrStaking.connect(manager).updateStakingProgram(ethers.parseEther("0.1"), ethers.parseEther("100"), now, endTime);
        });

        it("Check staking program details", async function () {
            const stakingProgram = await rrStaking.getStakingProgram();
            expect(stakingProgram.minStaking).to.be.equal(ethers.parseEther("0.1"));
            expect(stakingProgram.maxStaking).to.be.equal(ethers.parseEther("100"));
        });

        it("Check staking token address", async function () {
            const stakingTokenAddress = await rrStaking.getStakingToken();
            expect(stakingTokenAddress).to.be.equal(tokenAddress);
        });
    });

    describe("Staking token", async function () {
        it("Stake token", async function () {

            await expect(rrStaking.stake(ethers.parseEther("1"))).to.be.revertedWithCustomError(rrStaking, "STAKING_NOT_STARTED");

            await time.increase(86400);

            await expect(rrStaking.stake(ethers.parseEther("0.01"))).to.be.revertedWithCustomError(rrStaking, "MIN_STAKING_AMOUNT_EXCEEDED");
            await expect(rrStaking.stake(ethers.parseEther("101"))).to.be.revertedWithCustomError(rrStaking, "MAX_STAKING_AMOUNT_EXCEEDED");

            await rrStaking.stake(ethers.parseEther("1"));
            const userStake = await rrStaking.balanceOf(ownerAddress);
            console.log("After Staking: ", ethers.formatEther(userStake) + "TKN");
            expect(userStake).to.be.equal(ethers.parseEther("1"));
        });


        it("Unstake token", async function () {
            await expect(rrStaking.unstake(ethers.parseEther("6"))).to.be.revertedWithCustomError(rrStaking, "INVALID_STAKED_AMOUNT");

            await rrStaking.unstake(ethers.parseEther("1"));
            const userStake = await rrStaking.balanceOf(ownerAddress);
            console.log("After UnStaking: ", ethers.formatEther(userStake) + "TKN");
            expect(userStake).to.be.equal(ethers.parseEther("0"));
        });

        it("Staking ended", async function () {
            await time.increase(86400);
            await expect(rrStaking.stake(ethers.parseEther("1"))).to.be.revertedWithCustomError(rrStaking, "STAKING_ENDED");
        });
    });

    describe("Extra", async function () {

        it("Test staking token transfer", async function () {
            await expect(rrStaking.connect(user1).transfer(ownerAddress, ethers.parseEther("1"))).to.be.revertedWithCustomError(rrStaking, "TOKEN_TRANSFER_DISABLED");
        });

    });
});