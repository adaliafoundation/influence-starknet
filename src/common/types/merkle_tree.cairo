//! MerkleTree implementation.
//!
//! # Example
//! ```
//! use alexandria_data_structures::merkle_tree::MerkleTreeTrait;
//!
//! // Create a new merkle tree instance.
//! let mut merkle_tree = MerkleTreeTrait::new();
//! let mut proof = ArrayTrait::new();
//! proof.append(element_1);
//! proof.append(element_2);
//! // Compute the merkle root.
//! let root = merkle_tree.compute_root(leaf, proof);

// Core lib imports
use array::SpanTrait;
use hash::LegacyHash;
use traits::Into;

/// MerkleTree representation.
#[derive(Drop)]
struct MerkleTree {}

/// MerkleTree trait.
trait MerkleTreeTrait {
    /// Create a new merkle tree instance.
    fn new() -> MerkleTree;
    /// Compute the merkle root of a given proof.
    fn compute_root(ref self: MerkleTree, current_node: felt252, proof: Span<felt252>) -> felt252;
    /// Verify a merkle proof.
    fn verify(ref self: MerkleTree, root: felt252, leaf: felt252, proof: Span<felt252>) -> bool;
}

/// MerkleTree implementation.
impl MerkleTreeImpl of MerkleTreeTrait {
    /// Create a new merkle tree instance.
    #[inline(always)]
    fn new() -> MerkleTree {
        MerkleTree {}
    }

    /// Compute the merkle root of a given proof.
    /// # Arguments
    /// * `current_node` - The current node of the proof.
    /// * `proof` - The proof.
    /// # Returns
    /// The merkle root.
    fn compute_root(
        ref self: MerkleTree, mut current_node: felt252, mut proof: Span<felt252>
    ) -> felt252 {
        loop {
            match proof.pop_front() {
                Option::Some(proof_element) => {
                    // Compute the hash of the current node and the current element of the proof.
                    // We need to check if the current node is smaller than the current element of the proof.
                    // If it is, we need to swap the order of the hash.
                    if Into::<felt252, u256>::into(current_node) < (*proof_element).into() {
                        current_node = LegacyHash::hash(current_node, *proof_element);
                    } else {
                        current_node = LegacyHash::hash(*proof_element, current_node);
                    }
                },
                Option::None(()) => {
                    break current_node;
                },
            };
        }
    }

    /// Verify a merkle proof.
    /// # Arguments
    /// * `root` - The merkle root.
    /// * `leaf` - The leaf to verify.
    /// * `proof` - The proof.
    /// # Returns
    /// True if the proof is valid, false otherwise.
    fn verify(
        ref self: MerkleTree, root: felt252, leaf: felt252, mut proof: Span<felt252>
    ) -> bool {
        let computed_root = self.compute_root(leaf, proof);
        computed_root == root
    }
}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use array::{ArrayTrait, SpanTrait};
    use hash::LegacyHash;
    use traits::Into;

    use super::{MerkleTree, MerkleTreeTrait};

    #[test]
    #[available_gas(2000000)]
    fn merkle_tree_test() {
        let mut merkle_tree = MerkleTreeTrait::new();
        // Create a proof.
        let proof = generate_proof_2_elements(
            275015828570532818958877094293872118179858708489648969448465143543997518327,
            3081470326846576744486900207655708080595997326743041181982939514729891127832
        );

        let leaf = 1743721452664603547538108163491160873761573033120794192633007665066782417603;
        let expected_merkle_root =
            455571898402516024591265345720711356365422160584912150000578530706912124657;
        test_case_compute_root(ref merkle_tree, proof, leaf, expected_merkle_root);

        // Create a valid proof.
        let mut valid_proof = generate_proof_2_elements(
            275015828570532818958877094293872118179858708489648969448465143543997518327,
            3081470326846576744486900207655708080595997326743041181982939514729891127832
        );
        // Verify the proof is valid.
        test_case_verify(ref merkle_tree, expected_merkle_root, leaf, valid_proof, true);

        // Create an invalid proof.
        let invalid_proof = generate_proof_2_elements(
            275015828570532818958877094293872118179858708489648969448465143543997518327 + 1,
            3081470326846576744486900207655708080595997326743041181982939514729891127832
        );
        // Verify the proof is invalid.
        test_case_verify(ref merkle_tree, expected_merkle_root, leaf, invalid_proof, false);

        // Create a valid proof but we will pass a wrong leaf.
        let valid_proof = generate_proof_2_elements(
            275015828570532818958877094293872118179858708489648969448465143543997518327,
            3081470326846576744486900207655708080595997326743041181982939514729891127832
        );
        // Verify the proof is invalid when passed the wrong leaf to verify.
        test_case_verify(
            ref merkle_tree,
            expected_merkle_root,
            1743721452664603547538108163491160873761573033120794192633007665066782417603 + 1,
            valid_proof,
            false
        );
    }

    // Tests merkle trees and proofs generated by JS utils
    #[test]
    #[available_gas(2000000)]
    fn test_utils() {
        let mut merkle_tree = MerkleTreeTrait::new();
        let mut proof: Array<felt252> = ArrayTrait::new();
        proof.append(2);
        proof.append(1078504723311822443900992338775481548059850561756203702548080974952533155775);
        proof.append(2642159642802802357817745026347077277988547597516177952258099282359767915971);

        let mut leaf = 1;
        let mut expected_root = 89428389394322347504365134305502788910642935783044206274458641273419909977;
        let mut root = merkle_tree.compute_root(leaf, proof.span());
        assert(root == expected_root, 'roots do not match');

        proof = ArrayTrait::new();
        proof.append(0);
        proof.append(0);
        proof.append(1585031860307053614775232457055372934135351753486924178555528195594933887604);

        leaf = 5;
        expected_root = 815620707321845763171801209177191381904265440601989923776687031080786864371;
        root = merkle_tree.compute_root(leaf, proof.span());
        assert(root == expected_root, 'roots do not match');
    }

    fn test_case_compute_root(
        ref merkle_tree: MerkleTree, proof: Array<felt252>, leaf: felt252, expected_root: felt252
    ) {
        let mut merkle_tree = MerkleTreeTrait::new();
        let root = merkle_tree.compute_root(leaf, proof.span());
        assert(root == expected_root, 'wrong result');
    }

    fn test_case_verify(
        ref merkle_tree: MerkleTree,
        root: felt252,
        leaf: felt252,
        proof: Array<felt252>,
        expected_result: bool
    ) {
        let result = merkle_tree.verify(root, leaf, proof.span());
        assert(result == expected_result, 'wrong result');
    }

    fn generate_proof_2_elements(element_1: felt252, element_2: felt252) -> Array<felt252> {
        let mut proof = ArrayTrait::new();
        proof.append(element_1);
        proof.append(element_2);
        proof
    }
}
