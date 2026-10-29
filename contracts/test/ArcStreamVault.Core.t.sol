// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ArcStreamVault} from "../ArcStreamVault.sol";
import {ArcStreamVaultTestBase} from "./ArcStreamVault.Base.t.sol";

/// Deployment, happy paths, events, getters, updateContractor.
contract ArcStreamVaultCoreTest is ArcStreamVaultTestBase {
    // ---------------------------------------------------------------- deploy
    function test_Constructor_StoresTokenAndStartsEmpty() public view {
        assertEq(address(vault.usdc()), address(usdc));
        assertEq(vault.escrowCount(), 0);
        assertEq(vault.MAX_MILESTONES(), 50);
    }

    // ---------------------------------------------------------- createEscrow
    function test_CreateEscrow_StoresAgreementAndPullsFunds() public {
        uint256 id = _createDefault();
        assertEq(id, 1);
        assertEq(vault.escrowCount(), 1);

        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        assertEq(e.employer, employer);
        assertEq(e.contractor, contractor);
        assertEq(e.totalDeposited, TOTAL);
        assertEq(e.totalReleased, 0);
        assertEq(e.milestoneCount, 3);
        assertFalse(e.isTerminated);

        assertEq(usdc.balanceOf(address(vault)), TOTAL);
        assertEq(usdc.balanceOf(employer), EMPLOYER_FUNDS - TOTAL);
    }

    function test_CreateEscrow_StoresMilestones() public {
        uint256[] memory a = _three();
        string[] memory d = new string[](3);
        d[0] = "design";
        d[1] = "build";
        d[2] = "ship";
        vm.prank(employer);
        uint256 id = vault.createEscrow(contractor, a, d, "");

        ArcStreamVault.Milestone memory m = vault.getMilestone(id, 1);
        assertEq(m.amount, M1);
        assertEq(m.description, "build");
        assertFalse(m.isApproved);
        assertFalse(m.isReleased);
        assertFalse(m.isWorkSubmitted);
        assertEq(m.workProofHash, "");
        assertEq(vault.getMilestone(id, 2).description, "ship");
    }

    function test_CreateEscrow_IdsIncrementAndAreIndependent() public {
        uint256 id1 = _createDefault();
        uint256 id2 = _createDefault();
        assertEq(id1, 1);
        assertEq(id2, 2);
        _approve(id1, 0);
        assertEq(vault.approvedPending(id1), M0);
        assertEq(vault.approvedPending(id2), 0);
        assertEq(usdc.balanceOf(address(vault)), 2 * TOTAL);
    }

    function test_CreateEscrow_EmitsEscrowCreated() public {
        uint256[] memory a = _three();
        string[] memory d = _descs(3);
        vm.expectEmit(true, true, true, true, address(vault));
        emit ArcStreamVault.EscrowCreated(1, employer, contractor, TOTAL, 3);
        vm.prank(employer);
        vault.createEscrow(contractor, a, d, "");
    }

    function test_CreateEscrow_MaxMilestonesAllowed() public {
        uint256[] memory a = new uint256[](50);
        for (uint256 i; i < 50; ++i) {
            a[i] = 1e6;
        }
        string[] memory d = _descs(50);
        vm.prank(employer);
        uint256 id = vault.createEscrow(contractor, a, d, "");
        assertEq(vault.getEscrow(id).milestoneCount, 50);
        assertEq(vault.getEscrow(id).totalDeposited, 50e6);
    }

    function test_CreateEscrow_SingleMilestoneOneUnit() public {
        uint256[] memory a = new uint256[](1);
        a[0] = 1;
        string[] memory d = _descs(1);
        vm.prank(employer);
        uint256 id = vault.createEscrow(contractor, a, d, "");
        assertEq(vault.getEscrow(id).totalDeposited, 1);
    }

    // ------------------------------------------------------ approveMilestone
    function test_ApproveMilestone_SetsFlagAndPending() public {
        uint256 id = _createDefault();
        _approve(id, 1);
        assertTrue(vault.getMilestone(id, 1).isApproved);
        assertFalse(vault.getMilestone(id, 0).isApproved);
        assertEq(vault.approvedPending(id), M1);
        _approve(id, 2);
        assertEq(vault.approvedPending(id), M1 + M2);
    }

    function test_ApproveMilestone_EmitsEvent() public {
        uint256 id = _createDefault();
        _submit(id, 2);
        vm.expectEmit(true, true, false, true, address(vault));
        emit ArcStreamVault.MilestoneApproved(id, 2, employer);
        _approveOnly(id, 2);
    }

    function test_ApproveMilestone_DoesNotMoveFundsOrTerminate() public {
        uint256 id = _createDefault();
        _approve(id, 0);
        assertEq(usdc.balanceOf(address(vault)), TOTAL);
        assertEq(usdc.balanceOf(contractor), 0);
        assertFalse(vault.getEscrow(id).isTerminated);
        assertTrue(vault.getMilestone(id, 0).isWorkSubmitted, "proof flag preserved after approval");
        assertEq(vault.getMilestone(id, 0).workProofHash, PROOF);
    }

    // ------------------------------------------------------ releaseMilestone
    function test_ReleaseMilestone_ByEmployerPaysContractor() public {
        uint256 id = _createDefault();
        _approve(id, 0);
        _release(id, 0);

        assertEq(usdc.balanceOf(contractor), M0);
        assertEq(usdc.balanceOf(address(vault)), TOTAL - M0);
        assertEq(vault.approvedPending(id), 0);
        assertEq(vault.getEscrow(id).totalReleased, M0);
        assertTrue(vault.getMilestone(id, 0).isReleased);
    }

    function test_ReleaseMilestone_ByContractorPaysContractor() public {
        uint256 id = _createDefault();
        _approve(id, 1);
        vm.prank(contractor);
        vault.releaseMilestone(id, 1, "");
        assertEq(usdc.balanceOf(contractor), M1);
    }

    function test_ReleaseMilestone_EmitsEvent() public {
        uint256 id = _createDefault();
        _approve(id, 2);
        vm.expectEmit(true, true, false, true, address(vault));
        emit ArcStreamVault.MilestoneReleased(id, 2, contractor, M2);
        _release(id, 2);
    }

    function test_ReleaseAll_LeavesVaultEmpty() public {
        uint256 id = _createDefault();
        for (uint256 i; i < 3; ++i) {
            _approve(id, i);
            _release(id, i);
        }
        assertEq(usdc.balanceOf(contractor), TOTAL);
        assertEq(usdc.balanceOf(address(vault)), 0);
        assertEq(vault.getEscrow(id).totalReleased, TOTAL);
    }

    // ------------------------------------------------------ refundRemaining
    function test_RefundRemaining_ByEmployerReturnsUnapproved() public {
        uint256 id = _createDefault();
        _approve(id, 0);
        uint256 before_ = usdc.balanceOf(employer);
        _refund(id);
        assertEq(usdc.balanceOf(employer), before_ + M1 + M2);
        assertEq(vault.refundedAmounts(id), M1 + M2);
        assertTrue(vault.getEscrow(id).isTerminated);
        assertEq(usdc.balanceOf(address(vault)), M0);
    }

    function test_RefundRemaining_ByContractorRefundsEmployer() public {
        uint256 id = _createDefault();
        uint256 before_ = usdc.balanceOf(employer);
        vm.prank(contractor);
        vault.refundRemaining(id, "");
        assertEq(usdc.balanceOf(employer), before_ + TOTAL);
        assertEq(usdc.balanceOf(contractor), 0);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_RefundRemaining_EmitsEvent() public {
        uint256 id = _createDefault();
        _approve(id, 1);
        vm.expectEmit(true, true, false, true, address(vault));
        emit ArcStreamVault.EscrowRefunded(id, employer, M0 + M2);
        _refund(id);
    }

    // ------------------------------------------------------ updateContractor
    function test_UpdateContractor_RotatesAndEmits() public {
        uint256 id = _createDefault();
        vm.expectEmit(true, true, true, true, address(vault));
        emit ArcStreamVault.ContractorUpdated(id, contractor, newContractor);
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);
        assertEq(vault.getEscrow(id).contractor, newContractor);
    }

    function test_UpdateContractor_NewWalletReceivesPayout() public {
        uint256 id = _createDefault();
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);
        _approve(id, 0);
        _release(id, 0);
        assertEq(usdc.balanceOf(newContractor), M0);
        assertEq(usdc.balanceOf(contractor), 0);
    }

    function test_UpdateContractor_RotationHandsOverAuthority() public {
        uint256 id = _createDefault();
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);

        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.updateContractor(id, outsider);

        _approve(id, 0);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.releaseMilestone(id, 0, "");

        vm.prank(newContractor);
        vault.releaseMilestone(id, 0, "");
        assertEq(usdc.balanceOf(newContractor), M0);
    }

    function test_UpdateContractor_ChainOfRotations() public {
        uint256 id = _createDefault();
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);
        vm.prank(newContractor);
        vault.updateContractor(id, outsider);
        assertEq(vault.getEscrow(id).contractor, outsider);
    }

    function test_UpdateContractor_WorksAfterTermination() public {
        uint256 id = _createDefault();
        _approve(id, 0);
        _refund(id);
        assertTrue(vault.getEscrow(id).isTerminated);

        vm.expectEmit(true, true, true, true, address(vault));
        emit ArcStreamVault.ContractorUpdated(id, contractor, newContractor);
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);

        // approved-pending milestone is still claimable and goes to the NEW wallet
        _release(id, 0);
        assertEq(usdc.balanceOf(newContractor), M0);
        assertEq(usdc.balanceOf(contractor), 0);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_UpdateContractor_AfterTermination_EmployerStillCannot() public {
        uint256 id = _createDefault();
        _approve(id, 0);
        _refund(id);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.updateContractor(id, newContractor);
    }

    function test_UpdateContractor_AfterTermination_OldWalletLosesRights() public {
        uint256 id = _createDefault();
        _approve(id, 0);
        vm.prank(contractor);
        vault.refundRemaining(id, ""); // contractor-initiated termination
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.updateContractor(id, outsider);
    }

    // ---------------------------------------------------------------- getters
    function test_GetMilestone_UnapprovedFlagsUnchangedAfterTermination() public {
        uint256 id = _createDefault();
        _refund(id);
        ArcStreamVault.Milestone memory m = vault.getMilestone(id, 0);
        assertFalse(m.isApproved);
        assertFalse(m.isReleased);
        assertEq(m.amount, M0);
    }
}
