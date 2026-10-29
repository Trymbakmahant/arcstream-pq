// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ArcStreamVaultPQBase} from "./ArcStreamVault.PQBase.t.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";

contract ArcStreamVaultPQFuzzTest is ArcStreamVaultPQBase {
    function testFuzz_AnyIndexVerifies(uint256 n, uint256 idx, bytes32 keySeed) public {
        n = bound(n, 1, 50);
        idx = bound(idx, 0, n - 1);
        bytes memory key = abi.encodePacked(keySeed);
        uint256 id = _createN(n, key);
        _ready(id, idx);
        _release(id, idx, _sigFor(key, id, idx));
        assertTrue(vault.getMilestone(id, idx).isReleased);
        assertEq(usdc.balanceOf(contractor), UNIT);
    }

    function testFuzz_RefundVerifies(uint256 n, bytes32 keySeed) public {
        n = bound(n, 1, 50);
        bytes memory key = abi.encodePacked(keySeed);
        uint256 id = _createN(n, key);
        uint256 before = usdc.balanceOf(employer);
        _refund(id, _sigFor(key, id, n));
        assertEq(usdc.balanceOf(employer), before + n * UNIT);
        assertTrue(vault.getEscrow(id).isTerminated);
    }

    function testFuzz_WrongActionFails(uint256 n, uint256 a, uint256 b) public {
        n = bound(n, 2, 50);
        a = bound(a, 0, n - 1);
        b = bound(b, 0, n);
        vm.assume(a != b);
        uint256 id = _createProtected(n);
        _ready(id, a);
        _expectInvalidRelease(id, a, _sig(id, b));
    }

    function testFuzz_WrongEscrowIdFails(uint256 otherId) public {
        uint256 id = _createProtected(2);
        vm.assume(otherId != id);
        _ready(id, 0);
        _expectInvalidRelease(id, 0, _sig(otherId, 0));
        _expectInvalidRefund(id, _sig(otherId, 2));
    }

    function testFuzz_WrongKeyFails(bytes32 seedA, bytes32 seedB) public {
        vm.assume(seedA != seedB);
        bytes memory keyA = abi.encodePacked(seedA);
        uint256 id = _createN(2, keyA);
        _ready(id, 0);
        _expectInvalidRelease(id, 0, _sigFor(abi.encodePacked(seedB), id, 0));
        _expectInvalidRefund(id, _sigFor(abi.encodePacked(seedB), id, 2));
    }

    function testFuzz_ChainIdBinding(uint64 signedChain, uint64 liveChain) public {
        vm.assume(signedChain != liveChain);
        vm.assume(liveChain != 0);
        uint256 id = _createProtected(2);
        _ready(id, 0);
        vm.chainId(liveChain);
        _expectInvalidRelease(id, 0, _sigOver(pqKey, _digest(signedChain, address(vault), id, 0)));
        _release(id, 0, _sig(id, 0));
        assertTrue(vault.getMilestone(id, 0).isReleased);
    }

    function testFuzz_MutatedSignatureHeadFails(uint256 n, uint256 idx, uint256 pos, uint8 xorMask) public {
        n = bound(n, 1, 20);
        idx = bound(idx, 0, n - 1);
        pos = bound(pos, 0, 31);
        xorMask = uint8(bound(xorMask, 1, 255));
        uint256 id = _createProtected(n);
        _ready(id, idx);
        bytes memory sig = _sig(id, idx);
        sig[pos] = bytes1(uint8(sig[pos]) ^ xorMask);
        _expectInvalidRelease(id, idx, sig);
    }

    function testFuzz_WrongLengthSignatureFails(uint256 len) public {
        len = bound(len, 0, 9000);
        vm.assume(len != SIG_LEN);
        uint256 id = _createProtected(2);
        _ready(id, 0);
        bytes memory sig = _sig(id, 0);
        bytes memory wrong = new bytes(len);
        for (uint256 i; i < len && i < 32; ++i) {
            wrong[i] = sig[i];
        }
        _expectInvalidRelease(id, 0, wrong);
        _expectInvalidRefund(id, wrong);
    }

    function testFuzz_RandomBytesNeverAuthorize(bytes calldata junk) public {
        uint256 id = _createProtected(2);
        _ready(id, 0);
        _expectInvalidRelease(id, 0, junk);
        _expectInvalidRefund(id, junk);
    }

    function testFuzz_PublicKeyLength(uint256 len) public {
        len = bound(len, 1, 200);
        vm.assume(len != 32);
        uint256[] memory a = new uint256[](1);
        a[0] = UNIT;
        vm.prank(employer);
        vm.expectRevert(ArcStreamVault.InvalidPQPublicKey.selector);
        vault.createEscrow(contractor, a, _descs(1), new bytes(len));
    }

    function testFuzz_AnyThirtyTwoByteKeyAccepted(bytes32 keySeed) public {
        uint256 id = _createN(1, abi.encodePacked(keySeed));
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        assertTrue(e.isPQProtected);
        assertEq(e.pqCommitment, keccak256(abi.encodePacked(keySeed)));
    }

    function testFuzz_ContractorAndUnprotectedIgnoreProofBytes(uint256 n, bytes calldata junk) public {
        n = bound(n, 1, 10);
        uint256 id = _createProtected(n);
        _ready(id, 0);
        vm.prank(contractor);
        vault.releaseMilestone(id, 0, junk);
        assertEq(usdc.balanceOf(contractor), UNIT);

        uint256 id2 = _createN(n, "");
        _ready(id2, 0);
        vm.prank(employer);
        vault.releaseMilestone(id2, 0, junk);
        assertEq(usdc.balanceOf(contractor), 2 * UNIT);
    }
}
