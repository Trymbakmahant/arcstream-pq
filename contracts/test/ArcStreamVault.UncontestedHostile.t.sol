// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";
import {BlocklistToken} from "../test-helpers/BlocklistToken.sol";
import {ReentrantToken} from "../test-helpers/ReentrantToken.sol";
import {ReentrancyAttacker} from "../test-helpers/ReentrancyAttacker.sol";

/// claimUncontestedMilestone against a USDC-style blocklist and a reentrant hostile token.
contract ArcStreamVaultUncontestedHostileTest is Test {
    address internal employer = makeAddr("employer");
    address internal contractor = makeAddr("contractor");
    address internal newContractor = makeAddr("newContractor");

    uint256 internal constant M0 = 100e6;
    uint256 internal constant M1 = 200e6;
    uint256 internal constant M2 = 300e6;
    uint256 internal constant TOTAL = 600e6;

    bytes4 internal GUARD = ReentrancyGuard.ReentrancyGuardReentrantCall.selector;

    function _three() internal pure returns (uint256[] memory a) {
        a = new uint256[](3);
        a[0] = M0;
        a[1] = M1;
        a[2] = M2;
    }

    function _descs() internal pure returns (string[] memory d) {
        d = new string[](3);
        d[0] = "a";
        d[1] = "b";
        d[2] = "c";
    }

    // ================================================================= blocklist
    function _blockSetup() internal returns (ArcStreamVault v, BlocklistToken t, uint256 id) {
        t = new BlocklistToken();
        v = new ArcStreamVault(address(t));
        t.mint(employer, 10_000e6);
        vm.prank(employer);
        t.approve(address(v), type(uint256).max);
        vm.prank(employer);
        id = v.createEscrow(contractor, _three(), _descs(), "", 0);
        vm.prank(contractor);
        v.submitMilestoneWork(id, 0, "proof");
        skip(7 days);
    }

    function test_Blocklist_BlockedContractorClaimRevertsAtomically() public {
        (ArcStreamVault v, BlocklistToken t, uint256 id) = _blockSetup();
        t.setBlocked(contractor, true);

        vm.prank(contractor);
        vm.expectRevert(abi.encodeWithSelector(BlocklistToken.Blocked.selector, contractor));
        v.claimUncontestedMilestone(id, 0);

        // everything rolled back
        ArcStreamVault.Milestone memory m = v.getMilestone(id, 0);
        assertFalse(m.isReleased);
        assertFalse(m.isApproved);
        assertTrue(m.isWorkSubmitted);
        assertEq(v.getEscrow(id).totalReleased, 0);
        assertEq(v.submittedUnapprovedCount(id), 1);
        assertEq(t.balanceOf(address(v)), TOTAL);
    }

    function test_Blocklist_RecoversByUpdateContractorThenClaim() public {
        (ArcStreamVault v, BlocklistToken t, uint256 id) = _blockSetup();
        t.setBlocked(contractor, true);

        vm.prank(contractor);
        v.updateContractor(id, newContractor); // no token transfer, so works while blocked

        vm.prank(contractor);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        v.claimUncontestedMilestone(id, 0);

        vm.prank(newContractor);
        v.claimUncontestedMilestone(id, 0);
        assertEq(t.balanceOf(newContractor), M0);
        assertEq(t.balanceOf(address(v)), TOTAL - M0);
        assertTrue(v.getMilestone(id, 0).isReleased);
    }

    function test_Blocklist_UnblockedContractorCanClaimLater() public {
        (ArcStreamVault v, BlocklistToken t, uint256 id) = _blockSetup();
        t.setBlocked(contractor, true);
        vm.prank(contractor);
        vm.expectRevert();
        v.claimUncontestedMilestone(id, 0);
        t.setBlocked(contractor, false);
        vm.prank(contractor);
        v.claimUncontestedMilestone(id, 0);
        assertEq(t.balanceOf(contractor), M0);
    }

    function test_Blocklist_BlockedEmployerDoesNotAffectClaim() public {
        (ArcStreamVault v, BlocklistToken t, uint256 id) = _blockSetup();
        t.setBlocked(employer, true);
        vm.prank(contractor);
        v.claimUncontestedMilestone(id, 0);
        assertEq(t.balanceOf(contractor), M0);
    }

    // ================================================================= reentrancy
    ReentrantToken internal token;
    ReentrancyAttacker internal attacker;
    ArcStreamVault internal vault;

    function _hostileSetup() internal {
        token = new ReentrantToken();
        vault = new ArcStreamVault(address(token));
        attacker = new ReentrancyAttacker();
        token.mint(employer, 10_000e6);
        vm.prank(employer);
        token.approve(address(vault), type(uint256).max);
    }

    function _assertAllGuarded() internal view {
        uint256 n = attacker.resultCount();
        assertEq(n, attacker.attemptCount(), "hook ran every attempt");
        assertGt(n, 0);
        for (uint256 i; i < n; ++i) {
            assertFalse(attacker.oks(i), "reentrant call must fail");
            assertEq(attacker.selectors(i), GUARD, "must fail on reentrancy guard");
        }
    }

    /// A contractor contract reenters from the token hook paid by claimUncontestedMilestone.
    function test_Reentrancy_ContractorHookDuringClaim_AllBlocked() public {
        _hostileSetup();
        vm.prank(employer);
        uint256 id = vault.createEscrow(address(attacker), _three(), _descs(), "", 0);
        attacker.exec(address(vault), abi.encodeCall(ArcStreamVault.submitMilestoneWork, (id, 0, "p")));
        attacker.exec(address(vault), abi.encodeCall(ArcStreamVault.submitMilestoneWork, (id, 1, "p")));
        skip(7 days);

        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.claimUncontestedMilestone, (id, 0)));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.claimUncontestedMilestone, (id, 1)));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.releaseMilestone, (id, 0, "")));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.refundRemaining, (id, "")));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.submitMilestoneWork, (id, 2, "p")));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.mutualCancel, (id, 0, M1 + M2)));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.claimSettlement, (id)));
        token.enableHooks(true);

        attacker.exec(address(vault), abi.encodeCall(ArcStreamVault.claimUncontestedMilestone, (id, 0)));

        assertEq(attacker.hookCalls(), 1, "hook fired exactly once");
        _assertAllGuarded();
        assertEq(token.balanceOf(address(attacker)), M0, "paid exactly once");
        assertEq(token.balanceOf(address(vault)), TOTAL - M0);
        assertEq(vault.getEscrow(id).totalReleased, M0);
        assertEq(vault.submittedUnapprovedCount(id), 1, "m1 untouched by blocked reentry");
        assertFalse(vault.getMilestone(id, 1).isReleased);
        assertFalse(vault.getEscrow(id).isTerminated);
    }

    /// The same contractor hook attempting to claim while being paid by an employer release.
    function test_Reentrancy_ContractorHookDuringRelease_CannotClaimUncontested() public {
        _hostileSetup();
        vm.prank(employer);
        uint256 id = vault.createEscrow(address(attacker), _three(), _descs(), "", 0);
        attacker.exec(address(vault), abi.encodeCall(ArcStreamVault.submitMilestoneWork, (id, 0, "p")));
        attacker.exec(address(vault), abi.encodeCall(ArcStreamVault.submitMilestoneWork, (id, 1, "p")));
        vm.prank(employer);
        vault.approveMilestone(id, 0);
        skip(7 days);

        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.claimUncontestedMilestone, (id, 0)));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.claimUncontestedMilestone, (id, 1)));
        token.enableHooks(true);

        vm.prank(employer);
        vault.releaseMilestone(id, 0, "");

        _assertAllGuarded();
        assertEq(token.balanceOf(address(attacker)), M0, "paid once, no double-spend of m0");
        assertEq(vault.getEscrow(id).totalReleased, M0);
        assertFalse(vault.getMilestone(id, 1).isReleased);
    }

    /// Hostile token fires an arbitrary call from itself right after paying; it must hit the guard.
    function test_Reentrancy_TokenCallbackDuringClaim_Blocked() public {
        _hostileSetup();
        vm.prank(employer);
        uint256 id = vault.createEscrow(contractor, _three(), _descs(), "", 0);
        vm.prank(contractor);
        vault.submitMilestoneWork(id, 0, "p");
        vm.prank(contractor);
        vault.submitMilestoneWork(id, 1, "p");
        skip(7 days);

        token.arm(contractor, address(vault), abi.encodeCall(ArcStreamVault.claimUncontestedMilestone, (id, 1)));
        vm.prank(contractor);
        vault.claimUncontestedMilestone(id, 0);

        assertEq(token.fires(), 1);
        assertFalse(token.lastOk(), "callback must not succeed");
        assertEq(token.balanceOf(contractor), M0);
        assertFalse(vault.getMilestone(id, 1).isReleased);
        assertEq(vault.getEscrow(id).totalReleased, M0);
    }

    /// After the guarded claim, the vault is fully usable again (guard released).
    function test_Reentrancy_GuardReleasedAfterClaim() public {
        _hostileSetup();
        vm.prank(employer);
        uint256 id = vault.createEscrow(contractor, _three(), _descs(), "", 0);
        vm.prank(contractor);
        vault.submitMilestoneWork(id, 0, "p");
        vm.prank(contractor);
        vault.submitMilestoneWork(id, 1, "p");
        skip(7 days);
        vm.prank(contractor);
        vault.claimUncontestedMilestone(id, 0);
        vm.prank(contractor);
        vault.claimUncontestedMilestone(id, 1);
        assertEq(token.balanceOf(contractor), M0 + M1);
    }
}
