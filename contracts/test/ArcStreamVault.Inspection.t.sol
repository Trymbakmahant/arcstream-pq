// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ArcStreamVaultTestBase} from "./ArcStreamVault.Base.t.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";

/// createEscrow(inspectionPeriod) validation, submittedAt recording, and uncontestedClaimTime.
contract ArcStreamVaultInspectionTest is ArcStreamVaultTestBase {
    // ------------------------------------------------------------ constants
    function test_Constants() public view {
        assertEq(vault.DEFAULT_INSPECTION_PERIOD(), 7 days);
        assertEq(vault.MIN_INSPECTION_PERIOD(), 1 days);
        assertEq(vault.MAX_INSPECTION_PERIOD(), 30 days);
    }

    // ------------------------------------------------------------ period selection
    function test_Create_ZeroSelectsDefaultSevenDays() public {
        uint256 id = _createPeriod(0, "");
        assertEq(vault.getEscrow(id).inspectionPeriod, 7 days);
    }

    function test_Create_MinPeriodAccepted() public {
        uint256 id = _createPeriod(1 days, "");
        assertEq(vault.getEscrow(id).inspectionPeriod, 1 days);
    }

    function test_Create_MaxPeriodAccepted() public {
        uint256 id = _createPeriod(30 days, "");
        assertEq(vault.getEscrow(id).inspectionPeriod, 30 days);
    }

    function test_Create_ExplicitSevenDaysEqualsDefault() public {
        uint256 id = _createPeriod(7 days, "");
        assertEq(vault.getEscrow(id).inspectionPeriod, vault.DEFAULT_INSPECTION_PERIOD());
    }

    function test_Create_OneSecondBelowMinReverts() public {
        uint256[] memory a = _three();
        string[] memory d = _descs(3);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.InvalidInspectionPeriod.selector);
        vault.createEscrow(contractor, a, d, "", 1 days - 1);
    }

    function test_Create_OneSecondReverts() public {
        uint256[] memory a = _three();
        string[] memory d = _descs(3);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.InvalidInspectionPeriod.selector);
        vault.createEscrow(contractor, a, d, "", 1);
    }

    function test_Create_OneSecondAboveMaxReverts() public {
        uint256[] memory a = _three();
        string[] memory d = _descs(3);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.InvalidInspectionPeriod.selector);
        vault.createEscrow(contractor, a, d, "", 30 days + 1);
    }

    function test_Create_HugePeriodReverts() public {
        uint256[] memory a = _three();
        string[] memory d = _descs(3);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.InvalidInspectionPeriod.selector);
        vault.createEscrow(contractor, a, d, "", type(uint256).max);
    }

    function test_Create_InvalidPeriodMovesNoFundsAndCreatesNothing() public {
        uint256[] memory a = _three();
        string[] memory d = _descs(3);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.InvalidInspectionPeriod.selector);
        vault.createEscrow(contractor, a, d, "", 31 days);
        assertEq(vault.escrowCount(), 0);
        assertEq(usdc.balanceOf(address(vault)), 0);
        assertEq(usdc.balanceOf(employer), EMPLOYER_FUNDS);
    }

    function test_Create_PeriodIsPerEscrow() public {
        uint256 a = _createPeriod(2 days, "");
        uint256 b = _createPeriod(0, "");
        uint256 c = _createPeriod(30 days, pqKey);
        assertEq(vault.getEscrow(a).inspectionPeriod, 2 days);
        assertEq(vault.getEscrow(b).inspectionPeriod, 7 days);
        assertEq(vault.getEscrow(c).inspectionPeriod, 30 days);
    }

    function test_Create_ProtectedEscrowStoresPeriodAndKey() public {
        uint256 id = _createPeriod(3 days, pqKey);
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        assertEq(e.inspectionPeriod, 3 days);
        assertTrue(e.isPQProtected);
        assertEq(e.pqPublicKey, pqKey);
    }

    function test_Create_OtherValidationsStillPrecedeOrCoexist() public {
        // zero contractor still reverts InvalidContractor even with a valid period
        uint256[] memory a = _three();
        string[] memory d = _descs(3);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.InvalidContractor.selector);
        vault.createEscrow(address(0), a, d, "", 7 days);
    }

    // ------------------------------------------------------------ submittedAt
    function test_NewMilestone_SubmittedAtIsZero() public {
        uint256 id = _createPeriod(0, "");
        for (uint256 i; i < 3; ++i) {
            assertEq(vault.getMilestone(id, i).submittedAt, 0);
        }
    }

    function test_Submit_RecordsBlockTimestamp() public {
        uint256 id = _createPeriod(0, "");
        vm.warp(1_700_000_000);
        _submit(id, 1);
        assertEq(vault.getMilestone(id, 1).submittedAt, 1_700_000_000);
        assertEq(vault.getMilestone(id, 0).submittedAt, 0, "other milestones untouched");
        assertEq(vault.getMilestones(id)[1].submittedAt, 1_700_000_000);
    }

    function test_Resubmit_RestartsSubmittedAt() public {
        uint256 id = _createPeriod(0, "");
        vm.warp(1_000_000);
        _submit(id, 0);
        vm.warp(1_000_000 + 3 days);
        _submit(id, 0);
        assertEq(vault.getMilestone(id, 0).submittedAt, 1_000_000 + 3 days);
        assertEq(vault.submittedUnapprovedCount(id), 1, "resubmit does not double count");
    }

    function test_Submit_EmitsWorkSubmittedUnchanged() public {
        uint256 id = _createPeriod(0, "");
        vm.expectEmit(true, false, false, true, address(vault));
        emit ArcStreamVault.WorkSubmitted(id, 2, PROOF);
        _submit(id, 2);
    }

    function test_FailedSubmit_DoesNotChangeSubmittedAt() public {
        uint256 id = _createPeriod(0, "");
        vm.warp(5_000_000);
        _submit(id, 0);
        _approveOnly(id, 0);
        vm.warp(5_000_000 + 1 days);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.MilestoneAlreadyApproved.selector);
        vault.submitMilestoneWork(id, 0, "again");
        assertEq(vault.getMilestone(id, 0).submittedAt, 5_000_000);
    }

    // ------------------------------------------------------------ uncontestedClaimTime view
    function test_ClaimTime_ZeroBeforeSubmission() public {
        uint256 id = _createPeriod(0, "");
        assertEq(vault.uncontestedClaimTime(id, 0), 0);
    }

    function test_ClaimTime_IsSubmittedAtPlusPeriod() public {
        uint256 id = _createPeriod(5 days, "");
        vm.warp(2_000_000);
        _submit(id, 0);
        assertEq(vault.uncontestedClaimTime(id, 0), 2_000_000 + 5 days);
        assertEq(vault.uncontestedClaimTime(id, 1), 0);
    }

    function test_ClaimTime_UsesDefaultForZeroPeriod() public {
        uint256 id = _createPeriod(0, "");
        _submit(id, 0);
        assertEq(vault.uncontestedClaimTime(id, 0), block.timestamp + 7 days);
    }

    function test_ClaimTime_RestartsOnResubmission() public {
        uint256 id = _createPeriod(2 days, "");
        vm.warp(10_000_000);
        _submit(id, 0);
        vm.warp(10_000_000 + 1 days);
        _submit(id, 0);
        assertEq(vault.uncontestedClaimTime(id, 0), 10_000_000 + 1 days + 2 days);
    }

    function test_ClaimTime_StillReportedAfterApprovalButZeroAfterRelease() public {
        uint256 id = _createPeriod(0, "");
        vm.warp(3_000_000);
        _submit(id, 0);
        _approveOnly(id, 0);
        assertEq(vault.uncontestedClaimTime(id, 0), 3_000_000 + 7 days);
        _release(id, 0);
        assertEq(vault.uncontestedClaimTime(id, 0), 0);
    }

    function test_ClaimTime_ZeroAfterUncontestedClaim() public {
        uint256 id = _createPeriod(1 days, "");
        _submit(id, 0);
        skip(1 days);
        _claimU(id, 0);
        assertEq(vault.uncontestedClaimTime(id, 0), 0);
    }

    function test_ClaimTime_HistoricalAfterRefundTermination() public {
        uint256 id = _createPeriod(1 days, "");
        vm.warp(4_000_000);
        _submit(id, 0);
        _approveOnly(id, 0);
        // submit/approve leave nothing unsubmitted-unapproved blocking refund: refund the other two
        _refund(id);
        assertTrue(vault.getEscrow(id).isTerminated);
        assertEq(vault.uncontestedClaimTime(id, 0), 4_000_000 + 1 days);
    }

    function test_ClaimTime_RevertsOnUnknownEscrow() public {
        vm.expectRevert(ArcStreamVault.EscrowNotFound.selector);
        vault.uncontestedClaimTime(1, 0);
    }

    function test_ClaimTime_RevertsOutOfRange() public {
        uint256 id = _createPeriod(0, "");
        vm.expectRevert(ArcStreamVault.MilestoneOutOfRange.selector);
        vault.uncontestedClaimTime(id, 3);
    }
}
