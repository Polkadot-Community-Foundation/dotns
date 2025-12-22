// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../../base/BaseDotns.t.sol";
import {IDotnsRegistry} from "../../../contracts/registry/IDotnsRegistry.sol";

contract DotnsRegistryTests is BaseDotns {
    function test_root_record_is_initialized_and_owned_by_owner() public {
        bytes32 root = bytes32(0);
        assertEq(dotnsRegistry.owner(root), owner);
        assertTrue(dotnsRegistry.recordExists(root));
        assertEq(dotnsRegistry.resolver(root), address(0));
    }

    function test_owner_updates_registrar_controller_emits_event_and_persists() public {
        address oldController = dotnsRegistry.registrarController();
        address newController = makeAddr("new_controller");
        if (newController == oldController) newController = makeAddr("new_controller_2");

        vm.expectEmit(true, true, false, false, address(dotnsRegistry));
        emit IDotnsRegistry.RegistrarControllerUpdated(oldController, newController);

        vm.prank(owner);
        dotnsRegistry.updateRegistrarController(newController);

        assertEq(dotnsRegistry.registrarController(), newController);
    }

    function test_owner_can_rotate_registrar_controller_multiple_times() public {
        address c1 = makeAddr("c1");
        address c2 = makeAddr("c2");
        if (c1 == c2) c2 = makeAddr("c2_alt");

        vm.prank(owner);
        dotnsRegistry.updateRegistrarController(c1);
        assertEq(dotnsRegistry.registrarController(), c1);

        vm.prank(owner);
        dotnsRegistry.updateRegistrarController(c2);
        assertEq(dotnsRegistry.registrarController(), c2);
    }

    function test_registrar_controller_sets_owner_emits_event_and_record_exists_and_sets_resolver()
        public
    {
        bytes32 node = keccak256("node_b");
        address res = address(dotnsReverseResolver);

        vm.prank(owner);
        dotnsRegistry.updateRegistrarController(address(dotnsRegistrarController));

        vm.expectEmit(true, false, false, true, address(dotnsRegistry));
        emit IDotnsRegistry.NodeTransferred(node, ed);

        vm.prank(address(dotnsRegistrarController));
        dotnsRegistry.setOwner(node, ed, res);

        assertEq(dotnsRegistry.owner(node), ed);
        assertTrue(dotnsRegistry.recordExists(node));
        assertEq(dotnsRegistry.resolver(node), res);
    }

    function test_registrar_controller_sets_owner_for_multiple_nodes() public {
        bytes32 n1 = keccak256("n1");
        bytes32 n2 = keccak256("n2");
        address res = address(dotnsReverseResolver);

        vm.prank(owner);
        dotnsRegistry.updateRegistrarController(address(dotnsRegistrarController));

        vm.startPrank(address(dotnsRegistrarController));
        dotnsRegistry.setOwner(n1, ed, res);
        dotnsRegistry.setOwner(n2, tiago, res);
        vm.stopPrank();

        assertEq(dotnsRegistry.owner(n1), ed);
        assertEq(dotnsRegistry.owner(n2), tiago);
        assertTrue(dotnsRegistry.recordExists(n1));
        assertTrue(dotnsRegistry.recordExists(n2));
        assertEq(dotnsRegistry.resolver(n1), res);
        assertEq(dotnsRegistry.resolver(n2), res);
    }

    function test_node_owner_creates_subnode_emits_event_and_returns_expected_subnode() public {
        bytes32 root = bytes32(0);
        bytes32 label = keccak256(bytes("alice"));
        bytes32 expected = keccak256(abi.encodePacked(root, label));

        vm.expectEmit(true, true, false, true, address(dotnsRegistry));
        emit IDotnsRegistry.NewOwner(root, label, ed);

        vm.prank(owner);
        bytes32 returned = dotnsRegistry.setSubnodeOwner(root, label, ed);

        assertEq(returned, expected);
        assertEq(dotnsRegistry.owner(expected), ed);
        assertTrue(dotnsRegistry.recordExists(expected));
        assertEq(dotnsRegistry.resolver(expected), address(0));
    }

    function test_subnode_starts_with_zero_resolver() public {
        bytes32 root = bytes32(0);
        bytes32 label = keccak256(bytes("bob"));
        bytes32 subnode = keccak256(abi.encodePacked(root, label));

        vm.prank(owner);
        dotnsRegistry.setSubnodeOwner(root, label, ed);

        assertEq(dotnsRegistry.resolver(subnode), address(0));
    }

    function test_node_owner_sets_resolver_emits_event_and_persists() public {
        bytes32 root = bytes32(0);
        bytes32 label = keccak256(bytes("carol"));
        bytes32 node = keccak256(abi.encodePacked(root, label));
        address res = makeAddr("resolver");

        vm.prank(owner);
        dotnsRegistry.setSubnodeOwner(root, label, ed);

        vm.expectEmit(true, false, false, true, address(dotnsRegistry));
        emit IDotnsRegistry.NewResolver(node, res);

        vm.prank(ed);
        dotnsRegistry.setResolver(node, res);

        assertEq(dotnsRegistry.resolver(node), res);
    }

    function test_node_owner_can_clear_resolver_to_zero() public {
        bytes32 root = bytes32(0);
        bytes32 label = keccak256(bytes("dave"));
        bytes32 node = keccak256(abi.encodePacked(root, label));
        address res = makeAddr("resolver");

        vm.prank(owner);
        dotnsRegistry.setSubnodeOwner(root, label, ed);

        vm.prank(ed);
        dotnsRegistry.setResolver(node, res);
        assertEq(dotnsRegistry.resolver(node), res);

        vm.prank(ed);
        dotnsRegistry.setResolver(node, address(0));
        assertEq(dotnsRegistry.resolver(node), address(0));
    }

    function test_subnode_owner_creates_nested_subnode_under_owned_parent() public {
        bytes32 root = bytes32(0);
        bytes32 parentLabel = keccak256(bytes("parent"));
        bytes32 parentNode = keccak256(abi.encodePacked(root, parentLabel));

        vm.prank(owner);
        dotnsRegistry.setSubnodeOwner(root, parentLabel, ed);

        bytes32 childLabel = keccak256(bytes("child"));
        bytes32 childNode = keccak256(abi.encodePacked(parentNode, childLabel));

        vm.prank(ed);
        bytes32 returned = dotnsRegistry.setSubnodeOwner(parentNode, childLabel, tiago);

        assertEq(returned, childNode);
        assertEq(dotnsRegistry.owner(childNode), tiago);
        assertTrue(dotnsRegistry.recordExists(childNode));
        assertEq(dotnsRegistry.resolver(childNode), address(0));
    }
}
