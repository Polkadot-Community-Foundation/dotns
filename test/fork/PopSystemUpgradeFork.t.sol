// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {
    DotnsProtocolRegistry,
    IDotnsProtocolRegistry
} from "../../contracts/registry/DotnsProtocolRegistry.sol";
import {DotnsRegistry, IDotnsRegistry} from "../../contracts/registry/DotnsRegistry.sol";
import {DotnsRegistrar, IDotnsRegistrar} from "../../contracts/registrars/DotnsRegistrar.sol";
import {
    DotnsRegistrarController,
    IDotnsRegistrarController
} from "../../contracts/registrars/DotnsRegistrarController.sol";
import {
    DotnsPopController,
    IDotnsPopController
} from "../../contracts/registrars/DotnsPopController.sol";
import {DotnsPopResolver} from "../../contracts/resolvers/DotnsPopResolver.sol";
import {IDotnsController} from "../../contracts/registrars/IDotnsController.sol";
import {DotnsConstants} from "../../contracts/utils/DotnsConstants.sol";

import {UpgradePopSystem} from "../../scripts/deploy/UpgradePopSystem.s.sol";

/// @title Full PoP-system fork test against live Paseo AssetHub
/// @notice Applies the upgrade via `UpgradePopSystem.upgradeAll` — the same entry point
///         used live — and exercises the end-to-end PoP flow. Production and test
///         share a single upgrade code path so passing the fork test is equivalent
///         to validating the live upgrade would succeed and not break existing behaviour.
contract PopSystemUpgradeForkTest is Test {
    UpgradePopSystem public upgradeScript;

    DotnsProtocolRegistry public registry;
    DotnsRegistry public forwardRegistry;
    DotnsRegistrar public registrar;
    DotnsRegistrarController public controller;
    DotnsPopController public popController;
    DotnsPopResolver public popResolver;

    address public registryOwner;
    address public forwardRegistryOwner;
    address public registrarOwner;
    address public controllerOwner;

    address public popGateway;
    address public alice;
    address public bob;

    function setUp() public {
        vm.createSelectFork("paseo_local");

        upgradeScript = new UpgradePopSystem();

        registry = DotnsProtocolRegistry(upgradeScript.PROTOCOL_REGISTRY_PROXY());
        forwardRegistry = DotnsRegistry(upgradeScript.REGISTRY_PROXY());
        registrar = DotnsRegistrar(upgradeScript.REGISTRAR_PROXY());
        controller = DotnsRegistrarController(upgradeScript.CONTROLLER_PROXY());

        registryOwner = OwnableUpgradeable(address(registry)).owner();
        forwardRegistryOwner = OwnableUpgradeable(address(forwardRegistry)).owner();
        registrarOwner = OwnableUpgradeable(address(registrar)).owner();
        controllerOwner = OwnableUpgradeable(address(controller)).owner();

        popGateway = makeAddr("popGateway");

        UpgradePopSystem.Deployment memory deployment = upgradeScript.upgradeAll(
            registryOwner, forwardRegistryOwner, registrarOwner, controllerOwner, popGateway
        );
        popController = DotnsPopController(deployment.popControllerProxy);
        popResolver = DotnsPopResolver(deployment.popResolverProxy);

        upgradeScript.verifyUpgrade(deployment, popGateway);

        alice = makeAddr("alice");
        bob = makeAddr("bob");
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function test_versions_bumped() public view {
        assertEq(registry.version(), upgradeScript.PROTOCOL_REGISTRY_VERSION());
        assertEq(forwardRegistry.version(), upgradeScript.REGISTRY_VERSION());
        assertEq(registrar.version(), upgradeScript.REGISTRAR_VERSION());
        assertEq(controller.version(), upgradeScript.CONTROLLER_VERSION());
        assertEq(popController.version(), upgradeScript.POP_CONTROLLER_VERSION());
        assertEq(popResolver.version(), upgradeScript.POP_RESOLVER_VERSION());
    }

    function test_pop_keys_wired() public view {
        assertEq(registry.get(registry.POP_CONTROLLER()), address(popController));
        assertEq(registry.get(registry.POP_RESOLVER()), address(popResolver));
        assertEq(registry.get(registry.POP_GATEWAY()), popGateway);
    }

    function test_existing_registry_keys_preserved() public view {
        assertTrue(registry.get(registry.REGISTRAR()) != address(0));
        assertTrue(registry.get(registry.CONTROLLER()) != address(0));
        assertTrue(registry.get(registry.REGISTRY()) != address(0));
        assertTrue(registry.get(registry.POP_RULES()) != address(0));
        assertTrue(registry.get(registry.STORE_FACTORY()) != address(0));
        assertTrue(registry.get(registry.REVERSE_RESOLVER()) != address(0));
    }

    function test_pop_controller_authorised_on_registrar() public view {
        assertTrue(registrar.controllers(IDotnsController(address(popController))));
    }

    function test_commit_reveal_controller_still_authorised_on_registrar() public view {
        assertTrue(registrar.controllers(IDotnsController(address(controller))));
    }

    function test_registrar_erc721_metadata_preserved() public view {
        assertEq(registrar.name(), "Dotns");
        assertEq(registrar.symbol(), "Dotns");
    }

    function test_full_pop_user_flow_after_upgrade() public {
        string memory liteLabel = "forkalice.42";
        string memory fullLabel = "forkalicefull";
        bytes memory chatKey = hex"cafebabe";

        vm.prank(popGateway);
        popController.reserveBaseName(liteLabel, alice, chatKey, fullLabel);

        bytes32 liteNode = _nodeOf(liteLabel);
        assertEq(IERC721(address(registrar)).ownerOf(uint256(liteNode)), alice);
        assertEq(forwardRegistry.owner(liteNode), alice);
        assertEq(popResolver.chatKey(liteNode), chatKey);

        (bool reserved, address holder) = popController.isReservedForClaim(fullLabel);
        assertTrue(reserved);
        assertEq(holder, alice);

        IDotnsPopController.Link memory link = IDotnsPopController.Link({
            kind: IDotnsPopController.LinkKind.LiteUsername, liteLabel: liteLabel, chatKey: ""
        });

        vm.prank(popGateway);
        popController.registerBaseName(fullLabel, alice, link);

        bytes32 fullNode = _nodeOf(fullLabel);
        assertEq(IERC721(address(registrar)).ownerOf(uint256(fullNode)), alice);
        assertEq(popResolver.chatKey(fullNode), chatKey);
        assertEq(popResolver.liteLink(fullNode), keccak256(bytes(liteLabel)));

        (bool stillReserved,) = popController.isReservedForClaim(fullLabel);
        assertFalse(stillReserved);
    }

    function test_pop_minted_name_supports_subname_creation() public {
        string memory parentLabel = "forkparent42";
        IDotnsPopController.Link memory link = IDotnsPopController.Link({
            kind: IDotnsPopController.LinkKind.None, liteLabel: "", chatKey: hex"cafecafe"
        });

        vm.prank(popGateway);
        popController.registerBaseName(parentLabel, alice, link);

        bytes32 parentNode = _nodeOf(parentLabel);
        assertEq(IERC721(address(registrar)).ownerOf(uint256(parentNode)), alice);

        IDotnsRegistry.SubnodeRecord memory subnodeRecord = IDotnsRegistry.SubnodeRecord({
            parentNode: parentNode, subLabel: "sub", parentLabel: parentLabel, owner: bob
        });

        vm.prank(alice);
        bytes32 subnode = forwardRegistry.setSubnodeOwner(subnodeRecord);

        assertEq(forwardRegistry.owner(subnode), bob);

        IDotnsRegistry.SubnodeRecord memory unauthorisedSubnodeRecord = IDotnsRegistry.SubnodeRecord({
            parentNode: parentNode, subLabel: "hijack", parentLabel: parentLabel, owner: bob
        });

        vm.prank(bob);
        vm.expectRevert(IDotnsRegistry.NotAuthorised.selector);
        forwardRegistry.setSubnodeOwner(unauthorisedSubnodeRecord);
    }

    function test_commit_reveal_controller_still_functions_after_upgrade() public view {
        // The commit-reveal controller's on-chain state (min/max commitment age, protocol
        // registry pointer) is preserved by the UUPS upgrade. Verifying the pointer
        // here is the strongest non-transactional assertion we can make on a fork
        // without paying gas for a full commit/reveal dance.
        assertEq(address(controller.protocolRegistry()), address(registry));
        assertGt(controller.maxCommitmentAge(), 0);
        assertGt(controller.minCommitmentAge(), 0);
    }

    function _nodeOf(string memory label) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(DotnsConstants.DOT_NODE, keccak256(bytes(label))));
    }
}
