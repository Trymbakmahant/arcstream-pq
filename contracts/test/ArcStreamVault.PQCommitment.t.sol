// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ArcStreamVaultPQBase} from "./ArcStreamVault.PQBase.t.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";

/// Commitment uniqueness, replay resistance, and lost-secret recovery.
contract ArcStreamVaultPQCommitmentTest is ArcStreamVaultPQBase {
    uint256 internal constant N = 3;

    // ------------------------------------------------------------ getEscrow / flags

    function test_GetEscrowReportsProtection() public {
        bytes32 root = _rootFor(employer, SEED, N);
        uint256 id = _createN(N, root);
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        assertEq(e.pqCommitment, root);
        assertTrue(e.isPQProtected);
        assertTrue(vault.pqCommitmentUsed(employer, root));
        assertFalse(vault.pqCommitmentUsed(employer2, root));
        // base fields are unaffected
        assertEq(e.employer, employer);
        assertEq(e.contractor, contractor);
        assertEq(e.totalDeposited, N * UNIT);
        assertEq(e.milestoneCount, N);
        assertFalse(e.isTerminated);
    }

    function test_ZeroCommitmentIsUnprotectedAndReusable() public {
        uint256 a = _createN(N, bytes32(0));
        uint256 b = _createN(N, bytes32(0));
        uint256 c = _createN(2, bytes32(0));
        uint256[3] memory ids = [a, b, c];
        for (uint256 i; i < 3; ++i) {
            ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(ids[i]);
            assertEq(e.pqCommitment, bytes32(0));
            assertFalse(e.isPQProtected);
        }
        assertFalse(vault.pqCommitmentUsed(employer, bytes32(0)));
    }

    function test_CreateDefaultIsUnprotected() public {
        uint256 id = _createDefault();
        assertFalse(vault.getEscrow(id).isPQProtected);
        assertEq(vault.getEscrow(id).pqCommitment, bytes32(0));
    }

    // ------------------------------------------------------------ uniqueness

    function test_RevertWhen_SameEmployerReusesRoot() public {
        bytes32 root = _rootFor(employer, SEED, N);
        _createN(N, root);
        uint256 countBefore = vault.escrowCount();
        uint256 balBefore = usdc.balanceOf(employer);

        vm.expectRevert(ArcStreamVault.CommitmentAlreadyUsed.selector);
        _createN(N, root);

        assertEq(vault.escrowCount(), countBefore);
        assertEq(usdc.balanceOf(employer), balBefore);
    }

    function test_RootStaysUsedAfterEscrowTerminates() public {
        bytes32 root = _rootFor(employer, SEED, N);
        uint256 id = _createN(N, root);
        _refund(id, _proofFor(employer, SEED, N, N));
        vm.expectRevert(ArcStreamVault.CommitmentAlreadyUsed.selector);
        _createN(N, root);
    }

    function test_RevertWhen_ReusedRootWithDifferentMilestoneCount() public {
        bytes32 root = _rootFor(employer, SEED, N);
        _createN(N, root);
        vm.expectRevert(ArcStreamVault.CommitmentAlreadyUsed.selector);
        _createN(5, root);
    }

    function test_DifferentEmployerMayUseSameRoot() public {
        bytes32 root = _rootFor(employer, SEED, N);
        uint256 idA = _createN(N, root);
        uint256 idB = _createN2(N, root);
        assertTrue(vault.pqCommitmentUsed(employer, root));
        assertTrue(vault.pqCommitmentUsed(employer2, root));
        assertTrue(vault.getEscrow(idA).isPQProtected);
        assertTrue(vault.getEscrow(idB).isPQProtected);
        assertEq(vault.getEscrow(idB).pqCommitment, root);
    }

    function test_EmployerACannotReserveEmployerBsRoot() public {
        bytes32 root = _rootFor(employer2, SEED, N);
        _createN(N, root); // employer burns it for itself
        // employer2 is unaffected
        uint256 id = _createN2(N, root);
        assertTrue(vault.getEscrow(id).isPQProtected);
    }

    function test_ProofBuiltForEmployerAFailsOnEmployerBsEscrow() public {
        bytes32 rootA = _rootFor(employer, SEED, N);
        _createN(N, rootA);
        // employer2 reuses A's root, so A's proofs are structurally valid for the root...
        uint256 idB = _createN2(N, rootA);
        _ready(idB, 0);
        // ...but the leaf binds the escrow's employer (employer2), so A's proof is rejected
        vm.expectRevert(ArcStreamVault.InvalidQuantumProof.selector);
        vm.prank(employer2);
        vault.releaseMilestone(idB, 0, _proofFor(employer, SEED, N, 0));
        // employer2 can't even prove with a tree built for itself (root differs)
        vm.expectRevert(ArcStreamVault.InvalidQuantumProof.selector);
        vm.prank(employer2);
        vault.releaseMilestone(idB, 0, _proofFor(employer2, SEED, N, 0));
        // the contractor path is the only way out and needs no proof
        vm.prank(contractor);
        vault.releaseMilestone(idB, 0, "");
        assertEq(usdc.balanceOf(contractor), UNIT);
    }

    // ------------------------------------------------------------ replay

    function test_RevertWhen_RevealedProofReplaysOnReleasedMilestone() public {
        uint256 id = _createN(N, _rootFor(employer, SEED, N));
        _ready(id, 0);
        bytes memory proof = _proofFor(employer, SEED, N, 0);
        _release(id, 0, proof);

        vm.expectRevert(ArcStreamVault.MilestoneAlreadyReleased.selector);
        vm.prank(employer);
        vault.releaseMilestone(id, 0, proof);

        assertEq(usdc.balanceOf(contractor), UNIT);
        assertEq(vault.getEscrow(id).totalReleased, UNIT);
    }

    function test_RevealedProofCannotAuthorizeOtherMilestone() public {
        uint256 id = _createN(N, _rootFor(employer, SEED, N));
        _ready(id, 0);
        _ready(id, 1);
        bytes memory proof0 = _proofFor(employer, SEED, N, 0);
        _release(id, 0, proof0);
        vm.expectRevert(ArcStreamVault.InvalidQuantumProof.selector);
        vm.prank(employer);
        vault.releaseMilestone(id, 1, proof0);
        assertFalse(vault.getMilestone(id, 1).isReleased);
    }

    function test_RevealedProofCannotBeReusedCrossEscrow() public {
        uint256 idA = _createN(N, _rootFor(employer, SEED, N));
        // employer cannot reuse the same tree for another escrow...
        vm.expectRevert(ArcStreamVault.CommitmentAlreadyUsed.selector);
        _createN(N, _rootFor(employer, SEED, N));
        // ...and a fresh tree rejects the first tree's revealed proof
        uint256 idB = _createN(N, _rootFor(employer, SEED_B, N));
        _ready(idA, 0);
        _ready(idB, 0);
        bytes memory proofA = _proofFor(employer, SEED, N, 0);
        _release(idA, 0, proofA);
        vm.expectRevert(ArcStreamVault.InvalidQuantumProof.selector);
        vm.prank(employer);
        vault.releaseMilestone(idB, 0, proofA);
        assertFalse(vault.getMilestone(idB, 0).isReleased);
    }

    function test_ReleaseAfterSettlementStillBlockedDespiteValidProof() public {
        uint256 id = _createN(N, _rootFor(employer, SEED, N));
        _ready(id, 0);
        _settle(id, UNIT, 2 * UNIT);
        vm.expectRevert(ArcStreamVault.EscrowSettled.selector);
        vm.prank(employer);
        vault.releaseMilestone(id, 0, _proofFor(employer, SEED, N, 0));
    }

    // ------------------------------------------------------------ lost-secret recovery

    function test_LostSecretRecoveryViaMutualCancel() public {
        uint256 id = _createN(N, _rootFor(employer, SEED, N));
        _ready(id, 0);
        uint256 empBefore = usdc.balanceOf(employer);

        // employer has lost every secret: release and refund are both blocked
        vm.expectRevert(ArcStreamVault.InvalidQuantumProof.selector);
        vm.prank(employer);
        vault.releaseMilestone(id, 0, "");
        vm.expectRevert(ArcStreamVault.InvalidQuantumProof.selector);
        vm.prank(employer);
        vault.refundRemaining(id, "");

        // cooperative recovery needs no proof
        _settle(id, UNIT, 2 * UNIT);
        assertTrue(vault.isSettled(id));

        vm.prank(contractor);
        vault.claimSettlement(id);
        vm.prank(employer);
        vault.claimSettlement(id);

        assertEq(usdc.balanceOf(contractor), UNIT);
        assertEq(usdc.balanceOf(employer), empBefore + 2 * UNIT);
        assertEq(usdc.balanceOf(address(vault)), 0);
        // protection metadata survives settlement
        assertTrue(vault.getEscrow(id).isPQProtected);
    }

    function test_LostSecretStillAllowsContractorReleaseOfApprovedWork() public {
        uint256 id = _createN(N, _rootFor(employer, SEED, N));
        _ready(id, 0);
        _ready(id, 1);
        vm.prank(contractor);
        vault.releaseMilestone(id, 0, "");
        vm.prank(contractor);
        vault.releaseMilestone(id, 1, "");
        assertEq(usdc.balanceOf(contractor), 2 * UNIT);
    }

    function test_ContractorWaiverRecoversUnapprovedFundsWithoutSecrets() public {
        uint256 id = _createN(N, _rootFor(employer, SEED, N));
        _ready(id, 0);
        uint256 empBefore = usdc.balanceOf(employer);
        vm.prank(contractor);
        vault.refundRemaining(id, "");
        assertEq(usdc.balanceOf(employer), empBefore + (N - 1) * UNIT);
    }

    function test_ContractorRotationDoesNotAffectProtection() public {
        uint256 id = _createN(N, _rootFor(employer, SEED, N));
        _ready(id, 0);
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);
        // proof does not bind the contractor: payout goes to the new contractor
        _release(id, 0, _proofFor(employer, SEED, N, 0));
        assertEq(usdc.balanceOf(newContractor), UNIT);
        assertEq(usdc.balanceOf(contractor), 0);
    }
}
