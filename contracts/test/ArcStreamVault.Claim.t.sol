// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";
import {ArcStreamVaultTestBase} from "./ArcStreamVault.Base.t.sol";

/// claimSettlement: per-party payout, accounting, rotation, guards.
contract ArcStreamVaultClaimTest is ArcStreamVaultTestBase {
    uint256 internal id;
    uint256 internal constant C_SHARE = 250e6;
    uint256 internal constant E_SHARE = TOTAL - 250e6;

    function setUp() public override {
        super.setUp();
        id = _createDefault();
    }

    function _claim(address who) internal {
        vm.prank(who);
        vault.claimSettlement(id);
    }

    // ----------------------------------------------------------- payouts
    function test_Claim_EmployerGetsOwnShareOnly() public {
        _settle(id, C_SHARE, E_SHARE);
        uint256 before_ = usdc.balanceOf(employer);

        vm.expectEmit(true, true, false, true, address(vault));
        emit ArcStreamVault.SettlementClaimed(id, employer, E_SHARE);
        _claim(employer);

        assertEq(usdc.balanceOf(employer), before_ + E_SHARE);
        assertEq(usdc.balanceOf(contractor), 0);
        assertEq(usdc.balanceOf(address(vault)), C_SHARE);
        assertEq(vault.employerSettlementOwed(id), 0);
        assertEq(vault.contractorSettlementOwed(id), C_SHARE, "other share untouched");
        assertEq(vault.refundedAmounts(id), E_SHARE, "employer share adds to refunded");
        assertEq(vault.getEscrow(id).totalReleased, 0);
    }

    function test_Claim_ContractorGetsOwnShareOnly() public {
        _settle(id, C_SHARE, E_SHARE);
        uint256 empBal = usdc.balanceOf(employer);

        vm.expectEmit(true, true, false, true, address(vault));
        emit ArcStreamVault.SettlementClaimed(id, contractor, C_SHARE);
        _claim(contractor);

        assertEq(usdc.balanceOf(contractor), C_SHARE);
        assertEq(usdc.balanceOf(employer), empBal);
        assertEq(usdc.balanceOf(address(vault)), E_SHARE);
        assertEq(vault.contractorSettlementOwed(id), 0);
        assertEq(vault.employerSettlementOwed(id), E_SHARE);
        assertEq(vault.getEscrow(id).totalReleased, C_SHARE, "contractor share adds to totalReleased");
        assertEq(vault.refundedAmounts(id), 0);
    }

    function test_Claim_BothClaim_VaultEmptyAndAccountingClosed() public {
        _settle(id, C_SHARE, E_SHARE);
        _claim(contractor);
        _claim(employer);
        assertEq(usdc.balanceOf(address(vault)), 0);
        assertEq(usdc.balanceOf(contractor), C_SHARE);
        assertEq(usdc.balanceOf(employer), EMPLOYER_FUNDS - TOTAL + E_SHARE);
        assertEq(_remaining(id), 0);
        assertEq(vault.getEscrow(id).totalReleased, C_SHARE);
        assertEq(vault.refundedAmounts(id), E_SHARE);
    }

    function test_Claim_UnclaimedCreditsStayInRemaining() public {
        _settle(id, C_SHARE, E_SHARE);
        assertEq(_remaining(id), TOTAL);
        _claim(employer);
        assertEq(_remaining(id), C_SHARE);
        assertGe(usdc.balanceOf(address(vault)), _remaining(id));
    }

    function test_Claim_EventEmittedBeforeTokenTransfer() public {
        _settle(id, C_SHARE, E_SHARE);
        vm.recordLogs();
        _claim(contractor);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        int256 claimIdx = -1;
        int256 transferIdx = -1;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(vault) && logs[i].topics[0] == ArcStreamVault.SettlementClaimed.selector) {
                claimIdx = int256(i);
            }
            if (logs[i].emitter == address(usdc) && logs[i].topics[0] == keccak256("Transfer(address,address,uint256)"))
            {
                transferIdx = int256(i);
            }
        }
        assertGe(claimIdx, 0, "SettlementClaimed emitted");
        assertGe(transferIdx, 0, "token Transfer emitted");
        assertLt(claimIdx, transferIdx, "event precedes transfer");
    }

    function test_Claim_ZeroShareParty_NothingToRefund() public {
        _settle(id, 0, TOTAL);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.NothingToRefund.selector);
        vault.claimSettlement(id);
        _claim(employer);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_Claim_AfterRefundTerminationSettlement() public {
        _approve(id, 0);
        _refund(id);
        uint256 empAfterRefund = usdc.balanceOf(employer);
        _settle(id, 40e6, M0 - 40e6);
        _claim(contractor);
        _claim(employer);
        assertEq(usdc.balanceOf(contractor), 40e6);
        assertEq(usdc.balanceOf(employer), empAfterRefund + M0 - 40e6);
        assertEq(usdc.balanceOf(address(vault)), 0);
        assertEq(vault.refundedAmounts(id), M1 + M2 + (M0 - 40e6));
        assertEq(_remaining(id), 0);
    }

    // --------------------------------------------------------- rotation
    function test_Claim_ContractorRotatesWalletThenClaims() public {
        _settle(id, C_SHARE, E_SHARE);
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);

        // credit follows the current contractor role
        _claim(newContractor);
        assertEq(usdc.balanceOf(newContractor), C_SHARE);
        assertEq(usdc.balanceOf(contractor), 0);
        assertEq(vault.contractorSettlementOwed(id), 0);
    }

    function test_Claim_OldContractorCannotClaimAfterRotation() public {
        _settle(id, C_SHARE, E_SHARE);
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.claimSettlement(id);
    }

    function test_Claim_RotationAfterSettlementDoesNotChangeEmployerShare() public {
        _settle(id, C_SHARE, E_SHARE);
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);
        _claim(employer);
        assertEq(vault.employerSettlementOwed(id), 0);
        assertEq(vault.contractorSettlementOwed(id), C_SHARE);
    }

    // ----------------------------------------------------------- reverts
    function test_Revert_Claim_NotSettled() public {
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.NotSettled.selector);
        vault.claimSettlement(id);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.NotSettled.selector);
        vault.claimSettlement(id);
    }

    function test_Revert_Claim_NotSettled_WithPendingProposal() public {
        vm.prank(employer);
        vault.mutualCancel(id, C_SHARE, E_SHARE);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.NotSettled.selector);
        vault.claimSettlement(id);
    }

    function test_Revert_Claim_NotSettled_AfterPlainRefund() public {
        _refund(id);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.NotSettled.selector);
        vault.claimSettlement(id);
    }

    function test_Revert_Claim_DoubleClaim() public {
        _settle(id, C_SHARE, E_SHARE);
        _claim(employer);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.NothingToRefund.selector);
        vault.claimSettlement(id);
        _claim(contractor);
        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.NothingToRefund.selector);
        vault.claimSettlement(id);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_Revert_Claim_Outsider() public {
        _settle(id, C_SHARE, E_SHARE);
        vm.prank(outsider);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.claimSettlement(id);
    }

    function test_Claim_OtherEscrowsUnaffected() public {
        uint256 id2 = _createDefault();
        _settle(id, C_SHARE, E_SHARE);
        _claim(employer);
        _claim(contractor);
        assertEq(usdc.balanceOf(address(vault)), TOTAL);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.NotSettled.selector);
        vault.claimSettlement(id2);
        assertEq(_remaining(id2), TOTAL);
    }
}
