// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ArcStreamVaultPQBase} from "./ArcStreamVault.PQBase.t.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";
import {PQMerkle} from "../test-helpers/PQMerkle.sol";

/// Tree-shape coverage: 1, 2, 3, 5 and 50 milestones (odd-node promotion, depth up to 6).
contract ArcStreamVaultPQMerkleTest is ArcStreamVaultPQBase {
    /// Self-check of the Solidity Merkle helper against OpenZeppelin's verifier.
    function _selfCheck(uint256 n) internal view returns (uint256 maxDepth) {
        bytes32[] memory l = PQMerkle.leaves(address(vault), employer, SEED, n);
        bytes32 root = PQMerkle.rootOf(l);
        for (uint256 a; a <= n; ++a) {
            bytes32[] memory path = PQMerkle.pathOf(l, a);
            assertTrue(MerkleProof.verify(path, root, l[a]), "helper/OZ mismatch");
            if (path.length > maxDepth) maxDepth = path.length;
        }
    }

    function _releaseAllWithProofs(uint256 n) internal {
        uint256 id = _createN(n, _rootFor(employer, SEED, n));
        for (uint256 i; i < n; ++i) {
            _ready(id, i);
        }
        for (uint256 i; i < n; ++i) {
            bytes memory proof = _p(n, i);
            vm.expectEmit(true, false, false, true, address(vault));
            emit ArcStreamVault.QuantumProofVerified(id, i, vault.getEscrow(id).pqCommitment);
            _release(id, i, proof);
            assertTrue(vault.getMilestone(id, i).isReleased);
        }
        assertEq(usdc.balanceOf(contractor), n * UNIT);
        assertEq(usdc.balanceOf(address(vault)), 0);
        assertEq(vault.getEscrow(id).totalReleased, n * UNIT);
    }

    function _refundWithProof(uint256 n) internal {
        uint256 id = _createN(n, _rootFor(employer, SEED, n));
        uint256 before = usdc.balanceOf(employer);
        // every release-leaf proof is rejected for refund
        for (uint256 i; i < n; ++i) {
            _expectInvalidRefund(id, _p(n, i));
        }
        vm.expectEmit(true, false, false, true, address(vault));
        emit ArcStreamVault.QuantumProofVerified(id, n, vault.getEscrow(id).pqCommitment);
        _refund(id, _p(n, n));
        assertEq(usdc.balanceOf(employer), before + n * UNIT);
        assertTrue(vault.getEscrow(id).isTerminated);
    }

    // ---- helper self-checks

    function test_HelperMatchesOpenZeppelinVerifier() public view {
        uint256[6] memory sizes = [uint256(1), 2, 3, 5, 8, 50];
        for (uint256 i; i < sizes.length; ++i) {
            _selfCheck(sizes[i]);
        }
    }

    function test_TreeDepthBounds() public view {
        assertEq(_selfCheck(1), 1); // 2 leaves
        assertEq(_selfCheck(2), 2); // 3 leaves
        assertEq(_selfCheck(3), 2); // 4 leaves
        assertEq(_selfCheck(5), 3); // 6 leaves
        assertEq(_selfCheck(50), 6); // 51 leaves
        assertLe(_selfCheck(50), vault.MAX_PQ_PROOF_DEPTH());
    }

    // ---- on-chain verification per tree size

    function test_Milestones1_ReleaseAll() public {
        _releaseAllWithProofs(1);
    }

    function test_Milestones2_ReleaseAll() public {
        _releaseAllWithProofs(2);
    }

    function test_Milestones3_ReleaseAll() public {
        _releaseAllWithProofs(3);
    }

    function test_Milestones5_ReleaseAll() public {
        _releaseAllWithProofs(5);
    }

    function test_Milestones50_ReleaseAll() public {
        _releaseAllWithProofs(50);
    }

    function test_Milestones1_Refund() public {
        _refundWithProof(1);
    }

    function test_Milestones2_Refund() public {
        _refundWithProof(2);
    }

    function test_Milestones3_Refund() public {
        _refundWithProof(3);
    }

    function test_Milestones5_Refund() public {
        _refundWithProof(5);
    }

    function test_Milestones50_Refund() public {
        _refundWithProof(50);
    }

    function test_Milestones50_LastPromotedLeafAndDeepestPath() public {
        uint256 n = 50;
        uint256 id = _createN(n, _rootFor(employer, SEED, n));
        // refund leaf is index 50 of 51 leaves: an odd, promoted node on several levels
        _ready(id, 49);
        _ready(id, 0);
        _release(id, 49, _p(n, 49));
        _release(id, 0, _p(n, 0));
        // cross-wired proofs between neighbours fail
        _ready(id, 1);
        _expectInvalidRelease(id, 1, _p(n, 0));
        _expectInvalidRelease(id, 1, _p(n, 49));
        _release(id, 1, _p(n, 1));
    }

    function test_Milestones5_MutatedProofsFail() public {
        uint256 n = 5;
        uint256 id = _createN(n, _rootFor(employer, SEED, n));
        _ready(id, 4);
        (bytes32 s, bytes32[] memory path) = abi.decode(_p(n, 4), (bytes32, bytes32[]));
        for (uint256 k; k < path.length; ++k) {
            (, bytes32[] memory fresh) = abi.decode(_p(n, 4), (bytes32, bytes32[]));
            _expectInvalidRelease(id, 4, _tamperPath(s, fresh, k));
        }
        _release(id, 4, _p(n, 4));
    }
}
