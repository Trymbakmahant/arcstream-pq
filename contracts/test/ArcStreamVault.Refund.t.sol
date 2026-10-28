// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ArcStreamVault} from "../ArcStreamVault.sol";
import {ArcStreamVaultTestBase} from "./ArcStreamVault.Base.t.sol";

/// refundRemaining accounting.
contract ArcStreamVaultRefundTest is ArcStreamVaultTestBase {
    function test_Refund_ApprovedPendingStaysClaimableByContractor() public {
        uint256 id = _createDefault();
        _approve(id, 0);
        _approve(id, 2);
        _refund(id);

        assertEq(vault.refundedAmounts(id), M1);
        assertEq(vault.approvedPending(id), M0 + M2);
        assertEq(usdc.balanceOf(address(vault)), M0 + M2);

        vm.prank(contractor);
        vault.releaseMilestone(id, 0, "");
        vm.prank(contractor);
        vault.releaseMilestone(id, 2, "");
        assertEq(usdc.balanceOf(contractor), M0 + M2);
        assertEq(usdc.balanceOf(address(vault)), 0);
        assertEq(vault.approvedPending(id), 0);
        assertEq(vault.getEscrow(id).totalReleased, M0 + M2);
    }

    function test_Refund_ApprovedPendingClaimableByEmployerCall() public {
        uint256 id = _createDefault();
        _approve(id, 1);
        _refund(id);
        _release(id, 1);
        assertEq(usdc.balanceOf(contractor), M1);
    }

    function test_Refund_ExcludesAlreadyReleased() public {
        uint256 id = _createDefault();
        _approve(id, 0);
        _release(id, 0);
        uint256 before_ = usdc.balanceOf(employer);
        _refund(id);
        assertEq(usdc.balanceOf(employer), before_ + M1 + M2);
        assertEq(vault.refundedAmounts(id), M1 + M2);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_Refund_NoDoubleRefund() public {
        uint256 id = _createDefault();
        _approve(id, 0);
        _refund(id);
        uint256 empBal = usdc.balanceOf(employer);
        uint256 vaultBal = usdc.balanceOf(address(vault));

        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.EscrowTerminated.selector);
        vault.refundRemaining(id, "");

        // even after the pending milestone is released, a second refund is impossible
        _release(id, 0);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.EscrowTerminated.selector);
        vault.refundRemaining(id, "");

        assertEq(usdc.balanceOf(employer), empBal);
        assertEq(vaultBal, M0);
        assertEq(vault.refundedAmounts(id), M1 + M2);
    }

    function test_Refund_NothingToRefund_WhenAllApproved() public {
        uint256 id = _createDefault();
        for (uint256 i; i < 3; ++i) {
            _approve(id, i);
        }
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.NothingToRefund.selector);
        vault.refundRemaining(id, "");
        // does NOT terminate: state untouched
        assertFalse(vault.getEscrow(id).isTerminated);
        assertEq(vault.refundedAmounts(id), 0);
    }

    function test_Refund_NothingToRefund_WhenAllReleased() public {
        uint256 id = _createDefault();
        for (uint256 i; i < 3; ++i) {
            _approve(id, i);
            _release(id, i);
        }
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.NothingToRefund.selector);
        vault.refundRemaining(id, "");
    }

    function test_Refund_NothingToRefund_MixedApprovedReleased() public {
        uint256 id = _createDefault();
        for (uint256 i; i < 3; ++i) {
            _approve(id, i);
        }
        _release(id, 1);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.NothingToRefund.selector);
        vault.refundRemaining(id, "");
    }

    function test_Refund_AfterNothingToRefund_ApprovalsStillWork() public {
        // all-but... create single-milestone escrow, approve, refund fails, escrow stays live
        uint256[] memory a = new uint256[](1);
        a[0] = 5e6;
        string[] memory d = _descs(1);
        vm.prank(employer);
        uint256 id = vault.createEscrow(contractor, a, d, bytes32(0));
        _approve(id, 0);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.NothingToRefund.selector);
        vault.refundRemaining(id, "");
        _release(id, 0);
        assertEq(usdc.balanceOf(contractor), 5e6);
    }

    function test_Refund_OtherEscrowsUnaffected() public {
        uint256 id1 = _createDefault();
        uint256 id2 = _createDefault();
        _refund(id1);
        assertFalse(vault.getEscrow(id2).isTerminated);
        assertEq(usdc.balanceOf(address(vault)), TOTAL);
        _approve(id2, 0);
        _release(id2, 0);
        assertEq(usdc.balanceOf(contractor), M0);
    }

    function test_Refund_GoesToEmployerEvenWhenContractorCalls() public {
        uint256 id = _createDefault();
        _approve(id, 2);
        vm.prank(contractor);
        vault.refundRemaining(id, "");
        assertEq(usdc.balanceOf(contractor), 0);
        assertEq(usdc.balanceOf(employer), EMPLOYER_FUNDS - M2);
    }

    function test_Refund_AfterContractorRotation_StillPaysEmployer() public {
        uint256 id = _createDefault();
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);
        vm.prank(newContractor);
        vault.refundRemaining(id, "");
        assertEq(usdc.balanceOf(employer), EMPLOYER_FUNDS);
    }
}
