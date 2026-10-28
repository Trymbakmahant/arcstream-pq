// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// Test-only Merkle helper for ArcStreamVault's hash-based PQ second factor.
/// leaf(action, secret) = keccak256(bytes.concat(keccak256(abi.encode(chainid, vault, employer, action, secret))))
/// Tree: one leaf per milestone (action = index) plus a refund leaf (action = milestoneCount).
/// Sorted-pair hashing; an odd trailing node is promoted unchanged (OpenZeppelin MerkleProof compatible).
library PQMerkle {
    function secretOf(bytes32 seed, uint256 action) internal pure returns (bytes32) {
        return keccak256(abi.encode("pq-secret", seed, action));
    }

    function leafOf(address vault, address employer, uint256 action, bytes32 secret)
        internal
        view
        returns (bytes32)
    {
        return keccak256(bytes.concat(keccak256(abi.encode(block.chainid, vault, employer, action, secret))));
    }

    /// milestoneCount + 1 leaves, secrets derived from `seed`.
    function leaves(address vault, address employer, bytes32 seed, uint256 milestoneCount)
        internal
        view
        returns (bytes32[] memory l)
    {
        l = new bytes32[](milestoneCount + 1);
        for (uint256 a; a <= milestoneCount; ++a) {
            l[a] = leafOf(vault, employer, a, secretOf(seed, a));
        }
    }

    function hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function _reduce(bytes32[] memory cur, uint256 len) private pure returns (uint256 next) {
        next = (len + 1) / 2;
        for (uint256 i; i < len / 2; ++i) {
            cur[i] = hashPair(cur[2 * i], cur[2 * i + 1]);
        }
        if (len % 2 == 1) cur[len / 2] = cur[len - 1];
    }

    function rootOf(bytes32[] memory l) internal pure returns (bytes32) {
        bytes32[] memory cur = new bytes32[](l.length);
        for (uint256 i; i < l.length; ++i) {
            cur[i] = l[i];
        }
        uint256 len = l.length;
        while (len > 1) {
            len = _reduce(cur, len);
        }
        return cur[0];
    }

    function pathOf(bytes32[] memory l, uint256 index) internal pure returns (bytes32[] memory out) {
        bytes32[] memory cur = new bytes32[](l.length);
        for (uint256 i; i < l.length; ++i) {
            cur[i] = l[i];
        }
        bytes32[] memory tmp = new bytes32[](16);
        uint256 n;
        uint256 len = l.length;
        uint256 idx = index;
        while (len > 1) {
            uint256 sib = idx ^ 1;
            if (sib < len) tmp[n++] = cur[sib];
            len = _reduce(cur, len);
            idx /= 2;
        }
        out = new bytes32[](n);
        for (uint256 i; i < n; ++i) {
            out[i] = tmp[i];
        }
    }

    function root(address vault, address employer, bytes32 seed, uint256 milestoneCount)
        internal
        view
        returns (bytes32)
    {
        return rootOf(leaves(vault, employer, seed, milestoneCount));
    }

    /// abi.encode(bytes32 secret, bytes32[] path) for `action`.
    function proof(address vault, address employer, bytes32 seed, uint256 milestoneCount, uint256 action)
        internal
        view
        returns (bytes memory)
    {
        bytes32[] memory l = leaves(vault, employer, seed, milestoneCount);
        return abi.encode(secretOf(seed, action), pathOf(l, action));
    }
}
