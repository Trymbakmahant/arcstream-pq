// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {stdError} from "forge-std/Test.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";
import {FeeOnTransferToken} from "../test-helpers/FeeOnTransferToken.sol";
import {ArcStreamVaultTestBase} from "./ArcStreamVault.Base.t.sol";

/// Every custom error + access control.
contract ArcStreamVaultRevertTest is ArcStreamVaultTestBase {
    // ------------------------------------------------------- InvalidToken
    function test_Revert_Constructor_ZeroAddress() public {
        vm.expectRevert(ArcStreamVault.InvalidToken.selector);
        new ArcStreamVault(address(0));
    }

    function test_Revert_Constructor_EoaToken() public {
        vm.expectRevert(ArcStreamVault.InvalidToken.selector);
        new ArcStreamVault(outsider);
    }

    // ------------------------------------------------- createEscrow reverts
    function test_Revert_Create_ZeroContractor() public {
        uint256[] memory a = _three();
        string[] memory d = _descs(3);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.InvalidContractor.selector);
        vault.createEscrow(address(0), a, d, "");
    }

    function test_Revert_Create_ContractorIsEmployer() public {
        uint256[] memory a = _three();
        string[] memory d = _descs(3);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.InvalidContractor.selector);
        vault.createEscrow(employer, a, d, "");
    }

    function test_Revert_Create_ArrayLengthMismatch() public {
        uint256[] memory a = _three();
        string[] memory d = _descs(2);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.ArrayLengthMismatch.selector);
        vault.createEscrow(contractor, a, d, "");
    }

    function test_Revert_Create_ZeroMilestones() public {
        uint256[] memory a = new uint256[](0);
        string[] memory d = new string[](0);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.InvalidMilestoneCount.selector);
        vault.createEscrow(contractor, a, d, "");
    }

    function test_Revert_Create_TooManyMilestones() public {
        uint256[] memory a = new uint256[](51);
        for (uint256 i; i < 51; ++i) {
            a[i] = 1e6;
        }
        string[] memory d = _descs(51);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.InvalidMilestoneCount.selector);
        vault.createEscrow(contractor, a, d, "");
    }

    function test_Revert_Create_ZeroAmount() public {
        uint256[] memory a = _three();
        a[1] = 0;
        string[] memory d = _descs(3);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.InvalidAmount.selector);
        vault.createEscrow(contractor, a, d, "");
        assertEq(vault.escrowCount(), 0);
    }

    function test_Revert_Create_TotalOverflow() public {
        uint256[] memory a = new uint256[](2);
        a[0] = type(uint256).max;
        a[1] = 1;
        string[] memory d = _descs(2);
        vm.prank(employer);
        vm.expectRevert(stdError.arithmeticError);
        vault.createEscrow(contractor, a, d, "");
    }

    function test_Revert_Create_InsufficientAllowance() public {
        vm.prank(employer);
        usdc.approve(address(vault), TOTAL - 1);
        uint256[] memory a = _three();
        string[] memory d = _descs(3);
        vm.prank(employer);
        vm.expectRevert();
        vault.createEscrow(contractor, a, d, "");
        assertEq(vault.escrowCount(), 0);
    }

    function test_Revert_Create_InsufficientBalance() public {
        address poor = makeAddr("poor");
        vm.prank(poor);
        usdc.approve(address(vault), type(uint256).max);
        uint256[] memory a = _three();
        string[] memory d = _descs(3);
        vm.prank(poor);
        vm.expectRevert();
        vault.createEscrow(contractor, a, d, "");
    }

    // ----------------------------------------- UnexpectedTokenReceipt (fee)
    function _feeVault(uint256 feeBps, uint256 bonus) internal returns (ArcStreamVault v, FeeOnTransferToken t) {
        t = new FeeOnTransferToken();
        v = new ArcStreamVault(address(t));
        t.setFeeBps(feeBps);
        t.setBonus(bonus);
        t.mint(employer, 1_000_000e6);
        vm.prank(employer);
        t.approve(address(v), type(uint256).max);
    }

    function test_Revert_Create_FeeOnTransferToken() public {
        (ArcStreamVault v, FeeOnTransferToken t) = _feeVault(100, 0); // 1% fee
        uint256[] memory a = _three();
        string[] memory d = _descs(3);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.UnexpectedTokenReceipt.selector);
        v.createEscrow(contractor, a, d, "");
        // atomic: no escrow persisted, no funds moved
        assertEq(v.escrowCount(), 0);
        assertEq(t.balanceOf(address(v)), 0);
        assertEq(t.balanceOf(employer), 1_000_000e6);
    }

    function test_Revert_Create_OverDeliveringToken() public {
        (ArcStreamVault v,) = _feeVault(0, 1);
        uint256[] memory a = _three();
        string[] memory d = _descs(3);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.UnexpectedTokenReceipt.selector);
        v.createEscrow(contractor, a, d, "");
        assertEq(v.escrowCount(), 0);
    }

    function test_Create_ZeroFeeTokenWorks() public {
        (ArcStreamVault v,) = _feeVault(0, 0);
        uint256[] memory a = _three();
        string[] memory d = _descs(3);
        vm.prank(employer);
        assertEq(v.createEscrow(contractor, a, d, ""), 1);
    }

    // ------------------------------------------------------ EscrowNotFound
    function test_Revert_EscrowNotFound_AllEntryPoints() public {
        _createDefault();
        bytes4 sel = ArcStreamVault.EscrowNotFound.selector;

        vm.prank(contractor);
        vm.expectRevert(sel);
        vault.updateContractor(99, newContractor);

        vm.prank(employer);
        vm.expectRevert(sel);
        vault.approveMilestone(99, 0);

        vm.prank(employer);
        vm.expectRevert(sel);
        vault.releaseMilestone(99, 0, "");

        vm.prank(employer);
        vm.expectRevert(sel);
        vault.refundRemaining(99, "");

        vm.expectRevert(sel);
        vault.getEscrow(99);

        vm.expectRevert(sel);
        vault.getMilestone(99, 0);

        vm.expectRevert(sel);
        vault.getMilestones(99);

        vm.prank(contractor);
        vm.expectRevert(sel);
        vault.submitMilestoneWork(99, 0, "p");

        vm.prank(employer);
        vm.expectRevert(sel);
        vault.mutualCancel(99, 0, 0);

        vm.prank(employer);
        vm.expectRevert(sel);
        vault.claimSettlement(99);
    }

    function test_Revert_Approve_WorkNotSubmitted_Direct() public {
        uint256 id = _createDefault();
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.WorkNotSubmitted.selector);
        vault.approveMilestone(id, 0);
    }

    function test_Revert_Release_AfterSettlement_EscrowSettled() public {
        uint256 id = _createDefault();
        _approve(id, 0);
        _settle(id, M0, TOTAL - M0);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.EscrowSettled.selector);
        vault.releaseMilestone(id, 0, "");
    }

    function test_Revert_NewEntryPoints_Unauthorized() public {
        uint256 id = _createDefault();
        vm.startPrank(outsider);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.submitMilestoneWork(id, 0, "p");
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.mutualCancel(id, 0, TOTAL);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.claimSettlement(id);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.cancelMutualCancelProposal(id);
        vm.stopPrank();
    }

    function test_Revert_EscrowNotFound_IdZero() public {
        _createDefault();
        vm.expectRevert(ArcStreamVault.EscrowNotFound.selector);
        vault.getEscrow(0);
    }

    // ------------------------------------------------------- Unauthorized
    function test_Revert_UpdateContractor_Unauthorized() public {
        uint256 id = _createDefault();
        vm.prank(outsider);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.updateContractor(id, newContractor);
        vm.prank(employer); // employer cannot change contractor
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.updateContractor(id, newContractor);
    }

    function test_Revert_Approve_Unauthorized() public {
        uint256 id = _createDefault();
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.approveMilestone(id, 0);
        vm.prank(outsider);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.approveMilestone(id, 0);
    }

    function test_Revert_Release_Unauthorized() public {
        uint256 id = _createDefault();
        _approve(id, 0);
        vm.prank(outsider);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.releaseMilestone(id, 0, "");
    }

    function test_Revert_Refund_Unauthorized() public {
        uint256 id = _createDefault();
        vm.prank(outsider);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.refundRemaining(id, "");
    }

    // ------------------------------------------------- InvalidContractor (update)
    function test_Revert_Update_ZeroAddress() public {
        uint256 id = _createDefault();
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.InvalidContractor.selector);
        vault.updateContractor(id, address(0));
    }

    function test_Revert_Update_ToEmployer() public {
        uint256 id = _createDefault();
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.InvalidContractor.selector);
        vault.updateContractor(id, employer);
    }

    function test_Revert_Update_ToSameContractor() public {
        uint256 id = _createDefault();
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.InvalidContractor.selector);
        vault.updateContractor(id, contractor);
    }

    // -------------------------------------------------- MilestoneOutOfRange
    function test_Revert_OutOfRange_ApproveReleaseGet() public {
        uint256 id = _createDefault();
        bytes4 sel = ArcStreamVault.MilestoneOutOfRange.selector;
        vm.prank(employer);
        vm.expectRevert(sel);
        vault.approveMilestone(id, 3);
        vm.prank(employer);
        vm.expectRevert(sel);
        vault.releaseMilestone(id, 3, "");
        vm.expectRevert(sel);
        vault.getMilestone(id, 3);
    }

    // --------------------------------------------------- EscrowTerminated
    function test_Revert_Approve_AfterTermination() public {
        uint256 id = _createDefault();
        _approve(id, 0);
        _refund(id);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.EscrowTerminated.selector);
        vault.approveMilestone(id, 1);
    }

    function test_Revert_Refund_Twice() public {
        uint256 id = _createDefault();
        _approve(id, 0);
        _refund(id);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.EscrowTerminated.selector);
        vault.refundRemaining(id, "");
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.EscrowTerminated.selector);
        vault.refundRemaining(id, "");
    }

    // ------------------------------------------- Already approved / released
    function test_Revert_Approve_Twice() public {
        uint256 id = _createDefault();
        _approve(id, 0);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.MilestoneAlreadyApproved.selector);
        vault.approveMilestone(id, 0);
    }

    function test_Revert_Release_Twice() public {
        uint256 id = _createDefault();
        _approve(id, 0);
        _release(id, 0);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.MilestoneAlreadyReleased.selector);
        vault.releaseMilestone(id, 0, "");
        assertEq(usdc.balanceOf(contractor), M0);
    }

    function test_Revert_Approve_AfterRelease() public {
        uint256 id = _createDefault();
        _approve(id, 0);
        _release(id, 0);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.MilestoneAlreadyReleased.selector);
        vault.approveMilestone(id, 0);
    }

    // -------------------------------------------------- MilestoneNotApproved
    function test_Revert_Release_NotApproved() public {
        uint256 id = _createDefault();
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.MilestoneNotApproved.selector);
        vault.releaseMilestone(id, 0, "");
    }

    function test_Revert_Release_UnapprovedAfterTermination() public {
        uint256 id = _createDefault();
        _approve(id, 0);
        _refund(id);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.MilestoneNotApproved.selector);
        vault.releaseMilestone(id, 1, "");
    }
}
