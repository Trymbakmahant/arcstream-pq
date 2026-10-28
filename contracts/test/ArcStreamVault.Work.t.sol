// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ArcStreamVault} from "../ArcStreamVault.sol";
import {ArcStreamVaultTestBase} from "./ArcStreamVault.Base.t.sol";

/// submitMilestoneWork, approve-after-submit, and the employer-refund submission guard.
contract ArcStreamVaultWorkTest is ArcStreamVaultTestBase {
    uint256 internal id;

    function setUp() public override {
        super.setUp();
        id = _createDefault();
    }

    function _longProof(uint256 n) internal pure returns (string memory) {
        return string(new bytes(n)); // n zero bytes: nonempty, length n
    }

    // -------------------------------------------------------------- happy
    function test_Submit_StoresProofAndFlag() public {
        _submit(id, 1);
        ArcStreamVault.Milestone memory m = vault.getMilestone(id, 1);
        assertEq(m.workProofHash, PROOF);
        assertTrue(m.isWorkSubmitted);
        assertFalse(m.isApproved);
        assertFalse(m.isReleased);
        assertEq(vault.submittedUnapprovedCount(id), 1);
        // other milestones untouched
        assertFalse(vault.getMilestone(id, 0).isWorkSubmitted);
        assertEq(vault.getMilestone(id, 0).workProofHash, "");
    }

    function test_Submit_EmitsWorkSubmitted() public {
        vm.expectEmit(true, false, false, true, address(vault));
        emit ArcStreamVault.WorkSubmitted(id, 2, "ipfs://abc");
        vm.prank(contractor);
        vault.submitMilestoneWork(id, 2, "ipfs://abc");
    }

    function test_Submit_ResubmitReplacesProofWithoutDoubleCounting() public {
        _submit(id, 0);
        assertEq(vault.submittedUnapprovedCount(id), 1);

        vm.expectEmit(true, false, false, true, address(vault));
        emit ArcStreamVault.WorkSubmitted(id, 0, "second");
        vm.prank(contractor);
        vault.submitMilestoneWork(id, 0, "second");

        assertEq(vault.getMilestone(id, 0).workProofHash, "second");
        assertEq(vault.submittedUnapprovedCount(id), 1);
        // a single approval fully clears the counter (no double counting)
        _approveOnly(id, 0);
        assertEq(vault.submittedUnapprovedCount(id), 0);
    }

    function test_Submit_MaxLengthProofAccepted() public {
        string memory p = _longProof(256);
        vm.prank(contractor);
        vault.submitMilestoneWork(id, 0, p);
        assertEq(bytes(vault.getMilestone(id, 0).workProofHash).length, 256);
        assertEq(vault.MAX_WORK_PROOF_LENGTH(), 256);
    }

    function test_Submit_MultipleMilestonesCountIndependently() public {
        _submit(id, 0);
        _submit(id, 2);
        assertEq(vault.submittedUnapprovedCount(id), 2);
        _approveOnly(id, 0);
        assertEq(vault.submittedUnapprovedCount(id), 1);
        _approveOnly(id, 2);
        assertEq(vault.submittedUnapprovedCount(id), 0);
    }

    function test_Submit_CountsAreIsolatedPerEscrow() public {
        uint256 id2 = _createDefault();
        _submit(id, 0);
        assertEq(vault.submittedUnapprovedCount(id), 1);
        assertEq(vault.submittedUnapprovedCount(id2), 0);
    }

    function test_Submit_RotatedContractorCanSubmitOldCannot() public {
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.submitMilestoneWork(id, 0, PROOF);
        vm.prank(newContractor);
        vault.submitMilestoneWork(id, 0, PROOF);
        assertTrue(vault.getMilestone(id, 0).isWorkSubmitted);
    }

    function test_FullLifecycle_SubmitApproveRelease() public {
        _submit(id, 0);
        _approveOnly(id, 0);
        _release(id, 0);
        ArcStreamVault.Milestone memory m = vault.getMilestone(id, 0);
        assertTrue(m.isWorkSubmitted);
        assertTrue(m.isApproved);
        assertTrue(m.isReleased);
        assertEq(m.workProofHash, PROOF);
        assertEq(usdc.balanceOf(contractor), M0);
    }

    // ------------------------------------------------------------ reverts
    function test_Revert_Submit_NotContractor() public {
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.submitMilestoneWork(id, 0, PROOF);
        vm.prank(outsider);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.submitMilestoneWork(id, 0, PROOF);
    }

    function test_Revert_Submit_EscrowNotFound() public {
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.EscrowNotFound.selector);
        vault.submitMilestoneWork(99, 0, PROOF);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.EscrowNotFound.selector);
        vault.submitMilestoneWork(0, 0, PROOF);
    }

    function test_Revert_Submit_MilestoneOutOfRange() public {
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.MilestoneOutOfRange.selector);
        vault.submitMilestoneWork(id, 3, PROOF);
    }

    function test_Revert_Submit_EmptyProof() public {
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.EmptyWorkProof.selector);
        vault.submitMilestoneWork(id, 0, "");
    }

    function test_Revert_Submit_ProofTooLong() public {
        string memory p = _longProof(257);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.WorkProofTooLong.selector);
        vault.submitMilestoneWork(id, 0, p);
        assertFalse(vault.getMilestone(id, 0).isWorkSubmitted);
    }

    function test_Revert_Submit_AfterApproval() public {
        _approve(id, 0);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.MilestoneAlreadyApproved.selector);
        vault.submitMilestoneWork(id, 0, "changed");
        assertEq(vault.getMilestone(id, 0).workProofHash, PROOF, "approved proof is frozen");
    }

    function test_Revert_Submit_AfterRelease() public {
        _approve(id, 0);
        _release(id, 0);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.MilestoneAlreadyReleased.selector);
        vault.submitMilestoneWork(id, 0, PROOF);
    }

    function test_Revert_Submit_AfterRefundTermination() public {
        _approve(id, 0);
        _refund(id);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.EscrowTerminated.selector);
        vault.submitMilestoneWork(id, 1, PROOF);
    }

    function test_Revert_Submit_AfterMutualSettlement() public {
        _settle(id, 100e6, TOTAL - 100e6);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.EscrowTerminated.selector);
        vault.submitMilestoneWork(id, 0, PROOF);
    }

    function test_Revert_Approve_WorkNotSubmitted() public {
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.WorkNotSubmitted.selector);
        vault.approveMilestone(id, 0);
        assertFalse(vault.getMilestone(id, 0).isApproved);
        assertEq(vault.approvedPending(id), 0);
    }

    function test_Revert_Approve_OnlySubmittedMilestoneCanBeApproved() public {
        _submit(id, 0);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.WorkNotSubmitted.selector);
        vault.approveMilestone(id, 1);
    }

    function test_Approve_SetsPendingAndDecrementsCounter() public {
        _submit(id, 1);
        vm.expectEmit(true, true, false, true, address(vault));
        emit ArcStreamVault.MilestoneApproved(id, 1, employer);
        _approveOnly(id, 1);
        assertEq(vault.approvedPending(id), M1);
        assertEq(vault.submittedUnapprovedCount(id), 0);
    }

    // ------------------------------------------------------- refund guard
    function test_Refund_EmployerBlockedWhileSubmittedWorkUnapproved() public {
        _submit(id, 1);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.WorkAlreadySubmitted.selector);
        vault.refundRemaining(id, "");
        assertFalse(vault.getEscrow(id).isTerminated);
        assertEq(vault.refundedAmounts(id), 0);
        assertEq(usdc.balanceOf(address(vault)), TOTAL);
    }

    function test_Refund_EmployerStillBlockedUntilAllSubmittedApproved() public {
        _submit(id, 0);
        _submit(id, 1);
        _approveOnly(id, 0);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.WorkAlreadySubmitted.selector);
        vault.refundRemaining(id, "");
        _approveOnly(id, 1);
        _refund(id); // only milestone 2 (never submitted) refundable
        assertEq(vault.refundedAmounts(id), M2);
        assertTrue(vault.getEscrow(id).isTerminated);
    }

    function test_Refund_EmployerAllowedWhenNothingSubmitted() public {
        uint256 before_ = usdc.balanceOf(employer);
        _refund(id);
        assertEq(usdc.balanceOf(employer), before_ + TOTAL);
    }

    function test_Refund_ContractorWaiverNotBlockedBySubmission() public {
        _submit(id, 0);
        _submit(id, 1);
        _approveOnly(id, 0);
        uint256 before_ = usdc.balanceOf(employer);
        vm.prank(contractor);
        vault.refundRemaining(id, "");
        // submitted-but-unapproved M1 and unsubmitted M2 both refunded; approved M0 retained
        assertEq(usdc.balanceOf(employer), before_ + M1 + M2);
        assertEq(vault.refundedAmounts(id), M1 + M2);
        assertEq(usdc.balanceOf(address(vault)), M0);
        // approved funds remain claimable
        _release(id, 0);
        assertEq(usdc.balanceOf(contractor), M0);
    }

    function test_Refund_EmployerBlockedThenContractorWaiverSucceeds() public {
        _submit(id, 2);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.WorkAlreadySubmitted.selector);
        vault.refundRemaining(id, "");
        vm.prank(contractor);
        vault.refundRemaining(id, "");
        assertEq(vault.refundedAmounts(id), TOTAL);
    }

    function test_Refund_GuardOrder_TerminatedBeatsSubmitted() public {
        _submit(id, 0);
        vm.prank(contractor);
        vault.refundRemaining(id, "");
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.EscrowTerminated.selector);
        vault.refundRemaining(id, "");
    }

    function test_Refund_ResubmissionKeepsEmployerBlocked() public {
        _submit(id, 0);
        _submit(id, 0);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.WorkAlreadySubmitted.selector);
        vault.refundRemaining(id, "");
    }

    function test_Refund_GuardIsPerEscrow() public {
        uint256 id2 = _createDefault();
        _submit(id, 0);
        vm.prank(employer);
        vault.refundRemaining(id2, ""); // id2 has no submissions
        assertTrue(vault.getEscrow(id2).isTerminated);
    }
}
