// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ArcStreamVaultPQBase} from "./ArcStreamVault.PQBase.t.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";

contract ArcStreamVaultPQFuzzTest is ArcStreamVaultPQBase {
    /// Any milestone count 1-50 and any target index verifies and pays exactly that milestone.
    function testFuzz_AnyIndexVerifies(uint256 n, uint256 idx, bytes32 seed) public {
        n = bound(n, 1, 50);
        idx = bound(idx, 0, n - 1);
        uint256 id = _createProtected(n, seed);
        _ready(id, idx);
        _release(id, idx, _proofFor(employer, seed, n, idx));
        assertTrue(vault.getMilestone(id, idx).isReleased);
        assertEq(usdc.balanceOf(contractor), UNIT);
        assertEq(vault.getEscrow(id).totalReleased, UNIT);
        assertEq(usdc.balanceOf(address(vault)), (n - 1) * UNIT);
    }

    function testFuzz_RefundLeafVerifies(uint256 n, bytes32 seed) public {
        n = bound(n, 1, 50);
        uint256 id = _createProtected(n, seed);
        uint256 before = usdc.balanceOf(employer);
        _refund(id, _proofFor(employer, seed, n, n));
        assertEq(usdc.balanceOf(employer), before + n * UNIT);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    /// A proof for action a never authorizes a different release index b.
    function testFuzz_WrongIndexFails(uint256 n, uint256 a, uint256 b, bytes32 seed) public {
        n = bound(n, 2, 50);
        a = bound(a, 0, n - 1);
        b = bound(b, 0, n - 1);
        if (a == b) b = (a + 1) % n;
        uint256 id = _createProtected(n, seed);
        _ready(id, b);
        bytes memory proof = _proofFor(employer, seed, n, a);
        vm.expectRevert(ArcStreamVault.InvalidQuantumProof.selector);
        vm.prank(employer);
        vault.releaseMilestone(id, b, proof);
        assertEq(usdc.balanceOf(contractor), 0);
    }

    /// No release-leaf proof authorizes a refund, and the refund proof authorizes no release.
    function testFuzz_ReleaseAndRefundProofsAreNotInterchangeable(uint256 n, uint256 idx, bytes32 seed) public {
        n = bound(n, 2, 50); // >=2 so something stays refundable after one milestone is approved
        idx = bound(idx, 0, n - 1);
        uint256 id = _createProtected(n, seed);
        _ready(id, idx);
        bytes memory releaseProof = _proofFor(employer, seed, n, idx);
        bytes memory refundProof = _proofFor(employer, seed, n, n);
        vm.expectRevert(ArcStreamVault.InvalidQuantumProof.selector);
        vm.prank(employer);
        vault.refundRemaining(id, releaseProof);
        vm.expectRevert(ArcStreamVault.InvalidQuantumProof.selector);
        vm.prank(employer);
        vault.releaseMilestone(id, idx, refundProof);
    }

    /// Flipping any single byte of a valid proof makes it fail (any revert; ABI-malformed may be empty).
    function testFuzz_MutatedProofFails(uint256 n, uint256 idx, bytes32 seed, uint256 pos, uint8 xorMask) public {
        n = bound(n, 1, 50);
        idx = bound(idx, 0, n - 1);
        uint256 id = _createProtected(n, seed);
        _ready(id, idx);
        bytes memory proof = _proofFor(employer, seed, n, idx);
        pos = bound(pos, 0, proof.length - 1);
        uint8 mask = xorMask == 0 ? 1 : xorMask;
        proof[pos] = bytes1(uint8(proof[pos]) ^ mask);

        vm.expectRevert();
        vm.prank(employer);
        vault.releaseMilestone(id, idx, proof);

        assertFalse(vault.getMilestone(id, idx).isReleased);
        assertEq(usdc.balanceOf(contractor), 0);
        assertEq(usdc.balanceOf(address(vault)), n * UNIT);
    }

    /// Truncated proofs always fail.
    function testFuzz_TruncatedProofFails(uint256 n, uint256 idx, bytes32 seed, uint256 cut) public {
        n = bound(n, 1, 50);
        idx = bound(idx, 0, n - 1);
        uint256 id = _createProtected(n, seed);
        _ready(id, idx);
        bytes memory proof = _proofFor(employer, seed, n, idx);
        cut = bound(cut, 1, proof.length);
        bytes memory shortened = new bytes(proof.length - cut);
        for (uint256 i; i < shortened.length; ++i) {
            shortened[i] = proof[i];
        }
        vm.expectRevert();
        vm.prank(employer);
        vault.releaseMilestone(id, idx, shortened);
        assertFalse(vault.getMilestone(id, idx).isReleased);
    }

    /// Arbitrary bytes never authorize an employer release on a protected escrow.
    function testFuzz_RandomBytesNeverAuthorize(uint256 n, bytes calldata junk) public {
        n = bound(n, 1, 8);
        uint256 id = _createProtected(n, SEED);
        _ready(id, 0);
        vm.expectRevert();
        vm.prank(employer);
        vault.releaseMilestone(id, 0, junk);
        vm.expectRevert();
        vm.prank(employer);
        vault.refundRemaining(id, junk);
    }

    /// A proof built for another employer's leaves never verifies for this employer.
    function testFuzz_ProofBindsEmployer(uint256 n, uint256 idx, bytes32 seed) public {
        n = bound(n, 1, 50);
        idx = bound(idx, 0, n - 1);
        uint256 id = _createProtected(n, seed);
        _ready(id, idx);
        bytes memory foreign = _proofFor(employer2, seed, n, idx);
        vm.expectRevert(ArcStreamVault.InvalidQuantumProof.selector);
        vm.prank(employer);
        vault.releaseMilestone(id, idx, foreign);
    }

    /// Contractor calls and unprotected escrows never need a proof, whatever the bytes.
    function testFuzz_ContractorAndUnprotectedIgnoreProofBytes(uint256 n, bytes calldata junk) public {
        n = bound(n, 1, 8);
        uint256 prot = _createProtected(n, SEED);
        uint256 open = _createN(n, bytes32(0));
        _ready(prot, 0);
        _ready(open, 0);
        vm.prank(contractor);
        vault.releaseMilestone(prot, 0, junk);
        vm.prank(employer);
        vault.releaseMilestone(open, 0, junk);
        assertEq(usdc.balanceOf(contractor), 2 * UNIT);
    }
}
