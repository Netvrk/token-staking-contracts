## Token Staking Contracts

The **Token Staking Contracts** form the backbone of incentivizing user participation in the Netvrk metaverse ecosystem. These contracts allow users to stake tokens and earn rewards based on predefined conditions, promoting both engagement and long-term token holding. Below is a detailed explanation of the two types of staking contracts:

---

### **1. Staking.sol**

This contract enables users to participate in **staking programs** with highly configurable parameters. Key features include:

- **Program Customization**: Staking programs can have unique durations, annual percentage yield (APY) rates, minimum and maximum staking limits, and defined start-end windows. For example, staking programs can be set for durations of 3 months, 6 months, 9 months, and 12 months.
- **Multiple Programs Support**: Users can choose from multiple active staking programs, each with its distinct configuration.
- **Rewards Calculation**: Rewards are based on the APY rate and the staked amount over the program’s duration.
- **User Operations**:
  - Users can **stake tokens** into any available program.
  - They can **view accumulated rewards** at any time.
  - Upon program completion or as allowed, users can **withdraw their staked tokens** along with earned rewards.

This contract is ideal for offering structured, time-bound staking options with predictable rewards.

---

### **2. RRStaking.sol**

This contract follows a **simpler staking approach**, designed to integrate with the broader **Netvrk Rewards System**. Its primary features are:

- **External Duration Tracking**: User staking durations are recorded and tracked externally, ensuring accurate calculations for quarterly reward distribution.
- **Comprehensive Reward Criteria**:
  - Rewards are distributed as part of **quarterly Netvrk rewards**.
  - **Additional Factors**: Reward eligibility depends on:
    - The duration of token staking.
    - Ownership of specific NFTs.
    - The duration for which NFTs have been staked.
    - Adherence to eligibility criteria set by Netvrk for the specific quarter, aligning with **crypto compliance regulations**.
- **Customizability**: The simple structure ensures it can adapt to evolving reward mechanisms and compliance standards.

This contract suits scenarios where rewards are part of a more complex system, emphasizing the integration of staking with NFT-based utility and other ecosystem dynamics.

---

### **Test Contracts on Holesky**

- **Token Contract**: [0x9Ee1d6a13B1724803CF7EE60014E0cF9EC4b5052](https://holesky.etherscan.io/address/0x9Ee1d6a13B1724803CF7EE60014E0cF9EC4b5052)
- **Staking Contract**: [0x451a9A54aAD00aABbCCA220C15616B904B6a921D](https://holesky.etherscan.io/address/0x451a9A54aAD00aABbCCA220C15616B904B6a921D)
- **RR Staking Contract**: [0x7dF9446b53fFB2C5F998252c468b926e70a6a015](https://holesky.etherscan.io/address/0x7dF9446b53fFB2C5F998252c468b926e70a6a015)

---

### **Technical Documentation**

For detailed technical documentation and code implementation, please refer to the contract code. The code includes comprehensive comments and documentation to help you understand the functionality and integration points of each contract.
