import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const StakingModule = buildModule("StakingModule", (m) => {
  const staking = m.contract("Staking", ["0x5D01c7dF02a7D5ec6fc031cb670C16EC8Fc11A62"]);

  return { staking };
});

export default StakingModule;
