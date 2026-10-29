// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {ArcStreamVaultTestBase} from "./ArcStreamVault.Base.t.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";

/// claimUncontestedMilestone: happy path, exact time boundary, reverts, and who may call.
contract ArcStreamVaultUncontestedTest is ArcStreamVaultTestBase {
    // ------------------------------------------------------------ happy path
    function test_Claim_PaysContractorAfterDefaultWindowWithoutApproval() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        skip(7 days);

        uint256 cBefore = usdc.balanceOf(contractor);
        uint256 vBefore = usdc.balanceOf(address(vault));
        _claimU(id, 0);

        assertEq(usdc.balanceOf(contractor), cBefore + M0);
        assertEq(usdc.balanceOf(address(vault)), vBefore - M0);
        ArcStreamVault.Milestone memory m = vault.getMilestone(id, 0);
        assertTrue(m.isApproved);
        assertTrue(m.isReleased);
        assertEq(vault.getEscrow(id).totalReleased, M0);
        assertEq(vault.submittedUnapprovedCount(id), 0);
        assertEq(vault.approvedPending(id), 0);
        assertFalse(vault.getEscrow(id).isTerminated);
    }

    function test_Claim_EmitsUncontestedMilestoneClaimed() public {
        uint256 id = _createDefault();
        _submit(id, 1);
        skip(7 days);
        vm.expectEmit(true, false, true, true, address(vault));
        emit ArcStreamVault.UncontestedMilestoneClaimed(id, 1, contractor, M1);
        _claimU(id, 1);
    }

    function test_Claim_EventPrecedesTokenTransfer() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        skip(7 days);
        vm.recordLogs();
        _claimU(id, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2, "claim event + token Transfer only");
        assertEq(logs[0].emitter, address(vault));
        assertEq(logs[0].topics[0], ArcStreamVault.UncontestedMilestoneClaimed.selector);
        assertEq(logs[1].emitter, address(usdc));
    }

    function test_Claim_DoesNotEmitMilestoneReleasedOrApproved() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        skip(7 days);
        vm.recordLogs();
        _claimU(id, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != ArcStreamVault.MilestoneReleased.selector);
            assertTrue(logs[i].topics[0] != ArcStreamVault.MilestoneApproved.selector);
        }
    }

    function test_Claim_PaysEachMilestoneIndependently() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        skip(1 days);
        _submit(id, 1);
        skip(6 days); // m0 at 7d, m1 at 6d
        _claimU(id, 0);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.InspectionPeriodActive.selector);
        vault.claimUncontestedMilestone(id, 1);
        skip(1 days);
        _claimU(id, 1);
        assertEq(usdc.balanceOf(contractor), M0 + M1);
        assertEq(vault.getEscrow(id).totalReleased, M0 + M1);
        assertFalse(vault.getMilestone(id, 2).isReleased);
    }

    function test_Claim_AllMilestonesDrainsEscrow() public {
        uint256 id = _createDefault();
        for (uint256 i; i < 3; ++i) {
            _submit(id, i);
        }
        skip(7 days);
        for (uint256 i; i < 3; ++i) {
            _claimU(id, i);
        }
        assertEq(usdc.balanceOf(contractor), TOTAL);
        assertEq(usdc.balanceOf(address(vault)), 0);
        assertEq(_remaining(id), 0);
    }

    function test_Claim_ApprovedAfterWindowAlsoClaimable() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        _approveOnly(id, 0);
        skip(7 days);
        _claimU(id, 0);
        assertEq(usdc.balanceOf(contractor), M0);
    }

    // ------------------------------------------------------------ exact boundary
    function _boundary(uint256 period) internal {
        uint256 id = _createPeriod(period, "");
        _submit(id, 0);
        uint256 deadline = block.timestamp + (period == 0 ? 7 days : period);
        assertEq(vault.uncontestedClaimTime(id, 0), deadline);

        vm.warp(deadline - 1);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.InspectionPeriodActive.selector);
        vault.claimUncontestedMilestone(id, 0);
        assertFalse(vault.getMilestone(id, 0).isReleased);

        vm.warp(deadline);
        _claimU(id, 0);
        assertEq(usdc.balanceOf(contractor), M0);
    }

    function test_Boundary_Default() public {
        _boundary(0);
    }

    function test_Boundary_Min() public {
        _boundary(1 days);
    }

    function test_Boundary_Max() public {
        _boundary(30 days);
    }

    function test_Boundary_Custom() public {
        _boundary(12 days + 345);
    }

    function test_Boundary_ImmediatelyAfterSubmitReverts() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.InspectionPeriodActive.selector);
        vault.claimUncontestedMilestone(id, 0);
    }

    function test_Boundary_LongAfterDeadlineStillClaimable() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        skip(365 days);
        _claimU(id, 0);
        assertEq(usdc.balanceOf(contractor), M0);
    }

    function test_Boundary_ApprovedMilestoneStillSubjectToWindow() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        _approveOnly(id, 0);
        skip(7 days - 1);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.InspectionPeriodActive.selector);
        vault.claimUncontestedMilestone(id, 0);
        // employer-approved work is still payable immediately via release
        vm.prank(contractor);
        vault.releaseMilestone(id, 0, "");
        assertEq(usdc.balanceOf(contractor), M0);
    }

    // ------------------------------------------------------------ resubmission restarts window
    function test_Resubmit_RestartsWindow() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        uint256 firstDeadline = block.timestamp + 7 days;
        vm.warp(firstDeadline - 1);
        _submit(id, 0); // restart one second before the first deadline
        uint256 secondDeadline = block.timestamp + 7 days;

        vm.warp(firstDeadline); // old deadline no longer suffices
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.InspectionPeriodActive.selector);
        vault.claimUncontestedMilestone(id, 0);

        vm.warp(secondDeadline - 1);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.InspectionPeriodActive.selector);
        vault.claimUncontestedMilestone(id, 0);

        vm.warp(secondDeadline);
        _claimU(id, 0);
        assertEq(usdc.balanceOf(contractor), M0);
    }

    function test_Resubmit_AfterDeadlineRestartsInsteadOfClaiming() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        skip(8 days);
        _submit(id, 0); // claim was available, but resubmission re-arms the window
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.InspectionPeriodActive.selector);
        vault.claimUncontestedMilestone(id, 0);
        skip(7 days);
        _claimU(id, 0);
    }

    function test_Resubmit_DoesNotAffectOtherMilestones() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        _submit(id, 1);
        uint256 d1 = vault.uncontestedClaimTime(id, 1);
        skip(3 days);
        _submit(id, 0);
        assertEq(vault.uncontestedClaimTime(id, 1), d1);
    }

    // ------------------------------------------------------------ reverts
    function test_Revert_EscrowNotFound() public {
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.EscrowNotFound.selector);
        vault.claimUncontestedMilestone(7, 0);
    }

    function test_Revert_MilestoneOutOfRange() public {
        uint256 id = _createDefault();
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.MilestoneOutOfRange.selector);
        vault.claimUncontestedMilestone(id, 3);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.MilestoneOutOfRange.selector);
        vault.claimUncontestedMilestone(id, type(uint256).max);
    }

    function test_Revert_WorkNotSubmitted() public {
        uint256 id = _createDefault();
        skip(365 days);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.WorkNotSubmitted.selector);
        vault.claimUncontestedMilestone(id, 0);
    }

    function test_Revert_WorkNotSubmitted_OtherMilestoneSubmitted() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        skip(30 days);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.WorkNotSubmitted.selector);
        vault.claimUncontestedMilestone(id, 1);
    }

    function test_Revert_DoubleClaim_MilestoneAlreadyReleased() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        skip(7 days);
        _claimU(id, 0);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.MilestoneAlreadyReleased.selector);
        vault.claimUncontestedMilestone(id, 0);
        assertEq(usdc.balanceOf(contractor), M0, "paid once");
    }

    function test_Revert_ClaimAfterEmployerRelease_AlreadyReleased() public {
        uint256 id = _createDefault();
        _approve(id, 0);
        _release(id, 0);
        skip(30 days);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.MilestoneAlreadyReleased.selector);
        vault.claimUncontestedMilestone(id, 0);
        assertEq(usdc.balanceOf(contractor), M0, "paid once");
    }

    function test_Revert_ClaimAfterContractorRelease_AlreadyReleased() public {
        uint256 id = _createDefault();
        _approve(id, 0);
        vm.prank(contractor);
        vault.releaseMilestone(id, 0, "");
        skip(30 days);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.MilestoneAlreadyReleased.selector);
        vault.claimUncontestedMilestone(id, 0);
    }

    function test_Revert_InspectionPeriodActive_DoesNotChangeState() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.InspectionPeriodActive.selector);
        vault.claimUncontestedMilestone(id, 0);
        assertEq(vault.submittedUnapprovedCount(id), 1);
        assertEq(vault.getEscrow(id).totalReleased, 0);
        assertEq(usdc.balanceOf(contractor), 0);
    }

    // ------------------------------------------------------------ wrong callers
    function test_Revert_EmployerCannotClaim() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        skip(7 days);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.claimUncontestedMilestone(id, 0);
    }

    function test_Revert_OutsiderCannotClaim() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        skip(7 days);
        vm.prank(outsider);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.claimUncontestedMilestone(id, 0);
    }

    function test_Revert_UnauthorizedPrecedesTimingAndRangeChecks() public {
        uint256 id = _createDefault();
        vm.prank(outsider);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.claimUncontestedMilestone(id, 99);
    }

    function test_Revert_RotatedOutContractorCannotClaim() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);
        skip(7 days);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.claimUncontestedMilestone(id, 0);
    }

    function test_RotatedInContractorCanClaimAndIsPaid() public {
        uint256 id = _createDefault();
        _submit(id, 0); // submitted by the original contractor
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);
        skip(7 days);

        vm.expectEmit(true, false, true, true, address(vault));
        emit ArcStreamVault.UncontestedMilestoneClaimed(id, 0, newContractor, M0);
        vm.prank(newContractor);
        vault.claimUncontestedMilestone(id, 0);

        assertEq(usdc.balanceOf(newContractor), M0);
        assertEq(usdc.balanceOf(contractor), 0);
    }

    function test_RotationDoesNotResetWindow() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        uint256 deadline = vault.uncontestedClaimTime(id, 0);
        skip(3 days);
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);
        assertEq(vault.uncontestedClaimTime(id, 0), deadline);
        vm.warp(deadline);
        vm.prank(newContractor);
        vault.claimUncontestedMilestone(id, 0);
    }
}
