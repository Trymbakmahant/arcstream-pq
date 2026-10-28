// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ArcStreamVault} from "../ArcStreamVault.sol";
import {ArcStreamVaultTestBase} from "./ArcStreamVault.Base.t.sol";

/// Fuzz: submission length, settlement conservation, arbitrary valid splits.
contract ArcStreamVaultFuzzSettlementTest is ArcStreamVaultTestBase {
    uint256 internal constant MAX_AMT = 1e9 * 1e6;

    function _prepare(uint256 seed, uint256 n, uint64 submitMask, uint64 approveMask, uint64 releaseMask, bool refund)
        internal
        returns (uint256 id, uint256 total)
    {
        uint256[] memory a = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            a[i] = 1 + (uint256(keccak256(abi.encode(seed, i))) % MAX_AMT);
            total += a[i];
        }
        usdc.mint(employer, total);
        string[] memory d = _descs(n);
        vm.prank(employer);
        id = vault.createEscrow(contractor, a, d, bytes32(0));

        for (uint256 i; i < n; ++i) {
            if ((submitMask >> i) & 1 == 1) {
                _submit(id, i);
                if ((approveMask >> i) & 1 == 1) {
                    _approveOnly(id, i);
                    if ((releaseMask >> i) & 1 == 1) _release(id, i);
                }
            }
        }
        if (refund) {
            // contractor waiver is never blocked by submissions; may revert NothingToRefund
            vm.prank(contractor);
            try vault.refundRemaining(id, "") {} catch {}
        }
    }

    // ------------------------------------------------------- proof length
    function testFuzz_Submit_ProofLengthBoundary(uint16 lenRaw) public {
        uint256 id = _createDefault();
        uint256 len = bound(lenRaw, 1, 600);
        string memory p = string(new bytes(len));
        vm.prank(contractor);
        if (len > 256) {
            vm.expectRevert(ArcStreamVault.WorkProofTooLong.selector);
            vault.submitMilestoneWork(id, 0, p);
            assertFalse(vault.getMilestone(id, 0).isWorkSubmitted);
        } else {
            vault.submitMilestoneWork(id, 0, p);
            assertEq(bytes(vault.getMilestone(id, 0).workProofHash).length, len);
            assertEq(vault.submittedUnapprovedCount(id), 1);
        }
    }

    function testFuzz_Submit_RepeatedSubmissionsNeverDoubleCount(uint8 timesRaw, uint8 idxRaw) public {
        uint256 id = _createDefault();
        uint256 times = bound(timesRaw, 1, 10);
        uint256 idx = bound(idxRaw, 0, 2);
        for (uint256 i; i < times; ++i) {
            _submit(id, idx);
        }
        assertEq(vault.submittedUnapprovedCount(id), 1);
        _approveOnly(id, idx);
        assertEq(vault.submittedUnapprovedCount(id), 0);
    }

    // ------------------------------------------------ settlement conservation
    function testFuzz_Settlement_Conservation(
        uint256 seed,
        uint8 nRaw,
        uint64 submitMask,
        uint64 approveMask,
        uint64 releaseMask,
        bool refund,
        uint256 cSeed
    ) public {
        uint256 n = bound(nRaw, 1, 20);
        (uint256 id, uint256 total) = _prepare(seed, n, submitMask, approveMask, releaseMask, refund);
        uint256 remaining = _remaining(id);
        if (remaining == 0) return;

        uint256 cShare = bound(cSeed, 0, remaining);
        uint256 eShare = remaining - cShare;
        _settle(id, cShare, eShare);

        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        assertEq(vault.contractorSettlementOwed(id), cShare);
        assertEq(vault.employerSettlementOwed(id), eShare);
        // conservation: owed + released + refunded == deposited
        assertEq(cShare + eShare + e.totalReleased + vault.refundedAmounts(id), total);
        assertEq(vault.approvedPending(id), 0);
        assertGe(usdc.balanceOf(address(vault)), cShare + eShare);

        uint256 cBefore = usdc.balanceOf(contractor);
        uint256 eBefore = usdc.balanceOf(employer);
        if (cShare > 0) {
            vm.prank(contractor);
            vault.claimSettlement(id);
        }
        if (eShare > 0) {
            vm.prank(employer);
            vault.claimSettlement(id);
        }
        assertEq(usdc.balanceOf(contractor), cBefore + cShare);
        assertEq(usdc.balanceOf(employer), eBefore + eShare);
        assertEq(usdc.balanceOf(address(vault)), 0);
        e = vault.getEscrow(id);
        assertEq(e.totalReleased + vault.refundedAmounts(id), total, "fully accounted after claims");
        assertEq(_remaining(id), 0);
    }

    function testFuzz_Settlement_ClaimOnlyPaysOwnShare(uint256 cSeed, bool contractorFirst) public {
        uint256 id = _createDefault();
        uint256 cShare = bound(cSeed, 1, TOTAL - 1);
        uint256 eShare = TOTAL - cShare;
        _settle(id, cShare, eShare);

        address first = contractorFirst ? contractor : employer;
        uint256 firstShare = contractorFirst ? cShare : eShare;
        uint256 vaultBefore = usdc.balanceOf(address(vault));
        vm.prank(first);
        vault.claimSettlement(id);
        assertEq(usdc.balanceOf(address(vault)), vaultBefore - firstShare);
        assertEq(_remaining(id), TOTAL - firstShare);
        // second claim by same party gets nothing
        vm.prank(first);
        vm.expectRevert(ArcStreamVault.NothingToRefund.selector);
        vault.claimSettlement(id);
    }

    // ------------------------------------------------------- arbitrary splits
    function testFuzz_MutualCancel_InvalidSplitReverts(uint128 c, uint128 e) public {
        uint256 id = _createDefault();
        vm.assume(uint256(c) + uint256(e) != TOTAL);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.InvalidSplit.selector);
        vault.mutualCancel(id, c, e);
        (address p,,) = vault.mutualCancelProposals(id);
        assertEq(p, address(0));
    }

    function testFuzz_MutualCancel_AnyValidSplitSettles(uint256 cSeed, bool employerFirst) public {
        uint256 id = _createDefault();
        uint256 c = bound(cSeed, 0, TOTAL);
        uint256 e = TOTAL - c;
        address first = employerFirst ? employer : contractor;
        address second = employerFirst ? contractor : employer;
        vm.prank(first);
        vault.mutualCancel(id, c, e);
        assertFalse(vault.isSettled(id));
        vm.prank(second);
        vault.mutualCancel(id, c, e);
        assertTrue(vault.isSettled(id));
        assertEq(vault.contractorSettlementOwed(id), c);
        assertEq(vault.employerSettlementOwed(id), e);
    }

    function testFuzz_MutualCancel_MismatchedSharesNeverSettle(uint256 c1Seed, uint256 c2Seed) public {
        uint256 id = _createDefault();
        uint256 c1 = bound(c1Seed, 0, TOTAL);
        uint256 c2 = bound(c2Seed, 0, TOTAL);
        vm.prank(employer);
        vault.mutualCancel(id, c1, TOTAL - c1);
        vm.prank(contractor);
        vault.mutualCancel(id, c2, TOTAL - c2);
        assertEq(vault.isSettled(id), c1 == c2);
        if (c1 != c2) {
            (address p, uint256 c,) = vault.mutualCancelProposals(id);
            assertEq(p, contractor);
            assertEq(c, c2);
        }
    }

    function testFuzz_MutualCancel_SamePartyNeverSettlesAlone(uint256 cSeed, uint8 timesRaw) public {
        uint256 id = _createDefault();
        uint256 c = bound(cSeed, 0, TOTAL);
        uint256 times = bound(timesRaw, 2, 6);
        for (uint256 i; i < times; ++i) {
            vm.prank(employer);
            vault.mutualCancel(id, c, TOTAL - c);
        }
        assertFalse(vault.isSettled(id));
    }
}
