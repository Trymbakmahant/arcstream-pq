// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Test-only hostile token. After a transfer it (a) optionally fires one armed
/// low-level call from the token itself, and (b) calls `onTokenReceived()` on contract
/// recipients (ERC-777-style hook). Neither can revert the transfer.
contract ReentrantToken is ERC20 {
    bool public armed;
    address public trigger;
    address public target;
    bytes public data;
    bool public lastOk;
    bytes public lastRet;
    uint256 public fires;
    bool public hooksEnabled;

    constructor() ERC20("Hostile USDC", "hUSDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function enableHooks(bool on) external {
        hooksEnabled = on;
    }

    /// @dev Fire `target.call(data)` once, right after the next transfer whose receiver is `trigger_`.
    function arm(address trigger_, address target_, bytes calldata data_) external {
        armed = true;
        trigger = trigger_;
        target = target_;
        data = data_;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (armed && to == trigger) {
            armed = false;
            fires++;
            (lastOk, lastRet) = target.call(data);
        }
        if (hooksEnabled && to.code.length > 0) {
            // solhint-disable-next-line avoid-low-level-calls
            to.call(abi.encodeWithSignature("onTokenReceived()"));
        }
    }
}
