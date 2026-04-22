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
import {IPopRules} from "../../contracts/pop/IPopRules.sol";
import {PopRules} from "../../contracts/pop/PopRules.sol";

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

    // Pre-upgrade snapshot of every registry address the upgrade is NOT supposed
    // to touch. Recorded before `upgradeAll` so tests can assert strict equality
    // post-upgrade rather than the weaker "non-zero" oracle.
    address public preUpgradeRegistrar;
    address public preUpgradeController;
    address public preUpgradeRegistry;
    address public preUpgradePopRules;
    address public preUpgradeStoreFactory;
    address public preUpgradeReverseResolver;

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

        // Snapshot every address the upgrade must preserve, BEFORE applying.
        preUpgradeRegistrar = registry.get(DotnsConstants.REGISTRAR);
        preUpgradeController = registry.get(DotnsConstants.CONTROLLER);
        preUpgradeRegistry = registry.get(DotnsConstants.REGISTRY);
        preUpgradePopRules = registry.get(DotnsConstants.POP_RULES);
        preUpgradeStoreFactory = registry.get(DotnsConstants.STORE_FACTORY);
        preUpgradeReverseResolver = registry.get(DotnsConstants.REVERSE_RESOLVER);

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
        assertEq(registry.get(DotnsConstants.POP_CONTROLLER), address(popController));
        assertEq(registry.get(DotnsConstants.POP_RESOLVER), address(popResolver));
        assertEq(registry.get(DotnsConstants.POP_GATEWAY), popGateway);
    }

    // Every key the upgrade is NOT meant to write must equal its pre-upgrade value
    // byte-for-byte. The previous "!= address(0)" oracle silently passes even when
    // the upgrade overwrites a key with a fresh address, so this strengthens to
    // snapshot-equality against the values captured in `setUp` before `upgradeAll`.
    function test_existing_registry_keys_preserved() public view {
        assertEq(registry.get(DotnsConstants.REGISTRAR), preUpgradeRegistrar);
        assertEq(registry.get(DotnsConstants.CONTROLLER), preUpgradeController);
        assertEq(registry.get(DotnsConstants.REGISTRY), preUpgradeRegistry);
        assertEq(registry.get(DotnsConstants.POP_RULES), preUpgradePopRules);
        assertEq(registry.get(DotnsConstants.STORE_FACTORY), preUpgradeStoreFactory);
        assertEq(registry.get(DotnsConstants.REVERSE_RESOLVER), preUpgradeReverseResolver);
    }

    // Cheap live-state sanity check: `PopRules._onlyRegistry` reads through
    // `protocolRegistry` to resolve the registrar, so an unset pointer here
    // would silently revert every post-upgrade cross-flow sync write. Asserting
    // it explicitly prevents a whole class of "nothing happens" regressions.
    function test_popRules_protocol_registry_wired() public view {
        assertEq(address(PopRules(preUpgradePopRules).protocolRegistry()), address(registry));
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
        string memory liteLabel = "forkalice42";
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

    // Drives a real commit-reveal registration end-to-end on the forked live
    // state. The previous variant only read the controller's configuration
    // pointers; it passed even if every post-upgrade transaction would revert.
    // Using a NoStatus-classified label (>=9 chars with 2 trailing digits)
    // means we also exercise the PopRules price path and the Store write.
    function test_commit_reveal_controller_still_functions_after_upgrade() public {
        string memory label = "forkregister42";
        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label, owner: alice, secret: keccak256("fork-secret"), reserved: false
            });

        bytes32 commitment = controller.makeCommitment(registration);
        vm.prank(alice);
        controller.commit(commitment);
        vm.warp(block.timestamp + controller.minCommitmentAge() + 1);

        uint256 price = IPopRules(preUpgradePopRules).priceWithCheck(label, alice).price;

        vm.prank(alice);
        controller.register{value: price}(registration);

        assertEq(IERC721(address(registrar)).ownerOf(uint256(_nodeOf(label))), alice);
    }

    // Live-state variant of the _removeUserFromQueue head-branch sync: a head
    // user relinquishing while a live waiter exists must promote that waiter
    // in PopRules. Unit coverage exists for the queue side; the fork proves
    // the cross-contract write reaches PopRules on the live deployment.
    function test_head_relinquish_promotes_successor_in_pop_rules() public {
        string memory baseStem = "forkrelinquish";

        vm.prank(popGateway);
        popController.reserveBaseName("forkr142", alice, hex"01", baseStem);
        vm.prank(popGateway);
        popController.reserveBaseName("forkr242", bob, hex"02", baseStem);

        IPopRules popRules = IPopRules(preUpgradePopRules);
        (address aliceHolder,) = popRules.getBaseNameReservation(baseStem);
        assertEq(aliceHolder, alice);

        vm.prank(alice);
        popController.relinquishReservation();

        (address bobHolder, uint64 expires) = popRules.getBaseNameReservation(baseStem);
        assertEq(bobHolder, bob);
        assertGt(expires, block.timestamp);
    }

    // Live-state variant of `_advanceExpiredHead` sync. After both entries age
    // out of the local controller window, the invariant holds: PopRules never
    // points at the evicted head.
    function test_head_expiry_promotes_successor_in_pop_rules() public {
        string memory baseStem = "forkexpirestem";

        vm.prank(popGateway);
        popController.reserveBaseName("forke142", alice, hex"01", baseStem);
        vm.prank(popGateway);
        popController.reserveBaseName("forke242", bob, hex"02", baseStem);

        IPopRules popRules = IPopRules(preUpgradePopRules);
        vm.warp(block.timestamp + 100 weeks);

        vm.prank(popGateway);
        popController.expireReservation(baseStem);

        (address holder,) = popRules.getBaseNameReservation(baseStem);
        assertTrue(holder != alice);
    }

    // Rotating the PoP controller via `protocolRegistry.set` must immediately
    // lock the old controller out of resolver writes on the live deployment.
    // Unit coverage exists (`test_rotating_pop_controller_changes_authorised_writer`),
    // but rotation is a governance-time action on the registry and the fork is
    // the only surface that proves the live state picks the swap up.
    function test_rotating_pop_controller_locks_out_old_controller() public {
        address replacement = makeAddr("replacementPopController");

        vm.prank(OwnableUpgradeable(address(registry)).owner());
        registry.set(DotnsConstants.POP_CONTROLLER, replacement);

        vm.prank(address(popController));
        vm.expectRevert();
        popResolver.setChatKey(_nodeOf("forkalice42"), hex"01");
    }

    function _nodeOf(string memory label) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(DotnsConstants.DOT_NODE, keccak256(bytes(label))));
    }
}
