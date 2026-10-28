// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";
import {MockERC20} from "../test-helpers/MockERC20.sol";
import {PQMerkle} from "../test-helpers/PQMerkle.sol";

abstract contract ArcStreamVaultTestBase is Test {
    ArcStreamVault internal vault;
    MockERC20 internal usdc;

    address internal employer = makeAddr("employer");
    address internal contractor = makeAddr("contractor");
    address internal newContractor = makeAddr("newContractor");
    address internal outsider = makeAddr("outsider");

    uint256 internal constant M0 = 100e6;
    uint256 internal constant M1 = 200e6;
    uint256 internal constant M2 = 300e6;
    uint256 internal constant TOTAL = 600e6;
    uint256 internal constant EMPLOYER_FUNDS = 1_000_000e6;
    string internal constant PROOF = "ipfs://proof";

    function setUp() public virtual {
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        vault = new ArcStreamVault(address(usdc));
        usdc.mint(employer, EMPLOYER_FUNDS);
        vm.prank(employer);
        usdc.approve(address(vault), type(uint256).max);
    }

    function _three() internal pure returns (uint256[] memory a) {
        a = new uint256[](3);
        a[0] = M0;
        a[1] = M1;
        a[2] = M2;
    }

    function _descs(uint256 n) internal pure returns (string[] memory d) {
        d = new string[](n);
        for (uint256 i; i < n; ++i) {
            d[i] = "milestone";
        }
    }

    function _createDefault() internal returns (uint256 id) {
        uint256[] memory a = _three();
        string[] memory d = _descs(3);
        vm.prank(employer);
        id = vault.createEscrow(contractor, a, d, bytes32(0));
    }

    // ------------------------------------------------------------ PQ helpers

    /// Employer creates an escrow of `n` milestones (amount 10e6 each) with `root` as commitment.
    function _createN(uint256 n, bytes32 root) internal returns (uint256 id) {
        uint256[] memory a = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            a[i] = 10e6;
        }
        string[] memory d = _descs(n);
        vm.prank(employer);
        id = vault.createEscrow(contractor, a, d, root);
    }

    /// Root for `who` as employer over `n` milestones from `seed`.
    function _rootFor(address who, bytes32 seed, uint256 n) internal view returns (bytes32) {
        return PQMerkle.root(address(vault), who, seed, n);
    }

    function _proofFor(address who, bytes32 seed, uint256 n, uint256 action) internal view returns (bytes memory) {
        return PQMerkle.proof(address(vault), who, seed, n, action);
    }

    /// Employer-created protected escrow with `n` milestones, tree built from `seed`.
    function _createProtected(uint256 n, bytes32 seed) internal returns (uint256 id) {
        id = _createN(n, _rootFor(employer, seed, n));
    }

    /// Employer release with explicit proof bytes.
    function _release(uint256 id, uint256 i, bytes memory proof) internal {
        vm.prank(employer);
        vault.releaseMilestone(id, i, proof);
    }

    /// Employer refund with explicit proof bytes.
    function _refund(uint256 id, bytes memory proof) internal {
        vm.prank(employer);
        vault.refundRemaining(id, proof);
    }

    /// Current contractor submits work proof for milestone `i`.
    function _submit(uint256 id, uint256 i) internal {
        address c = vault.getEscrow(id).contractor;
        vm.prank(c);
        vault.submitMilestoneWork(id, i, PROOF);
    }

    /// Employer approves an already-submitted milestone.
    function _approveOnly(uint256 id, uint256 i) internal {
        vm.prank(employer);
        vault.approveMilestone(id, i);
    }

    /// Submit (by current contractor) then approve (by employer).
    function _approve(uint256 id, uint256 i) internal {
        _submit(id, i);
        _approveOnly(id, i);
    }

    function _release(uint256 id, uint256 i) internal {
        vm.prank(employer);
        vault.releaseMilestone(id, i, "");
    }

    function _refund(uint256 id) internal {
        vm.prank(employer);
        vault.refundRemaining(id, "");
    }

    function _remaining(uint256 id) internal view returns (uint256) {
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        return e.totalDeposited - e.totalReleased - vault.refundedAmounts(id);
    }

    /// Employer proposes, current contractor accepts the identical split -> settled.
    function _settle(uint256 id, uint256 cShare, uint256 eShare) internal {
        address c = vault.getEscrow(id).contractor;
        vm.prank(employer);
        vault.mutualCancel(id, cShare, eShare);
        vm.prank(c);
        vault.mutualCancel(id, cShare, eShare);
    }
}
