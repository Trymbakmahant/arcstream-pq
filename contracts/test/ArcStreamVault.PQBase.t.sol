// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ArcStreamVaultTestBase} from "./ArcStreamVault.Base.t.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";

/// Shared PQ fixtures: a second employer and expectation helpers. No tests here.
abstract contract ArcStreamVaultPQBase is ArcStreamVaultTestBase {
    address internal employer2 = makeAddr("employer2");

    uint256 internal constant UNIT = 10e6; // milestone amount used by _createN

    function setUp() public virtual override {
        super.setUp();
        usdc.mint(employer2, EMPLOYER_FUNDS);
        vm.prank(employer2);
        usdc.approve(address(vault), type(uint256).max);
    }

    /// Employer2 creates a `n`-milestone escrow with an explicit key.
    function _createN2(uint256 n, bytes memory key) internal returns (uint256 id) {
        uint256[] memory a = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            a[i] = UNIT;
        }
        vm.prank(employer2);
        id = vault.createEscrow(contractor, a, _descs(n), key, 0);
    }

    /// Submit + approve milestone `i` of `id` (contractor submits, the escrow's employer approves).
    function _ready(uint256 id, uint256 i) internal {
        address e = vault.getEscrow(id).employer;
        address c = vault.getEscrow(id).contractor;
        vm.prank(c);
        vault.submitMilestoneWork(id, i, PROOF);
        vm.prank(e);
        vault.approveMilestone(id, i);
    }

    /// Employer release attempt expected to revert InvalidQuantumProof; state must not move.
    function _expectInvalidRelease(uint256 id, uint256 i, bytes memory proof) internal {
        uint256 vaultBal = usdc.balanceOf(address(vault));
        uint256 conBal = usdc.balanceOf(contractor);
        vm.expectRevert(ArcStreamVault.InvalidQuantumProof.selector);
        vm.prank(employer);
        vault.releaseMilestone(id, i, proof);
        assertEq(usdc.balanceOf(address(vault)), vaultBal);
        assertFalse(vault.getMilestone(id, i).isReleased);
        assertEq(usdc.balanceOf(contractor), conBal);
    }

    function _expectInvalidRefund(uint256 id, bytes memory proof) internal {
        uint256 vaultBal = usdc.balanceOf(address(vault));
        vm.expectRevert(ArcStreamVault.InvalidQuantumProof.selector);
        vm.prank(employer);
        vault.refundRemaining(id, proof);
        assertEq(usdc.balanceOf(address(vault)), vaultBal);
        assertFalse(vault.getEscrow(id).isTerminated);
        assertEq(vault.refundedAmounts(id), 0);
    }
}
