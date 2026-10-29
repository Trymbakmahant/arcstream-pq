// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";
import {MockERC20} from "../test-helpers/MockERC20.sol";
import {MockArcPQ} from "../test-helpers/MockArcPQ.sol";

abstract contract ArcStreamVaultTestBase is Test {
    ArcStreamVault internal vault;
    MockERC20 internal usdc;

    address internal employer = makeAddr("employer");
    address internal contractor = makeAddr("contractor");
    address internal newContractor = makeAddr("newContractor");
    address internal outsider = makeAddr("outsider");

    uint256 internal constant M0 = 100e6;
    uint256 internal constant M1 = 200e6;
    uint256 internal constant M2 = 300e6;
    uint256 internal constant TOTAL = 600e6;
    uint256 internal constant EMPLOYER_FUNDS = 1_000_000e6;
    string internal constant PROOF = "ipfs://proof";

    address internal constant PQ_PRECOMPILE = 0x1800000000000000000000000000000000000004;
    bytes32 internal constant PQ_DOMAIN_ID = keccak256("ArcStreamVault.PQ.v1");
    uint256 internal constant SIG_LEN = 7856;
    bytes internal pqKey = abi.encodePacked(keccak256("pq-public-key-A"));
    bytes internal pqKeyB = abi.encodePacked(keccak256("pq-public-key-B"));

    function setUp() public virtual {
        vm.etch(PQ_PRECOMPILE, address(new MockArcPQ()).code);
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        vault = new ArcStreamVault(address(usdc));
        usdc.mint(employer, EMPLOYER_FUNDS);
        vm.prank(employer);
        usdc.approve(address(vault), type(uint256).max);
    }

    function _three() internal pure returns (uint256[] memory a) {
        a = new uint256[](3);
        a[0] = M0;
        a[1] = M1;
        a[2] = M2;
    }

    function _descs(uint256 n) internal pure returns (string[] memory d) {
        d = new string[](n);
        for (uint256 i; i < n; ++i) {
            d[i] = "milestone";
        }
    }

    function _createDefault() internal returns (uint256 id) {
        uint256[] memory a = _three();
        string[] memory d = _descs(3);
        vm.prank(employer);
        id = vault.createEscrow(contractor, a, d, "", 0);
    }

    // ------------------------------------------------------------ PQ helpers

    /// Employer creates an escrow of `n` milestones (amount 10e6 each) with `key` as PQ public key.
    function _createN(uint256 n, bytes memory key) internal returns (uint256 id) {
        uint256[] memory a = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            a[i] = 10e6;
        }
        string[] memory d = _descs(n);
        vm.prank(employer);
        id = vault.createEscrow(contractor, a, d, key, 0);
    }

    /// Employer-created protected escrow with `n` milestones under `pqKey`.
    function _createProtected(uint256 n) internal returns (uint256 id) {
        id = _createN(n, pqKey);
    }

    /// Independently recomputed domain-bound digest (does not call vault.pqSigningMessage).
    function _digest(uint256 chainId, address vaultAddr, uint256 id, uint256 action) internal pure returns (bytes32) {
        return keccak256(abi.encode(PQ_DOMAIN_ID, chainId, vaultAddr, id, action));
    }

    /// Mock-valid 7856-byte signature of `key` over `digest` (hash + zero padding).
    function _sigOver(bytes memory key, bytes32 digest) internal pure returns (bytes memory) {
        return abi.encodePacked(keccak256(abi.encodePacked(key, abi.encodePacked(digest))), new bytes(SIG_LEN - 32));
    }

    /// Valid signature by `key` for (escrow, action) on the live vault and chain.
    function _sigFor(bytes memory key, uint256 id, uint256 action) internal view returns (bytes memory) {
        return _sigOver(key, _digest(block.chainid, address(vault), id, action));
    }

    /// Valid signature by the default key.
    function _sig(uint256 id, uint256 action) internal view returns (bytes memory) {
        return _sigFor(pqKey, id, action);
    }

    /// Employer release with explicit proof bytes.
    function _release(uint256 id, uint256 i, bytes memory proof) internal {
        vm.prank(employer);
        vault.releaseMilestone(id, i, proof);
    }

    /// Employer refund with explicit proof bytes.
    function _refund(uint256 id, bytes memory proof) internal {
        vm.prank(employer);
        vault.refundRemaining(id, proof);
    }

    /// Current contractor submits work proof for milestone `i`.
    function _submit(uint256 id, uint256 i) internal {
        address c = vault.getEscrow(id).contractor;
        vm.prank(c);
        vault.submitMilestoneWork(id, i, PROOF);
    }

    /// Employer approves an already-submitted milestone.
    function _approveOnly(uint256 id, uint256 i) internal {
        vm.prank(employer);
        vault.approveMilestone(id, i);
    }

    /// Submit (by current contractor) then approve (by employer).
    function _approve(uint256 id, uint256 i) internal {
        _submit(id, i);
        _approveOnly(id, i);
    }

    function _release(uint256 id, uint256 i) internal {
        vm.prank(employer);
        vault.releaseMilestone(id, i, "");
    }

    function _refund(uint256 id) internal {
        vm.prank(employer);
        vault.refundRemaining(id, "");
    }

    uint256 internal constant DEF_PERIOD = 7 days;
    uint256 internal constant MIN_PERIOD = 1 days;
    uint256 internal constant MAX_PERIOD = 30 days;

    /// Three-milestone escrow (M0/M1/M2) with an explicit inspection period and optional PQ key.
    function _createPeriod(uint256 period, bytes memory key) internal returns (uint256 id) {
        uint256[] memory a = _three();
        string[] memory d = _descs(3);
        vm.prank(employer);
        id = vault.createEscrow(contractor, a, d, key, period);
    }

    /// Current contractor claims an uncontested milestone.
    function _claimU(uint256 id, uint256 i) internal {
        address c = vault.getEscrow(id).contractor;
        vm.prank(c);
        vault.claimUncontestedMilestone(id, i);
    }

    function _remaining(uint256 id) internal view returns (uint256) {
        ArcStreamVault.EscrowAgreement memory e = vault.getEscrow(id);
        return e.totalDeposited - e.totalReleased - vault.refundedAmounts(id);
    }

    /// Employer proposes, current contractor accepts the identical split -> settled.
    function _settle(uint256 id, uint256 cShare, uint256 eShare) internal {
        address c = vault.getEscrow(id).contractor;
        vm.prank(employer);
        vault.mutualCancel(id, cShare, eShare);
        vm.prank(c);
        vault.mutualCancel(id, cShare, eShare);
    }
}
