// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ArcStreamVaultPQBase} from "./ArcStreamVault.PQBase.t.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";
import {PQMerkle as PQLib} from "../test-helpers/PQMerkle.sol";

/// Protected-escrow release / refund behaviour for the hash-based second factor.
contract ArcStreamVaultPQTest is ArcStreamVaultPQBase {
    uint256 internal constant N = 3;

    function _protected() internal returns (uint256 id, bytes32 root) {
        root = _rootFor(employer, SEED, N);
        id = _createN(N, root);
    }

    // ------------------------------------------------------------ release: success

    function test_EmployerReleaseWithValidProof() public {
        (uint256 id,) = _protected();
        _ready(id, 0);
        _release(id, 0, _p(N, 0));
        assertEq(usdc.balanceOf(contractor), UNIT);
        assertTrue(vault.getMilestone(id, 0).isReleased);
        assertEq(vault.getEscrow(id).totalReleased, UNIT);
    }

    function test_ReleaseEmitsQuantumProofVerifiedBeforePayout() public {
        (uint256 id, bytes32 root) = _protected();
        _ready(id, 1);
        bytes memory proof = _p(N, 1);

        vm.expectEmit(true, false, false, true, address(vault));
        emit ArcStreamVault.QuantumProofVerified(id, 1, root);
        vm.expectEmit(true, true, false, true, address(vault));
        emit ArcStreamVault.MilestoneReleased(id, 1, contractor, UNIT);
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Transfer(address(vault), contractor, UNIT);
        _release(id, 1, proof);
    }

    function test_VerifiedEventPrecedesTokenTransferInLogOrder() public {
        (uint256 id,) = _protected();
        _ready(id, 0);
        bytes memory proof = _p(N, 0);
        vm.recordLogs();
        _release(id, 0, proof);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        int256 verifiedAt = -1;
        int256 transferAt = -1;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(vault) && logs[i].topics[0] == ArcStreamVault.QuantumProofVerified.selector) {
                verifiedAt = int256(i);
            }
            if (logs[i].emitter == address(usdc) && logs[i].topics[0] == IERC20.Transfer.selector) {
                transferAt = int256(i);
            }
        }
        assertGe(verifiedAt, 0, "verified event missing");
        assertGe(transferAt, 0, "transfer missing");
        assertLt(verifiedAt, transferAt, "proof event must precede payout");
    }

    function test_ReleaseOrderIsFreeAcrossMilestones() public {
        (uint256 id,) = _protected();
        _ready(id, 2);
        _ready(id, 0);
        _release(id, 2, _p(N, 2));
        _release(id, 0, _p(N, 0));
        assertEq(usdc.balanceOf(contractor), 2 * UNIT);
    }

    // ------------------------------------------------------------ release: invalid proofs

    function test_RevertWhen_ReleaseWithEmptyProof() public {
        (uint256 id,) = _protected();
        _ready(id, 0);
        _expectInvalidRelease(id, 0, "");
    }

    function test_RevertWhen_ReleaseWithShortProof() public {
        (uint256 id,) = _protected();
        _ready(id, 0);
        uint256[5] memory lens = [uint256(1), 32, 64, 95, 0];
        for (uint256 i; i < lens.length; ++i) {
            _expectInvalidRelease(id, 0, new bytes(lens[i]));
        }
    }

    function test_RevertWhen_ReleaseWithEmptyPathProof() public {
        (uint256 id,) = _protected();
        _ready(id, 0);
        // exactly 96 bytes: valid ABI shape, secret + empty path
        bytes memory proof = abi.encode(PQ_secret(0), new bytes32[](0));
        assertEq(proof.length, 96);
        _expectInvalidRelease(id, 0, proof);
    }

    function PQ_secret(uint256 action) internal pure returns (bytes32) {
        return PQLib.secretOf(SEED, action);
    }

    function test_RevertWhen_ReleaseWithWrongSecret() public {
        (uint256 id,) = _protected();
        _ready(id, 0);
        (, bytes32[] memory path) = abi.decode(_p(N, 0), (bytes32, bytes32[]));
        _expectInvalidRelease(id, 0, abi.encode(keccak256("wrong"), path));
    }

    function test_RevertWhen_ProofForOtherIndexUsed() public {
        (uint256 id,) = _protected();
        _ready(id, 0);
        _ready(id, 1);
        // milestone 1's proof on milestone 0
        _expectInvalidRelease(id, 0, _p(N, 1));
        // and the reverse
        _expectInvalidRelease(id, 1, _p(N, 0));
    }

    function test_SecretCannotAuthorizeDifferentAction() public {
        (uint256 id,) = _protected();
        _ready(id, 0);
        _ready(id, 1);
        // secret of action 1 paired with the path of action 0 (and vice versa) fails
        (, bytes32[] memory path0) = abi.decode(_p(N, 0), (bytes32, bytes32[]));
        (bytes32 secret1, bytes32[] memory path1) = abi.decode(_p(N, 1), (bytes32, bytes32[]));
        _expectInvalidRelease(id, 0, abi.encode(secret1, path0));
        _expectInvalidRelease(id, 0, abi.encode(secret1, path1));
        // the secret revealed for milestone 1 is valid ONLY for milestone 1
        _release(id, 1, abi.encode(secret1, path1));
        _expectInvalidRelease(id, 0, abi.encode(secret1, path1));
    }

    function test_RevertWhen_ProofFromAnotherEscrowOfSameEmployer() public {
        (uint256 idA,) = _protected();
        uint256 idB = _createN(N, _rootFor(employer, SEED_B, N));
        _ready(idA, 0);
        _ready(idB, 0);
        _expectInvalidRelease(idB, 0, _p(N, 0)); // A's proof on B
        _expectInvalidRelease(idA, 0, _proofFor(employer, SEED_B, N, 0)); // B's proof on A
        // each still releases with its own proof
        _release(idA, 0, _p(N, 0));
        _release(idB, 0, _proofFor(employer, SEED_B, N, 0));
    }

    function test_RevertWhen_ProofBuiltForAnotherEmployer() public {
        (uint256 id,) = _protected();
        _ready(id, 0);
        // same seed but leaves bound to employer2 -> not a member of employer's tree
        _expectInvalidRelease(id, 0, _proofFor(employer2, SEED, N, 0));
    }

    function test_RevertWhen_ProofForWrongVaultOrChain() public {
        (uint256 id,) = _protected();
        _ready(id, 0);
        // leaf built against a different vault address
        bytes32[] memory l = new bytes32[](N + 1);
        for (uint256 a; a <= N; ++a) {
            l[a] = keccak256(
                bytes.concat(keccak256(abi.encode(block.chainid, address(0xBEEF), employer, a, PQ_secret(a))))
            );
        }
        bytes memory foreign = abi.encode(PQ_secret(0), _pathOf(l, 0));
        _expectInvalidRelease(id, 0, foreign);
        // leaf built for a different chainid
        for (uint256 a; a <= N; ++a) {
            l[a] = keccak256(
                bytes.concat(keccak256(abi.encode(block.chainid + 1, address(vault), employer, a, PQ_secret(a))))
            );
        }
        _expectInvalidRelease(id, 0, abi.encode(PQ_secret(0), _pathOf(l, 0)));
    }

    function _pathOf(bytes32[] memory l, uint256 idx) internal pure returns (bytes32[] memory) {
        return PQLib.pathOf(l, idx);
    }

    function test_RevertWhen_PathTooLong() public {
        (uint256 id,) = _protected();
        _ready(id, 0);
        uint256 maxDepth = vault.MAX_PQ_PROOF_DEPTH();
        assertEq(maxDepth, 8);
        // valid secret, 9 siblings -> rejected by the depth cap
        _expectInvalidRelease(id, 0, abi.encode(PQ_secret(0), new bytes32[](maxDepth + 1)));
        // valid path with extra junk sibling appended also fails
        (bytes32 s, bytes32[] memory path) = abi.decode(_p(N, 0), (bytes32, bytes32[]));
        bytes32[] memory longer = new bytes32[](path.length + 1);
        for (uint256 i; i < path.length; ++i) {
            longer[i] = path[i];
        }
        longer[path.length] = keccak256("junk");
        _expectInvalidRelease(id, 0, abi.encode(s, longer));
    }

    function test_RevertWhen_PathTampered() public {
        (uint256 id,) = _protected();
        _ready(id, 0);
        (bytes32 s, bytes32[] memory path) = abi.decode(_p(N, 0), (bytes32, bytes32[]));
        assertGt(path.length, 0);
        for (uint256 k; k < path.length; ++k) {
            (, bytes32[] memory fresh) = abi.decode(_p(N, 0), (bytes32, bytes32[]));
            _expectInvalidRelease(id, 0, _tamperPath(s, fresh, k));
        }
        // dropping the last sibling also fails
        bytes32[] memory shorter = new bytes32[](path.length - 1);
        for (uint256 i; i < shorter.length; ++i) {
            shorter[i] = path[i];
        }
        _expectInvalidRelease(id, 0, abi.encode(s, shorter));
    }

    function test_RevertWhen_ApprovalMissingTakesPrecedenceOverProof() public {
        (uint256 id,) = _protected();
        // not submitted/approved: state check fires before the proof check
        vm.expectRevert(ArcStreamVault.MilestoneNotApproved.selector);
        vm.prank(employer);
        vault.releaseMilestone(id, 0, "");
    }

    // ------------------------------------------------------------ refund

    function test_EmployerRefundRequiresRefundLeafProof() public {
        (uint256 id,) = _protected();
        _expectInvalidRefund(id, "");
        _expectInvalidRefund(id, new bytes(95));
        _expectInvalidRefund(id, _p(N, 0));
        _expectInvalidRefund(id, _p(N, 1));
        _expectInvalidRefund(id, _p(N, 2));
    }

    function test_ReleaseLeafProofDoesNotAuthorizeRefund() public {
        (uint256 id,) = _protected();
        _ready(id, 0);
        // release proof works for release...
        _release(id, 0, _p(N, 0));
        // ...but cannot be replayed as a refund authorization
        _expectInvalidRefund(id, _p(N, 0));
    }

    function test_RefundLeafProofCannotReleaseAMilestone() public {
        (uint256 id,) = _protected();
        _ready(id, 0);
        _expectInvalidRelease(id, 0, _p(N, N));
    }

    function test_EmployerRefundWithValidProof() public {
        (uint256 id, bytes32 root) = _protected();
        uint256 before = usdc.balanceOf(employer);
        bytes memory proof = _p(N, N);

        vm.expectEmit(true, false, false, true, address(vault));
        emit ArcStreamVault.QuantumProofVerified(id, N, root);
        vm.expectEmit(true, true, false, true, address(vault));
        emit ArcStreamVault.EscrowRefunded(id, employer, N * UNIT);
        _refund(id, proof);

        assertEq(usdc.balanceOf(employer), before + N * UNIT);
        assertTrue(vault.getEscrow(id).isTerminated);
        assertEq(vault.refundedAmounts(id), N * UNIT);
    }

    function test_RefundProofCannotBeReplayed() public {
        (uint256 id,) = _protected();
        bytes memory proof = _p(N, N);
        _refund(id, proof);
        vm.expectRevert(ArcStreamVault.EscrowTerminated.selector);
        vm.prank(employer);
        vault.refundRemaining(id, proof);
    }

    function test_RefundKeepsApprovedMilestoneReleasableWithProof() public {
        (uint256 id,) = _protected();
        _ready(id, 0);
        _refund(id, _p(N, N));
        assertEq(vault.refundedAmounts(id), (N - 1) * UNIT);
        // approved funds stay claimable; employer release still needs milestone proof
        _expectInvalidRelease(id, 0, _p(N, N));
        _release(id, 0, _p(N, 0));
        assertEq(usdc.balanceOf(contractor), UNIT);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_ProofCheckedAfterStateChecks() public {
        (uint256 id,) = _protected();
        _ready(id, 0); // not submitted-unapproved, so refund is state-valid
        vm.prank(contractor);
        vault.submitMilestoneWork(id, 1, PROOF);
        // submitted-unapproved work blocks employer refund before any proof is looked at
        vm.expectRevert(ArcStreamVault.WorkAlreadySubmitted.selector);
        vm.prank(employer);
        vault.refundRemaining(id, "");
    }

    // ------------------------------------------------------------ contractor & unprotected

    function test_ContractorReleaseNeedsNoProof() public {
        (uint256 id,) = _protected();
        _ready(id, 0);
        _ready(id, 1);
        vm.recordLogs();
        vm.prank(contractor);
        vault.releaseMilestone(id, 0, "");
        assertEq(_countVerified(), 0, "no proof event for contractor");
        // garbage proof bytes are ignored for the contractor
        vm.prank(contractor);
        vault.releaseMilestone(id, 1, hex"deadbeef");
        assertEq(usdc.balanceOf(contractor), 2 * UNIT);
    }

    function test_ContractorRefundWaiverNeedsNoProof() public {
        (uint256 id,) = _protected();
        vm.recordLogs();
        vm.prank(contractor);
        vault.refundRemaining(id, "");
        assertEq(_countVerified(), 0);
        assertTrue(vault.getEscrow(id).isTerminated);
        assertEq(vault.refundedAmounts(id), N * UNIT);
    }

    function test_ContractorRefundIgnoresGarbageProof() public {
        (uint256 id,) = _protected();
        vm.prank(contractor);
        vault.refundRemaining(id, hex"01");
        assertTrue(vault.getEscrow(id).isTerminated);
    }

    function test_UnprotectedEscrowIgnoresProofBytes() public {
        uint256 id = _createN(N, bytes32(0));
        _ready(id, 0);
        vm.recordLogs();
        _release(id, 0, hex"123456");
        assertEq(_countVerified(), 0);
        assertEq(usdc.balanceOf(contractor), UNIT);
        _refund(id, new bytes(500));
        assertEq(_countVerified(), 0);
        assertTrue(vault.getEscrow(id).isTerminated);
    }

    function test_OutsiderStillUnauthorizedWithValidProof() public {
        (uint256 id,) = _protected();
        _ready(id, 0);
        bytes memory proof = _p(N, 0);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vm.prank(outsider);
        vault.releaseMilestone(id, 0, proof);
        vm.expectRevert(ArcStreamVault.Unauthorized.selector);
        vm.prank(outsider);
        vault.refundRemaining(id, _p(N, N));
    }

    function _countVerified() internal returns (uint256 n) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == ArcStreamVault.QuantumProofVerified.selector) n++;
        }
    }
}
