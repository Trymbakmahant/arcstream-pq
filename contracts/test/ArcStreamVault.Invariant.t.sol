// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";
import {MockERC20} from "../test-helpers/MockERC20.sol";
import {MockArcPQ} from "../test-helpers/MockArcPQ.sol";

/// Bounded-action handler (incl. warp + claimUncontested): random sequences of create / submit / approve / release / refund /
/// rotate / donate / mutualCancel (both parties) / claimSettlement / cancelProposal across
/// several employers and contractors.
contract VaultHandler is Test {
    ArcStreamVault public vault;
    MockERC20 public usdc;

    address[3] public employers;
    address[6] public wallets;

    uint256 public creates;
    uint256 public submits;
    uint256 public approves;
    uint256 public releases;
    uint256 public refunds;
    uint256 public rotations;
    uint256 public donated;
    uint256 public proposals;
    uint256 public settlements;
    uint256 public claims;
    uint256 public cancels;
    uint256 public pqCreates;
    uint256 public pqReleases;
    uint256 public pqRefunds;
    /// Employer actions on protected escrows with a missing/wrong proof that nevertheless succeeded.
    uint256 public badProofSuccesses;

    /// Uncontested-claim ghosts.
    uint256 public warps;
    uint256 public uncontestedClaims;
    uint256 public uncontestedClaimedAmount;
    /// Successful claims that should have been impossible (early / unsubmitted / terminated).
    uint256 public badClaimSuccesses;
    /// Successful claims by a caller other than the current contractor.
    uint256 public wrongCallerClaimSuccesses;
    /// Claims whose deadline had passed but that nevertheless reverted (liveness violation).
    uint256 public livenessFailures;

    uint256 internal constant SIG_LEN = 7856;

    mapping(uint256 id => bytes key) internal keyOf;

    constructor(ArcStreamVault v, MockERC20 t) {
        vault = v;
        usdc = t;
        for (uint256 i; i < 3; ++i) {
            employers[i] = makeAddr(string.concat("handlerEmployer", vm.toString(i)));
        }
        for (uint256 i; i < 6; ++i) {
            wallets[i] = makeAddr(string.concat("handlerWallet", vm.toString(i)));
        }
    }

    function _pickId(uint256 seed) internal view returns (uint256) {
        uint256 count = vault.escrowCount();
        if (count == 0) return 0;
        // concentrate activity on the first few escrows so multi-step lifecycles are reached
        return bound(seed, 1, count < 3 ? count : 3);
    }

    function create(uint256 eSeed, uint256 cSeed, uint256 nSeed, uint256 amtSeed) external {
        _create(eSeed, cSeed, nSeed, amtSeed, false);
    }

    /// PQ-protected escrow; the handler reuses a small pool of 32-byte keys across escrows.
    function createProtected(uint256 eSeed, uint256 cSeed, uint256 nSeed, uint256 amtSeed) external {
        _create(eSeed, cSeed, nSeed, amtSeed, true);
    }

    function _arrays(uint256 nSeed, uint256 amtSeed)
        internal
        pure
        returns (uint256[] memory a, string[] memory d, uint256 total)
    {
        uint256 n = bound(nSeed, 1, 8);
        a = new uint256[](n);
        d = new string[](n);
        for (uint256 i; i < n; ++i) {
            a[i] = bound(uint256(keccak256(abi.encode(amtSeed, i))), 1, 1_000_000e6);
            d[i] = "m";
            total += a[i];
        }
    }

    function _create(uint256 eSeed, uint256 cSeed, uint256 nSeed, uint256 amtSeed, bool protectedEscrow)
        internal
        returns (uint256 id)
    {
        (uint256[] memory a, string[] memory d, uint256 total) = _arrays(nSeed, amtSeed);
        address e = employers[eSeed % 3];
        usdc.mint(e, total);
        bytes memory key;
        if (protectedEscrow) key = _key(creates % 3);
        vm.startPrank(e);
        usdc.approve(address(vault), total);
        id = vault.createEscrow(wallets[cSeed % 6], a, d, key, _period(amtSeed));
        vm.stopPrank();
        creates++;
        if (protectedEscrow) {
            keyOf[id] = key;
            pqCreates++;
        }
    }

    /// Create a protected escrow and drive it with valid mock proofs: release and/or refund.
    function protectedFlow(uint256 eSeed, uint256 cSeed, uint256 nSeed, uint256 amtSeed, uint8 mode) external {
        uint256 id = _create(eSeed, cSeed, nSeed, amtSeed, true);
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        uint256 m = mode % 3;
        if (m == 2 && e.milestoneCount == 1) m = 0; // nothing left to refund once approved
        if (m != 1) {
            vm.prank(e.contractor);
            vault.submitMilestoneWork(id, 0, "proof");
            vm.prank(e.employer);
            vault.approveMilestone(id, 0);
            submits++;
            approves++;
        }
        if (m == 0) {
            vm.prank(e.employer);
            vault.releaseMilestone(id, 0, _proof(id, e, 0));
            releases++;
            pqReleases++;
        } else {
            vm.prank(e.employer);
            vault.refundRemaining(id, _proof(id, e, e.milestoneCount));
            refunds++;
            pqRefunds++;
            if (m == 2) {
                vm.prank(e.employer);
                vault.releaseMilestone(id, 0, _proof(id, e, 0));
                releases++;
                pqReleases++;
            }
        }
    }

    /// Mix of default (0), min, max and arbitrary in-range inspection periods.
    function _period(uint256 seed) internal pure returns (uint256) {
        uint256 k = uint256(keccak256(abi.encode(seed, "period-kind"))) % 4;
        if (k == 0) return 0;
        if (k == 1) return 1 days;
        if (k == 2) return 30 days;
        return 1 days + (uint256(keccak256(abi.encode(seed, "period-val"))) % (29 days + 1));
    }

    function _key(uint256 i) internal pure returns (bytes memory) {
        return abi.encodePacked(keccak256(abi.encode("handler-key", i)));
    }

    function _sigWith(bytes memory key, uint256 id, uint256 action) internal view returns (bytes memory) {
        bytes32 digest = keccak256(abi.encode(keccak256("ArcStreamVault.PQ.v1"), block.chainid, address(vault), id, action));
        return abi.encodePacked(keccak256(abi.encodePacked(key, abi.encodePacked(digest))), new bytes(SIG_LEN - 32));
    }

    /// Valid mock signature for the escrow's own key, or empty for unprotected escrows.
    function _proof(uint256 id, ArcStreamVault.EscrowAgreement memory e, uint256 action)
        internal
        view
        returns (bytes memory)
    {
        if (!e.isPQProtected) return "";
        return _sigWith(keyOf[id], id, action);
    }

    /// Employer actions on a protected escrow with an invalid proof must never succeed.
    function badProofAttempt(uint256 idSeed, uint256 mSeed, bool refundAction, uint8 kind) external {
        uint256 id = _pickId(idSeed);
        if (id == 0) return;
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        if (!e.isPQProtected) return;
        uint256 m = bound(mSeed, 0, (e.milestoneCount < 3 ? e.milestoneCount : 3) - 1);
        uint256 action = refundAction ? e.milestoneCount : m;
        uint256 k = kind % 6;
        bytes memory bad;
        if (k == 0) {
            bad = "";
        } else if (k == 1) {
            bad = _sigWith(keyOf[id], id, refundAction ? m : e.milestoneCount); // wrong action
        } else if (k == 2) {
            bad = _sigWith(_key(7), id, action); // wrong key
        } else if (k == 3) {
            bad = _sigWith(keyOf[id], id + 1, action); // wrong escrow id
        } else if (k == 4) {
            bad = new bytes(SIG_LEN); // well-formed but wrong
        } else {
            bad = new bytes(SIG_LEN - 1); // wrong length
        }
        vm.prank(e.employer);
        if (refundAction) {
            try vault.refundRemaining(id, bad) {
                badProofSuccesses++;
            } catch {}
        } else {
            try vault.releaseMilestone(id, m, bad) {
                badProofSuccesses++;
            } catch {}
        }
    }

    function submit(uint256 idSeed, uint256 mSeed, uint8 lenSeed) external {
        uint256 id = _pickId(idSeed);
        if (id == 0) return;
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        uint256 m = bound(mSeed, 0, (e.milestoneCount < 3 ? e.milestoneCount : 3) - 1);
        string memory proof = string(new bytes(bound(lenSeed, 1, 64)));
        vm.prank(e.contractor);
        try vault.submitMilestoneWork(id, m, proof) {
            submits++;
        } catch {}
    }

    function approve(uint256 idSeed, uint256 mSeed) external {
        uint256 id = _pickId(idSeed);
        if (id == 0) return;
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        uint256 m = bound(mSeed, 0, (e.milestoneCount < 3 ? e.milestoneCount : 3) - 1);
        vm.prank(e.employer);
        try vault.approveMilestone(id, m) {
            approves++;
        } catch {}
    }

    /// Submit then approve in one step, so approved/released flows are well exercised.
    function submitAndApprove(uint256 idSeed, uint256 mSeed) external {
        uint256 id = _pickId(idSeed);
        if (id == 0) return;
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        uint256 m = bound(mSeed, 0, (e.milestoneCount < 3 ? e.milestoneCount : 3) - 1);
        vm.prank(e.contractor);
        try vault.submitMilestoneWork(id, m, "proof") {
            submits++;
        } catch {
            return;
        }
        vm.prank(e.employer);
        try vault.approveMilestone(id, m) {
            approves++;
        } catch {}
    }

    function release(uint256 idSeed, uint256 mSeed, bool byEmployer) external {
        uint256 id = _pickId(idSeed);
        if (id == 0) return;
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        uint256 m = bound(mSeed, 0, (e.milestoneCount < 3 ? e.milestoneCount : 3) - 1);
        vm.prank(byEmployer ? e.employer : e.contractor);
        bytes memory proof = byEmployer ? _proof(id, e, m) : bytes("");
        try vault.releaseMilestone(id, m, proof) {
            releases++;
            if (byEmployer && e.isPQProtected) pqReleases++;
        } catch {}
    }

    function refund(uint256 idSeed, bool byEmployer) external {
        uint256 id = _pickId(idSeed);
        if (id == 0) return;
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        vm.prank(byEmployer ? e.employer : e.contractor);
        bytes memory proof = byEmployer ? _proof(id, e, e.milestoneCount) : bytes("");
        try vault.refundRemaining(id, proof) {
            refunds++;
            if (byEmployer && e.isPQProtected) pqRefunds++;
        } catch {}
    }

    function rotate(uint256 idSeed, uint256 wSeed) external {
        uint256 id = _pickId(idSeed);
        if (id == 0) return;
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        vm.prank(e.contractor);
        try vault.updateContractor(id, wallets[wSeed % 6]) {
            rotations++;
        } catch {}
    }

    /// One party proposes (or accepts, if it happens to match the pending proposal).
    function mutualCancelOne(uint256 idSeed, bool byEmployer, uint256 cSeed) external {
        uint256 id = _pickId(idSeed);
        if (id == 0) return;
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        uint256 remaining = e.totalDeposited - e.totalReleased - vault.refundedAmounts(id);
        if (remaining == 0) return;
        uint256 c = bound(cSeed, 0, remaining);
        bool wasSettled = vault.isSettled(id);
        vm.prank(byEmployer ? e.employer : e.contractor);
        try vault.mutualCancel(id, c, remaining - c) {
            proposals++;
            if (!wasSettled && vault.isSettled(id)) settlements++;
        } catch {}
    }

    /// Both parties call with identical shares (employer first), usually settling.
    function mutualCancelBoth(uint256 idSeed, uint256 cSeed) external {
        uint256 id = _pickId(idSeed);
        if (id == 0) return;
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        uint256 remaining = e.totalDeposited - e.totalReleased - vault.refundedAmounts(id);
        if (remaining == 0 || vault.isSettled(id)) return;
        uint256 c = bound(cSeed, 0, remaining);
        vm.prank(e.employer);
        try vault.mutualCancel(id, c, remaining - c) {
            proposals++;
        } catch {
            return;
        }
        vm.prank(e.contractor);
        try vault.mutualCancel(id, c, remaining - c) {
            proposals++;
            if (vault.isSettled(id)) settlements++;
        } catch {}
    }

    function claim(uint256 idSeed, bool byEmployer) external {
        uint256 id = _pickId(idSeed);
        if (id == 0) return;
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        vm.prank(byEmployer ? e.employer : e.contractor);
        try vault.claimSettlement(id) {
            claims++;
        } catch {}
    }

    function cancelProposal(uint256 idSeed) external {
        uint256 id = _pickId(idSeed);
        if (id == 0) return;
        (address proposer,,) = vault.mutualCancelProposals(id);
        if (proposer == address(0)) return;
        vm.prank(proposer);
        try vault.cancelMutualCancelProposal(id) {
            cancels++;
        } catch {}
    }


    // ------------------------------------------------------------ inspection window actions
    /// Advance time by up to ~40 days so inspection windows actually elapse.
    function warp(uint256 secs) external {
        skip(bound(secs, 1, 40 days));
        warps++;
    }

    /// Contractor claims a milestone; checks the timing/state preconditions independently.
    function claimUncontested(uint256 idSeed, uint256 mSeed) external {
        uint256 id = _pickId(idSeed);
        if (id == 0) return;
        _tryClaim(id, bound(mSeed, 0, (vault.getEscrow(id).milestoneCount < 3 ? vault.getEscrow(id).milestoneCount : 3) - 1));
    }

    function _tryClaim(uint256 id, uint256 m) internal {
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        uint256 deadline = vault.uncontestedClaimTime(id, m);
        uint256 amount = vault.getMilestone(id, m).amount;
        bool eligible = deadline != 0 && block.timestamp >= deadline && !e.isTerminated;
        vm.prank(e.contractor);
        try vault.claimUncontestedMilestone(id, m) {
            uncontestedClaims++;
            uncontestedClaimedAmount += amount;
            if (!eligible) badClaimSuccesses++;
        } catch {
            if (eligible) livenessFailures++;
        }
    }

    /// Submit (optionally approve), wait exactly until / just before the deadline, then claim.
    function submitWarpClaim(uint256 idSeed, uint256 mSeed, uint8 mode) external {
        uint256 id = _pickId(idSeed);
        if (id == 0) return;
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        uint256 m = bound(mSeed, 0, (e.milestoneCount < 3 ? e.milestoneCount : 3) - 1);
        vm.prank(e.contractor);
        try vault.submitMilestoneWork(id, m, "proof") {
            submits++;
        } catch {
            return;
        }
        if (mode & 1 != 0) {
            vm.prank(e.employer);
            try vault.approveMilestone(id, m) {
                approves++;
            } catch {}
        }
        uint256 deadline = vault.uncontestedClaimTime(id, m);
        if (mode & 2 != 0) {
            vm.warp(deadline - 1); // one second early: must not be claimable
            _tryClaim(id, m);
        }
        vm.warp(deadline); // exactly at the deadline: must be claimable (if still active)
        _tryClaim(id, m);
    }

    /// Anyone but the current contractor attempts to claim; must never succeed.
    function badClaimAttempt(uint256 idSeed, uint256 mSeed, uint256 callerSeed) external {
        uint256 id = _pickId(idSeed);
        if (id == 0) return;
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        uint256 m = bound(mSeed, 0, (e.milestoneCount < 3 ? e.milestoneCount : 3) - 1);
        address who = callerSeed % 3 == 0 ? e.employer : wallets[callerSeed % 6];
        if (who == e.contractor) who = e.employer;
        vm.prank(who);
        try vault.claimUncontestedMilestone(id, m) {
            wrongCallerClaimSuccesses++;
        } catch {}
    }

    /// Unassigned donations must only ever increase the vault's surplus.
    function donate(uint256 amount) external {
        amount = bound(amount, 0, 1_000e6);
        usdc.mint(address(vault), amount);
        donated += amount;
    }
}

/// forge-config: default.invariant.runs = 64
/// forge-config: default.invariant.depth = 64
contract ArcStreamVaultInvariantTest is Test {
    ArcStreamVault internal vault;
    MockERC20 internal usdc;
    VaultHandler internal handler;

    function setUp() public {
        vm.etch(0x1800000000000000000000000000000000000004, address(new MockArcPQ()).code);
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        vault = new ArcStreamVault(address(usdc));
        handler = new VaultHandler(vault, usdc);
        targetContract(address(handler));
    }

    function _outstanding() internal view returns (uint256 sum) {
        uint256 count = vault.escrowCount();
        for (uint256 id = 1; id <= count; ++id) {
            ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
            sum += e.totalDeposited - e.totalReleased - vault.refundedAmounts(id);
        }
    }

    /// vault USDC balance >= sum(totalDeposited - totalReleased - refundedAmounts)
    function invariant_VaultBalanceCoversOutstanding() public view {
        assertGe(usdc.balanceOf(address(vault)), _outstanding());
    }

    /// The vault is exactly backed (no leak, no over-pay), counting unclaimed settlement credit.
    function invariant_BalanceEqualsOutstandingPlusDonations() public view {
        assertEq(usdc.balanceOf(address(vault)), _outstanding() + handler.donated());
    }

    /// No employer release/refund on a protected escrow ever succeeded without the right proof.
    function invariant_ProtectedActionsNeverBypassed() public view {
        assertEq(handler.badProofSuccesses(), 0);
    }

    /// Protected escrows keep a 32-byte key whose keccak256 is the commitment; others hold none.
    function invariant_PQKeyAndCommitmentConsistent() public view {
        uint256 count = vault.escrowCount();
        for (uint256 id = 1; id <= count; ++id) {
            ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
            if (e.isPQProtected) {
                assertEq(e.pqPublicKey.length, 32);
                assertEq(e.pqCommitment, keccak256(e.pqPublicKey));
            } else {
                assertEq(e.pqPublicKey.length, 0);
                assertEq(e.pqCommitment, bytes32(0));
            }
        }
    }

    function invariant_PerEscrowAccountingConsistent() public view {
        uint256 count = vault.escrowCount();
        for (uint256 id = 1; id <= count; ++id) {
            ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
            uint256 refunded = vault.refundedAmounts(id);
            assertLe(e.totalReleased + refunded, e.totalDeposited);
            uint256 remaining = e.totalDeposited - e.totalReleased - refunded;
            assertLe(vault.approvedPending(id), remaining);
            if (vault.isSettled(id)) {
                assertTrue(e.isTerminated);
                assertEq(vault.approvedPending(id), 0);
            } else {
                // refund recorded iff terminated (mutual settlement is the only other terminator)
                assertEq(e.isTerminated, refunded > 0);
                assertEq(vault.contractorSettlementOwed(id), 0);
                assertEq(vault.employerSettlementOwed(id), 0);
            }
        }
    }

    /// Once refund-terminated, the unreleased remainder is exactly the approved-pending amount.
    function invariant_TerminatedEscrowOnlyOwesApprovedPending() public view {
        uint256 count = vault.escrowCount();
        for (uint256 id = 1; id <= count; ++id) {
            ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
            if (e.isTerminated && !vault.isSettled(id)) {
                assertEq(e.totalDeposited - e.totalReleased - vault.refundedAmounts(id), vault.approvedPending(id));
            }
        }
    }

    /// After mutual settlement, the remainder is exactly the unclaimed owed credits.
    function invariant_SettledRemainderEqualsUnclaimedCredits() public view {
        uint256 count = vault.escrowCount();
        for (uint256 id = 1; id <= count; ++id) {
            if (vault.isSettled(id)) {
                assertEq(_remainingOf(id), vault.contractorSettlementOwed(id) + vault.employerSettlementOwed(id));
            }
        }
    }

    function _remainingOf(uint256 id) internal view returns (uint256) {
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        return e.totalDeposited - e.totalReleased - vault.refundedAmounts(id);
    }

    /// submittedUnapprovedCount and approvedPending match the milestone flags.
    function invariant_MilestoneFlagsMatchCounters() public view {
        uint256 count = vault.escrowCount();
        for (uint256 id = 1; id <= count; ++id) {
            ArcStreamVault.Milestone[] memory ms = vault.getMilestones(id);
            uint256 submittedUnapproved;
            uint256 pending;
            for (uint256 i; i < ms.length; ++i) {
                if (ms[i].isWorkSubmitted && !ms[i].isApproved) submittedUnapproved++;
                if (ms[i].isApproved && !ms[i].isReleased) pending += ms[i].amount;
                if (ms[i].isApproved) assertTrue(ms[i].isWorkSubmitted, "approved implies submitted");
                if (ms[i].isReleased) assertTrue(ms[i].isApproved, "released implies approved");
            }
            assertEq(vault.submittedUnapprovedCount(id), submittedUnapproved);
            if (!vault.isSettled(id)) assertEq(vault.approvedPending(id), pending);
        }
    }

    /// No claim ever succeeded early, on unsubmitted work, or on a terminated escrow;
    /// no non-contractor ever claimed; eligible claims never failed.
    function invariant_ClaimsOnlyWhenEligible() public view {
        assertEq(handler.badClaimSuccesses(), 0);
        assertEq(handler.wrongCallerClaimSuccesses(), 0);
        assertEq(handler.livenessFailures(), 0);
    }

    /// Everything paid via uncontested claims is reflected in totalReleased.
    function invariant_UncontestedClaimsWithinTotalReleased() public view {
        uint256 released;
        uint256 count = vault.escrowCount();
        for (uint256 id = 1; id <= count; ++id) {
            released += vault.getEscrow(id).totalReleased;
        }
        assertLe(handler.uncontestedClaimedAmount(), released);
    }

    /// Period bounds, submittedAt history and uncontestedClaimTime stay coherent.
    function invariant_InspectionWindowCoherent() public view {
        uint256 count = vault.escrowCount();
        for (uint256 id = 1; id <= count; ++id) {
            ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
            assertGe(e.inspectionPeriod, 1 days);
            assertLe(e.inspectionPeriod, 30 days);
            ArcStreamVault.Milestone[] memory ms = vault.getMilestones(id);
            for (uint256 i; i < ms.length; ++i) {
                uint256 t = vault.uncontestedClaimTime(id, i);
                if (!ms[i].isWorkSubmitted) {
                    assertEq(ms[i].submittedAt, 0);
                    assertEq(t, 0);
                } else {
                    assertGt(ms[i].submittedAt, 0);
                    assertLe(ms[i].submittedAt, block.timestamp);
                    assertEq(t, ms[i].isReleased ? 0 : ms[i].submittedAt + e.inspectionPeriod);
                }
            }
        }
    }

    /// Non-vacuity: the handler's submit + warp + claim path really pays out, in every mode.
    function test_Handler_SubmitWarpClaimPathIsReachable() public {
        handler.create(0, 0, 3, 11);
        handler.submitWarpClaim(1, 0, 0); // unapproved branch, claim at deadline
        assertEq(handler.uncontestedClaims(), 1);
        handler.submitWarpClaim(1, 1, 1); // approved branch
        assertEq(handler.uncontestedClaims(), 2);
        handler.submitWarpClaim(1, 2, 3); // approved + one-second-early attempt first
        assertEq(handler.uncontestedClaims(), 3);
        assertEq(handler.badClaimSuccesses(), 0);
        assertEq(handler.livenessFailures(), 0);
        assertGt(handler.uncontestedClaimedAmount(), 0);
        handler.badClaimAttempt(1, 0, 0);
        assertEq(handler.wrongCallerClaimSuccesses(), 0);
        handler.warp(5 days);
        assertEq(handler.warps(), 1);
    }
}
