// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";
import {ArcStreamVaultTestBase} from "./ArcStreamVault.Base.t.sol";

/// mutualCancel two-party consent, proposal management, post-settlement guards.
contract ArcStreamVaultSettlementTest is ArcStreamVaultTestBase {
    uint256 internal id;
    uint256 internal constant C_SHARE = 250e6;
    uint256 internal constant E_SHARE = TOTAL - 250e6;

    function setUp() public override {
        super.setUp();
        id = _createDefault();
    }

    function _proposal(uint256 eid) internal view returns (address p, uint256 c, uint256 e) {
        return vault.mutualCancelProposals(eid);
    }

    function _propose(address who, uint256 c, uint256 e) internal {
        vm.prank(who);
        vault.mutualCancel(id, c, e);
    }

    // ------------------------------------------------------------ proposals
    function test_Propose_FirstCallStoresProposalOnly() public {
        uint256 vaultBal = usdc.balanceOf(address(vault));
        vm.expectEmit(true, true, false, true, address(vault));
        emit ArcStreamVault.MutualCancelProposed(id, employer, C_SHARE, E_SHARE);
        _propose(employer, C_SHARE, E_SHARE);

        (address p, uint256 c, uint256 e) = _proposal(id);
        assertEq(p, employer);
        assertEq(c, C_SHARE);
        assertEq(e, E_SHARE);
        assertFalse(vault.isSettled(id));
        assertFalse(vault.getEscrow(id).isTerminated);
        assertEq(usdc.balanceOf(address(vault)), vaultBal, "no transfer on proposal");
        assertEq(vault.contractorSettlementOwed(id), 0);
        assertEq(vault.employerSettlementOwed(id), 0);
    }

    function test_Propose_ByContractorFirst() public {
        _propose(contractor, C_SHARE, E_SHARE);
        (address p,,) = _proposal(id);
        assertEq(p, contractor);
    }

    function test_Propose_DifferingCallFromOtherPartyReplaces() public {
        _propose(employer, C_SHARE, E_SHARE);
        vm.expectEmit(true, true, false, true, address(vault));
        emit ArcStreamVault.MutualCancelProposed(id, contractor, 300e6, 300e6);
        _propose(contractor, 300e6, 300e6);

        (address p, uint256 c, uint256 e) = _proposal(id);
        assertEq(p, contractor);
        assertEq(c, 300e6);
        assertEq(e, 300e6);
        assertFalse(vault.isSettled(id));
    }

    function test_Propose_SamePartyRepeatReplacesNotSettles() public {
        _propose(employer, C_SHARE, E_SHARE);
        // identical repeat by the same party must NOT settle
        vm.expectEmit(true, true, false, true, address(vault));
        emit ArcStreamVault.MutualCancelProposed(id, employer, C_SHARE, E_SHARE);
        _propose(employer, C_SHARE, E_SHARE);
        assertFalse(vault.isSettled(id));
        // differing repeat replaces the shares
        _propose(employer, 0, TOTAL);
        (address p, uint256 c, uint256 e) = _proposal(id);
        assertEq(p, employer);
        assertEq(c, 0);
        assertEq(e, TOTAL);
    }

    function test_Propose_ReplacedProposalCannotBeAcceptedWithOldShares() public {
        _propose(employer, C_SHARE, E_SHARE);
        _propose(employer, 0, TOTAL);
        // contractor now calls with the OLD shares -> that is a differing call -> new proposal
        _propose(contractor, C_SHARE, E_SHARE);
        assertFalse(vault.isSettled(id));
        (address p,,) = _proposal(id);
        assertEq(p, contractor);
    }

    // ------------------------------------------------------------ settle
    function test_Settle_IdenticalCallFromOtherPartySettles() public {
        _propose(employer, C_SHARE, E_SHARE);
        uint256 vaultBal = usdc.balanceOf(address(vault));
        uint256 empBal = usdc.balanceOf(employer);

        vm.expectEmit(true, false, false, true, address(vault));
        emit ArcStreamVault.EscrowMutuallyCancelled(id, C_SHARE, E_SHARE);
        _propose(contractor, C_SHARE, E_SHARE);

        assertTrue(vault.isSettled(id));
        assertTrue(vault.getEscrow(id).isTerminated);
        assertEq(vault.approvedPending(id), 0);
        assertEq(vault.contractorSettlementOwed(id), C_SHARE);
        assertEq(vault.employerSettlementOwed(id), E_SHARE);
        (address p, uint256 c, uint256 e) = _proposal(id);
        assertEq(p, address(0));
        assertEq(c + e, 0, "proposal cleared");
        // no token transfer yet
        assertEq(usdc.balanceOf(address(vault)), vaultBal);
        assertEq(usdc.balanceOf(employer), empBal);
        assertEq(usdc.balanceOf(contractor), 0);
        // principal accounting untouched until claimed
        assertEq(vault.getEscrow(id).totalReleased, 0);
        assertEq(vault.refundedAmounts(id), 0);
    }

    function test_Settle_ContractorProposesEmployerAccepts() public {
        _propose(contractor, 600e6, 0);
        _propose(employer, 600e6, 0);
        assertTrue(vault.isSettled(id));
        assertEq(vault.contractorSettlementOwed(id), TOTAL);
        assertEq(vault.employerSettlementOwed(id), 0);
    }

    function test_Settle_IncludesApprovedPendingAndSupersedesIt() public {
        _approve(id, 0);
        _approve(id, 1);
        assertEq(vault.approvedPending(id), M0 + M1);
        _settle(id, 10e6, TOTAL - 10e6);
        assertEq(vault.approvedPending(id), 0);
        assertEq(vault.contractorSettlementOwed(id), 10e6);
        assertEq(vault.employerSettlementOwed(id), TOTAL - 10e6);
    }

    function test_Settle_AllowsSubmittedUnapprovedWork() public {
        _submit(id, 0);
        // employer cannot refund unilaterally, but mutual cancel resolves the dispute
        _settle(id, M0, TOTAL - M0);
        assertTrue(vault.isSettled(id));
    }

    function test_Settle_AfterPartialRelease_UsesRemainingOnly() public {
        _approve(id, 0);
        _release(id, 0);
        _settle(id, 100e6, TOTAL - M0 - 100e6);
        assertEq(vault.contractorSettlementOwed(id) + vault.employerSettlementOwed(id), TOTAL - M0);
    }

    function test_Settle_AfterRefundTermination_SplitsApprovedPending() public {
        _approve(id, 0);
        _refund(id); // refunds M1+M2; M0 approved-pending remains
        assertTrue(vault.getEscrow(id).isTerminated);
        assertEq(_remaining(id), M0);

        _settle(id, 30e6, M0 - 30e6);
        assertTrue(vault.isSettled(id));
        assertEq(vault.approvedPending(id), 0);
        assertEq(vault.contractorSettlementOwed(id), 30e6);
        assertEq(vault.employerSettlementOwed(id), M0 - 30e6);
    }

    function test_Settle_ZeroShareForOnePartyAllowed() public {
        _settle(id, 0, TOTAL);
        assertEq(vault.contractorSettlementOwed(id), 0);
        assertEq(vault.employerSettlementOwed(id), TOTAL);
    }

    function test_Settle_StaleProposalAfterReleaseFailsInvalidSplit() public {
        _approve(id, 0);
        _propose(employer, C_SHARE, E_SHARE);
        _release(id, 0); // remaining drops to TOTAL - M0
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.InvalidSplit.selector);
        vault.mutualCancel(id, C_SHARE, E_SHARE);
        assertFalse(vault.isSettled(id));
    }

    function test_Settle_ProposalIsPerEscrow() public {
        uint256 id2 = _createDefault();
        _propose(employer, C_SHARE, E_SHARE);
        (address p,,) = vault.mutualCancelProposals(id2);
        assertEq(p, address(0));
        // identical call on a different escrow is a new proposal, not a settlement
        vm.prank(contractor);
        vault.mutualCancel(id2, C_SHARE, E_SHARE);
        assertFalse(vault.isSettled(id2));
        assertFalse(vault.isSettled(id));
    }

    // ------------------------------------------------------------ reverts
    function test_Revert_InvalidSplit_SumTooLowOrHigh() public {
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.InvalidSplit.selector);
        vault.mutualCancel(id, 100e6, 100e6);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.InvalidSplit.selector);
        vault.mutualCancel(id, TOTAL, 1);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.InvalidSplit.selector);
        vault.mutualCancel(id, 0, 0);
    }

    function test_Revert_InvalidSplit_ContractorShareAboveRemaining() public {
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.InvalidSplit.selector);
        vault.mutualCancel(id, TOTAL + 1, 0);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.InvalidSplit.selector);
        vault.mutualCancel(id, type(uint256).max, 0);
    }

    function test_Revert_InvalidSplit_DoesNotStoreProposal() public {
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.InvalidSplit.selector);
        vault.mutualCancel(id, 1, 1);
        (address p,,) = _proposal(id);
        assertEq(p, address(0));
    }

    function test_Revert_NothingToRefund_WhenRemainingZero() public {
        for (uint256 i; i < 3; ++i) {
            _approve(id, i);
            _release(id, i);
        }
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.NothingToRefund.selector);
        vault.mutualCancel(id, 0, 0);
    }

    function test_Revert_EscrowSettled_AfterSettlement() public {
        _settle(id, C_SHARE, E_SHARE);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.EscrowSettled.selector);
        vault.mutualCancel(id, C_SHARE, E_SHARE);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.EscrowSettled.selector);
        vault.mutualCancel(id, 0, TOTAL);
    }

    function test_Revert_Unauthorized_Outsider() public {
        vm.prank(outsider);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.mutualCancel(id, C_SHARE, E_SHARE);
    }

    function test_Revert_Unauthorized_RotatedOutContractor() public {
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.mutualCancel(id, C_SHARE, E_SHARE);
    }

    function test_Revert_EscrowNotFound_MutualCancelAndClaimAndCancelProposal() public {
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.EscrowNotFound.selector);
        vault.mutualCancel(99, 0, 0);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.EscrowNotFound.selector);
        vault.claimSettlement(99);
        // no proposal exists -> Unauthorized (no escrow lookup)
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.cancelMutualCancelProposal(99);
    }

    // --------------------------------------------- post-settlement guards
    function test_Settled_ApprovedMilestoneCannotBePaidTwice() public {
        _approve(id, 0);
        _settle(id, 0, TOTAL); // contractor waives everything incl. approved M0
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.EscrowSettled.selector);
        vault.releaseMilestone(id, 0, "");
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.EscrowSettled.selector);
        vault.releaseMilestone(id, 0, "");
        assertEq(usdc.balanceOf(contractor), 0);
    }

    function test_Settled_ApproveAndRefundAndSubmitBlocked() public {
        _submit(id, 0);
        _settle(id, C_SHARE, E_SHARE);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.EscrowTerminated.selector);
        vault.approveMilestone(id, 0);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.EscrowTerminated.selector);
        vault.refundRemaining(id, "");
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.EscrowTerminated.selector);
        vault.refundRemaining(id, "");
    }

    function test_Settled_ReleaseUnapprovedStillEscrowSettledFirst() public {
        _settle(id, C_SHARE, E_SHARE);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.EscrowSettled.selector);
        vault.releaseMilestone(id, 1, "");
    }

    // ----------------------------------------------- cancel proposal
    function test_CancelProposal_ProposerCancels() public {
        _propose(employer, C_SHARE, E_SHARE);
        vm.expectEmit(true, true, false, false, address(vault));
        emit ArcStreamVault.MutualCancelProposalCancelled(id, employer);
        vm.prank(employer);
        vault.cancelMutualCancelProposal(id);
        (address p, uint256 c, uint256 e) = _proposal(id);
        assertEq(p, address(0));
        assertEq(c + e, 0);
    }

    function test_CancelProposal_ThenOtherPartyCannotSettleWithOldShares() public {
        _propose(employer, C_SHARE, E_SHARE);
        vm.prank(employer);
        vault.cancelMutualCancelProposal(id);
        _propose(contractor, C_SHARE, E_SHARE); // fresh proposal, not acceptance
        assertFalse(vault.isSettled(id));
        (address p,,) = _proposal(id);
        assertEq(p, contractor);
    }

    function test_Revert_CancelProposal_NonProposer() public {
        _propose(employer, C_SHARE, E_SHARE);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.cancelMutualCancelProposal(id);
        vm.prank(outsider);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.cancelMutualCancelProposal(id);
        (address p,,) = _proposal(id);
        assertEq(p, employer, "proposal intact");
    }

    function test_Revert_CancelProposal_NoProposal() public {
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.cancelMutualCancelProposal(id);
    }

    function test_Revert_CancelProposal_AfterSettlementNothingToCancel() public {
        _settle(id, C_SHARE, E_SHARE);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.cancelMutualCancelProposal(id);
    }

    // ------------------------------------------ updateContractor deletes
    function test_UpdateContractor_DeletesContractorsOwnProposal() public {
        _propose(contractor, C_SHARE, E_SHARE);
        vm.expectEmit(true, true, false, false, address(vault));
        emit ArcStreamVault.MutualCancelProposalCancelled(id, contractor);
        vm.expectEmit(true, true, true, true, address(vault));
        emit ArcStreamVault.ContractorUpdated(id, contractor, newContractor);
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);

        (address p, uint256 c, uint256 e) = _proposal(id);
        assertEq(p, address(0));
        assertEq(c + e, 0);

        // employer's identical call is now a fresh proposal, not an acceptance
        _propose(employer, C_SHARE, E_SHARE);
        assertFalse(vault.isSettled(id));
    }

    function test_UpdateContractor_KeepsEmployersProposal() public {
        _propose(employer, C_SHARE, E_SHARE);
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);
        (address p, uint256 c, uint256 e) = _proposal(id);
        assertEq(p, employer);
        assertEq(c, C_SHARE);
        assertEq(e, E_SHARE);
        // the NEW contractor can accept it
        vm.prank(newContractor);
        vault.mutualCancel(id, C_SHARE, E_SHARE);
        assertTrue(vault.isSettled(id));
    }

    function test_UpdateContractor_NoProposalNoCancelEvent() public {
        vm.recordLogs();
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "only ContractorUpdated");
    }
}
