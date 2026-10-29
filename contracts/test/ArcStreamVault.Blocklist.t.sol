// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";
import {MockArcPQ} from "../test-helpers/MockArcPQ.sol";
import {BlocklistToken} from "../test-helpers/BlocklistToken.sol";

/// A blocklisted/reverting recipient must only be able to block its own claim.
contract ArcStreamVaultBlocklistTest is Test {
    ArcStreamVault internal vault;
    BlocklistToken internal token;

    address internal employer = makeAddr("employer");
    address internal contractor = makeAddr("contractor");
    address internal newContractor = makeAddr("newContractor");

    uint256 internal constant TOTAL = 600e6;
    uint256 internal constant C_SHARE = 250e6;
    uint256 internal constant E_SHARE = 350e6;
    uint256 internal id;

    address internal constant PQ_PRECOMPILE = 0x1800000000000000000000000000000000000004;
    bytes internal pqKey = abi.encodePacked(keccak256("pq-public-key-A"));

    /// Mock-valid SLH-DSA signature by `pqKey` over the vault's domain-bound digest.
    function _pqSig(uint256 escrowId, uint256 action) internal view returns (bytes memory) {
        bytes32 digest = vault.pqSigningMessage(escrowId, action);
        return abi.encodePacked(keccak256(abi.encodePacked(pqKey, abi.encodePacked(digest))), new bytes(7856 - 32));
    }

    function setUp() public {
        vm.etch(PQ_PRECOMPILE, address(new MockArcPQ()).code);
        token = new BlocklistToken();
        vault = new ArcStreamVault(address(token));
        token.mint(employer, 10_000e6);
        vm.prank(employer);
        token.approve(address(vault), type(uint256).max);

        uint256[] memory a = new uint256[](3);
        a[0] = 100e6;
        a[1] = 200e6;
        a[2] = 300e6;
        string[] memory d = new string[](3);
        d[0] = "a";
        d[1] = "b";
        d[2] = "c";
        vm.prank(employer);
        id = vault.createEscrow(contractor, a, d, "");

        vm.prank(employer);
        vault.mutualCancel(id, C_SHARE, E_SHARE);
        vm.prank(contractor);
        vault.mutualCancel(id, C_SHARE, E_SHARE);
        assertTrue(vault.isSettled(id));
    }

    function test_Blocklist_BlockedContractorCannotClaim_EmployerStillCan() public {
        token.setBlocked(contractor, true);

        vm.prank(contractor);
        vm.expectRevert(abi.encodeWithSelector(BlocklistToken.Blocked.selector, contractor));
        vault.claimSettlement(id);
        // failed claim rolled back completely
        assertEq(vault.contractorSettlementOwed(id), C_SHARE);
        assertEq(vault.getEscrow(id).totalReleased, 0);

        uint256 before_ = token.balanceOf(employer);
        vm.prank(employer);
        vault.claimSettlement(id);
        assertEq(token.balanceOf(employer), before_ + E_SHARE);
        assertEq(vault.refundedAmounts(id), E_SHARE);
        assertEq(token.balanceOf(address(vault)), C_SHARE);
    }

    function test_Blocklist_BlockedEmployerCannotClaim_ContractorStillCan() public {
        token.setBlocked(employer, true);

        vm.prank(employer);
        vm.expectRevert(abi.encodeWithSelector(BlocklistToken.Blocked.selector, employer));
        vault.claimSettlement(id);
        assertEq(vault.employerSettlementOwed(id), E_SHARE);
        assertEq(vault.refundedAmounts(id), 0);

        vm.prank(contractor);
        vault.claimSettlement(id);
        assertEq(token.balanceOf(contractor), C_SHARE);
        assertEq(token.balanceOf(address(vault)), E_SHARE);
    }

    function test_Blocklist_UnblockedPartyCanClaimLater() public {
        token.setBlocked(contractor, true);
        vm.prank(contractor);
        vm.expectRevert();
        vault.claimSettlement(id);
        token.setBlocked(contractor, false);
        vm.prank(contractor);
        vault.claimSettlement(id);
        assertEq(token.balanceOf(contractor), C_SHARE);
    }

    function test_Blocklist_BlockedContractorRotatesToCleanWalletAndClaims() public {
        token.setBlocked(contractor, true);
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);
        vm.prank(newContractor);
        vault.claimSettlement(id);
        assertEq(token.balanceOf(newContractor), C_SHARE);
        assertEq(token.balanceOf(contractor), 0);
    }

    function test_Blocklist_BlockedContractorBlocksOnlyOwnClaim_FullDrain() public {
        token.setBlocked(contractor, true);
        vm.prank(employer);
        vault.claimSettlement(id);
        // contractor credit remains safely held, accounted for
        assertEq(token.balanceOf(address(vault)), C_SHARE);
        assertEq(vault.contractorSettlementOwed(id), C_SHARE);
        assertEq(vault.getEscrow(id).totalDeposited - vault.getEscrow(id).totalReleased - vault.refundedAmounts(id), C_SHARE);
    }

    function test_Blocklist_BlockedContractorDoesNotBlockEmployerRefundPath() public {
        // separate escrow, no settlement: blocked contractor cannot block employer refund
        uint256[] memory a = new uint256[](1);
        a[0] = 50e6;
        string[] memory d = new string[](1);
        d[0] = "x";
        vm.prank(employer);
        uint256 id2 = vault.createEscrow(contractor, a, d, "");
        token.setBlocked(contractor, true);
        uint256 before_ = token.balanceOf(employer);
        vm.prank(employer);
        vault.refundRemaining(id2, "");
        assertEq(token.balanceOf(employer), before_ + 50e6);
    }

    // ------------------------------------------------------------ protected escrows

    function _protected() internal returns (uint256 pid) {
        uint256[] memory a = new uint256[](2);
        a[0] = 50e6;
        a[1] = 70e6;
        string[] memory d = new string[](2);
        d[0] = "x";
        d[1] = "y";
        vm.prank(employer);
        pid = vault.createEscrow(contractor, a, d, pqKey);
    }

    function test_Blocklist_ProtectedReleaseRollsBackWhenContractorBlocked_ThenSucceedsOnUnblock() public {
        uint256 pid = _protected();
        vm.prank(contractor);
        vault.submitMilestoneWork(pid, 0, "p");
        vm.prank(employer);
        vault.approveMilestone(pid, 0);
        token.setBlocked(contractor, true);

        bytes memory sig = _pqSig(pid, 0);
        vm.prank(employer);
        vm.expectRevert(abi.encodeWithSelector(BlocklistToken.Blocked.selector, contractor));
        vault.releaseMilestone(pid, 0, sig);
        assertFalse(vault.getMilestone(pid, 0).isReleased);
        assertEq(vault.getEscrow(pid).totalReleased, 0);

        token.setBlocked(contractor, false);
        vm.prank(employer);
        vault.releaseMilestone(pid, 0, sig);
        assertEq(token.balanceOf(contractor), 50e6);
    }

    function test_Blocklist_BlockedContractorDoesNotBlockProtectedEmployerRefund() public {
        uint256 pid = _protected();
        token.setBlocked(contractor, true);
        uint256 before_ = token.balanceOf(employer);
        bytes memory sig = _pqSig(pid, 2);
        vm.prank(employer);
        vault.refundRemaining(pid, sig);
        assertEq(token.balanceOf(employer), before_ + 120e6);
    }

    function test_Blocklist_BlockedEmployerCannotRefundProtected_ContractorWaiverStillBlockedToo() public {
        uint256 pid = _protected();
        token.setBlocked(employer, true);
        bytes memory sig = _pqSig(pid, 2);
        vm.prank(employer);
        vm.expectRevert(abi.encodeWithSelector(BlocklistToken.Blocked.selector, employer));
        vault.refundRemaining(pid, sig);
        assertFalse(vault.getEscrow(pid).isTerminated);
        // the refund destination is the employer, so a contractor waiver is blocked as well
        vm.prank(contractor);
        vm.expectRevert(abi.encodeWithSelector(BlocklistToken.Blocked.selector, employer));
        vault.refundRemaining(pid, "");
    }
}
