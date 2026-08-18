// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {BaseDotns} from "../../base/BaseDotns.t.sol";
import {DotnsNameWhitelist} from "../../../contracts/whitelist/DotnsNameWhitelist.sol";
import {IDotnsNameWhitelist} from "../../../contracts/whitelist/IDotnsNameWhitelist.sol";
import {IDotnsRoleManager} from "../../../contracts/access/IDotnsRoleManager.sol";
import {IDotnsProtocolRegistry} from "../../../contracts/registry/IDotnsProtocolRegistry.sol";
import {DotnsConstants} from "../../../contracts/utils/DotnsConstants.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/// @title DotnsNameWhitelist unit tests
/// @notice Covers the request-to-decision lifecycle, access control, the request window, the
///         controller-only consume hook, and the review views.
contract DotnsNameWhitelistTests is BaseDotns {
    DotnsNameWhitelist internal whitelist;
    address internal operator;

    function setUp() public override {
        super.setUp();
        operator = _createUser("operator");

        vm.startPrank(owner);
        whitelist = DotnsNameWhitelist(
            Upgrades.deployUUPSProxy(
                "DotnsNameWhitelist.sol:DotnsNameWhitelist",
                abi.encodeCall(
                    DotnsNameWhitelist.initialize,
                    (IDotnsProtocolRegistry(address(protocolRegistry)))
                )
            )
        );
        whitelist.setRole(DotnsConstants.WHITELIST_OPERATOR_ROLE, operator, true);
        whitelist.setWindow(0, 30 days);
        vm.stopPrank();

        vm.label(address(whitelist), "DotnsNameWhitelist");
    }

    function _request(address who, string memory label) internal {
        vm.prank(who);
        whitelist.requestName(label);
    }

    function test_requestName_records_and_emits() public {
        bytes32 node = _nodeOf(BASE_LABEL_A);
        vm.expectEmit(true, true, false, true, address(whitelist));
        emit IDotnsNameWhitelist.NameRequested(node, ed, BASE_LABEL_A);
        _request(ed, BASE_LABEL_A);

        IDotnsNameWhitelist.Grant memory grant = whitelist.grantOf(BASE_LABEL_A);
        assertEq(uint256(grant.status), uint256(IDotnsNameWhitelist.GrantStatus.Requested));
        assertEq(grant.grantee, ed);
        assertEq(grant.requestedAt, uint64(block.timestamp));
        assertEq(grant.decidedAt, 0);
        assertEq(grant.label, BASE_LABEL_A);
        assertEq(whitelist.grantCount(), 1);
        assertEq(whitelist.granteeOf(BASE_LABEL_A), address(0));
    }

    function test_requestName_reverts_when_already_exists() public {
        _request(ed, BASE_LABEL_A);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsNameWhitelist.AlreadyExists.selector, _nodeOf(BASE_LABEL_A)
            )
        );
        _request(tiago, BASE_LABEL_A);
    }

    function test_requestName_reverts_after_reject() public {
        _request(ed, BASE_LABEL_A);
        vm.prank(operator);
        whitelist.reject(BASE_LABEL_A);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsNameWhitelist.AlreadyExists.selector, _nodeOf(BASE_LABEL_A)
            )
        );
        _request(ed, BASE_LABEL_A);
    }

    function test_requestName_reverts_for_non_canonical_label() public {
        vm.expectRevert(IDotnsNameWhitelist.InvalidLabel.selector);
        _request(ed, "bad.label");
    }

    function test_requestName_reverts_before_and_after_window() public {
        vm.prank(owner);
        whitelist.setWindow(1 days, 1 days);

        vm.expectRevert(IDotnsNameWhitelist.WindowClosed.selector);
        _request(ed, BASE_LABEL_A);

        vm.warp(block.timestamp + 3 days);
        vm.expectRevert(IDotnsNameWhitelist.WindowClosed.selector);
        _request(ed, BASE_LABEL_A);
    }

    function test_accept_by_operator_reserves_and_stamps() public {
        _request(ed, BASE_LABEL_A);
        bytes32 node = _nodeOf(BASE_LABEL_A);

        vm.expectEmit(true, true, false, true, address(whitelist));
        emit IDotnsNameWhitelist.NameAccepted(node, ed, BASE_LABEL_A);
        vm.prank(operator);
        whitelist.accept(BASE_LABEL_A);

        assertEq(whitelist.granteeOf(BASE_LABEL_A), ed);
        assertTrue(whitelist.isGrantedTo(BASE_LABEL_A, ed));
        assertEq(whitelist.grantOf(BASE_LABEL_A).decidedAt, uint64(block.timestamp));
    }

    function test_accept_reverts_when_not_requested() public {
        vm.expectRevert(
            abi.encodeWithSelector(IDotnsNameWhitelist.NotRequested.selector, _nodeOf(BASE_LABEL_A))
        );
        vm.prank(operator);
        whitelist.accept(BASE_LABEL_A);
    }

    function test_accept_reverts_for_unauthorised_caller() public {
        _request(ed, BASE_LABEL_A);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsRoleManager.NotRoleOrOwner.selector,
                tiago,
                DotnsConstants.WHITELIST_OPERATOR_ROLE
            )
        );
        vm.prank(tiago);
        whitelist.accept(BASE_LABEL_A);
    }

    function test_reject_records_and_emits() public {
        _request(ed, BASE_LABEL_A);
        bytes32 node = _nodeOf(BASE_LABEL_A);

        vm.expectEmit(true, true, false, true, address(whitelist));
        emit IDotnsNameWhitelist.NameRejected(node, ed, BASE_LABEL_A);
        vm.prank(operator);
        whitelist.reject(BASE_LABEL_A);

        IDotnsNameWhitelist.Grant memory grant = whitelist.grantOf(BASE_LABEL_A);
        assertEq(uint256(grant.status), uint256(IDotnsNameWhitelist.GrantStatus.Rejected));
        assertEq(grant.decidedAt, uint64(block.timestamp));
        assertEq(whitelist.granteeOf(BASE_LABEL_A), address(0));
        assertEq(whitelist.grantCount(), 1);
    }

    function test_reject_reverts_when_not_requested() public {
        vm.expectRevert(
            abi.encodeWithSelector(IDotnsNameWhitelist.NotRequested.selector, _nodeOf(BASE_LABEL_A))
        );
        vm.prank(operator);
        whitelist.reject(BASE_LABEL_A);
    }

    function test_grantName_direct_by_owner() public {
        bytes32 node = _nodeOf(BASE_LABEL_A);
        uint64 nowTimestamp = uint64(block.timestamp);

        vm.expectEmit(true, true, false, true, address(whitelist));
        emit IDotnsNameWhitelist.NameAccepted(node, ed, BASE_LABEL_A);
        vm.prank(owner);
        whitelist.grantName(BASE_LABEL_A, ed);

        assertEq(whitelist.granteeOf(BASE_LABEL_A), ed);
        IDotnsNameWhitelist.Grant memory grant = whitelist.grantOf(BASE_LABEL_A);
        assertEq(uint256(grant.status), uint256(IDotnsNameWhitelist.GrantStatus.Accepted));
        assertEq(grant.requestedAt, nowTimestamp);
        assertEq(grant.decidedAt, nowTimestamp);
        assertEq(grant.label, BASE_LABEL_A);
    }

    function test_grantName_reverts_for_zero_grantee() public {
        vm.expectRevert(IDotnsNameWhitelist.ZeroGrantee.selector);
        vm.prank(operator);
        whitelist.grantName(BASE_LABEL_A, address(0));
    }

    function test_grantName_reverts_for_non_canonical_label() public {
        vm.expectRevert(IDotnsNameWhitelist.InvalidLabel.selector);
        vm.prank(operator);
        whitelist.grantName("bad.label", ed);
    }

    function test_grantName_reverts_when_already_exists() public {
        vm.prank(operator);
        whitelist.grantName(BASE_LABEL_A, ed);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsNameWhitelist.AlreadyExists.selector, _nodeOf(BASE_LABEL_A)
            )
        );
        vm.prank(operator);
        whitelist.grantName(BASE_LABEL_A, tiago);
    }

    function test_grantName_reverts_for_unauthorised_caller() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsRoleManager.NotRoleOrOwner.selector,
                tiago,
                DotnsConstants.WHITELIST_OPERATOR_ROLE
            )
        );
        vm.prank(tiago);
        whitelist.grantName(BASE_LABEL_A, ed);
    }

    function test_grantNames_batch_grants_each() public {
        string[] memory labels = new string[](2);
        labels[0] = BASE_LABEL_A;
        labels[1] = BASE_LABEL_B;
        vm.prank(operator);
        whitelist.grantNames(labels, ed);

        assertEq(whitelist.granteeOf(BASE_LABEL_A), ed);
        assertEq(whitelist.granteeOf(BASE_LABEL_B), ed);
        assertEq(whitelist.grantCount(), 2);
    }

    function test_grantNames_reverts_on_duplicate_label() public {
        string[] memory labels = new string[](2);
        labels[0] = BASE_LABEL_A;
        labels[1] = BASE_LABEL_A;
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsNameWhitelist.AlreadyExists.selector, _nodeOf(BASE_LABEL_A)
            )
        );
        vm.prank(operator);
        whitelist.grantNames(labels, ed);
    }

    function test_revokeName_clears_entry() public {
        vm.prank(operator);
        whitelist.grantName(BASE_LABEL_A, ed);
        bytes32 node = _nodeOf(BASE_LABEL_A);

        vm.expectEmit(true, true, false, true, address(whitelist));
        emit IDotnsNameWhitelist.NameRevoked(node, ed, BASE_LABEL_A);
        vm.prank(operator);
        whitelist.revokeName(BASE_LABEL_A);

        assertEq(whitelist.grantCount(), 0);
        assertEq(
            uint256(whitelist.grantOf(BASE_LABEL_A).status),
            uint256(IDotnsNameWhitelist.GrantStatus.None)
        );
    }

    function test_revokeName_reverts_when_absent() public {
        vm.expectRevert(
            abi.encodeWithSelector(IDotnsNameWhitelist.NotGranted.selector, _nodeOf(BASE_LABEL_A))
        );
        vm.prank(operator);
        whitelist.revokeName(BASE_LABEL_A);
    }

    function test_consume_by_public_controller_removes_grant() public {
        vm.prank(operator);
        whitelist.grantName(BASE_LABEL_A, ed);
        bytes32 node = _nodeOf(BASE_LABEL_A);

        vm.expectEmit(true, true, false, true, address(whitelist));
        emit IDotnsNameWhitelist.NameConsumed(node, ed, BASE_LABEL_A);
        vm.prank(address(dotnsRegistrarController));
        whitelist.consume(BASE_LABEL_A, ed);

        assertEq(whitelist.grantCount(), 0);
    }

    function test_consume_by_pop_controller_removes_grant() public {
        vm.prank(operator);
        whitelist.grantName(BASE_LABEL_A, ed);
        vm.prank(address(dotnsPopController));
        whitelist.consume(BASE_LABEL_A, ed);
        assertEq(whitelist.grantCount(), 0);
    }

    function test_consume_reverts_for_non_controller() public {
        vm.prank(operator);
        whitelist.grantName(BASE_LABEL_A, ed);
        vm.expectRevert(abi.encodeWithSelector(IDotnsNameWhitelist.NotController.selector, ed));
        vm.prank(ed);
        whitelist.consume(BASE_LABEL_A, ed);
    }

    function test_consume_reverts_for_wrong_registrant() public {
        vm.prank(operator);
        whitelist.grantName(BASE_LABEL_A, ed);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsNameWhitelist.NotGrantee.selector, tiago, _nodeOf(BASE_LABEL_A)
            )
        );
        vm.prank(address(dotnsRegistrarController));
        whitelist.consume(BASE_LABEL_A, tiago);
    }

    function test_consume_reverts_when_only_requested() public {
        _request(ed, BASE_LABEL_A);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsNameWhitelist.NotGrantee.selector, ed, _nodeOf(BASE_LABEL_A)
            )
        );
        vm.prank(address(dotnsRegistrarController));
        whitelist.consume(BASE_LABEL_A, ed);
    }

    function test_consume_reverts_after_reject() public {
        _request(ed, BASE_LABEL_A);
        vm.prank(operator);
        whitelist.reject(BASE_LABEL_A);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsNameWhitelist.NotGrantee.selector, ed, _nodeOf(BASE_LABEL_A)
            )
        );
        vm.prank(address(dotnsRegistrarController));
        whitelist.consume(BASE_LABEL_A, ed);
    }

    function test_full_lifecycle_request_accept_consume() public {
        _request(ed, BASE_LABEL_A);
        vm.prank(operator);
        whitelist.accept(BASE_LABEL_A);
        assertTrue(whitelist.isGrantedTo(BASE_LABEL_A, ed));

        vm.prank(address(dotnsRegistrarController));
        whitelist.consume(BASE_LABEL_A, ed);

        assertEq(whitelist.grantCount(), 0);
        assertEq(
            uint256(whitelist.grantOf(BASE_LABEL_A).status),
            uint256(IDotnsNameWhitelist.GrantStatus.None)
        );
    }

    function test_setWindow_sets_and_emits() public {
        uint64 startsIn = 1 days;
        uint64 duration = 5 days;
        uint64 openAt = uint64(block.timestamp) + startsIn;
        uint64 closeAt = openAt + duration;

        vm.expectEmit(false, false, false, true, address(whitelist));
        emit IDotnsNameWhitelist.WindowSet(openAt, closeAt);
        vm.prank(owner);
        whitelist.setWindow(startsIn, duration);

        (uint64 gotOpen, uint64 gotClose) = whitelist.window();
        assertEq(gotOpen, openAt);
        assertEq(gotClose, closeAt);
    }

    function test_isWindowOpen_tracks_the_window() public {
        uint64 openAt = uint64(block.timestamp) + 1 days;
        uint64 closeAt = openAt + 1 days;
        vm.prank(owner);
        whitelist.setWindow(1 days, 1 days);

        assertFalse(whitelist.isWindowOpen());

        vm.warp(openAt);
        assertTrue(whitelist.isWindowOpen());

        vm.warp(closeAt);
        assertFalse(whitelist.isWindowOpen());
    }

    function test_setWindow_reverts_for_zero_duration() public {
        vm.expectRevert(IDotnsNameWhitelist.BadWindow.selector);
        vm.prank(owner);
        whitelist.setWindow(1 days, 0);
    }

    function test_setWindow_reverts_for_non_owner() public {
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, operator)
        );
        vm.prank(operator);
        whitelist.setWindow(0, 1 days);
    }

    function test_initialize_reverts_on_second_call() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        whitelist.initialize(IDotnsProtocolRegistry(address(protocolRegistry)));
    }

    function test_grants_pagination_boundaries() public {
        string[] memory labels = new string[](3);
        labels[0] = BASE_LABEL_A;
        labels[1] = BASE_LABEL_B;
        labels[2] = BASE_LABEL_C;
        vm.prank(operator);
        whitelist.grantNames(labels, ed);

        assertEq(whitelist.grantCount(), 3);
        assertEq(whitelist.grants(3, 10).length, 0);
        assertEq(whitelist.grants(2, 10).length, 1);
        assertEq(whitelist.grants(0, 0).length, 0);
        assertEq(whitelist.grants(1, 1).length, 1);
        assertEq(whitelist.grants(0, 100).length, 3);
    }
}
