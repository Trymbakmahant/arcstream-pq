// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ArcStreamVault} from "../ArcStreamVault.sol";
import {ArcStreamVaultTestBase} from "./ArcStreamVault.Base.t.sol";

contract ArcStreamVaultFuzzTest is ArcStreamVaultTestBase {
    uint256 internal constant MAX_AMT = 1e12 * 1e6; // 1 trillion USDC per milestone

    function _amounts(uint256 seed, uint256 n) internal pure returns (uint256[] memory a, uint256 sum) {
        a = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            a[i] = bound_(uint256(keccak256(abi.encode(seed, i))), 1, MAX_AMT);
            sum += a[i];
        }
    }

    function bound_(uint256 x, uint256 lo, uint256 hi) internal pure returns (uint256) {
        return lo + (x % (hi - lo + 1));
    }

    function _fundEmployer(uint256 amount) internal {
        usdc.mint(employer, amount);
    }

    function testFuzz_CreateEscrow_TotalsAndBalances(uint256 seed, uint8 nRaw) public {
        uint256 n = bound(nRaw, 1, 50);
        (uint256[] memory a, uint256 sum) = _amounts(seed, n);
        _fundEmployer(sum);
        string[] memory d = _descs(n);
        uint256 empBefore = usdc.balanceOf(employer);

        vm.prank(employer);
        uint256 id = vault.createEscrow(contractor, a, d, "");

        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        assertEq(e.totalDeposited, sum);
        assertEq(e.milestoneCount, n);
        assertEq(usdc.balanceOf(address(vault)), sum);
        assertEq(usdc.balanceOf(employer), empBefore - sum);
        for (uint256 i; i < n; ++i) {
            assertEq(vault.getMilestone(id, i).amount, a[i]);
        }
    }

    /// Release/refund conservation: contractor gets exactly sum(approved), employer exactly
    /// sum(unapproved), vault ends at zero, and balance tracks deposited - released - refunded at each step.
    function testFuzz_ReleaseRefundConservation(uint256 seed, uint8 nRaw, uint64 approveMask, uint64 releaseMask)
        public
    {
        uint256 n = bound(nRaw, 1, 50);
        (uint256[] memory a, uint256 total) = _amounts(seed, n);
        _fundEmployer(total);
        string[] memory d = _descs(n);
        uint256 empStart = usdc.balanceOf(employer);

        vm.prank(employer);
        uint256 id = vault.createEscrow(contractor, a, d, "");

        uint256 approvedSum;
        for (uint256 i; i < n; ++i) {
            if ((approveMask >> i) & 1 == 1) {
                _approve(id, i);
                approvedSum += a[i];
            }
        }
        assertEq(vault.approvedPending(id), approvedSum);

        uint256 releasedSum;
        for (uint256 i; i < n; ++i) {
            if ((approveMask >> i) & 1 == 1 && (releaseMask >> i) & 1 == 1) {
                _release(id, i);
                releasedSum += a[i];
            }
        }
        assertEq(usdc.balanceOf(contractor), releasedSum);
        assertEq(usdc.balanceOf(address(vault)), total - releasedSum);
        assertEq(vault.getEscrow(id).totalReleased, releasedSum);
        assertEq(vault.approvedPending(id), approvedSum - releasedSum);

        uint256 unapproved = total - approvedSum;
        if (unapproved == 0) {
            vm.prank(employer);
            vm.expectRevert(ArcStreamVault.NothingToRefund.selector);
            vault.refundRemaining(id, "");
            assertFalse(vault.getEscrow(id).isTerminated);
        } else {
            _refund(id);
            assertEq(vault.refundedAmounts(id), unapproved);
            assertEq(usdc.balanceOf(employer), empStart - total + unapproved);
            assertEq(usdc.balanceOf(address(vault)), approvedSum - releasedSum);
            // no second refund
            vm.prank(employer);
            vm.expectRevert(ArcStreamVault.EscrowTerminated.selector);
            vault.refundRemaining(id, "");
        }

        // contractor claims every remaining approved milestone
        for (uint256 i; i < n; ++i) {
            if ((approveMask >> i) & 1 == 1 && (releaseMask >> i) & 1 == 0) {
                vm.prank(contractor);
                vault.releaseMilestone(id, i, "");
            }
        }
        assertEq(usdc.balanceOf(contractor), approvedSum);
        assertEq(usdc.balanceOf(address(vault)), 0);
        assertEq(usdc.balanceOf(employer), empStart - approvedSum);
        assertEq(vault.approvedPending(id), 0);
        assertEq(vault.getEscrow(id).totalReleased, approvedSum);
    }

    function testFuzz_RefundByEitherParty_SameAmount(uint256 seed, uint8 nRaw, uint64 approveMask, bool byContractor)
        public
    {
        uint256 n = bound(nRaw, 1, 50);
        (uint256[] memory a, uint256 total) = _amounts(seed, n);
        _fundEmployer(total);
        string[] memory d = _descs(n);
        vm.prank(employer);
        uint256 id = vault.createEscrow(contractor, a, d, "");

        uint256 approvedSum;
        for (uint256 i; i < n; ++i) {
            if ((approveMask >> i) & 1 == 1) {
                _approve(id, i);
                approvedSum += a[i];
            }
        }
        vm.assume(approvedSum < total);
        uint256 empBefore = usdc.balanceOf(employer);
        vm.prank(byContractor ? contractor : employer);
        vault.refundRemaining(id, "");
        assertEq(usdc.balanceOf(employer), empBefore + (total - approvedSum));
        assertEq(usdc.balanceOf(contractor), 0);
    }

    function testFuzz_UpdateContractor_PayoutFollowsRotation(address to, uint96 amt) public {
        vm.assume(to != address(0) && to != employer && to != contractor);
        vm.assume(to.code.length == 0 && to != address(vault));
        uint256 amount = bound(amt, 1, 1e18);
        uint256[] memory a = new uint256[](1);
        a[0] = amount;
        string[] memory d = _descs(1);
        _fundEmployer(amount);
        vm.prank(employer);
        uint256 id = vault.createEscrow(contractor, a, d, "");

        vm.prank(contractor);
        vault.updateContractor(id, to);
        _approve(id, 0);
        _release(id, 0);
        assertEq(usdc.balanceOf(to), amount);
        assertEq(usdc.balanceOf(contractor), 0);
    }

    function testFuzz_Unauthorized_Callers(address caller) public {
        vm.assume(caller != employer && caller != contractor && caller != address(0));
        uint256 id = _createDefault();
        vm.startPrank(caller);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.approveMilestone(id, 0);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.releaseMilestone(id, 0, "");
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.refundRemaining(id, "");
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.updateContractor(id, caller);
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
}
