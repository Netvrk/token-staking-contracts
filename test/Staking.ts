import { time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import hre from "hardhat";
import MerkleTree from "merkletreejs";
import { formatEther, keccak256, parseEther } from "viem";

describe("Staking", function () {
  let staking: any;
  let token: any;
  let owner: any;
  let user1: any;
  let user2: any;
  let user3: any;
  let user4: any;
  let tree: any;

  let whiteListAddresses: string[];
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  before(async function () {
    // Contracts are deployed using the first signer/account by default

    [owner, user1, user2, user3, user4] = await hre.viem.getWalletClients();

    whiteListAddresses = [owner.account.address, user1.account.address, user2.account.address];
    tree = new MerkleTree(
      whiteListAddresses.map((x: any) => keccak256(x)),
      keccak256,
      { sortPairs: true }
    );
  });

  describe("Deployment", async function () {
    it("Deploy token & staking token", async function () {
      const root = "0x" + tree.getRoot().toString("hex");
      token = await hre.viem.deployContract("Token", [owner.account.address]);
      staking = await hre.viem.deployContract("Staking", [owner.account.address, token.address, root]);
    });

    it("Approve token", async function () {
      await token.write.approve([staking.address, parseEther("10000")]);
      // send tokens to contract
      await token.write.transfer([staking.address, parseEther("10000")]);
    });

    it("Update merkle root", async function () {
      const root = "0x" + tree.getRoot().toString("hex");
      await expect(staking.write.updateMerkleRoot([root])).to.be.revertedWithCustomError;
      whiteListAddresses.push(user3.account.address);
      tree = new MerkleTree(
        whiteListAddresses.map((x: any) => keccak256(x)),
        keccak256,
        { sortPairs: true }
      );
      const root2 = "0x" + tree.getRoot().toString("hex");
      await staking.write.updateMerkleRoot([root2]);
    });

    it("Add 6 & 9 months staking program", async function () {
      const now = (await time.latest()) + 86400;
      await expect(staking.write.addStakingProgram([6, 6 * 30, 1200, parseEther("0.1"), parseEther("100"), now, now + 6 * 30 * 86400])).to.be
        .revertedWithCustomError;
      await staking.write.addStakingProgram([9, 9 * 30, 1500, parseEther("0.1"), parseEther("100"), now, now + 9 * 30 * 86400]);
    });

    it("Update staking program", async function () {
      const now = (await time.latest()) + 86400;
      await expect(staking.write.updateStakingProgram([10, 6 * 30, 1200, parseEther("0.1"), parseEther("100"), now, now + 6 * 30 * 86400])).to.be
        .revertedWithCustomError;
      await staking.write.updateStakingProgram([9, 9 * 30, 1600, parseEther("0.1"), parseEther("100"), now, now + 9 * 30 * 86400]);
    });

    it("6 months [0]: Stake token", async function () {
      const hexProof = tree.getHexProof(keccak256(owner.account.address));
      await expect(staking.write.stake([6, parseEther("101"), hexProof])).to.be.revertedWithCustomError;
      await expect(staking.write.stake([6, parseEther("0.01"), hexProof])).to.be.revertedWithCustomError;
      await expect(staking.write.stake([9, parseEther("1"), hexProof])).to.be.revertedWithCustomError;
      await staking.write.stake([6, parseEther("1"), hexProof]);
      const userStake = await staking.read.getUserStake([owner.account.address, 6, 0]);
      expect(userStake.staked).to.be.equal(parseEther("1"));

    });

    it("6 months [1]: Stake token", async function () {
      const hexProof = tree.getHexProof(keccak256(owner.account.address));
      await staking.write.stake([6, parseEther("1"), hexProof]);

      // Check stakes counts
      const allStakes = await staking.read.getUserStakes([owner.account.address, 6]);
      const totalStakes = await staking.read.getUserStakesCount([owner.account.address, 6]);
      expect(Number(totalStakes)).to.be.equal(allStakes.length);

      // check all staked amount
      let allstaked = 0n;
      for (let i = 0; i < allStakes.length; i++) {
        const userStake = await staking.read.getUserStake([owner.account.address, 6, i]);
        allstaked += userStake.staked;
        expect(userStake.staked).to.be.equal(parseEther("1"));
      }
      // check total staked amount
      const program = await staking.read.getStakingProgram([6]);
      expect(allstaked).to.be.equal(program.totalStaked);

      // check total users: should be 1
      expect(Number(program.totalUsers)).to.be.equal(1);

    });

    it("9 months: Stake token", async function () {
      const hexProof = tree.getHexProof(keccak256(owner.account.address));

      // claim after claimed
      await expect(staking.write.claim([9, 0, hexProof])).to.be.revertedWithCustomError;
      // check not started
      await expect(staking.write.stake([9, parseEther("1"), hexProof])).to.be.revertedWithCustomError;
      await time.increase(86400);
      await staking.write.stake([9, parseEther("1"), hexProof]);

      // check total staked amount
      const program = await staking.read.getStakingProgram([9]);
      expect(program.totalStaked).to.be.equal(parseEther("1"));


    });


    it("Check transfer of synthetic token", async function () {
      await expect(staking.write.transfer([user1.account.address, parseEther("0.5")])).to.be.revertedWithCustomError;
    });

    it("Calculate intermediate rewards", async function () {
      await showStakedAmount(owner.account.address);
      await time.increase(86400);
      const stake = await staking.read.getUserStake([owner.account.address, 6, 0]);
      const reward = await staking.read.getPendingRewards([owner.account.address, 6, 0]);
      expect(Number(reward[0])).to.be.lt(Number(stake.staked - stake.reward));
    });

    it("Claim before end", async function () {
      const hexProof = tree.getHexProof(keccak256(owner.account.address));
      await expect(staking.write.claim([6, 0, hexProof])).to.be.revertedWithCustomError;
    });

    it("6 months: Stake after end", async function () {
      const hexProof = tree.getHexProof(keccak256(owner.account.address));
      await time.increase(180 * 86400);
      // check stake period end
      await expect(staking.write.stake([6, parseEther("1"), hexProof])).to.be.revertedWithCustomError;
    });

    it("6 months [0]: Claim reward", async function () {
      const hexProof = tree.getHexProof(keccak256(owner.account.address));
      const pendingReward = await staking.read.getPendingRewards([owner.account.address, 6, 0]);
      await staking.write.claim([6, 0, hexProof]);

      const userStake0 = await staking.read.getUserStake([owner.account.address, 6, 0]);
      expect(userStake0.reward).to.be.equal(pendingReward[0]);

      const program = await staking.read.getStakingProgram([6]);
      expect(userStake0.reward).to.be.equal(program.claimedRewards);

      await expect(staking.write.claim([6, 0, hexProof])).to.be.revertedWithCustomError;
      await expect(staking.write.claim([6, 2, hexProof])).to.be.revertedWithCustomError;
    });

    it("6 months [1]: Claim reward", async function () {
      const hexProof = tree.getHexProof(keccak256(owner.account.address));
      const pendingReward = await staking.read.getPendingRewards([owner.account.address, 6, 1]);
      await staking.write.claim([6, 1, hexProof]);

      const userStake1 = await staking.read.getUserStake([owner.account.address, 6, 1]);
      expect(userStake1.reward).to.be.equal(pendingReward[0]);

      const program = await staking.read.getStakingProgram([6]);
      expect(program.pendingRewards).to.be.equal(0n);
      await showStakedAmount(owner.account.address);
    });

    it("9 months [0]: Claim reward", async function () {
      const hexProof = tree.getHexProof(keccak256(owner.account.address));
      // add 3 months to claim

      await time.increase(90 * 86400);

      const pendingReward = await staking.read.getPendingRewards([owner.account.address, 9, 0]);
      await staking.write.claim([9, 0, hexProof]);
      const userStake0 = await staking.read.getUserStake([owner.account.address, 9, 0]);
      expect(userStake0.reward).to.be.equal(pendingReward[0]);
      const program = await staking.read.getStakingProgram([9]);
      expect(program.pendingRewards).to.be.equal(0n);
      expect(program.claimedRewards).to.be.equal(userStake0.reward);

      await showStakedAmount(owner.account.address);
    });
  });


  async function showStakedAmount(user: any) {

    const xTokenBalance = await staking.read.balanceOf([user]);
    console.log("XToken Balance: ", formatEther(xTokenBalance));

    const programs = await staking.read.getStakingProgramIds();

    for (const prgm of programs) {
      const stakes = await staking.read.getUserStakes([user, prgm]);
      if (stakes.length > 0) {
        console.log("Staking Program:", prgm);
      }

      const stakeEndTime = await staking.read.getStakesEndTimesAndRemainingTimes([user, prgm]);

      for (let i = 0; i < stakes.length; i++) {
        const stake = stakes[i];
        console.log("Staked Amount:", formatEther(stake.staked), "Reward:", formatEther(stake.reward), "Claimed:", formatEther(stake.claimed), "Stake End Remaining:", stakeEndTime[i].remainingTime / 86400n);
      }
    }
  }
});
