// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Test-only malicious account. Acts as employer/contractor via `exec`, and when a hooked
/// token pays it, replays a configured list of calls into the vault, recording each outcome.
contract ReentrancyAttacker {
    struct Attempt {
        address target;
        bytes data;
    }

    Attempt[] internal attempts;
    bool[] public oks;
    bytes4[] public selectors;
    uint256 public hookCalls;
    bool internal inHook;

    function addAttempt(address target, bytes calldata data) external {
        attempts.push(Attempt(target, data));
    }

    function attemptCount() external view returns (uint256) {
        return attempts.length;
    }

    function resultCount() external view returns (uint256) {
        return oks.length;
    }

    function exec(address target, bytes calldata data) external returns (bytes memory ret) {
        bool ok;
        (ok, ret) = target.call(data);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(ret, 32), mload(ret))
            }
        }
    }

    function onTokenReceived() external {
        hookCalls++;
        if (inHook) return;
        inHook = true;
        for (uint256 i; i < attempts.length; ++i) {
            (bool ok, bytes memory ret) = attempts[i].target.call(attempts[i].data);
            oks.push(ok);
            selectors.push(ret.length >= 4 ? bytes4(ret) : bytes4(0));
        }
        inHook = false;
    }
}
