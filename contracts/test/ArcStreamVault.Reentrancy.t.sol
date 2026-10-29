// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";
import {MockArcPQ} from "../test-helpers/MockArcPQ.sol";
import {ReentrantToken} from "../test-helpers/ReentrantToken.sol";
import {ReentrancyAttacker} from "../test-helpers/ReentrancyAttacker.sol";

contract ArcStreamVaultReentrancyTest is Test {
    ArcStreamVault internal vault;
    ReentrantToken internal token;
    ReentrancyAttacker internal attacker;

    address internal employer = makeAddr("employer");
    address internal contractor = makeAddr("contractor");

    uint256 internal constant M0 = 100e6;
    uint256 internal constant M1 = 200e6;
    uint256 internal constant M2 = 300e6;
    uint256 internal constant TOTAL = 600e6;
    address internal constant PQ_PRECOMPILE = 0x1800000000000000000000000000000000000004;
    bytes internal pqKey = abi.encodePacked(keccak256("pq-public-key-A"));

    /// Mock-valid SLH-DSA signature by `pqKey` over the vault's domain-bound digest.
    function _pqSig(uint256 escrowId, uint256 action) internal view returns (bytes memory) {
        bytes32 digest = vault.pqSigningMessage(escrowId, action);
        return abi.encodePacked(keccak256(abi.encodePacked(pqKey, abi.encodePacked(digest))), new bytes(7856 - 32));
    }

    bytes4 internal GUARD = ReentrancyGuard.ReentrancyGuardReentrantCall.selector;

    function setUp() public {
        vm.etch(PQ_PRECOMPILE, address(new MockArcPQ()).code);
        token = new ReentrantToken();
        vault = new ArcStreamVault(address(token));
        attacker = new ReentrancyAttacker();
        token.mint(employer, 10_000e6);
        vm.prank(employer);
        token.approve(address(vault), type(uint256).max);
    }

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

    function _submitAs(address who, uint256 id, uint256 i) internal {
        vm.prank(who);
        vault.submitMilestoneWork(id, i, "proof");
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

    // ------------------------------------------- malicious contractor (hook on release)
    function test_Reentrancy_MaliciousContractor_CannotDoubleReleaseOrRefund() public {
        vm.prank(employer);
        uint256 id = vault.createEscrow(address(attacker), _three(), _descs(), "", 0);
        attacker.exec(address(vault), abi.encodeCall(ArcStreamVault.submitMilestoneWork, (id, 0, "p")));
        attacker.exec(address(vault), abi.encodeCall(ArcStreamVault.submitMilestoneWork, (id, 1, "p")));
        vm.startPrank(employer);
        vault.approveMilestone(id, 0);
        vault.approveMilestone(id, 1);
        vm.stopPrank();

        // attempts the hostile contractor replays from inside the token hook
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.submitMilestoneWork, (id, 2, "p")));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.mutualCancel, (id, 0, M1 + M2)));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.claimSettlement, (id)));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.releaseMilestone, (id, 0, "")));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.releaseMilestone, (id, 1, "")));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.refundRemaining, (id, "")));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.approveMilestone, (id, 2)));
        attacker.addAttempt(
            address(vault), abi.encodeCall(ArcStreamVault.createEscrow, (address(0xBEEF), _three(), _descs(), "", 0))
        );
        token.enableHooks(true);

        vm.prank(employer);
        vault.releaseMilestone(id, 0, "");

        assertEq(attacker.hookCalls(), 1, "hook fired exactly once");
        _assertAllGuarded();
        assertEq(token.balanceOf(address(attacker)), M0, "paid once");
        assertEq(token.balanceOf(address(vault)), TOTAL - M0);
        assertEq(vault.getEscrow(id).totalReleased, M0);
        assertEq(vault.approvedPending(id), M1);
        assertFalse(vault.getEscrow(id).isTerminated);
        assertEq(vault.escrowCount(), 1);
    }

    // ------------------------------------------- malicious employer (hook on refund)
    function test_Reentrancy_MaliciousEmployer_CannotDoubleRefund() public {
        token.mint(address(attacker), 1_000e6);
        attacker.exec(address(token), abi.encodeCall(token.approve, (address(vault), type(uint256).max)));
        bytes memory ret = attacker.exec(
            address(vault), abi.encodeCall(ArcStreamVault.createEscrow, (contractor, _three(), _descs(), "", 0))
        );
        uint256 id = abi.decode(ret, (uint256));
        _submitAs(contractor, id, 0);
        attacker.exec(address(vault), abi.encodeCall(ArcStreamVault.approveMilestone, (id, 0)));

        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.claimSettlement, (id)));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.mutualCancel, (id, 0, M1 + M2)));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.refundRemaining, (id, "")));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.releaseMilestone, (id, 0, "")));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.approveMilestone, (id, 1)));
        token.enableHooks(true);

        attacker.exec(address(vault), abi.encodeCall(ArcStreamVault.refundRemaining, (id, "")));

        assertEq(attacker.hookCalls(), 1);
        _assertAllGuarded();
        assertEq(token.balanceOf(address(attacker)), 1_000e6 - M0, "refunded exactly M1+M2 once");
        assertEq(token.balanceOf(address(vault)), M0, "approved milestone still escrowed");
        assertEq(vault.refundedAmounts(id), M1 + M2);
        assertEq(vault.approvedPending(id), M0);
        assertEq(token.balanceOf(contractor), 0);

        // honest contractor can still claim afterwards
        vm.prank(contractor);
        vault.releaseMilestone(id, 0, "");
        assertEq(token.balanceOf(contractor), M0);
        assertEq(token.balanceOf(address(vault)), 0);
    }

    // ------------------------------------------- hostile token reenters createEscrow
    function test_Reentrancy_TokenReentersCreateEscrow_Blocked() public {
        token.arm(
            address(vault),
            address(vault),
            abi.encodeCall(ArcStreamVault.createEscrow, (contractor, _three(), _descs(), "", 0))
        );
        vm.prank(employer);
        uint256 id = vault.createEscrow(contractor, _three(), _descs(), "", 0);

        assertEq(token.fires(), 1);
        assertFalse(token.lastOk());
        assertEq(bytes4(token.lastRet()), GUARD);
        assertEq(id, 1);
        assertEq(vault.escrowCount(), 1);
        assertEq(token.balanceOf(address(vault)), TOTAL);
    }

    // ------------------------------------------- hostile token reenters release / refund
    function test_Reentrancy_TokenReentersReleaseSameMilestone_Blocked() public {
        vm.prank(employer);
        uint256 id = vault.createEscrow(contractor, _three(), _descs(), "", 0);
        _submitAs(contractor, id, 0);
        vm.prank(employer);
        vault.approveMilestone(id, 0);

        token.arm(contractor, address(vault), abi.encodeCall(ArcStreamVault.releaseMilestone, (id, 0, "")));
        vm.prank(employer);
        vault.releaseMilestone(id, 0, "");

        assertEq(token.fires(), 1);
        assertFalse(token.lastOk());
        assertEq(bytes4(token.lastRet()), GUARD);
        assertEq(token.balanceOf(contractor), M0);
        assertEq(token.balanceOf(address(vault)), TOTAL - M0);
    }

    function test_Reentrancy_TokenReentersRefundDuringRelease_Blocked() public {
        vm.prank(employer);
        uint256 id = vault.createEscrow(contractor, _three(), _descs(), "", 0);
        _submitAs(contractor, id, 0);
        vm.prank(employer);
        vault.approveMilestone(id, 0);

        token.arm(contractor, address(vault), abi.encodeCall(ArcStreamVault.refundRemaining, (id, "")));
        vm.prank(employer);
        vault.releaseMilestone(id, 0, "");

        assertFalse(token.lastOk());
        assertEq(bytes4(token.lastRet()), GUARD);
        assertFalse(vault.getEscrow(id).isTerminated);
        assertEq(vault.refundedAmounts(id), 0);
    }

    function test_Reentrancy_TokenReentersReleaseDuringRefund_Blocked() public {
        vm.prank(employer);
        uint256 id = vault.createEscrow(contractor, _three(), _descs(), "", 0);
        _submitAs(contractor, id, 0);
        vm.prank(employer);
        vault.approveMilestone(id, 0);

        token.arm(employer, address(vault), abi.encodeCall(ArcStreamVault.releaseMilestone, (id, 0, "")));
        vm.prank(employer);
        vault.refundRemaining(id, "");

        assertFalse(token.lastOk());
        assertEq(bytes4(token.lastRet()), GUARD);
        assertEq(token.balanceOf(contractor), 0);
        assertEq(token.balanceOf(address(vault)), M0);
    }

    // ------------------------------------------- hostile token that reverts reentry up the stack
    function test_Reentrancy_RollbackLeavesNoPartialState() public {
        // Employer lacks funds -> transferFrom reverts -> whole createEscrow (incl. escrowCount) rolls back
        address poor = makeAddr("poor");
        vm.prank(poor);
        token.approve(address(vault), type(uint256).max);
        vm.prank(poor);
        vm.expectRevert();
        vault.createEscrow(contractor, _three(), _descs(), "", 0);
        assertEq(vault.escrowCount(), 0);
    }

    // ------------------------------------------- claimSettlement reentrancy
    uint256 internal constant C_SHARE = 250e6;
    uint256 internal constant E_SHARE = 350e6;

    function test_Reentrancy_ClaimSettlement_MaliciousContractorCannotReclaim() public {
        vm.prank(employer);
        uint256 id = vault.createEscrow(address(attacker), _three(), _descs(), "", 0);
        vm.prank(employer);
        vault.mutualCancel(id, C_SHARE, E_SHARE);
        attacker.exec(address(vault), abi.encodeCall(ArcStreamVault.mutualCancel, (id, C_SHARE, E_SHARE)));
        assertTrue(vault.isSettled(id));

        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.claimSettlement, (id)));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.releaseMilestone, (id, 0, "")));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.refundRemaining, (id, "")));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.submitMilestoneWork, (id, 0, "p")));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.approveMilestone, (id, 0)));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.mutualCancel, (id, 0, TOTAL)));
        token.enableHooks(true);

        attacker.exec(address(vault), abi.encodeCall(ArcStreamVault.claimSettlement, (id)));

        assertEq(attacker.hookCalls(), 1);
        _assertAllGuarded();
        assertEq(token.balanceOf(address(attacker)), C_SHARE, "paid exactly once");
        assertEq(token.balanceOf(address(vault)), E_SHARE);
        assertEq(vault.contractorSettlementOwed(id), 0);
        assertEq(vault.employerSettlementOwed(id), E_SHARE);
        assertEq(vault.getEscrow(id).totalReleased, C_SHARE);
    }

    function test_Reentrancy_ClaimSettlement_MaliciousEmployerCannotReclaim() public {
        token.mint(address(attacker), 1_000e6);
        attacker.exec(address(token), abi.encodeCall(token.approve, (address(vault), type(uint256).max)));
        bytes memory ret = attacker.exec(
            address(vault), abi.encodeCall(ArcStreamVault.createEscrow, (contractor, _three(), _descs(), "", 0))
        );
        uint256 id = abi.decode(ret, (uint256));
        attacker.exec(address(vault), abi.encodeCall(ArcStreamVault.mutualCancel, (id, C_SHARE, E_SHARE)));
        vm.prank(contractor);
        vault.mutualCancel(id, C_SHARE, E_SHARE);

        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.claimSettlement, (id)));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.refundRemaining, (id, "")));
        attacker.addAttempt(address(vault), abi.encodeCall(ArcStreamVault.mutualCancel, (id, 0, TOTAL)));
        token.enableHooks(true);

        attacker.exec(address(vault), abi.encodeCall(ArcStreamVault.claimSettlement, (id)));

        assertEq(attacker.hookCalls(), 1);
        _assertAllGuarded();
        assertEq(token.balanceOf(address(attacker)), 1_000e6 - TOTAL + E_SHARE, "refunded exactly once");
        assertEq(vault.refundedAmounts(id), E_SHARE);
        assertEq(token.balanceOf(address(vault)), C_SHARE);
        // honest contractor can still claim
        vm.prank(contractor);
        vault.claimSettlement(id);
        assertEq(token.balanceOf(contractor), C_SHARE);
        assertEq(token.balanceOf(address(vault)), 0);
    }

    function _settledEscrow() internal returns (uint256 id) {
        vm.prank(employer);
        id = vault.createEscrow(contractor, _three(), _descs(), "", 0);
        vm.prank(employer);
        vault.mutualCancel(id, C_SHARE, E_SHARE);
        vm.prank(contractor);
        vault.mutualCancel(id, C_SHARE, E_SHARE);
    }

    function test_Reentrancy_TokenReentersClaimDuringClaim_Blocked() public {
        uint256 id = _settledEscrow();
        token.arm(contractor, address(vault), abi.encodeCall(ArcStreamVault.claimSettlement, (id)));
        vm.prank(contractor);
        vault.claimSettlement(id);

        assertEq(token.fires(), 1);
        assertFalse(token.lastOk());
        assertEq(bytes4(token.lastRet()), GUARD);
        assertEq(token.balanceOf(contractor), C_SHARE);
        assertEq(token.balanceOf(address(vault)), E_SHARE);
    }

    function test_Reentrancy_TokenReentersSubmitDuringClaim_Blocked() public {
        uint256 id = _settledEscrow();
        token.arm(employer, address(vault), abi.encodeCall(ArcStreamVault.submitMilestoneWork, (id, 0, "p")));
        vm.prank(employer);
        vault.claimSettlement(id);

        assertFalse(token.lastOk());
        assertEq(bytes4(token.lastRet()), GUARD);
        assertFalse(vault.getMilestone(id, 0).isWorkSubmitted);
    }

    function test_Reentrancy_TokenReentersApproveDuringRelease_Blocked() public {
        vm.prank(employer);
        uint256 id = vault.createEscrow(contractor, _three(), _descs(), "", 0);
        _submitAs(contractor, id, 0);
        _submitAs(contractor, id, 1);
        vm.prank(employer);
        vault.approveMilestone(id, 0);

        token.arm(contractor, address(vault), abi.encodeCall(ArcStreamVault.approveMilestone, (id, 1)));
        vm.prank(employer);
        vault.releaseMilestone(id, 0, "");

        assertFalse(token.lastOk());
        assertEq(bytes4(token.lastRet()), GUARD);
        assertFalse(vault.getMilestone(id, 1).isApproved);
        assertEq(vault.approvedPending(id), 0);
    }

    function test_Reentrancy_TokenReentersSubmitDuringRelease_Blocked() public {
        vm.prank(employer);
        uint256 id = vault.createEscrow(contractor, _three(), _descs(), "", 0);
        _submitAs(contractor, id, 0);
        vm.prank(employer);
        vault.approveMilestone(id, 0);

        token.arm(contractor, address(vault), abi.encodeCall(ArcStreamVault.submitMilestoneWork, (id, 1, "p")));
        vm.prank(employer);
        vault.releaseMilestone(id, 0, "");

        assertFalse(token.lastOk());
        assertEq(bytes4(token.lastRet()), GUARD);
        assertFalse(vault.getMilestone(id, 1).isWorkSubmitted);
        assertEq(vault.submittedUnapprovedCount(id), 0);
    }

    function test_Reentrancy_TokenReentersMutualCancelDuringRefund_Blocked() public {
        vm.prank(employer);
        uint256 id = vault.createEscrow(contractor, _three(), _descs(), "", 0);
        token.arm(employer, address(vault), abi.encodeCall(ArcStreamVault.mutualCancel, (id, 0, 0)));
        vm.prank(employer);
        vault.refundRemaining(id, "");
        assertFalse(token.lastOk());
        assertEq(bytes4(token.lastRet()), GUARD);
    }

    // ------------------------------------------- protected escrows with valid proofs
    function _protectedApproved() internal returns (uint256 id) {
        vm.prank(employer);
        id = vault.createEscrow(contractor, _three(), _descs(), pqKey, 0);
        _submitAs(contractor, id, 0);
        vm.prank(employer);
        vault.approveMilestone(id, 0);
    }

    function test_Reentrancy_ProtectedRelease_TokenReplaysValidProof_Blocked() public {
        uint256 id = _protectedApproved();
        bytes memory sig = _pqSig(id, 0);
        token.arm(contractor, address(vault), abi.encodeCall(ArcStreamVault.releaseMilestone, (id, 0, sig)));
        vm.prank(employer);
        vault.releaseMilestone(id, 0, sig);

        assertEq(token.fires(), 1);
        assertFalse(token.lastOk());
        assertEq(bytes4(token.lastRet()), GUARD);
        assertEq(token.balanceOf(contractor), M0);
        assertEq(token.balanceOf(address(vault)), TOTAL - M0);
    }

    function test_Reentrancy_ProtectedRelease_TokenReentersRefundWithValidProof_Blocked() public {
        uint256 id = _protectedApproved();
        token.arm(
            contractor, address(vault), abi.encodeCall(ArcStreamVault.refundRemaining, (id, _pqSig(id, 3)))
        );
        bytes memory relSig = _pqSig(id, 0);
        vm.prank(employer);
        vault.releaseMilestone(id, 0, relSig);

        assertFalse(token.lastOk());
        assertEq(bytes4(token.lastRet()), GUARD);
        assertFalse(vault.getEscrow(id).isTerminated);
        assertEq(vault.refundedAmounts(id), 0);
    }

    function test_Reentrancy_ProtectedRefund_TokenReentersReleaseWithValidProof_Blocked() public {
        uint256 id = _protectedApproved();
        token.arm(
            employer, address(vault), abi.encodeCall(ArcStreamVault.releaseMilestone, (id, 0, _pqSig(id, 0)))
        );
        bytes memory refSig = _pqSig(id, 3);
        vm.prank(employer);
        vault.refundRemaining(id, refSig);

        assertFalse(token.lastOk());
        assertEq(bytes4(token.lastRet()), GUARD);
        assertEq(token.balanceOf(contractor), 0);
        assertEq(token.balanceOf(address(vault)), M0);
    }

    function test_Reentrancy_ProtectedCreate_TokenReentersCreateProtected_Blocked() public {
        token.arm(
            address(vault),
            address(vault),
            abi.encodeCall(ArcStreamVault.createEscrow, (contractor, _three(), _descs(), pqKey, 0))
        );
        vm.prank(employer);
        uint256 id = vault.createEscrow(contractor, _three(), _descs(), pqKey, 0);
        assertFalse(token.lastOk());
        assertEq(bytes4(token.lastRet()), GUARD);
        assertEq(id, 1);
        assertEq(vault.escrowCount(), 1);
    }
}
