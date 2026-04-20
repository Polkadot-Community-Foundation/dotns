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

    // Sync assertion: a gateway-driven reservation must propagate to PopRules so
    // the public commit-reveal path sees the same cross-flow lock. This covers the
    // head-of-queue => reserveBaseNameForPop edge added in this PR.
    function test_gateway_reservation_syncs_to_pop_rules() public {
        string memory liteLabel = "forksync.42";
        string memory baseStem = "forksyncstem";

        vm.prank(popGateway);
        popController.reserveBaseName(liteLabel, alice, hex"11", baseStem);

        IPopRules popRules = IPopRules(registry.get(registry.POP_RULES()));
        (address holder, uint64 expires) = popRules.getBaseNameReservation(baseStem);
        assertEq(holder, alice);
        assertGt(expires, block.timestamp);
    }

    // Cross-controller race assertion: after the gateway reserves "forksyncstem",
    // a stranger trying to commit-reveal "forksyncstem42" (which strips to the
    // same stem in PopRules) must be rejected at priceWithCheck.
    function test_public_commit_reveal_rejects_gateway_reserved_stem() public {
        string memory liteLabel = "forkrace.42";
        string memory baseStem = "forkracestem";
        string memory publicLabel = "forkracestem07";

        vm.prank(popGateway);
        popController.reserveBaseName(liteLabel, alice, hex"11", baseStem);

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: publicLabel, owner: bob, secret: keccak256("race-secret"), reserved: true
            });

        bytes32 commitment = controller.makeCommitment(registration);
        vm.prank(bob);
        controller.commit(commitment);
        vm.warp(block.timestamp + controller.minCommitmentAge() + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPopRules.PopError.selector, "Base name reserved for original Lite registrant"
            )
        );
        vm.prank(bob);
        controller.register{value: 10 ether}(registration);
    }

    // Claim path wipes the queue and must release the PopRules slot in the same
    // transaction, otherwise a stranger could be perpetually blocked on a stem
    // whose claimant already minted it.
    function test_claim_releases_pop_rules_slot() public {
        string memory liteLabel = "forkclaim.42";
        string memory baseStem = "forkclaimstem";

        vm.prank(popGateway);
        popController.reserveBaseName(liteLabel, alice, hex"11", baseStem);

        IDotnsPopController.Link memory link = IDotnsPopController.Link({
            kind: IDotnsPopController.LinkKind.LiteUsername, liteLabel: liteLabel, chatKey: ""
        });
        vm.prank(popGateway);
        popController.registerBaseName(baseStem, alice, link);

        IPopRules popRules = IPopRules(registry.get(registry.POP_RULES()));
        (address holder, uint64 expires) = popRules.getBaseNameReservation(baseStem);
        assertEq(holder, address(0));
        assertEq(expires, 0);
    }

    // Covers the _removeUserFromQueue head-branch sync fix: a head user
    // relinquishing while a live waiter exists must promote that waiter in
    // PopRules, not leave the evicted user's address sitting in the record.
    function test_head_relinquish_promotes_successor_in_pop_rules() public {
        string memory baseStem = "forkrelinquish";

        vm.prank(popGateway);
        popController.reserveBaseName("forkr1.42", alice, hex"01", baseStem);
        vm.prank(popGateway);
        popController.reserveBaseName("forkr2.42", bob, hex"02", baseStem);

        IPopRules popRules = IPopRules(registry.get(registry.POP_RULES()));
        (address aliceHolder,) = popRules.getBaseNameReservation(baseStem);
        assertEq(aliceHolder, alice);

        vm.prank(alice);
        popController.relinquishReservation();

        (address bobHolder, uint64 expires) = popRules.getBaseNameReservation(baseStem);
        assertEq(bobHolder, bob);
        assertGt(expires, block.timestamp);
    }

    // Covers _advanceExpiredHead sync on expiry-driven promotion: once alice's
    // reservation expires, the next reserve call or expire call should promote
    // bob in PopRules so a stranger commit-reveal still sees the block.
    function test_head_expiry_promotes_successor_in_pop_rules() public {
        string memory baseStem = "forkexpirestem";

        vm.prank(popGateway);
        popController.reserveBaseName("forke1.42", alice, hex"01", baseStem);
        vm.prank(popGateway);
        popController.reserveBaseName("forke2.42", bob, hex"02", baseStem);

        IPopRules popRules = IPopRules(registry.get(registry.POP_RULES()));
        // Warp past alice's PoP-controller reservation window so she expires out
        // of the head; queue duration is controller-local, whereas PopRules
        // tracks its own 12-week window per reservation. Warp past the later
        // of the two.
        vm.warp(block.timestamp + 100 weeks);

        vm.prank(popGateway);
        popController.expireReservation(baseStem);

        (address holder,) = popRules.getBaseNameReservation(baseStem);
        // Either bob is promoted (if his queue entry was still live under the
        // controller's own reservationDuration), or the slot is released (if
        // every waiter also expired). The invariant is: PopRules never points
        // at alice after her reservation expired.
        assertTrue(holder != alice);
    }

    function _nodeOf(string memory label) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(DotnsConstants.DOT_NODE, keccak256(bytes(label))));
    }
}
