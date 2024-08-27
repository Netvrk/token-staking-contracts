import { time } from "@nomicfoundation/hardhat-network-helpers";
import MerkleTree from "merkletreejs";
import { keccak256 } from "viem";


async function main() {
    const users: string[] = ["0x57291FE9b6dC5bBeF1451c4789d4e578ce956219", "0x50c1e68F01A0BE3bf6cD1a8E6b1Fe4c9AF7933B9", "0xf616DA40D5AFE3947cFB49FD06f8A922F115d38A"]
    const tree = new MerkleTree(
        users.map((x: any) => keccak256(x)),
        keccak256,
        { sortPairs: true }
    );
    const root = "0x" + tree.getRoot().toString("hex");
    console.log("Merkle root:", root);

    const merkleProofs = users.map((x: any) => tree.getHexProof(keccak256(x)));

    for (let i = 0; i < users.length; i++) {
        console.log("User:", users[i]);
        console.log("Proof:", merkleProofs[i]);
    }

    // after 5 mins
    const now = (await time.latest()) + 86400 + 300;

    console.log("Current Time:", now);

    const after6months = now + 6 * 30 * 86400;
    console.log("After 6 months:", after6months);
    console.log("Days in 6 months:", 6 * 30);

    const after9months = now + 9 * 30 * 86400;
    console.log("After 9 months:", after9months);
    console.log("Days in 9 months:", 9 * 30);

    const after12months = now + 12 * 30 * 86400;
    console.log("After 12 months:", after12months);
    console.log("Days in 12 months:", 12 * 30);
}



main().catch(console.error);