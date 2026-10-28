// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Test-only non-standard token: burns a fee from each transfer (receiver gets less)
/// and/or mints a bonus to the receiver (receiver gets more than requested).
contract FeeOnTransferToken is ERC20 {
    uint256 public feeBps;
    uint256 public bonus;

    constructor() ERC20("Fee USDC", "fUSDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function setFeeBps(uint256 bps) external {
        feeBps = bps;
    }

    function setBonus(uint256 b) external {
        bonus = b;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            return;
        }
        uint256 fee = (value * feeBps) / 10_000;
        super._update(from, to, value - fee);
        if (fee > 0) super._update(from, address(0), fee);
        if (bonus > 0) super._update(address(0), to, bonus);
    }
}
