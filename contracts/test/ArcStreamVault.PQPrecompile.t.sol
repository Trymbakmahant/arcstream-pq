// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ArcStreamVaultPQBase} from "./ArcStreamVault.PQBase.t.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";
import {
    MockArcPQEmptyReturn,
    MockArcPQWordTwo,
    MockArcPQLongReturn,
    MockArcPQShortReturn,
    MockArcPQReverting,
    MockArcPQAlwaysTrue
} from "../test-helpers/MockArcPQ.sol";

/// Misbehaving / vanished precompile after creation, and lifecycle functions that must be
/// unaffected by PQ protection.
contract ArcStreamVaultPQPrecompileTest is ArcStreamVaultPQBase {
    uint256 internal id;

    function setUp() public override {
        super.setUp();
        id = _createProtected(3);
        _ready(id, 0);
    }

    function _swap(address impl) internal {
        vm.etch(PQ_PRECOMPILE, impl.code);
    }

    function _assertBlocked(bytes memory proofRel, bytes memory proofRef) internal {
        _expectInvalidRelease(id, 0, proofRel);
        _expectInvalidRefund(id, proofRef);
    }

    // ------------------------------------------------------------ garbage precompile results

    function test_RevertWhen_PrecompileReturnsNoBytes() public {
        _swap(address(new MockArcPQEmptyReturn()));
        _assertBlocked(_sig(id, 0), _sig(id, 3));
    }

    function test_RevertWhen_PrecompileReturnsNonOneWord() public {
        _swap(address(new MockArcPQWordTwo()));
        _assertBlocked(_sig(id, 0), _sig(id, 3));
    }

    function test_RevertWhen_PrecompileReturnsMoreThanOneWord() public {
        _swap(address(new MockArcPQLongReturn()));
        _assertBlocked(_sig(id, 0), _sig(id, 3));
    }

    function test_RevertWhen_PrecompileReturnsShortData() public {
        _swap(address(new MockArcPQShortReturn()));
        _assertBlocked(_sig(id, 0), _sig(id, 3));
    }

    function test_RevertWhen_PrecompileReverts() public {
        _swap(address(new MockArcPQReverting()));
        _assertBlocked(_sig(id, 0), _sig(id, 3));
    }

    function test_RevertWhen_PrecompileRemovedAfterCreation() public {
        vm.etch(PQ_PRECOMPILE, "");
        _assertBlocked(_sig(id, 0), _sig(id, 3));
    }

    function test_RealMockRevertsOnLengthsMapToInvalidQuantumProof() public {
        // 7855-byte proof never reaches the precompile; vault rejects it first
        _assertBlocked(new bytes(7855), new bytes(1));
    }

    function test_PrecompileTrueIsWhatAuthorizes() public {
        // control: a verifier that answers word 1 for anything authorizes any 7856-byte blob,
        // but still not a wrong-length one
        _swap(address(new MockArcPQAlwaysTrue()));
        _expectInvalidRelease(id, 0, new bytes(100));
        vm.prank(employer);
        vault.releaseMilestone(id, 0, new bytes(SIG_LEN));
        assertEq(usdc.balanceOf(contractor), UNIT);
    }

    function test_BrokenPrecompileDoesNotBlockContractorOrMutualCancel() public {
        _swap(address(new MockArcPQReverting()));
        vm.prank(contractor);
        vault.releaseMilestone(id, 0, "");
        assertEq(usdc.balanceOf(contractor), UNIT);
        _settle(id, UNIT / 2, 3 * UNIT / 2);
        vm.prank(contractor);
        vault.claimSettlement(id);
        vm.prank(employer);
        vault.claimSettlement(id);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    // ------------------------------------------------------------ unaffected functions

    function test_SubmitApproveUpdateContractorUnaffectedOnProtectedEscrow() public {
        _swap(address(new MockArcPQReverting()));
        _submit(id, 1);
        _approveOnly(id, 1);
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);
        assertEq(vault.getEscrow(id).contractor, newContractor);
        // rotated contractor claims with no proof
        vm.prank(newContractor);
        vault.releaseMilestone(id, 1, "");
        assertEq(usdc.balanceOf(newContractor), UNIT);
    }

    function test_MutualCancelAndClaimUnaffectedOnProtectedEscrow() public {
        _settle(id, UNIT, 2 * UNIT);
        assertTrue(vault.isSettled(id));
        vm.prank(contractor);
        vault.claimSettlement(id);
        vm.prank(employer);
        vault.claimSettlement(id);
        assertEq(usdc.balanceOf(contractor), UNIT);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_EmployerReleaseAfterContractorRotationUsesSameSignature() public {
        bytes memory sig = _sig(id, 0);
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);
        _release(id, 0, sig);
        assertEq(usdc.balanceOf(newContractor), UNIT);
        assertEq(usdc.balanceOf(contractor), 0);
    }

    function test_EmployerReleaseBlockedAfterSettlementEvenWithValidProof() public {
        _settle(id, UNIT, 2 * UNIT);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.EscrowSettled.selector);
        vault.releaseMilestone(id, 0, _sig(id, 0));
    }

    function test_EmployerRefundAfterContractorTerminationRevertsTerminated() public {
        vm.prank(contractor);
        vault.refundRemaining(id, "");
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.EscrowTerminated.selector);
        vault.refundRemaining(id, _sig(id, 3));
        // approved milestone still releasable by the employer with proof
        _release(id, 0, _sig(id, 0));
        assertEq(usdc.balanceOf(contractor), UNIT);
    }
}
