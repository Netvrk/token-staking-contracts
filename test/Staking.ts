import { time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import hre from "hardhat";
import MerkleTree from "merkletreejs";
import { keccak256, parseEther } from "viem";

describe("Staking", () => {
  let staking: any;
  let token: any;
  let owner: any;
  let manager: any;
  let user1: any;
  let user2: any;
  let user3: any;
  let user4: any;
  let tree: any;

  let ownerAddress: `0x${string}`;
  let managerAddress: `0x${string}`;
  let user1Address: `0x${string}`;
  let user2Address: `0x${string}`;
  let user3Address: `0x${string}`;
  let user4Address: `0x${string}`;


  let tokenAddress: string;
  let stakingAddress: string;

  let whiteListAddresses: string[];
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  before(async () => {
    // Contracts are deployed using the first signer/account by default

    [owner, manager, user1, user2, user3, user4] = await hre.ethers.getSigners();

    ownerAddress = await owner.getAddress();
    managerAddress = await manager.getAddress();
    user1Address = await user1.getAddress();
    user2Address = await user2.getAddress();
    user3Address = await user3.getAddress();
    user4Address = await user4.getAddress();



    whiteListAddresses = [ownerAddress, user1Address, user2Address, user3Address, user4Address];
    tree = new MerkleTree(
      whiteListAddresses.map((x: any) => keccak256(x)),
      keccak256,
      { sortPairs: true }
    );
  });

  describe("Deployment and updates", async () => {
    it("Deploy token & staking token", async () => {
      const tokenContract = await hre.ethers.getContractFactory("Token");
      token = await tokenContract.deploy();
      tokenAddress = await token.getAddress();
      const stakingContract = await hre.ethers.getContractFactory("Staking");
      staking = await hre.upgrades.deployProxy(stakingContract, [tokenAddress, managerAddress]);
      stakingAddress = await staking.getAddress();
    });

    it("Approve token", async () => {
      await token.approve(stakingAddress, parseEther("10000"));
      // send tokens to contract
      await token.transfer(stakingAddress, parseEther("10000"));
    });

    it("Update merkle root", async () => {

      tree = new MerkleTree(
        whiteListAddresses.map((x: any) => keccak256(x)),
        keccak256,
        { sortPairs: true }
      );
      const root = "0x" + tree.getRoot().toString("hex");
      await staking.connect(manager).updateMerkleRoot(root);
      await expect(staking.updateMerkleRoot(root)).to.be.reverted;
      await expect(staking.connect(manager).updateMerkleRoot(root)).to.be.revertedWithCustomError(staking, "INVALID_MERKLE_ROOT");
    });

    it("Update staking token", async () => {
      await expect(staking.updateStakingToken(tokenAddress)).to.be.reverted;
      await staking.connect(manager).updateStakingToken(tokenAddress);

      const token = await staking.getStakingToken();
      expect(token).to.be.equal(tokenAddress);

    });


  });

  describe("Staking and claiming", async () => {

    it("Check transfer of synthetic token", async function () {
      await expect(staking.transfer(user1Address, parseEther("0.5"))).to.be.revertedWithCustomError(staking, "TOKEN_TRANSFER_DISABLED");
    });

    it("Add 6 & 9 months staking program", async () => {
      const now = (await time.latest()) + 86400;
      const endTime = now + 86400;

      await expect(staking.addStakingProgram(6, 6 * 30, 1000, parseEther("0.1"), parseEther("100"), now, endTime)).to.be.reverted;
      await expect(staking.connect(manager).addStakingProgram(6, 6 * 30, 1000, parseEther("0.1"), parseEther("100"), now - 86400, endTime)).to.be.revertedWithCustomError(staking, "STAKING_START_IN_PAST");
      await expect(staking.connect(manager).addStakingProgram(6, 6 * 30, 1000, parseEther("0.1"), parseEther("100"), now, now - 86400)).to.be.revertedWithCustomError(staking, "STAKING_END_BEFORE_START");
      await expect(staking.connect(manager).addStakingProgram(6, 6 * 30, 1000, parseEther("100"), parseEther("1"), now, endTime)).to.be.revertedWithCustomError(staking, "MIN_STAKING_GREATER_THAN_MAX");

      await staking.connect(manager).addStakingProgram(6, 6 * 30, 1000, parseEther("0.1"), parseEther("100"), now, endTime);
      await staking.connect(manager).addStakingProgram(9, 9 * 30, 1500, parseEther("0.1"), parseEther("100"), now, endTime);
      await expect(staking.connect(manager).addStakingProgram(6, 6 * 30, 1000, parseEther("0.1"), parseEther("100"), now, endTime)).to.be.revertedWithCustomError(staking, "STAKING_PROGRAM_ALREADY_EXISTS");

      const programIDs = await staking.getStakingProgramIds();
      expect(programIDs.length).to.be.equal(2);

    });

    it("Update staking program", async () => {
      const now = (await time.latest()) + 86400;

      const endTime = now + 86400;

      await expect(staking.updateStakingProgram(9, 9 * 30, 1600, parseEther("0.1"), parseEther("100"), now, endTime)).to.be.reverted;
      await expect(staking.connect(manager).updateStakingProgram(10, 6 * 30, 1200, parseEther("0.1"), parseEther("100"), now, endTime)).to.be
        .revertedWithCustomError(staking, "STAKING_PROGRAM_DOES_NOT_EXISTS");

      await expect(staking.connect(manager).updateStakingProgram(9, 9 * 30, 1000, parseEther("0.1"), parseEther("100"), now - 86400, endTime)).to.be.revertedWithCustomError(staking, "STAKING_START_IN_PAST");
      await expect(staking.connect(manager).updateStakingProgram(9, 9 * 30, 1000, parseEther("0.1"), parseEther("100"), now, endTime - 86400 - 100)).to.be.revertedWithCustomError(staking, "STAKING_END_BEFORE_START");
      await expect(staking.connect(manager).updateStakingProgram(9, 9 * 30, 1000, parseEther("100"), parseEther("1"), now, endTime)).to.be.revertedWithCustomError(staking, "MIN_STAKING_GREATER_THAN_MAX");

      await staking.connect(manager).updateStakingProgram(9, 9 * 30, 1600, parseEther("0.1"), parseEther("100"), now, endTime);
    });


    it("6 months [0]: Stake token", async () => {

      const hexProof = tree.getHexProof(keccak256(ownerAddress));
      await expect(staking.stake(6, parseEther("10"), hexProof)).to.be.revertedWithCustomError(staking, "STAKING_NOT_STARTED");
      // increment time by 1 day
      await time.increase(86400);
      await expect(staking.stake(6, parseEther("101"), hexProof)).to.be.revertedWithCustomError(staking, "MAX_STAKING_AMOUNT_EXCEEDED");
      await expect(staking.stake(6, parseEther("0.01"), hexProof)).to.be.revertedWithCustomError(staking, "MIN_STAKING_AMOUNT_EXCEEDED");

      // Staked 1 token
      await staking.stake(6, parseEther("1"), hexProof);
      const userStake = await staking.getUserStake(ownerAddress, 6, 0);
      expect(userStake.staked).to.be.equal(parseEther("1"));

    });

    it("6 months [1]: Stake token", async () => {
      const hexProof = tree.getHexProof(keccak256(ownerAddress));

      const alteredProof = [...hexProof];
      alteredProof[0] = "0x" + (parseInt(alteredProof[0]) + 1).toString(16);
      await expect(staking.stake(6, parseEther("1"), alteredProof)).to.be.revertedWithCustomError(staking, "INVALID_MERKLE_PROOF");

      await staking.stake(6, parseEther("1"), hexProof);

      // Check stakes counts
      const allStakes = await staking.getUserStakes(ownerAddress, 6);
      const totalStakes = await staking.getUserStakesCount(ownerAddress, 6);
      expect(Number(totalStakes)).to.be.equal(allStakes.length);

      // check all staked amount
      let allstaked = 0n;
      for (let i = 0; i < allStakes.length; i++) {
        const userStake = await staking.getUserStake(ownerAddress, 6, i);
        allstaked += userStake.staked;
        expect(userStake.staked).to.be.equal(parseEther("1"));
      }
      // check total staked amount
      const program = await staking.getStakingProgram(6);
      expect(allstaked).to.be.equal(program.totalStaked);

      // check total users: should be 1
      expect(Number(program.totalUsers)).to.be.equal(1);

    });

    it("9 months: Stake token", async () => {
      const hexProof = tree.getHexProof(keccak256(ownerAddress));
      // claim invalid stake id
      await expect(staking.claim(9, 0, hexProof)).to.be.revertedWithCustomError(staking, "INVALID_STAKE_ID");
      await staking.stake(9, parseEther("1"), hexProof);

      // check total staked amount
      const program = await staking.getStakingProgram(9);
      expect(program.totalStaked).to.be.equal(parseEther("1"));
    });


    it("Calculate intermediate rewards", async () => {
      await time.increase(86400);
      const stake = await staking.getUserStake(ownerAddress, 6, 0);
      const reward = await staking.getPendingRewards(ownerAddress, 6, 0);
      expect(Number(reward[0])).to.be.lt(Number(stake.staked - stake.reward));
    });

    it("Claim before end", async () => {
      const hexProof = tree.getHexProof(keccak256(ownerAddress));
      await expect(staking.claim(6, 0, hexProof)).to.be.revertedWithCustomError;
    });

    it("6 months: Stake after end", async () => {
      const hexProof = tree.getHexProof(keccak256(ownerAddress));

      await time.increase(2 * 86400);
      // check stake period end
      await expect(staking.stake(6, parseEther("1"), hexProof)).to.be.revertedWithCustomError(staking, "STAKING_ENDED");
    });


    it("Check pending rewards", async () => {
      const pendingReward = await staking.getPendingRewards(ownerAddress, 9, 0);
      expect(Number(pendingReward[0])).to.be.gt(0);

      const pendingReward2 = await staking.getPendingRewards(ownerAddress, 6, 5);
      expect(Number(pendingReward2[0])).to.be.equal(0);
    });


    it("6 months [0]: Claim reward", async () => {
      const hexProof = tree.getHexProof(keccak256(ownerAddress));
      await expect(staking.claim(6, 0, hexProof)).to.be.revertedWithCustomError(staking, "STAKING_DURATION_NOT_COMPLETED");


      const alteredProof = [...hexProof];
      alteredProof[0] = "0x" + (parseInt(alteredProof[0]) + 1).toString(16);
      await expect(staking.claim(6, 0, alteredProof)).to.be.revertedWithCustomError(staking, "INVALID_MERKLE_PROOF");

      // increment time by 6 months
      await time.increase(6 * 30 * 86400);

      const pendingReward = await staking.getPendingRewards(ownerAddress, 6, 0);
      await staking.claim(6, 0, hexProof);

      const userStake0 = await staking.getUserStake(ownerAddress, 6, 0);
      expect(userStake0.reward).to.be.equal(pendingReward[0]);

      const program = await staking.getStakingProgram(6);
      expect(userStake0.reward).to.be.equal(program.claimedRewards);

      await expect(staking.claim(6, 0, hexProof)).to.be.revertedWithCustomError(staking, "ALREADY_CLAIMED");
      await expect(staking.claim(6, 2, hexProof)).to.be.revertedWithCustomError(staking, "INVALID_STAKE_ID");

      const pendingReward2 = await staking.getPendingRewards(ownerAddress, 6, 0);
      expect(Number(pendingReward2[0])).to.be.equal(0);
    });

    it("6 months [1]: Claim reward", async () => {
      const hexProof = tree.getHexProof(keccak256(ownerAddress));
      const pendingReward = await staking.getPendingRewards(ownerAddress, 6, 1);

      await staking.claim(6, 1, hexProof);

      const userStake1 = await staking.getUserStake(ownerAddress, 6, 1);
      expect(userStake1.reward).to.be.equal(pendingReward[0]);

      const program = await staking.getStakingProgram(6);
      expect(program.pendingRewards).to.be.equal(0n);
    });

    it("9 months [0]: Claim reward", async () => {
      const hexProof = tree.getHexProof(keccak256(ownerAddress));

      await expect(staking.claim(9, 0, hexProof)).to.be.revertedWithCustomError(staking, "STAKING_DURATION_NOT_COMPLETED");

      // add 3 months to claim
      await time.increase(90 * 86400);

      const pendingReward = await staking.getPendingRewards(ownerAddress, 9, 0);
      await staking.claim(9, 0, hexProof);
      const userStake0 = await staking.getUserStake(ownerAddress, 9, 0);
      expect(userStake0.reward).to.be.equal(pendingReward[0]);
      const program = await staking.getStakingProgram(9);
      expect(program.claimedRewards).to.be.equal(userStake0.reward);

    });
  });

  describe("Withdraw", async () => {

    it("Withdraw all tokens", async () => {

      await expect(staking.connect(manager).withdrawFunds(tokenAddress, ownerAddress)).to.be.reverted;
      await staking.withdrawFunds(tokenAddress, ownerAddress);
      await expect(staking.withdrawFunds(tokenAddress, ownerAddress)).to.be.revertedWithCustomError(staking, "ZERO_BALANCE");
    });

  });


});
