// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ArcStreamVault} from "../ArcStreamVault.sol";
import {BlocklistToken} from "../test-helpers/BlocklistToken.sol";

/// A blocklisted/reverting recipient must only be able to block its own claim.
contract ArcStreamVaultBlocklistTest is Test {
    ArcStreamVault internal vault;
    BlocklistToken internal token;

    address internal employer = makeAddr("employer");
    address internal contractor = makeAddr("contractor");
    address internal newContractor = makeAddr("newContractor");

    uint256 internal constant TOTAL = 600e6;
    uint256 internal constant C_SHARE = 250e6;
    uint256 internal constant E_SHARE = 350e6;
    uint256 internal id;

    function setUp() public {
        token = new BlocklistToken();
        vault = new ArcStreamVault(address(token));
        token.mint(employer, 10_000e6);
        vm.prank(employer);
        token.approve(address(vault), type(uint256).max);

        uint256[] memory a = new uint256[](3);
        a[0] = 100e6;
        a[1] = 200e6;
        a[2] = 300e6;
        string[] memory d = new string[](3);
        d[0] = "a";
        d[1] = "b";
        d[2] = "c";
        vm.prank(employer);
        id = vault.createEscrow(contractor, a, d, bytes32(0));

        vm.prank(employer);
        vault.mutualCancel(id, C_SHARE, E_SHARE);
        vm.prank(contractor);
        vault.mutualCancel(id, C_SHARE, E_SHARE);
        assertTrue(vault.isSettled(id));
    }

    function test_Blocklist_BlockedContractorCannotClaim_EmployerStillCan() public {
        token.setBlocked(contractor, true);

        vm.prank(contractor);
        vm.expectRevert(abi.encodeWithSelector(BlocklistToken.Blocked.selector, contractor));
        vault.claimSettlement(id);
        // failed claim rolled back completely
        assertEq(vault.contractorSettlementOwed(id), C_SHARE);
        assertEq(vault.getEscrow(id).totalReleased, 0);

        uint256 before_ = token.balanceOf(employer);
        vm.prank(employer);
        vault.claimSettlement(id);
        assertEq(token.balanceOf(employer), before_ + E_SHARE);
        assertEq(vault.refundedAmounts(id), E_SHARE);
        assertEq(token.balanceOf(address(vault)), C_SHARE);
    }

    function test_Blocklist_BlockedEmployerCannotClaim_ContractorStillCan() public {
        token.setBlocked(employer, true);

        vm.prank(employer);
        vm.expectRevert(abi.encodeWithSelector(BlocklistToken.Blocked.selector, employer));
        vault.claimSettlement(id);
        assertEq(vault.employerSettlementOwed(id), E_SHARE);
        assertEq(vault.refundedAmounts(id), 0);

        vm.prank(contractor);
        vault.claimSettlement(id);
        assertEq(token.balanceOf(contractor), C_SHARE);
        assertEq(token.balanceOf(address(vault)), E_SHARE);
    }

    function test_Blocklist_UnblockedPartyCanClaimLater() public {
        token.setBlocked(contractor, true);
        vm.prank(contractor);
        vm.expectRevert();
        vault.claimSettlement(id);
        token.setBlocked(contractor, false);
        vm.prank(contractor);
        vault.claimSettlement(id);
        assertEq(token.balanceOf(contractor), C_SHARE);
    }

    function test_Blocklist_BlockedContractorRotatesToCleanWalletAndClaims() public {
        token.setBlocked(contractor, true);
        vm.prank(contractor);
        vault.updateContractor(id, newContractor);
        vm.prank(newContractor);
        vault.claimSettlement(id);
        assertEq(token.balanceOf(newContractor), C_SHARE);
        assertEq(token.balanceOf(contractor), 0);
    }

    function test_Blocklist_BlockedContractorBlocksOnlyOwnClaim_FullDrain() public {
        token.setBlocked(contractor, true);
        vm.prank(employer);
        vault.claimSettlement(id);
        // contractor credit remains safely held, accounted for
        assertEq(token.balanceOf(address(vault)), C_SHARE);
        assertEq(vault.contractorSettlementOwed(id), C_SHARE);
        assertEq(vault.getEscrow(id).totalDeposited - vault.getEscrow(id).totalReleased - vault.refundedAmounts(id), C_SHARE);
    }

    function test_Blocklist_BlockedContractorDoesNotBlockEmployerRefundPath() public {
        // separate escrow, no settlement: blocked contractor cannot block employer refund
        uint256[] memory a = new uint256[](1);
        a[0] = 50e6;
        string[] memory d = new string[](1);
        d[0] = "x";
        vm.prank(employer);
        uint256 id2 = vault.createEscrow(contractor, a, d, bytes32(0));
        token.setBlocked(contractor, true);
        uint256 before_ = token.balanceOf(employer);
        vm.prank(employer);
        vault.refundRemaining(id2, "");
        assertEq(token.balanceOf(employer), before_ + 50e6);
    }
}
