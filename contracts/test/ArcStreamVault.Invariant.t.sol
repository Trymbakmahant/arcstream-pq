// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";
import {MockERC20} from "../test-helpers/MockERC20.sol";
import {PQMerkle} from "../test-helpers/PQMerkle.sol";

/// Bounded-action handler: random sequences of create / submit / approve / release / refund /
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

    mapping(uint256 id => bytes32 seed) public seedOf;

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

    /// PQ-protected escrow with a fresh, unique tree per creation.
    function createProtected(uint256 eSeed, uint256 cSeed, uint256 nSeed, uint256 amtSeed) external {
        _create(eSeed, cSeed, nSeed, amtSeed, true);
    }

    function _create(uint256 eSeed, uint256 cSeed, uint256 nSeed, uint256 amtSeed, bool protectedEscrow) internal {
        address e = employers[eSeed % 3];
        address c = wallets[cSeed % 6];
        uint256 n = bound(nSeed, 1, 8);
        uint256[] memory a = new uint256[](n);
        string[] memory d = new string[](n);
        uint256 total;
        for (uint256 i; i < n; ++i) {
            a[i] = bound(uint256(keccak256(abi.encode(amtSeed, i))), 1, 1_000_000e6);
            d[i] = "m";
            total += a[i];
        }
        usdc.mint(e, total);
        bytes32 root;
        bytes32 seed;
        if (protectedEscrow) {
            seed = keccak256(abi.encode("handler-seed", creates));
            root = PQMerkle.root(address(vault), e, seed, n);
        }
        vm.startPrank(e);
        usdc.approve(address(vault), total);
        uint256 id = vault.createEscrow(c, a, d, root);
        vm.stopPrank();
        creates++;
        if (protectedEscrow) {
            seedOf[id] = seed;
            pqCreates++;
        }
    }

    function _proof(uint256 id, ArcStreamVault.EscrowAgreement memory e, uint256 action)
        internal
        view
        returns (bytes memory)
    {
        if (!e.isPQProtected) return "";
        return PQMerkle.proof(address(vault), e.employer, seedOf[id], e.milestoneCount, action);
    }

    /// Employer actions on a protected escrow with no proof / a wrong-action proof must never succeed.
    function badProofAttempt(uint256 idSeed, uint256 mSeed, bool refundAction, bool empty) external {
        uint256 id = _pickId(idSeed);
        if (id == 0) return;
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        if (!e.isPQProtected) return;
        uint256 m = bound(mSeed, 0, (e.milestoneCount < 3 ? e.milestoneCount : 3) - 1);
        // wrong action: release proof for milestone m used on refund, refund-leaf proof used on release
        bytes memory bad = empty ? bytes("") : _proof(id, e, refundAction ? m : e.milestoneCount);
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

    /// Protected escrows keep their commitment and flag; each commitment is registered as used.
    function invariant_PQCommitmentsConsistent() public view {
        uint256 count = vault.escrowCount();
        for (uint256 id = 1; id <= count; ++id) {
            ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
            assertEq(e.isPQProtected, e.pqCommitment != bytes32(0));
            if (e.isPQProtected) assertTrue(vault.pqCommitmentUsed(e.employer, e.pqCommitment));
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
}
