// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {ArcStreamVaultTestBase} from "./ArcStreamVault.Base.t.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";

/// Accounting branches, interplay with refund / release / approve / mutualCancel / PQ.
contract ArcStreamVaultUncontestedFlowsTest is ArcStreamVaultTestBase {
    // ------------------------------------------------------------ bookkeeping branches
    /// submitted-unapproved branch: only submittedUnapprovedCount decrements.
    function test_Accounting_UnapprovedBranch_DecrementsCounterOnly() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        _submit(id, 1);
        _approveOnly(id, 1); // m1 approved-pending, m0 submitted-unapproved
        assertEq(vault.submittedUnapprovedCount(id), 1);
        assertEq(vault.approvedPending(id), M1);

        skip(7 days);
        _claimU(id, 0);

        assertEq(vault.submittedUnapprovedCount(id), 0, "counter decremented");
        assertEq(vault.approvedPending(id), M1, "approvedPending untouched");
    }

    /// approved-pending branch: only approvedPending decrements.
    function test_Accounting_ApprovedBranch_DecrementsPendingOnly() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        _submit(id, 1);
        _approveOnly(id, 0); // m0 approved-pending, m1 submitted-unapproved
        assertEq(vault.submittedUnapprovedCount(id), 1);
        assertEq(vault.approvedPending(id), M0);

        skip(7 days);
        _claimU(id, 0);

        assertEq(vault.approvedPending(id), 0, "pending decremented");
        assertEq(vault.submittedUnapprovedCount(id), 1, "counter untouched");
        assertEq(vault.getEscrow(id).totalReleased, M0);
    }

    function test_Accounting_BothBranchesInSequenceEndAtZero() public {
        uint256 id = _createDefault();
        for (uint256 i; i < 3; ++i) {
            _submit(id, i);
        }
        _approveOnly(id, 0);
        _approveOnly(id, 2);
        skip(7 days);
        _claimU(id, 2);
        _claimU(id, 1);
        _claimU(id, 0);
        assertEq(vault.submittedUnapprovedCount(id), 0);
        assertEq(vault.approvedPending(id), 0);
        assertEq(vault.getEscrow(id).totalReleased, TOTAL);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    // ------------------------------------------------------------ refundRemaining interplay
    function test_Refund_BlockedWhileSubmittedUnapprovedThenAllowedAfterClaim() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.WorkAlreadySubmitted.selector);
        vault.refundRemaining(id, "");

        skip(7 days);
        _claimU(id, 0);

        uint256 eBefore = usdc.balanceOf(employer);
        _refund(id);
        assertEq(usdc.balanceOf(employer), eBefore + M1 + M2, "unsubmitted funds refunded");
        assertEq(vault.refundedAmounts(id), M1 + M2);
        assertTrue(vault.getEscrow(id).isTerminated);
        assertEq(usdc.balanceOf(address(vault)), 0);
        assertEq(usdc.balanceOf(contractor), M0);
    }

    function test_Refund_AfterApprovedBranchClaim_RefundsRemainderOnly() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        _approveOnly(id, 0);
        skip(7 days);
        _claimU(id, 0);

        uint256 eBefore = usdc.balanceOf(employer);
        _refund(id);
        // totalDeposited - totalReleased - approvedPending = 600 - 100 - 0
        assertEq(usdc.balanceOf(employer), eBefore + M1 + M2);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_Refund_StillBlockedByOtherSubmittedMilestoneAfterClaim() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        _submit(id, 1);
        skip(7 days);
        _claimU(id, 0);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.WorkAlreadySubmitted.selector);
        vault.refundRemaining(id, "");
        _claimU(id, 1);
        _refund(id);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_Refund_ApprovedPendingStillProtectedAfterOtherClaim() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        _submit(id, 1);
        _approveOnly(id, 1);
        skip(7 days);
        _claimU(id, 0); // unapproved branch; m1 remains approved-pending
        uint256 eBefore = usdc.balanceOf(employer);
        _refund(id);
        assertEq(usdc.balanceOf(employer), eBefore + M2, "only unsubmitted, unapproved refunded");
        // approved m1 remains claimable after refund termination via release
        vm.prank(contractor);
        vault.releaseMilestone(id, 1, "");
        assertEq(usdc.balanceOf(contractor), M0 + M1);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_Refund_ByContractorWaiverThenClaimReverts() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        vm.prank(contractor);
        vault.refundRemaining(id, "");
        skip(30 days);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.EscrowTerminated.selector);
        vault.claimUncontestedMilestone(id, 0);
    }

    function test_Terminated_ClaimRevertsEvenForApprovedMilestone() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        _approveOnly(id, 0);
        _refund(id); // employer refunds m1+m2, terminating
        skip(30 days);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.EscrowTerminated.selector);
        vault.claimUncontestedMilestone(id, 0);
        // approved funds remain claimable via release
        vm.prank(contractor);
        vault.releaseMilestone(id, 0, "");
        assertEq(usdc.balanceOf(contractor), M0);
    }

    function test_Terminated_PrecedesRangeCheck() public {
        uint256 id = _createDefault();
        _refund(id);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.EscrowTerminated.selector);
        vault.claimUncontestedMilestone(id, 50);
    }

    // ------------------------------------------------------------ settled escrows
    function test_Settled_ClaimReverts() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        skip(7 days);
        _settle(id, 250e6, 350e6);
        assertTrue(vault.isSettled(id));
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.EscrowTerminated.selector);
        vault.claimUncontestedMilestone(id, 0);
        // the settlement credit is the contractor's route
        vm.prank(contractor);
        vault.claimSettlement(id);
        assertEq(usdc.balanceOf(contractor), 250e6);
    }

    function test_Settled_AfterClaim_SplitMustMatchReducedRemaining() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        skip(7 days);
        _claimU(id, 0);
        assertEq(_remaining(id), M1 + M2);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.InvalidSplit.selector);
        vault.mutualCancel(id, 250e6, 350e6); // sums to the pre-claim 600
        _settle(id, 100e6, 400e6);
        assertTrue(vault.isSettled(id));
    }

    function test_PendingProposalDoesNotBlockClaim() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        vm.prank(employer);
        vault.mutualCancel(id, 0, TOTAL);
        skip(7 days);
        _claimU(id, 0);
        assertEq(usdc.balanceOf(contractor), M0);
        // stale proposal can no longer be accepted
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.InvalidSplit.selector);
        vault.mutualCancel(id, 0, TOTAL);
    }

    // ------------------------------------------------------------ post-claim lifecycle calls
    function test_AfterClaim_ReleaseRevertsAlreadyReleased() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        skip(7 days);
        _claimU(id, 0);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.MilestoneAlreadyReleased.selector);
        vault.releaseMilestone(id, 0, "");
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.MilestoneAlreadyReleased.selector);
        vault.releaseMilestone(id, 0, "");
    }

    function test_AfterClaim_ApproveRevertsAlreadyReleased() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        skip(7 days);
        _claimU(id, 0);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.MilestoneAlreadyReleased.selector);
        vault.approveMilestone(id, 0);
    }

    function test_AfterClaim_ResubmitRevertsAlreadyReleased() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        skip(7 days);
        _claimU(id, 0);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.MilestoneAlreadyReleased.selector);
        vault.submitMilestoneWork(id, 0, "again");
    }

    function test_AfterClaim_OtherMilestonesStillWork() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        skip(7 days);
        _claimU(id, 0);
        _approve(id, 1);
        _release(id, 1);
        assertEq(usdc.balanceOf(contractor), M0 + M1);
        assertEq(vault.getEscrow(id).totalReleased, M0 + M1);
    }

    function test_Employer_ApproveBeforeClaim_ReleaseBeforeWindowThenClaimReverts() public {
        uint256 id = _createDefault();
        _approve(id, 0);
        _release(id, 0);
        assertEq(vault.uncontestedClaimTime(id, 0), 0);
        skip(7 days);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.MilestoneAlreadyReleased.selector);
        vault.claimUncontestedMilestone(id, 0);
    }

    function test_ClaimedMilestoneFlagsInGetMilestones() public {
        uint256 id = _createDefault();
        _submit(id, 2);
        uint256 t = block.timestamp;
        skip(7 days);
        _claimU(id, 2);
        ArcStreamVault.Milestone memory m = vault.getMilestones(id)[2];
        assertTrue(m.isWorkSubmitted);
        assertTrue(m.isApproved);
        assertTrue(m.isReleased);
        assertEq(m.submittedAt, t, "submittedAt preserved as history");
        assertEq(m.workProofHash, PROOF);
    }

    // ------------------------------------------------------------ PQ-protected escrows
    function test_PQ_ClaimNeedsNoProofAndEmitsNoQuantumEvent() public {
        uint256 id = _createPeriod(0, pqKey);
        _submit(id, 0);
        skip(7 days);
        vm.recordLogs();
        _claimU(id, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != ArcStreamVault.QuantumProofVerified.selector);
        }
        assertEq(usdc.balanceOf(contractor), M0);
    }

    function test_PQ_EmployerReleaseStillNeedsProofButContractorClaimDoesNot() public {
        uint256 id = _createPeriod(0, pqKey);
        _submit(id, 0);
        _approveOnly(id, 0);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.InvalidQuantumProof.selector);
        vault.releaseMilestone(id, 0, "");
        skip(7 days);
        _claimU(id, 0);
        assertEq(usdc.balanceOf(contractor), M0);
    }

    function test_PQ_EmployerStillCannotClaim() public {
        uint256 id = _createPeriod(0, pqKey);
        _submit(id, 0);
        skip(7 days);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.claimUncontestedMilestone(id, 0);
    }

    function test_PQ_AfterClaimEmployerRefundNeedsProofForRemainder() public {
        uint256 id = _createPeriod(0, pqKey);
        _submit(id, 0);
        skip(7 days);
        _claimU(id, 0);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.InvalidQuantumProof.selector);
        vault.refundRemaining(id, "");
        _refund(id, _sig(id, 3));
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    // ------------------------------------------------------------ custom period flows
    function test_MinPeriod_EscrowClaimsAfterOneDay() public {
        uint256 id = _createPeriod(1 days, "");
        _submit(id, 0);
        skip(1 days - 1);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.InspectionPeriodActive.selector);
        vault.claimUncontestedMilestone(id, 0);
        skip(1);
        _claimU(id, 0);
    }

    function test_MaxPeriod_NotClaimableAtDefaultWindow() public {
        uint256 id = _createPeriod(30 days, "");
        _submit(id, 0);
        skip(7 days);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.InspectionPeriodActive.selector);
        vault.claimUncontestedMilestone(id, 0);
        skip(23 days);
        _claimU(id, 0);
    }

    function test_PeriodsAreIndependentAcrossEscrows() public {
        uint256 a = _createPeriod(1 days, "");
        uint256 b = _createPeriod(10 days, "");
        _submit(a, 0);
        _submit(b, 0);
        skip(1 days);
        _claimU(a, 0);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.InspectionPeriodActive.selector);
        vault.claimUncontestedMilestone(b, 0);
    }
}
