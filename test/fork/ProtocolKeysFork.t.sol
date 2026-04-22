// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {DotnsProtocolRegistry} from "../../contracts/registry/DotnsProtocolRegistry.sol";
import {DotnsRegistry} from "../../contracts/registry/DotnsRegistry.sol";
import {DotnsRegistrar} from "../../contracts/registrars/DotnsRegistrar.sol";
import {
    DotnsRegistrarController,
    IDotnsRegistrarController
} from "../../contracts/registrars/DotnsRegistrarController.sol";
import {DotnsReverseResolver} from "../../contracts/resolvers/DotnsReverseResolver.sol";
import {DotnsResolver} from "../../contracts/resolvers/DotnsResolver.sol";
import {DotnsContentResolver} from "../../contracts/resolvers/DotnsContentResolver.sol";
import {PopRules, IPopRules} from "../../contracts/pop/PopRules.sol";
import {DotnsConstants} from "../../contracts/utils/DotnsConstants.sol";

import {UpgradeProtocolKeys} from "../../scripts/deploy/UpgradeProtocolKeys.s.sol";

/// @title Protocol keys upgrade fork test — batch 1 (registry + core)
/// @notice Upgrades protocol registry, forward registry, registrar, and controller.
///         Split into two test contracts to stay within EVM memory limits during
///         OZ storage-layout validation (each referenceContract check is an FFI call).
contract ProtocolKeysForkBatch1Test is Test {
    UpgradeProtocolKeys public upgradeScript;

    DotnsProtocolRegistry public protocolRegistry;
    DotnsRegistry public registry;
    DotnsRegistrar public registrar;
    DotnsRegistrarController public controller;
    PopRules public popRules;

    address public owner;
    address public alice;

    function setUp() public {
        vm.createSelectFork("paseo");

        upgradeScript = new UpgradeProtocolKeys();

        protocolRegistry = DotnsProtocolRegistry(upgradeScript.PROTOCOL_REGISTRY_PROXY());
        registry = DotnsRegistry(upgradeScript.REGISTRY_PROXY());
        registrar = DotnsRegistrar(upgradeScript.REGISTRAR_PROXY());
        controller = DotnsRegistrarController(upgradeScript.CONTROLLER_PROXY());
        popRules = PopRules(upgradeScript.POP_RULES_PROXY());

        owner = OwnableUpgradeable(address(protocolRegistry)).owner();

        upgradeScript.upgradeBatch1(owner);

        alice = makeAddr("alice");
        vm.deal(alice, 100 ether);
    }

    function test_batch1_versions_bumped() public view {
        assertEq(protocolRegistry.version(), upgradeScript.PROTOCOL_REGISTRY_VERSION());
        assertEq(registry.version(), upgradeScript.REGISTRY_VERSION());
        assertEq(registrar.version(), upgradeScript.REGISTRAR_VERSION());
        assertEq(controller.version(), upgradeScript.CONTROLLER_VERSION());
    }

    function test_registry_keys_preserved() public view {
        assertTrue(protocolRegistry.get(DotnsConstants.REGISTRAR) != address(0));
        assertTrue(protocolRegistry.get(DotnsConstants.CONTROLLER) != address(0));
        assertTrue(protocolRegistry.get(DotnsConstants.REGISTRY) != address(0));
        assertTrue(protocolRegistry.get(DotnsConstants.REVERSE_RESOLVER) != address(0));
        assertTrue(protocolRegistry.get(DotnsConstants.RESOLVER) != address(0));
        assertTrue(protocolRegistry.get(DotnsConstants.CONTENT_RESOLVER) != address(0));
        assertTrue(protocolRegistry.get(DotnsConstants.POP_RULES) != address(0));
        assertTrue(protocolRegistry.get(DotnsConstants.STORE_FACTORY) != address(0));
    }

    function test_registrar_erc721_metadata_preserved() public view {
        assertEq(registrar.name(), "Dotns");
        assertEq(registrar.symbol(), "Dotns");
    }

    /// @notice End-to-end registration on the partially upgraded system proves core key lookups work.
    /// @dev PopRules is not yet upgraded in batch 1 but still functional (bytecode-only change).
    function test_register_after_batch1_upgrade() public {
        string memory label = "forkbatchone14";
        bytes32 secret = keccak256(abi.encodePacked(label, alice, block.timestamp));

        IDotnsRegistrarController.Registration memory reg = IDotnsRegistrarController.Registration({
            label: label, owner: alice, secret: secret, reserved: false
        });

        bytes32 commitment = controller.makeCommitment(reg);
        vm.prank(alice);
        controller.commit(commitment);

        vm.warp(block.timestamp + controller.minCommitmentAge() + 1);

        uint256 price = popRules.priceWithCheck(label, alice).price;
        vm.prank(alice);
        controller.register{value: price}(reg);

        bytes32 labelhash = keccak256(bytes(label));
        bytes32 node = keccak256(abi.encodePacked(DotnsConstants.DOT_NODE, labelhash));
        uint256 tokenId = uint256(node);

        assertEq(registrar.ownerOf(tokenId), alice, "alice owns the registered name");
        assertFalse(controller.available(label), "name no longer available");
    }
}

/// @title Protocol keys upgrade fork test — batch 2 (resolvers + pop rules)
/// @notice Upgrades reverse resolver, resolver, content resolver, and pop rules.
contract ProtocolKeysForkBatch2Test is Test {
    UpgradeProtocolKeys public upgradeScript;

    DotnsProtocolRegistry public protocolRegistry;
    DotnsReverseResolver public reverseResolver;
    DotnsResolver public resolver;
    DotnsContentResolver public contentResolver;
    PopRules public popRules;

    address public owner;

    function setUp() public {
        vm.createSelectFork("paseo_local");

        upgradeScript = new UpgradeProtocolKeys();

        protocolRegistry = DotnsProtocolRegistry(upgradeScript.PROTOCOL_REGISTRY_PROXY());
        reverseResolver = DotnsReverseResolver(upgradeScript.REVERSE_RESOLVER_PROXY());
        resolver = DotnsResolver(upgradeScript.RESOLVER_PROXY());
        contentResolver = DotnsContentResolver(upgradeScript.CONTENT_RESOLVER_PROXY());
        popRules = PopRules(upgradeScript.POP_RULES_PROXY());

        owner = OwnableUpgradeable(address(protocolRegistry)).owner();

        upgradeScript.upgradeBatch2(owner);
    }

    function test_batch2_versions_bumped() public view {
        assertEq(reverseResolver.version(), upgradeScript.REVERSE_RESOLVER_VERSION());
        assertEq(resolver.version(), upgradeScript.RESOLVER_VERSION());
        assertEq(contentResolver.version(), upgradeScript.CONTENT_RESOLVER_VERSION());
        assertEq(popRules.version(), upgradeScript.POP_RULES_VERSION());
    }
}
