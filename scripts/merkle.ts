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
}



main().catch(console.error);