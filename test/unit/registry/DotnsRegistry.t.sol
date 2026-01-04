// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns, IDotnsRegistrarController} from "../../base/BaseDotns.t.sol";
import {IDotnsRegistry} from "../../../contracts/registry/IDotnsRegistry.sol";
import {IPopOracle} from "../../../contracts/pop/IPopOracle.sol";

contract DotnsRegistryTests is BaseDotns {
    function test_root_record_is_initialized_and_owned_by_owner() public view {
        bytes32 root = bytes32(0);
        assertEq(dotnsRegistry.owner(root), owner);
        assertTrue(dotnsRegistry.recordExists(root));
        assertEq(dotnsRegistry.resolver(root), address(0));
    }

    function test_owner_updates_registrar_controller_emits_event_and_persists() public {
        IDotnsRegistrarController oldController = dotnsRegistry.registrarController();
        IDotnsRegistrarController newController =
            IDotnsRegistrarController(makeAddr("new_controller"));
        if (newController == oldController) {
            newController = IDotnsRegistrarController(makeAddr("new_controller_2"));
        }

        vm.expectEmit(true, true, false, false, address(dotnsRegistry));
        emit IDotnsRegistry.RegistrarControllerUpdated(oldController, newController);

        vm.prank(owner);
        dotnsRegistry.updateRegistrarController(newController);

        assertEq(address(dotnsRegistry.registrarController()), address(newController));
    }

    function test_owner_can_rotate_registrar_controller_multiple_times() public {
        address c1 = makeAddr("c1");
        address c2 = makeAddr("c2");
        if (c1 == c2) c2 = makeAddr("c2_alt");

        vm.prank(owner);
        dotnsRegistry.updateRegistrarController(IDotnsRegistrarController(c1));
        assertEq(address(dotnsRegistry.registrarController()), address(c1));

        vm.prank(owner);
        dotnsRegistry.updateRegistrarController(IDotnsRegistrarController(c2));
        assertEq(address(dotnsRegistry.registrarController()), address(c2));
    }

    function test_registrar_controller_sets_owner_emits_event_and_record_exists_and_sets_resolver()
        public
    {
        bytes32 node = keccak256("node_b");
        address res = address(dotnsReverseResolver);

        vm.prank(owner);
        dotnsRegistry.updateRegistrarController(dotnsRegistrarController);

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
        dotnsRegistry.updateRegistrarController(dotnsRegistrarController);

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
        string memory parentLabel = "parentnode01";
        bytes32 parentNode = _register(parentLabel, owner, IPopOracle.PopStatus.NoStatus);

        string memory subLabel = "alice";
        bytes32 subLabelhash = keccak256(bytes(subLabel));
        bytes32 expected = keccak256(abi.encodePacked(parentNode, subLabelhash));

        _ensureStoreFor(ed);

        IDotnsRegistry.SubnodeRecord memory record = IDotnsRegistry.SubnodeRecord({
            parentNode: parentNode, subLabel: subLabel, parentLabel: parentLabel, owner: ed
        });

        vm.expectEmit(true, true, false, true, address(dotnsRegistry));
        emit IDotnsRegistry.NewOwner(parentNode, subLabelhash, ed);

        vm.prank(owner);
        bytes32 returned = dotnsRegistry.setSubnodeOwner(record);

        assertEq(returned, expected);
        assertEq(dotnsRegistry.owner(returned), ed);
        assertTrue(dotnsRegistry.recordExists(returned));
        assertEq(dotnsRegistry.resolver(returned), address(dotnsReverseResolver));
    }

    function test_node_owner_sets_resolver_emits_event_and_persists() public {
        string memory parentLabel = "parentnode03";
        bytes32 parentNode = _register(parentLabel, owner, IPopOracle.PopStatus.NoStatus);

        string memory subLabel = "carol";
        bytes32 subLabelhash = keccak256(bytes(subLabel));
        bytes32 node = keccak256(abi.encodePacked(parentNode, subLabelhash));
        address newResolver = makeAddr("resolver");

        _ensureStoreFor(ed);

        IDotnsRegistry.SubnodeRecord memory record = IDotnsRegistry.SubnodeRecord({
            parentNode: parentNode, subLabel: subLabel, parentLabel: parentLabel, owner: ed
        });

        vm.prank(owner);
        dotnsRegistry.setSubnodeOwner(record);

        vm.expectEmit(true, false, false, true, address(dotnsRegistry));
        emit IDotnsRegistry.NewResolver(node, newResolver);

        vm.prank(ed);
        dotnsRegistry.setResolver(node, newResolver);

        assertEq(dotnsRegistry.resolver(node), newResolver);
    }

    function test_node_owner_can_clear_resolver_to_zero() public {
        string memory parentLabel = "parentnode04";
        bytes32 parentNode = _register(parentLabel, owner, IPopOracle.PopStatus.NoStatus);

        string memory subLabel = "dave";
        bytes32 subLabelhash = keccak256(bytes(subLabel));
        bytes32 node = keccak256(abi.encodePacked(parentNode, subLabelhash));
        address newResolver = makeAddr("resolver");

        _ensureStoreFor(ed);

        IDotnsRegistry.SubnodeRecord memory record = IDotnsRegistry.SubnodeRecord({
            parentNode: parentNode, subLabel: subLabel, parentLabel: parentLabel, owner: ed
        });

        vm.prank(owner);
        dotnsRegistry.setSubnodeOwner(record);

        vm.prank(ed);
        dotnsRegistry.setResolver(node, newResolver);
        assertEq(dotnsRegistry.resolver(node), newResolver);

        vm.prank(ed);
        dotnsRegistry.setResolver(node, address(0));
        assertEq(dotnsRegistry.resolver(node), address(0));
    }

    function test_subnode_owner_creates_nested_subnode_under_owned_parent() public {
        string memory parentLabel = "parentnode05";
        bytes32 parentNode = _register(parentLabel, ed, IPopOracle.PopStatus.NoStatus);

        string memory childLabel = "child";
        bytes32 childLabelhash = keccak256(bytes(childLabel));
        bytes32 expectedChildNode = keccak256(abi.encodePacked(parentNode, childLabelhash));

        _ensureStoreFor(tiago);

        IDotnsRegistry.SubnodeRecord memory record = IDotnsRegistry.SubnodeRecord({
            parentNode: parentNode, subLabel: childLabel, parentLabel: parentLabel, owner: tiago
        });

        vm.prank(ed);
        bytes32 returned = dotnsRegistry.setSubnodeOwner(record);

        assertEq(returned, expectedChildNode);
        assertEq(dotnsRegistry.owner(expectedChildNode), tiago);
        assertTrue(dotnsRegistry.recordExists(expectedChildNode));
        assertEq(dotnsRegistry.resolver(expectedChildNode), address(dotnsReverseResolver));
    }
}
