// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ArcStreamVaultTestBase} from "./ArcStreamVault.Base.t.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";

/// Fuzz over inspection periods, submission times, warps, resubmissions and approval masks.
contract ArcStreamVaultUncontestedFuzzTest is ArcStreamVaultTestBase {
    function _expectedPeriod(uint256 p) internal pure returns (uint256) {
        return p == 0 ? 7 days : p;
    }

    function testFuzz_PeriodValidation(uint256 period) public {
        uint256[] memory a = _three();
        string[] memory d = _descs(3);
        bool valid = period == 0 || (period >= 1 days && period <= 30 days);
        vm.prank(employer);
        if (!valid) {
            vm.expectRevert(ArcStreamVault.InvalidInspectionPeriod.selector);
            vault.createEscrow(contractor, a, d, "", period);
            assertEq(vault.escrowCount(), 0);
        } else {
            uint256 id = vault.createEscrow(contractor, a, d, "", period);
            assertEq(vault.getEscrow(id).inspectionPeriod, _expectedPeriod(period));
        }
    }

    function testFuzz_ValidPeriodAlwaysStored(uint256 period) public {
        period = bound(period, 1 days, 30 days);
        uint256 id = _createPeriod(period, "");
        assertEq(vault.getEscrow(id).inspectionPeriod, period);
    }

    /// Claim succeeds iff block.timestamp >= submittedAt + period.
    function testFuzz_ClaimSucceedsIffWindowElapsed(uint256 period, uint256 submitTs, uint256 offset) public {
        period = bound(period, 0, 31 days);
        if (period != 0 && period < 1 days) period = 1 days;
        if (period > 30 days) period = 30 days;
        submitTs = bound(submitTs, 1, 1e12);
        uint256 eff = _expectedPeriod(period);
        offset = bound(offset, 0, 2 * eff + 1);

        uint256 id = _createPeriod(period, "");
        vm.warp(submitTs);
        _submit(id, 0);
        assertEq(vault.uncontestedClaimTime(id, 0), submitTs + eff);

        vm.warp(submitTs + offset);
        if (offset < eff) {
            vm.prank(contractor);
            vm.expectRevert(ArcStreamVault.InspectionPeriodActive.selector);
            vault.claimUncontestedMilestone(id, 0);
            assertEq(usdc.balanceOf(contractor), 0);
        } else {
            _claimU(id, 0);
            assertEq(usdc.balanceOf(contractor), M0);
            assertEq(usdc.balanceOf(address(vault)), TOTAL - M0);
        }
    }

    /// The claim deadline always tracks the LATEST submission.
    function testFuzz_ResubmissionRestartsWindow(uint256 period, uint256 gap, uint256 probe) public {
        period = bound(period, 1 days, 30 days);
        gap = bound(gap, 0, 60 days);
        uint256 id = _createPeriod(period, "");
        _submit(id, 0);
        skip(gap);
        uint256 second = block.timestamp;
        _submit(id, 0);
        assertEq(vault.uncontestedClaimTime(id, 0), second + period);

        probe = bound(probe, 0, 2 * period);
        vm.warp(second + probe);
        if (probe < period) {
            vm.prank(contractor);
            vm.expectRevert(ArcStreamVault.InspectionPeriodActive.selector);
            vault.claimUncontestedMilestone(id, 0);
        } else {
            _claimU(id, 0);
            assertEq(usdc.balanceOf(contractor), M0);
        }
    }

    /// Random approval masks + claim orders keep every accounting identity intact.
    function testFuzz_MixedClaimsKeepAccountingConsistent(uint8 approveMask, uint8 claimMask, uint256 order) public {
        uint256 id = _createDefault();
        uint256[3] memory amts = [M0, M1, M2];
        for (uint256 i; i < 3; ++i) {
            _submit(id, i);
        }
        for (uint256 i; i < 3; ++i) {
            if (approveMask & (1 << i) != 0) _approveOnly(id, i);
        }
        skip(7 days);

        uint256 claimed;
        uint256 start = order % 3;
        for (uint256 k; k < 3; ++k) {
            uint256 i = (start + k) % 3;
            if (claimMask & (1 << i) != 0) {
                _claimU(id, i);
                claimed += amts[i];
            }
        }

        // recompute expected counters from the flags
        ArcStreamVault.Milestone[] memory ms = vault.getMilestones(id);
        uint256 unapproved;
        uint256 pending;
        for (uint256 i; i < 3; ++i) {
            if (ms[i].isWorkSubmitted && !ms[i].isApproved) unapproved++;
            if (ms[i].isApproved && !ms[i].isReleased) pending += ms[i].amount;
        }
        assertEq(vault.submittedUnapprovedCount(id), unapproved);
        assertEq(vault.approvedPending(id), pending);
        assertEq(vault.getEscrow(id).totalReleased, claimed);
        assertEq(usdc.balanceOf(contractor), claimed);
        assertEq(usdc.balanceOf(address(vault)), TOTAL - claimed);

        // employer refund: allowed iff nothing submitted-unapproved remains
        if (unapproved != 0) {
            vm.prank(employer);
            vm.expectRevert(ArcStreamVault.WorkAlreadySubmitted.selector);
            vault.refundRemaining(id, "");
        }
    }

    /// Exactly one of the two caller classes can claim: only the current contractor.
    function testFuzz_OnlyCurrentContractorCanClaim(address caller, bool rotate) public {
        uint256 id = _createDefault();
        _submit(id, 0);
        address current = contractor;
        if (rotate) {
            vm.prank(contractor);
            vault.updateContractor(id, newContractor);
            current = newContractor;
        }
        skip(7 days);
        vm.prank(caller);
        if (caller != current) {
            vm.expectRevert(ArcStreamVault.Unauthorized.selector);
            vault.claimUncontestedMilestone(id, 0);
        } else {
            vault.claimUncontestedMilestone(id, 0);
            assertEq(usdc.balanceOf(current), M0);
        }
    }

    /// A claim of any in-range, submitted milestone pays exactly its amount.
    function testFuzz_ClaimPaysExactAmount(uint256 count, uint256 pick, uint256 seed) public {
        count = bound(count, 1, 12);
        pick = bound(pick, 0, count - 1);
        uint256[] memory a = new uint256[](count);
        uint256 total;
        for (uint256 i; i < count; ++i) {
            a[i] = bound(uint256(keccak256(abi.encode(seed, i))), 1, 50_000e6);
            total += a[i];
        }
        string[] memory d = _descs(count);
        vm.prank(employer);
        uint256 id = vault.createEscrow(contractor, a, d, "", 0);
        _submit(id, pick);
        skip(7 days);
        _claimU(id, pick);
        assertEq(usdc.balanceOf(contractor), a[pick]);
        assertEq(usdc.balanceOf(address(vault)), total - a[pick]);
        assertEq(vault.getEscrow(id).totalReleased, a[pick]);
    }
}
