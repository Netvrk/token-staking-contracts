import { time } from "@nomicfoundation/hardhat-network-helpers";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers";
import hre from "hardhat";
import { parseEther } from "viem";

describe("Staking", function () {
  let staking: any;
  let token: any;
  let owner: any;
  let otherAccount: any;
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployStakingContract() {
    // Contracts are deployed using the first signer/account by default

    const tokenAddress = "0x4f96fe3b7a6cf9725f59d353f723c1bdb64ca6aa";
    const [owner, otherAccount] = await hre.viem.getWalletClients();

    const token = await hre.viem.deployContract("Token", [owner.account.address]);

    const staking = await hre.viem.deployContract("Staking", [owner.account.address, token.address]);

    const publicClient = await hre.viem.getPublicClient();
    return {
      stakingContract: staking,
      tokenContract: token,
      ownerAcc: owner,
      otherAcc: otherAccount,
      publicClient,
    };
  }

  describe("Deployment", function () {
    it("Deploy staking token", async function () {
      const { stakingContract, ownerAcc, otherAcc, tokenContract } = await loadFixture(deployStakingContract);
      token = tokenContract;
      staking = stakingContract;
      owner = ownerAcc;
      otherAccount = otherAcc;
      console.log("Staking deployed at:", staking.address);
    });

    it("Stake token", async function () {
      await staking.write.stake([6, parseEther("1")]);
    });
    it("Calculate reward", async function () {
      await time.increase(1 * 86400 + 500);
      const user = await staking.read.userStakingInfo([owner.account.address]);
      console.log(user);
      const reward = await staking.read.pendingRewards([owner.account.address, 6]);
      console.log("Reward:", reward);
    });
    it("Claim reward", async function () {
      await time.increase(180 * 86400);
      const reward = await staking.read.pendingRewards([owner.account.address, 6]);
      console.log("Pending Reward:", reward);
      const program = await staking.read.stakingProgramInfo([6]);
      console.log("Program:", program);
      await staking.write.claim([6]);
      console.log("Claimed");
      const program2 = await staking.read.stakingProgramInfo([6]);
      console.log("Program:", program2);
    });
  });
});
