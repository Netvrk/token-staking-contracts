import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const TokenModule = buildModule("TokenModule", (m) => {
  const token = m.contract("Token", ["0x5D01c7dF02a7D5ec6fc031cb670C16EC8Fc11A62"]);

  return { staking: token };
});

export default TokenModule;
