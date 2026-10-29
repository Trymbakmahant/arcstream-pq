// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Test-only stand-in for Arc's native SLH-DSA-SHA2-128s verification precompile
/// (0x1800000000000000000000000000000000000004). Mimics the real length checks and treats a
/// signature as valid iff its first 32 bytes equal keccak256(abi.encodePacked(vk, message)).
contract MockArcPQ {
    function verifySlhDsaSha2128s(bytes calldata vk, bytes calldata message, bytes calldata sig)
        external
        pure
        returns (bool)
    {
        require(vk.length == 32, "Invalid verifying key length");
        require(sig.length == 7856, "Invalid signature length");
        return bytes32(sig[0:32]) == keccak256(abi.encodePacked(vk, message));
    }
}

/// @dev Precompile variant that succeeds with zero bytes of returndata.
contract MockArcPQEmptyReturn {
    fallback() external {
        assembly {
            return(0, 0)
        }
    }
}

/// @dev Precompile variant that returns a single non-1 word (2).
contract MockArcPQWordTwo {
    fallback() external {
        assembly {
            mstore(0, 2)
            return(0, 32)
        }
    }
}

/// @dev Precompile variant that returns a 64-byte blob whose first word is 1.
contract MockArcPQLongReturn {
    fallback() external {
        assembly {
            mstore(0, 1)
            mstore(32, 1)
            return(0, 64)
        }
    }
}

/// @dev Precompile variant that returns only 31 bytes.
contract MockArcPQShortReturn {
    fallback() external {
        assembly {
            mstore(0, 1)
            return(1, 31)
        }
    }
}

/// @dev Precompile variant that always reverts.
contract MockArcPQReverting {
    fallback() external {
        revert("boom");
    }
}

/// @dev Precompile variant that always returns true (word 1) regardless of input.
contract MockArcPQAlwaysTrue {
    fallback() external {
        assembly {
            mstore(0, 1)
            return(0, 32)
        }
    }
}
