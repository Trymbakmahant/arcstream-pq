// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ArcStreamVault} from "../ArcStreamVault.sol";
import {ArcStreamVaultTestBase} from "./ArcStreamVault.Base.t.sol";

/// getMilestones, getUserEscrows, getUserEscrowCount, getUserEscrowsPage.
contract ArcStreamVaultViewsTest is ArcStreamVaultTestBase {
    address internal employer2 = makeAddr("employer2");

    function _createOne(address emp, address con) internal returns (uint256 id) {
        uint256[] memory a = new uint256[](1);
        a[0] = 1;
        string[] memory d = _descs(1);
        if (usdc.balanceOf(emp) == 0) usdc.mint(emp, 1_000e6);
        vm.startPrank(emp);
        usdc.approve(address(vault), type(uint256).max);
        id = vault.createEscrow(con, a, d, bytes32(0));
        vm.stopPrank();
    }

    function _assertIds(uint256[] memory got, uint256[] memory want) internal pure {
        require(got.length == want.length, "length mismatch");
        for (uint256 i; i < got.length; ++i) {
            require(got[i] == want[i], "id mismatch");
        }
    }

    function _ids(uint256 a) internal pure returns (uint256[] memory r) {
        r = new uint256[](1);
        r[0] = a;
    }

    function _ids(uint256 a, uint256 b) internal pure returns (uint256[] memory r) {
        r = new uint256[](2);
        r[0] = a;
        r[1] = b;
    }

    function _ids(uint256 a, uint256 b, uint256 c) internal pure returns (uint256[] memory r) {
        r = new uint256[](3);
        r[0] = a;
        r[1] = b;
        r[2] = c;
    }

    // ------------------------------------------------------- getMilestones
    function test_GetMilestones_ReturnsAllInOrder() public {
        uint256[] memory a = _three();
        string[] memory d = new string[](3);
        d[0] = "x";
        d[1] = "y";
        d[2] = "z";
        vm.prank(employer);
        uint256 id = vault.createEscrow(contractor, a, d, bytes32(0));

        ArcStreamVault.Milestone[] memory ms = vault.getMilestones(id);
        assertEq(ms.length, 3);
        assertEq(ms[0].amount, M0);
        assertEq(ms[1].amount, M1);
        assertEq(ms[2].amount, M2);
        assertEq(ms[0].description, "x");
        assertEq(ms[2].description, "z");
        for (uint256 i; i < 3; ++i) {
            assertFalse(ms[i].isApproved);
            assertFalse(ms[i].isReleased);
            assertFalse(ms[i].isWorkSubmitted);
            assertEq(ms[i].workProofHash, "");
        }
    }

    function test_GetMilestones_ReflectsLifecycle() public {
        uint256 id = _createDefault();
        _submit(id, 0);
        _approve(id, 1);
        _release(id, 1);
        ArcStreamVault.Milestone[] memory ms = vault.getMilestones(id);
        assertTrue(ms[0].isWorkSubmitted);
        assertFalse(ms[0].isApproved);
        assertEq(ms[0].workProofHash, PROOF);
        assertTrue(ms[1].isApproved);
        assertTrue(ms[1].isReleased);
        assertFalse(ms[2].isWorkSubmitted);
    }

    function test_GetMilestones_MatchesGetMilestone() public {
        uint256 id = _createDefault();
        _submit(id, 2);
        ArcStreamVault.Milestone[] memory ms = vault.getMilestones(id);
        for (uint256 i; i < 3; ++i) {
            ArcStreamVault.Milestone memory m = vault.getMilestone(id, i);
            assertEq(ms[i].amount, m.amount);
            assertEq(ms[i].workProofHash, m.workProofHash);
            assertEq(ms[i].isWorkSubmitted, m.isWorkSubmitted);
        }
    }

    function test_GetMilestones_MaxCount() public {
        uint256[] memory a = new uint256[](50);
        for (uint256 i; i < 50; ++i) {
            a[i] = 1e6;
        }
        string[] memory d = _descs(50);
        vm.prank(employer);
        uint256 id = vault.createEscrow(contractor, a, d, bytes32(0));
        assertEq(vault.getMilestones(id).length, 50);
    }

    function test_Revert_GetMilestones_NotFound() public {
        vm.expectRevert(ArcStreamVault.EscrowNotFound.selector);
        vault.getMilestones(1);
    }

    // ------------------------------------------------------ getUserEscrows
    function test_GetUserEscrows_EmployerAndContractorInIndexOrder() public {
        uint256 e1 = _createOne(employer, contractor);
        uint256 e2 = _createOne(employer2, contractor);
        uint256 e3 = _createOne(employer, outsider);
        _assertIds(vault.getUserEscrows(employer), _ids(e1, e3));
        _assertIds(vault.getUserEscrows(employer2), _ids(e2));
        _assertIds(vault.getUserEscrows(contractor), _ids(e1, e2));
        _assertIds(vault.getUserEscrows(outsider), _ids(e3));
    }

    function test_GetUserEscrows_UnknownUserEmpty() public {
        _createOne(employer, contractor);
        assertEq(vault.getUserEscrows(makeAddr("nobody")).length, 0);
        assertEq(vault.getUserEscrowCount(makeAddr("nobody")), 0);
    }

    function test_GetUserEscrows_RotatedOutContractorExcluded() public {
        uint256 e1 = _createOne(employer, contractor);
        uint256 e2 = _createOne(employer, contractor);
        vm.prank(contractor);
        vault.updateContractor(e1, newContractor);

        _assertIds(vault.getUserEscrows(contractor), _ids(e2));
        _assertIds(vault.getUserEscrows(newContractor), _ids(e1));
        // employer unaffected
        _assertIds(vault.getUserEscrows(employer), _ids(e1, e2));
        // historical index still counts the rotated-out entry
        assertEq(vault.getUserEscrowCount(contractor), 2);
        assertEq(vault.getUserEscrowCount(newContractor), 1);
    }

    function test_GetUserEscrows_RotationRoundTripNoDuplicates() public {
        uint256 e1 = _createOne(employer, contractor); // A = contractor, B = newContractor
        vm.prank(contractor);
        vault.updateContractor(e1, newContractor); // A -> B
        vm.prank(newContractor);
        vault.updateContractor(e1, contractor); // B -> A

        _assertIds(vault.getUserEscrows(contractor), _ids(e1));
        assertEq(vault.getUserEscrowCount(contractor), 1, "A indexed once");
        assertEq(vault.getUserEscrows(newContractor).length, 0);
        assertEq(vault.getUserEscrowCount(newContractor), 1, "B keeps historical entry");
    }

    function test_GetUserEscrows_RotationCanReorderResults() public {
        uint256 e1 = _createOne(employer, outsider);
        uint256 e2 = _createOne(employer, newContractor);
        // outsider (contractor of e1) hands e1 to newContractor: newContractor index = [e2, e1]
        vm.prank(outsider);
        vault.updateContractor(e1, newContractor);
        _assertIds(vault.getUserEscrows(newContractor), _ids(e2, e1));
    }

    function test_GetUserEscrows_WorksAfterSettlementAndTermination() public {
        uint256 e1 = _createDefault();
        _refund(e1);
        _assertIds(vault.getUserEscrows(employer), _ids(e1));
        _assertIds(vault.getUserEscrows(contractor), _ids(e1));
    }

    // ------------------------------------------------- getUserEscrowsPage
    function test_Page_BasicSlices() public {
        uint256 e1 = _createOne(employer, contractor);
        uint256 e2 = _createOne(employer, contractor);
        uint256 e3 = _createOne(employer, contractor);

        (uint256[] memory ids, uint256 next) = vault.getUserEscrowsPage(employer, 0, 2);
        _assertIds(ids, _ids(e1, e2));
        assertEq(next, 2);
        (ids, next) = vault.getUserEscrowsPage(employer, next, 2);
        _assertIds(ids, _ids(e3));
        assertEq(next, 3, "nextStart equals index length when finished");
    }

    function test_Page_ZeroLimitScansNothing() public {
        _createOne(employer, contractor);
        (uint256[] memory ids, uint256 next) = vault.getUserEscrowsPage(employer, 0, 0);
        assertEq(ids.length, 0);
        assertEq(next, 0);
    }

    function test_Page_StartBeyondEndClampsToLength() public {
        _createOne(employer, contractor);
        _createOne(employer, contractor);
        (uint256[] memory ids, uint256 next) = vault.getUserEscrowsPage(employer, 999, 10);
        assertEq(ids.length, 0);
        assertEq(next, 2);
    }

    function test_Page_UnknownUser() public view {
        (uint256[] memory ids, uint256 next) = vault.getUserEscrowsPage(outsider, 0, 10);
        assertEq(ids.length, 0);
        assertEq(next, 0);
    }

    function test_Page_LimitClampedToMaxPageSize() public {
        assertEq(vault.MAX_PAGE_SIZE(), 100);
        for (uint256 i; i < 105; ++i) {
            _createOne(employer, contractor);
        }
        (uint256[] memory ids, uint256 next) = vault.getUserEscrowsPage(employer, 0, type(uint256).max);
        assertEq(ids.length, 100, "scans at most MAX_PAGE_SIZE");
        assertEq(next, 100);
        assertEq(ids[0], 1);
        assertEq(ids[99], 100);

        (ids, next) = vault.getUserEscrowsPage(employer, next, type(uint256).max);
        assertEq(ids.length, 5);
        assertEq(next, 105);
        assertEq(ids[0], 101);
        assertEq(vault.getUserEscrows(employer).length, 105);
        assertEq(vault.getUserEscrowCount(employer), 105);
    }

    function test_Page_FilteredPageCanBeEmptyBeforeEnd() public {
        uint256 e1 = _createOne(employer, contractor);
        uint256 e2 = _createOne(employer, contractor);
        uint256 e3 = _createOne(employer2, contractor);
        // contractor index: [e1, e2, e3]; rotate e1 & e2 away
        vm.startPrank(contractor);
        vault.updateContractor(e1, newContractor);
        vault.updateContractor(e2, newContractor);
        vm.stopPrank();

        (uint256[] memory ids, uint256 next) = vault.getUserEscrowsPage(contractor, 0, 2);
        assertEq(ids.length, 0, "page filtered empty");
        assertEq(next, 2, "but index not finished");
        (ids, next) = vault.getUserEscrowsPage(contractor, next, 2);
        _assertIds(ids, _ids(e3));
        assertEq(next, 3);
    }

    function testFuzz_Page_ConcatenationEqualsFullList(uint8 nRaw, uint8 pageRaw) public {
        uint256 n = bound(nRaw, 0, 30);
        uint256 pageSize = bound(pageRaw, 1, 7);
        for (uint256 i; i < n; ++i) {
            _createOne(i % 2 == 0 ? employer : employer2, contractor);
        }
        uint256[] memory full = vault.getUserEscrows(contractor);
        assertEq(full.length, n);

        uint256 pos;
        uint256 next;
        uint256 guard;
        do {
            (uint256[] memory ids, uint256 nxt) = vault.getUserEscrowsPage(contractor, next, pageSize);
            for (uint256 i; i < ids.length; ++i) {
                assertEq(ids[i], full[pos++]);
            }
            if (nxt == next) break;
            next = nxt;
            ++guard;
        } while (next < vault.getUserEscrowCount(contractor) && guard < 100);
        assertEq(pos, n);
    }
}
