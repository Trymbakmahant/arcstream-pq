// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ArcStreamVaultTestBase} from "./ArcStreamVault.Base.t.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";

contract ArcStreamVaultSpecTest is ArcStreamVaultTestBase {
    uint256 internal constant A0 = 100e6;
    uint256 internal constant A1 = 200e6;
    uint256 internal constant SUM = 300e6;
    string internal constant D0 = "Design mockups";
    string internal constant D1 = "Frontend build";
    string internal constant HASH = "ipfs://QmWorkProofHash";

    function _two() internal pure returns (uint256[] memory a, string[] memory d) {
        a = new uint256[](2);
        a[0] = A0;
        a[1] = A1;
        d = new string[](2);
        d[0] = D0;
        d[1] = D1;
    }

    function _createTwo() internal returns (uint256 id) {
        (uint256[] memory a, string[] memory d) = _two();
        vm.prank(employer);
        id = vault.createEscrow(contractor, a, d, bytes32(0));
    }

    // 1
    function test_CreateEscrow() public {
        // Base setUp minted EMPLOYER_FUNDS and approved the vault; top up explicitly.
        usdc.mint(employer, 500e6);
        vm.prank(employer);
        usdc.approve(address(vault), type(uint256).max);
        assertEq(usdc.balanceOf(employer), EMPLOYER_FUNDS + 500e6);
        assertEq(usdc.balanceOf(address(vault)), 0);

        (uint256[] memory a, string[] memory d) = _two();

        vm.expectEmit(true, true, true, true, address(vault));
        emit ArcStreamVault.EscrowCreated(1, employer, contractor, SUM, 2);
        vm.prank(employer);
        uint256 id = vault.createEscrow(contractor, a, d, bytes32(0));

        assertEq(id, 1);
        assertEq(vault.escrowCount(), 1);
        assertEq(usdc.balanceOf(employer), EMPLOYER_FUNDS + 500e6 - SUM);
        assertEq(usdc.balanceOf(address(vault)), SUM);

        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(1);
        assertEq(e.employer, employer);
        assertEq(e.contractor, contractor);
        assertEq(e.totalDeposited, SUM);
        assertEq(e.totalReleased, 0);
        assertEq(e.milestoneCount, 2);
        assertFalse(e.isTerminated);

        ArcStreamVault.Milestone memory m0 = vault.getMilestone(1, 0);
        ArcStreamVault.Milestone memory m1 = vault.getMilestone(1, 1);
        assertEq(m0.amount, A0);
        assertEq(m0.description, D0);
        assertEq(m1.amount, A1);
        assertEq(m1.description, D1);
        assertFalse(m0.isApproved);
        assertFalse(m0.isReleased);
        assertFalse(m0.isWorkSubmitted);
        assertEq(m0.workProofHash, "");
        assertFalse(m1.isApproved);
        assertFalse(m1.isReleased);
        assertFalse(m1.isWorkSubmitted);
    }

    // 2
    function test_SubmitWorkAndApprove() public {
        uint256 id = _createTwo();

        vm.expectEmit(true, false, false, true, address(vault));
        emit ArcStreamVault.WorkSubmitted(id, 0, HASH);
        vm.prank(contractor);
        vault.submitMilestoneWork(id, 0, HASH);

        ArcStreamVault.Milestone memory m = vault.getMilestone(id, 0);
        assertEq(m.workProofHash, HASH);
        assertTrue(m.isWorkSubmitted);
        assertFalse(m.isApproved);
        assertEq(vault.submittedUnapprovedCount(id), 1);

        vm.expectEmit(true, true, false, true, address(vault));
        emit ArcStreamVault.MilestoneApproved(id, 0, employer);
        vm.prank(employer);
        vault.approveMilestone(id, 0);

        m = vault.getMilestone(id, 0);
        assertTrue(m.isApproved);
        assertFalse(m.isReleased);
        assertEq(vault.approvedPending(id), A0);
        assertEq(vault.submittedUnapprovedCount(id), 0);
        assertEq(usdc.balanceOf(contractor), 0);

        vm.expectEmit(true, true, false, true, address(vault));
        emit ArcStreamVault.MilestoneReleased(id, 0, contractor, A0);
        vm.prank(employer);
        vault.releaseMilestone(id, 0, "");

        assertEq(usdc.balanceOf(contractor), A0);
        assertEq(usdc.balanceOf(address(vault)), SUM - A0);
        assertEq(vault.getEscrow(id).totalReleased, A0);
        assertEq(vault.approvedPending(id), 0);
        m = vault.getMilestone(id, 0);
        assertTrue(m.isApproved);
        assertTrue(m.isReleased);
        assertTrue(m.isWorkSubmitted);
        // second milestone untouched
        ArcStreamVault.Milestone memory m1 = vault.getMilestone(id, 1);
        assertFalse(m1.isApproved);
        assertFalse(m1.isReleased);
        assertFalse(m1.isWorkSubmitted);
    }

    // 3
    function test_RevertWhen_EmployerRefundsAfterWorkSubmitted() public {
        uint256 id = _createTwo();
        vm.prank(contractor);
        vault.submitMilestoneWork(id, 0, HASH);

        uint256 empBal = usdc.balanceOf(employer);
        uint256 vaultBal = usdc.balanceOf(address(vault));

        vm.expectRevert(ArcStreamVault.WorkAlreadySubmitted.selector);
        vm.prank(employer);
        vault.refundRemaining(id, "");

        assertEq(usdc.balanceOf(employer), empBal);
        assertEq(usdc.balanceOf(address(vault)), vaultBal);
        assertEq(vaultBal, SUM);
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        assertFalse(e.isTerminated);
        assertEq(e.totalReleased, 0);
        assertEq(e.totalDeposited, SUM);
        assertEq(vault.refundedAmounts(id), 0);
        assertEq(vault.submittedUnapprovedCount(id), 1);
        assertEq(vault.approvedPending(id), 0);
    }

    // 4
    function test_MutualCancelFlow() public {
        uint256 id = _createTwo();
        uint256 half = SUM / 2; // 150e6
        uint256 empBefore = usdc.balanceOf(employer);

        vm.expectEmit(true, true, false, true, address(vault));
        emit ArcStreamVault.MutualCancelProposed(id, employer, half, half);
        vm.prank(employer);
        vault.mutualCancel(id, half, half);

        (address proposer, uint256 cs, uint256 es) = vault.mutualCancelProposals(id);
        assertEq(proposer, employer);
        assertEq(cs, half);
        assertEq(es, half);
        assertFalse(vault.isSettled(id));

        vm.expectEmit(true, false, false, true, address(vault));
        emit ArcStreamVault.EscrowMutuallyCancelled(id, half, half);
        vm.prank(contractor);
        vault.mutualCancel(id, half, half);

        assertTrue(vault.isSettled(id));
        assertTrue(vault.getEscrow(id).isTerminated);
        assertEq(vault.contractorSettlementOwed(id), half);
        assertEq(vault.employerSettlementOwed(id), half);
        assertEq(vault.approvedPending(id), 0);
        (proposer, cs, es) = vault.mutualCancelProposals(id);
        assertEq(proposer, address(0));
        assertEq(cs, 0);
        assertEq(es, 0);
        // no transfer yet
        assertEq(usdc.balanceOf(address(vault)), SUM);

        vm.expectEmit(true, true, false, true, address(vault));
        emit ArcStreamVault.SettlementClaimed(id, contractor, half);
        vm.prank(contractor);
        vault.claimSettlement(id);

        vm.expectEmit(true, true, false, true, address(vault));
        emit ArcStreamVault.SettlementClaimed(id, employer, half);
        vm.prank(employer);
        vault.claimSettlement(id);

        assertEq(usdc.balanceOf(contractor), 150e6);
        assertEq(usdc.balanceOf(employer), empBefore + 150e6);
        assertEq(usdc.balanceOf(address(vault)), 0);
        assertEq(vault.contractorSettlementOwed(id), 0);
        assertEq(vault.employerSettlementOwed(id), 0);
        assertEq(vault.getEscrow(id).totalReleased, half);
        assertEq(vault.refundedAmounts(id), half);

        // second claims revert
        vm.expectRevert(ArcStreamVault.NothingToRefund.selector);
        vm.prank(contractor);
        vault.claimSettlement(id);
        vm.expectRevert(ArcStreamVault.NothingToRefund.selector);
        vm.prank(employer);
        vault.claimSettlement(id);

        assertEq(usdc.balanceOf(contractor), 150e6);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    // 5
    function test_UpdateContractor() public {
        uint256 id = _createTwo();
        uint256 half = SUM / 2;
        uint256 empBefore = usdc.balanceOf(employer);

        // settle first (credit follows the *current* contractor role)
        vm.prank(employer);
        vault.mutualCancel(id, half, half);
        vm.prank(contractor);
        vault.mutualCancel(id, half, half);
        assertTrue(vault.isSettled(id));

        vm.expectEmit(true, true, true, true, address(vault));
        emit ArcStreamVault.ContractorUpdated(id, contractor, newContractor);
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);
        assertEq(vault.getEscrow(id).contractor, newContractor);

        // old address is no longer a party
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vm.prank(contractor);
        vault.claimSettlement(id);
        assertEq(usdc.balanceOf(contractor), 0);
        assertEq(usdc.balanceOf(address(vault)), SUM);
        assertEq(vault.contractorSettlementOwed(id), half);

        // new address claims exactly the contractor half
        vm.expectEmit(true, true, false, true, address(vault));
        emit ArcStreamVault.SettlementClaimed(id, newContractor, half);
        vm.prank(newContractor);
        vault.claimSettlement(id);

        assertEq(usdc.balanceOf(newContractor), half);
        assertEq(usdc.balanceOf(contractor), 0);
        assertEq(usdc.balanceOf(address(vault)), half);
        assertEq(vault.contractorSettlementOwed(id), 0);

        // employer still claims own half
        vm.prank(employer);
        vault.claimSettlement(id);
        assertEq(usdc.balanceOf(employer), empBefore + half);
        assertEq(usdc.balanceOf(address(vault)), 0);

        // old address still cannot claim; new address cannot double claim
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vm.prank(contractor);
        vault.claimSettlement(id);
        vm.expectRevert(ArcStreamVault.NothingToRefund.selector);
        vm.prank(newContractor);
        vault.claimSettlement(id);
    }

    // 6
    function test_RevertWhen_DoubleRelease() public {
        uint256 id = _createTwo();
        vm.prank(contractor);
        vault.submitMilestoneWork(id, 0, HASH);
        vm.prank(employer);
        vault.approveMilestone(id, 0);
        vm.prank(employer);
        vault.releaseMilestone(id, 0, "");
        assertEq(usdc.balanceOf(contractor), A0);

        vm.expectRevert(ArcStreamVault.MilestoneAlreadyReleased.selector);
        vm.prank(employer);
        vault.releaseMilestone(id, 0, "");

        vm.expectRevert(ArcStreamVault.MilestoneAlreadyReleased.selector);
        vm.prank(contractor);
        vault.releaseMilestone(id, 0, "");

        assertEq(usdc.balanceOf(contractor), A0);
        assertEq(usdc.balanceOf(address(vault)), SUM - A0);
        assertEq(vault.getEscrow(id).totalReleased, A0);
    }
}
