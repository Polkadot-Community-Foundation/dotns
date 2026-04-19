// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../../base/BaseDotns.t.sol";
import {IDotnsPopResolver} from "../../../contracts/resolvers/IDotnsPopResolver.sol";

/// @title DotnsPopResolverTests
/// @notice Behavioural unit tests for {DotnsPopResolver}. Coverage of byte-exact
///         persistence across arbitrary payloads lives in the PoP-controller fuzz
///         file; here we only assert behaviour that is not a default-value check
///         or a tautological storage-read.
contract DotnsPopResolverTests is BaseDotns {
    function test_setChatKey_writes_and_emits() public {
        bytes32 node = _nodeOf("alice.42");
        bytes memory chatKey = hex"01020304";

        vm.prank(address(dotnsPopController));
        vm.expectEmit(true, false, false, true);
        emit IDotnsPopResolver.ChatKeyUpdated(node, chatKey);
        dotnsPopResolver.setChatKey(node, chatKey);

        assertEq(dotnsPopResolver.chatKey(node), chatKey);
    }

    function test_setChatKey_reverts_for_unauthorised_caller() public {
        vm.prank(ed);
        vm.expectRevert(abi.encodeWithSelector(IDotnsPopResolver.NotPopController.selector, ed));
        dotnsPopResolver.setChatKey(_nodeOf("alice.42"), hex"01");
    }

    function test_setLiteLink_writes_and_emits() public {
        bytes32 fullNode = _nodeOf("alice");
        bytes32 liteLabelhash = keccak256(bytes("alice.42"));

        vm.prank(address(dotnsPopController));
        vm.expectEmit(true, true, false, false);
        emit IDotnsPopResolver.LiteLinkUpdated(fullNode, liteLabelhash);
        dotnsPopResolver.setLiteLink(fullNode, liteLabelhash);

        assertEq(dotnsPopResolver.liteLink(fullNode), liteLabelhash);
    }

    function test_setLiteLink_reverts_for_unauthorised_caller() public {
        vm.prank(ed);
        vm.expectRevert(abi.encodeWithSelector(IDotnsPopResolver.NotPopController.selector, ed));
        dotnsPopResolver.setLiteLink(_nodeOf("alice"), keccak256(bytes("alice.42")));
    }

    function test_rotating_pop_controller_changes_authorised_writer() public {
        address replacement = makeAddr("replacement");
        bytes32 key = protocolRegistry.POP_CONTROLLER();

        vm.prank(owner);
        protocolRegistry.set(key, replacement);

        vm.prank(address(dotnsPopController));
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsPopResolver.NotPopController.selector, address(dotnsPopController)
            )
        );
        dotnsPopResolver.setChatKey(_nodeOf("alice.42"), hex"01");

        vm.prank(replacement);
        dotnsPopResolver.setChatKey(_nodeOf("alice.42"), hex"02");
        assertEq(dotnsPopResolver.chatKey(_nodeOf("alice.42")), hex"02");
    }
}
