// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {ArcStreamVaultPQBase} from "./ArcStreamVault.PQBase.t.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";
import {MockArcPQ, MockArcPQEmptyReturn, MockArcPQReverting} from "../test-helpers/MockArcPQ.sol";

/// SLH-DSA-SHA2-128s second factor: creation, signing message, protected release/refund.
contract ArcStreamVaultPQTest is ArcStreamVaultPQBase {
    // ------------------------------------------------------------ creation

    function test_CreateProtected_StoresKeyCommitmentAndFlag() public {
        uint256 id = _createProtected(3);
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        assertTrue(e.isPQProtected);
        assertEq(e.pqPublicKey, pqKey);
        assertEq(e.pqCommitment, keccak256(pqKey));
        assertEq(e.employer, employer);
        assertEq(e.totalDeposited, 3 * UNIT);
    }

    function test_CreateUnprotected_EmptyKeyHasNoPQState() public {
        uint256 id = _createDefault();
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        assertFalse(e.isPQProtected);
        assertEq(e.pqPublicKey.length, 0);
        assertEq(e.pqCommitment, bytes32(0));
    }

    function test_CreateProtected_NeedsNoSignature() public {
        uint256 before = usdc.balanceOf(employer);
        uint256 id = _createProtected(2);
        assertEq(usdc.balanceOf(employer), before - 2 * UNIT);
        assertEq(usdc.balanceOf(address(vault)), 2 * UNIT);
        assertEq(id, 1);
    }

    function test_RevertWhen_PublicKeyLengthWrong() public {
        uint256[] memory a = new uint256[](1);
        a[0] = UNIT;
        string[] memory d = _descs(1);
        uint256[5] memory lens = [uint256(1), 16, 31, 33, 64];
        for (uint256 i; i < lens.length; ++i) {
            vm.prank(employer);
            vm.expectRevert(ArcStreamVault.InvalidPQPublicKey.selector);
            vault.createEscrow(contractor, a, d, new bytes(lens[i]));
        }
        assertEq(vault.escrowCount(), 0);
    }

    function test_RevertWhen_PrecompileAbsentAndKeyProvided() public {
        vm.etch(PQ_PRECOMPILE, "");
        uint256[] memory a = new uint256[](1);
        a[0] = UNIT;
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.PQPrecompileUnavailable.selector);
        vault.createEscrow(contractor, a, _descs(1), pqKey);
        assertEq(vault.escrowCount(), 0);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_UnprotectedCreationWorksWhenPrecompileAbsent() public {
        vm.etch(PQ_PRECOMPILE, "");
        uint256 id = _createDefault();
        assertFalse(vault.getEscrow(id).isPQProtected);
        assertEq(id, 1);
    }

    function test_BadKeyLengthTakesPrecedenceOverMissingPrecompile() public {
        vm.etch(PQ_PRECOMPILE, "");
        uint256[] memory a = new uint256[](1);
        a[0] = UNIT;
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.InvalidPQPublicKey.selector);
        vault.createEscrow(contractor, a, _descs(1), new bytes(31));
    }

    function test_RevertWhen_PrecompileSucceedsWithEmptyReturndataAtCreation() public {
        vm.etch(PQ_PRECOMPILE, address(new MockArcPQEmptyReturn()).code);
        uint256[] memory a = new uint256[](1);
        a[0] = UNIT;
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.PQPrecompileUnavailable.selector);
        vault.createEscrow(contractor, a, _descs(1), pqKey);
    }

    function test_CreateProtectedWorksWhenProbeReverts() public {
        // the live precompile reverts for the malformed empty probe key; any revert means "present"
        vm.etch(PQ_PRECOMPILE, address(new MockArcPQReverting()).code);
        uint256 id = _createProtected(1);
        assertTrue(vault.getEscrow(id).isPQProtected);
    }

    // ------------------------------------------------------------ signing message

    function test_SigningMessageIsExactDomainBoundDigest() public view {
        bytes32 expected = keccak256(abi.encode(keccak256("ArcStreamVault.PQ.v1"), block.chainid, address(vault), 7, 2));
        assertEq(vault.pqSigningMessage(7, 2), expected);
        assertEq(vault.PQ_DOMAIN(), keccak256("ArcStreamVault.PQ.v1"));
    }

    function test_SigningMessageBindsEveryField() public {
        bytes32 base = vault.pqSigningMessage(1, 0);
        assertNotEq(base, vault.pqSigningMessage(2, 0));
        assertNotEq(base, vault.pqSigningMessage(1, 1));
        vm.chainId(block.chainid + 1);
        assertNotEq(base, vault.pqSigningMessage(1, 0));
        ArcStreamVault other = new ArcStreamVault(address(usdc));
        vm.chainId(block.chainid - 1);
        assertNotEq(base, other.pqSigningMessage(1, 0));
    }

    function test_VaultPassesExactArgsToPrecompile() public {
        uint256 id = _createProtected(2);
        _ready(id, 1);
        bytes memory sig = _sig(id, 1);
        bytes memory expected = abi.encodeWithSelector(
            MockArcPQ.verifySlhDsaSha2128s.selector, pqKey, abi.encodePacked(_digest(block.chainid, address(vault), id, 1)), sig
        );
        vm.expectCall(PQ_PRECOMPILE, expected);
        _release(id, 1, sig);
    }

    // ------------------------------------------------------------ happy paths

    function test_ProtectedEmployerReleaseWithValidProof() public {
        uint256 id = _createProtected(3);
        _ready(id, 1);
        vm.expectEmit(true, false, false, true, address(vault));
        emit ArcStreamVault.QuantumProofVerified(id, 1, keccak256(pqKey));
        vm.expectEmit(true, false, true, true, address(vault));
        emit ArcStreamVault.MilestoneReleased(id, 1, contractor, UNIT);
        _release(id, 1, _sig(id, 1));
        assertEq(usdc.balanceOf(contractor), UNIT);
        assertTrue(vault.getMilestone(id, 1).isReleased);
        assertEq(vault.getEscrow(id).totalReleased, UNIT);
    }

    function test_ReleaseOrderIsFreeAcrossMilestones() public {
        uint256 id = _createProtected(3);
        _ready(id, 2);
        _ready(id, 0);
        _release(id, 2, _sig(id, 2));
        _release(id, 0, _sig(id, 0));
        assertEq(usdc.balanceOf(contractor), 2 * UNIT);
    }

    function test_ProtectedEmployerRefundWithValidProof() public {
        uint256 id = _createProtected(3);
        uint256 before = usdc.balanceOf(employer);
        vm.expectEmit(true, false, false, true, address(vault));
        emit ArcStreamVault.QuantumProofVerified(id, 3, keccak256(pqKey));
        vm.expectEmit(true, true, false, true, address(vault));
        emit ArcStreamVault.EscrowRefunded(id, employer, 3 * UNIT);
        _refund(id, _sig(id, 3));
        assertEq(usdc.balanceOf(employer), before + 3 * UNIT);
        assertTrue(vault.getEscrow(id).isTerminated);
        assertEq(vault.refundedAmounts(id), 3 * UNIT);
    }

    function test_RefundKeepsApprovedMilestoneReleasableWithProof() public {
        uint256 id = _createProtected(3);
        _ready(id, 0);
        _refund(id, _sig(id, 3));
        assertEq(vault.refundedAmounts(id), 2 * UNIT);
        _release(id, 0, _sig(id, 0));
        assertEq(usdc.balanceOf(contractor), UNIT);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_SameKeyReusedAcrossEscrowsWithPerEscrowMessages() public {
        uint256 id1 = _createProtected(2);
        uint256 id2 = _createProtected(2);
        uint256 id3 = _createProtected(1);
        assertEq(vault.getEscrow(id1).pqCommitment, vault.getEscrow(id3).pqCommitment);
        _ready(id1, 0);
        _ready(id2, 0);
        // a signature for escrow 1 does not open escrow 2
        _expectInvalidRelease(id2, 0, _sig(id1, 0));
        _release(id1, 0, _sig(id1, 0));
        _release(id2, 0, _sig(id2, 0));
        _refund(id3, _sig(id3, 1));
        assertEq(usdc.balanceOf(contractor), 2 * UNIT);
        assertTrue(vault.getEscrow(id3).isTerminated);
    }

    function test_DifferentEmployersMayUseDifferentKeysIndependently() public {
        uint256 id1 = _createProtected(1);
        uint256 id2 = _createN2(1, pqKeyB);
        _ready(id1, 0);
        _ready(id2, 0);
        vm.prank(employer2);
        vault.releaseMilestone(id2, 0, _sigFor(pqKeyB, id2, 0));
        assertEq(usdc.balanceOf(contractor), UNIT);
        _expectInvalidRelease(id1, 0, _sigFor(pqKeyB, id1, 0));
        _release(id1, 0, _sig(id1, 0));
    }

    function test_ProofIsNotBoundToSenderButOnlyPaysContractor() public {
        // a copy of the signature seen in the mempool cannot be used by an outsider
        uint256 id = _createProtected(1);
        _ready(id, 0);
        bytes memory sig = _sig(id, 0);
        vm.prank(outsider);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vault.releaseMilestone(id, 0, sig);
        assertEq(usdc.balanceOf(outsider), 0);
    }

    // ------------------------------------------------------------ invalid release proofs

    function test_RevertWhen_ReleaseWithoutProof() public {
        uint256 id = _createProtected(2);
        _ready(id, 0);
        _expectInvalidRelease(id, 0, "");
    }

    function test_RevertWhen_ReleaseProofWrongLength() public {
        uint256 id = _createProtected(2);
        _ready(id, 0);
        bytes memory sig = _sig(id, 0);
        _expectInvalidRelease(id, 0, new bytes(32));
        _expectInvalidRelease(id, 0, new bytes(7855));
        _expectInvalidRelease(id, 0, new bytes(7857));
        _expectInvalidRelease(id, 0, abi.encodePacked(sig, hex"00"));
        bytes memory truncated = new bytes(7855);
        for (uint256 i; i < 7855; ++i) {
            truncated[i] = sig[i];
        }
        _expectInvalidRelease(id, 0, truncated);
    }

    function test_RevertWhen_ReleaseProofWellFormedButWrong() public {
        uint256 id = _createProtected(2);
        _ready(id, 0);
        _expectInvalidRelease(id, 0, new bytes(SIG_LEN));
        bytes memory sig = _sig(id, 0);
        sig[0] = bytes1(uint8(sig[0]) ^ 1);
        _expectInvalidRelease(id, 0, sig);
    }

    function test_RevertWhen_ReleaseSignedByWrongKey() public {
        uint256 id = _createProtected(2);
        _ready(id, 0);
        _expectInvalidRelease(id, 0, _sigFor(pqKeyB, id, 0));
    }

    function test_RevertWhen_ReleaseSignedForWrongEscrowId() public {
        uint256 id = _createProtected(2);
        _ready(id, 0);
        _expectInvalidRelease(id, 0, _sig(id + 1, 0));
        _expectInvalidRelease(id, 0, _sig(0, 0));
    }

    function test_RevertWhen_ReleaseSignedForWrongAction() public {
        uint256 id = _createProtected(3);
        _ready(id, 0);
        _expectInvalidRelease(id, 0, _sig(id, 1));
        _expectInvalidRelease(id, 0, _sig(id, 3)); // refund action
    }

    function test_RevertWhen_ReleaseSignedForWrongChainId() public {
        uint256 id = _createProtected(2);
        _ready(id, 0);
        // digest built for another chain
        _expectInvalidRelease(id, 0, _sigOver(pqKey, _digest(block.chainid + 1, address(vault), id, 0)));
        // right-chain signature, but the chain id changed afterwards
        bytes memory sig = _sig(id, 0);
        vm.chainId(5042002);
        _expectInvalidRelease(id, 0, sig);
        // and a signature made for the new chain works
        _release(id, 0, _sig(id, 0));
        assertEq(usdc.balanceOf(contractor), UNIT);
    }

    function test_RevertWhen_ReleaseSignedForWrongVault() public {
        uint256 id = _createProtected(2);
        _ready(id, 0);
        ArcStreamVault other = new ArcStreamVault(address(usdc));
        _expectInvalidRelease(id, 0, _sigOver(pqKey, _digest(block.chainid, address(other), id, 0)));
    }

    function test_RevertWhen_ReleaseSignatureReplayedAfterRelease() public {
        uint256 id = _createProtected(2);
        _ready(id, 0);
        bytes memory sig = _sig(id, 0);
        _release(id, 0, sig);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.MilestoneAlreadyReleased.selector);
        vault.releaseMilestone(id, 0, sig);
    }

    function test_StateChecksPrecedeProofCheckOnRelease() public {
        uint256 id = _createProtected(2);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.MilestoneNotApproved.selector);
        vault.releaseMilestone(id, 0, "");
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.MilestoneOutOfRange.selector);
        vault.releaseMilestone(id, 2, "");
    }

    // ------------------------------------------------------------ invalid refund proofs

    function test_RevertWhen_RefundWithoutProofOrWrongLength() public {
        uint256 id = _createProtected(2);
        _expectInvalidRefund(id, "");
        _expectInvalidRefund(id, new bytes(7855));
        _expectInvalidRefund(id, new bytes(7857));
        _expectInvalidRefund(id, new bytes(SIG_LEN));
    }

    function test_RevertWhen_RefundSignedForWrongKeyIdOrAction() public {
        uint256 id = _createProtected(3);
        _createProtected(3);
        _expectInvalidRefund(id, _sigFor(pqKeyB, id, 3));
        _expectInvalidRefund(id, _sig(id + 1, 3));
        _expectInvalidRefund(id, _sig(id, 0));
        _expectInvalidRefund(id, _sig(id, 2));
        _expectInvalidRefund(id, _sig(id, 4));
    }

    function test_RevertWhen_RefundSignedForWrongChainOrVault() public {
        uint256 id = _createProtected(3);
        _expectInvalidRefund(id, _sigOver(pqKey, _digest(block.chainid + 1, address(vault), id, 3)));
        _expectInvalidRefund(id, _sigOver(pqKey, _digest(block.chainid, address(0xBEEF), id, 3)));
        bytes memory sig = _sig(id, 3);
        vm.chainId(1234);
        _expectInvalidRefund(id, sig);
    }

    function test_RefundSignatureCannotReleaseAndViceVersa() public {
        uint256 id = _createProtected(3);
        _ready(id, 2);
        // refund action == milestoneCount (3) is not a valid milestone index nor release action
        _expectInvalidRelease(id, 2, _sig(id, 3));
        _expectInvalidRefund(id, _sig(id, 2));
    }

    function test_RefundSignatureCannotBeReplayed() public {
        uint256 id = _createProtected(2);
        bytes memory sig = _sig(id, 2);
        _refund(id, sig);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.EscrowTerminated.selector);
        vault.refundRemaining(id, sig);
    }

    function test_RefundStillBlockedByWorkAlreadySubmittedEvenWithValidProof() public {
        uint256 id = _createProtected(2);
        _submit(id, 0);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.WorkAlreadySubmitted.selector);
        vault.refundRemaining(id, _sig(id, 2));
        // state check precedes proof check, even with a bogus proof
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.WorkAlreadySubmitted.selector);
        vault.refundRemaining(id, "");
    }

    function test_NothingToRefundPrecedesProofCheck() public {
        uint256 id = _createProtected(1);
        _ready(id, 0);
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.NothingToRefund.selector);
        vault.refundRemaining(id, "");
    }

    // ------------------------------------------------------------ contractor never needs a proof

    function test_ContractorReleaseNeedsNoProofOnProtectedEscrow() public {
        uint256 id = _createProtected(2);
        _ready(id, 0);
        vm.recordLogs();
        vm.expectEmit(true, false, true, true, address(vault));
        emit ArcStreamVault.MilestoneReleased(id, 0, contractor, UNIT);
        vm.prank(contractor);
        vault.releaseMilestone(id, 0, "");
        assertEq(usdc.balanceOf(contractor), UNIT);
        assertEq(_countVerified(), 0);
    }

    function test_ContractorRefundWaiverNeedsNoProofOnProtectedEscrow() public {
        uint256 id = _createProtected(3);
        _submit(id, 0); // contractor may waive even submitted work
        uint256 before = usdc.balanceOf(employer);
        vm.prank(contractor);
        vault.refundRemaining(id, "");
        assertEq(usdc.balanceOf(employer), before + 3 * UNIT);
        assertTrue(vault.getEscrow(id).isTerminated);
    }

    function test_ContractorIgnoresGarbageProofOnProtectedEscrow() public {
        uint256 id = _createProtected(2);
        _ready(id, 0);
        vm.prank(contractor);
        vault.releaseMilestone(id, 0, hex"deadbeef");
        vm.prank(contractor);
        vault.refundRemaining(id, hex"01");
        assertTrue(vault.getEscrow(id).isTerminated);
    }

    function test_UnprotectedEscrowIgnoresProofBytes() public {
        uint256 id = _createDefault();
        _approve(id, 0);
        vm.recordLogs();
        vm.prank(employer);
        vault.releaseMilestone(id, 0, hex"deadbeef");
        vm.prank(employer);
        vault.refundRemaining(id, new bytes(7856));
        assertEq(usdc.balanceOf(contractor), M0);
        assertEq(_countVerified(), 0);
    }

    function _countVerified() internal returns (uint256 n) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == ArcStreamVault.QuantumProofVerified.selector) ++n;
        }
    }
}
