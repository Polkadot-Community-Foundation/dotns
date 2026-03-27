// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {DotnsRegistry, IDotnsRegistry} from "../../contracts/registry/DotnsRegistry.sol";
import {DotnsRegistrar} from "../../contracts/registrars/DotnsRegistrar.sol";
import {
    DotnsRegistrarController,
    IDotnsRegistrarController
} from "../../contracts/registrars/DotnsRegistrarController.sol";
import {PopRules, IPopRules} from "../../contracts/pop/PopRules.sol";
import {UpgradeDotnsRegistry} from "../../scripts/deploy/UpgradeDotnsRegistry.s.sol";

/// @title Fork test for DotnsRegistry upgrade to v1.3.0
/// @notice Uses the exact same upgrade logic as UpgradeDotnsRegistry.s.sol
///         to validate the upgrade against live Paseo AssetHub state.
contract DotnsRegistryForkTest is Test {
    bytes32 private constant DOT_NODE =
        0x3fce7d1364a893e213bc4212792b517ffc88f5b13b86c8ef9c8d390c3a1370ce;

    // Deployed Paseo AssetHub addresses (from deployments/paseo-assethub/420420417.json)
    address constant REGISTRY_PROXY = 0x4Da0d37aBe96C06ab19963F31ca2DC0412057a6f;
    address constant REGISTRAR_PROXY = 0x329aAA5b6bEa94E750b2dacBa74Bf41291E6c2BD;
    address constant CONTROLLER_PROXY = 0xd09e0F1c1E6CE8Cf40df929ef4FC778629573651;
    address constant POP_RULES_PROXY = 0x4e8920B1E69d0cEA9b23CBFC87A17Ee6fE02d2d3;
    address constant REVERSE_RESOLVER_PROXY = 0x95D57363B491CF743970c640fe419541386ac8BF;
    address constant PROTOCOL_REGISTRY_PROXY = 0xF8531342444fAC0A75719130eECcf45314584EFe;
    address constant STORE_FACTORY = 0x030296782F4d3046B080BcB017f01837561D9702;

    DotnsRegistry public registry;
    DotnsRegistrar public registrar;
    DotnsRegistrarController public controller;
    PopRules public popRules;

    UpgradeDotnsRegistry public upgradeScript;

    address public proxyAdmin;
    address public registryOwner;
    address public userA;
    address public userB;

    function setUp() public {
        // Fork Paseo AssetHub
        vm.createSelectFork("paseo");

        registry = DotnsRegistry(REGISTRY_PROXY);
        registrar = DotnsRegistrar(REGISTRAR_PROXY);
        controller = DotnsRegistrarController(CONTROLLER_PROXY);
        popRules = PopRules(POP_RULES_PROXY);

        // OwnableUpgradeable.owner() -- the address that can authorise UUPS upgrades
        proxyAdmin = OwnableUpgradeable(REGISTRY_PROXY).owner();
        // DotnsRegistry.owner(bytes32(0)) -- the root node owner
        registryOwner = registry.owner(bytes32(0));
        userA = makeAddr("userA");
        userB = makeAddr("userB");
        vm.deal(userA, 100 ether);
        vm.deal(userB, 100 ether);

        // Deploy the upgrade script (but don't run it yet)
        upgradeScript = new UpgradeDotnsRegistry();

        // Execute upgrade using the EXACT same logic as the deploy script
        upgradeScript.upgradeRegistry(REGISTRY_PROXY, proxyAdmin);

        // Run the same verification the script runs
        upgradeScript.verifyUpgrade(REGISTRY_PROXY);
    }

    function test_version_is_1_3_0_after_upgrade() public view {
        assertEq(registry.version(), "1.3.0");
    }

    function test_root_record_intact_after_upgrade() public view {
        assertTrue(registry.recordExists(bytes32(0)));
        assertEq(registry.owner(bytes32(0)), registryOwner);
    }

    function test_parent_can_reassign_subnode_after_upgrade() public {
        // Register a base domain
        string memory label = "forktest01";
        bytes32 node = _register(label, userA);

        // Create subnode owned by userB
        IDotnsRegistry.SubnodeRecord memory record = IDotnsRegistry.SubnodeRecord({
            parentNode: node, subLabel: "dapp", parentLabel: label, owner: userB
        });

        vm.prank(userA);
        bytes32 subnode = registry.setSubnodeOwner(record);
        assertEq(registry.owner(subnode), userB);

        // Parent (userA) reassigns subnode to themselves
        record.owner = userA;
        vm.prank(userA);
        registry.setSubnodeOwner(record);
        assertEq(registry.owner(subnode), userA);
    }

    function test_tokenised_node_auth_unchanged_after_upgrade() public {
        string memory label = "forktest02";
        bytes32 node = _register(label, userA);

        // Owner can setResolver
        address newResolver = makeAddr("forkResolver");
        vm.prank(userA);
        registry.setResolver(node, newResolver);
        assertEq(registry.resolver(node), newResolver);

        // Non-owner cannot setResolver
        vm.prank(userB);
        vm.expectRevert(IDotnsRegistry.NotAuthorised.selector);
        registry.setResolver(node, address(0));
    }

    /// @notice Issue #107: parent can set resolver on subname via setSubnodeResolver.
    function test_issue107_parent_can_set_resolver_via_setSubnodeResolver() public {
        string memory label = "forkparent";
        bytes32 node = _register(label, userA);

        // userA creates subnode owned by userB
        IDotnsRegistry.SubnodeRecord memory record = IDotnsRegistry.SubnodeRecord({
            parentNode: node, subLabel: "dapp", parentLabel: label, owner: userB
        });

        vm.prank(userA);
        bytes32 subnode = registry.setSubnodeOwner(record);
        assertEq(registry.owner(subnode), userB);

        // Parent (userA) sets resolver on the subnode via setSubnodeResolver
        address newResolver = makeAddr("parentSetResolver");
        IDotnsRegistry.SubnodeResolverRecord memory resolverRecord =
            IDotnsRegistry.SubnodeResolverRecord({
                parentNode: node, subLabel: "dapp", parentLabel: label, resolver: newResolver
            });

        vm.prank(userA);
        registry.setSubnodeResolver(resolverRecord);
        assertEq(registry.resolver(subnode), newResolver);

        // Direct setResolver still reverts for the parent (only subnode owner can use it)
        vm.prank(userA);
        vm.expectRevert(IDotnsRegistry.NotAuthorised.selector);
        registry.setResolver(subnode, address(0));
    }

    /// @dev Known issue: ERC721 transferFrom triggers a Store write from the registrar,
    ///      but stores created via setSubnodeOwner only list the registry as controller.
    ///      The registrar is not authorised on subnode-owner stores.
    ///      TODO: fix Store controller setup in setSubnodeOwner, then update this test
    ///      to verify the full transfer + reassignment flow.
    function test_erc721_transfer_reverts_due_to_store_controller_gap() public {
        string memory label = "forktest03";
        bytes32 node = _register(label, userA);

        IDotnsRegistry.SubnodeRecord memory record = IDotnsRegistry.SubnodeRecord({
            parentNode: node, subLabel: "shop", parentLabel: label, owner: userB
        });

        vm.prank(userA);
        registry.setSubnodeOwner(record);

        // Transfer reverts because the registrar's _syncRecipientStore tries to write
        // to userB's store, but the registrar is not a controller on stores created
        // by setSubnodeOwner (only the registry is listed as controller).
        uint256 tokenId = uint256(node);
        vm.prank(userA);
        vm.expectRevert();
        registrar.transferFrom(userA, userB, tokenId);
    }

    // --- Internal helpers ---

    function _register(string memory label, address nameOwner) internal returns (bytes32 node) {
        vm.prank(nameOwner);
        popRules.setUserPopStatus(IPopRules.PopStatus.PopFull);

        bytes32 secret = keccak256(abi.encodePacked(label, nameOwner, block.timestamp));

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label, owner: nameOwner, secret: secret, reserved: true
            });

        bytes32 commitment = controller.makeCommitment(registration);

        vm.prank(nameOwner);
        controller.commit(commitment);

        uint256 minAge = controller.minCommitmentAge();
        vm.warp(block.timestamp + minAge + 1);

        uint256 price = popRules.priceWithCheck(label, nameOwner).price;

        vm.prank(nameOwner);
        controller.register{value: price}(registration);

        node = keccak256(abi.encodePacked(DOT_NODE, keccak256(bytes(label))));
    }
}
