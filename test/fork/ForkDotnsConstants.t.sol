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
import {DotnsResolver} from "../../contracts/resolvers/DotnsResolver.sol";
import {DotnsContentResolver} from "../../contracts/resolvers/DotnsContentResolver.sol";
import {DotnsReverseResolver} from "../../contracts/resolvers/DotnsReverseResolver.sol";
import {DotnsConstants} from "../../contracts/utils/DotnsConstants.sol";
import {
    KEY_CONTROLLER,
    KEY_REGISTRAR,
    KEY_REGISTRY,
    KEY_REVERSE_RESOLVER,
    KEY_POP_RULES,
    KEY_STORE_FACTORY
} from "../../contracts/registry/IDotnsProtocolRegistry.sol";
import {UpgradeConstants} from "../../scripts/UpgradeConstants.s.sol";

/// @title Fork test for DotnsConstants centralisation upgrade
/// @notice Forks live Paseo AssetHub, upgrades all contracts using the deploy
///         script, then validates post-upgrade behaviour.
contract ForkDotnsConstantsTest is Test {
    // Deployed Paseo AssetHub addresses
    address constant REGISTRY_PROXY = 0x4Da0d37aBe96C06ab19963F31ca2DC0412057a6f;
    address constant REGISTRAR_PROXY = 0x329aAA5b6bEa94E750b2dacBa74Bf41291E6c2BD;
    address constant CONTROLLER_PROXY = 0xd09e0F1c1E6CE8Cf40df929ef4FC778629573651;
    address constant POP_RULES_PROXY = 0x4e8920B1E69d0cEA9b23CBFC87A17Ee6fE02d2d3;
    address constant RESOLVER_PROXY = 0x95645C7fD0fF38790647FE13F87Eb11c1DCc8514;
    address constant CONTENT_RESOLVER_PROXY = 0x7756DF72CBc7f062e7403cD59e45fBc78bed1cD7;
    address constant REVERSE_RESOLVER_PROXY = 0x95D57363B491CF743970c640fe419541386ac8BF;

    DotnsRegistry public registry;
    DotnsRegistrar public registrar;
    DotnsRegistrarController public controller;
    PopRules public popRules;
    DotnsResolver public resolver;
    DotnsContentResolver public contentResolver;
    DotnsReverseResolver public reverseResolver;

    UpgradeConstants public upgradeScript;

    address public proxyAdmin;
    address public userA;
    address public userB;

    function setUp() public {
        vm.createSelectFork("paseo");

        registry = DotnsRegistry(REGISTRY_PROXY);
        registrar = DotnsRegistrar(REGISTRAR_PROXY);
        controller = DotnsRegistrarController(CONTROLLER_PROXY);
        popRules = PopRules(POP_RULES_PROXY);
        resolver = DotnsResolver(RESOLVER_PROXY);
        contentResolver = DotnsContentResolver(CONTENT_RESOLVER_PROXY);
        reverseResolver = DotnsReverseResolver(REVERSE_RESOLVER_PROXY);

        proxyAdmin = OwnableUpgradeable(REGISTRY_PROXY).owner();
        userA = makeAddr("userA");
        userB = makeAddr("userB");
        vm.deal(userA, 100 ether);
        vm.deal(userB, 100 ether);

        upgradeScript = new UpgradeConstants();

        upgradeScript.upgradeRegistry(REGISTRY_PROXY, proxyAdmin);
        upgradeScript.upgradeRegistrar(REGISTRAR_PROXY, proxyAdmin);
        upgradeScript.upgradeController(CONTROLLER_PROXY, proxyAdmin);
        upgradeScript.upgradePopRules(POP_RULES_PROXY, proxyAdmin);
        upgradeScript.upgradeResolver(RESOLVER_PROXY, proxyAdmin);
        upgradeScript.upgradeContentResolver(CONTENT_RESOLVER_PROXY, proxyAdmin);
        upgradeScript.upgradeReverseResolver(REVERSE_RESOLVER_PROXY, proxyAdmin);

        upgradeScript.verifyAll();
    }

    function test_root_record_intact_after_upgrade() public view {
        assertTrue(registry.recordExists(bytes32(0)));
        assertTrue(registry.owner(bytes32(0)) != address(0));
    }

    function test_registrar_name_intact() public view {
        assertEq(registrar.name(), "Dotns");
        assertEq(registrar.symbol(), "Dotns");
    }

    function test_controller_commitment_ages_intact() public view {
        assertTrue(controller.minCommitmentAge() > 0);
        assertTrue(controller.maxCommitmentAge() > controller.minCommitmentAge());
    }

    function test_pop_rules_starting_price_intact() public view {
        assertTrue(popRules.startingPrice() > 0);
    }

    function test_dotNode_matches_namehash() public pure {
        bytes32 dotLabel = keccak256(bytes("dot"));
        bytes32 expected = keccak256(abi.encodePacked(bytes32(0), dotLabel));
        assertEq(DotnsConstants.DOT_NODE, expected);
    }

    function test_protocolRegistryKeys() public pure {
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(KEY_CONTROLLER, bytes32("controller"));
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(KEY_REGISTRAR, bytes32("registrar"));
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(KEY_REGISTRY, bytes32("registry"));
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(KEY_REVERSE_RESOLVER, bytes32("reverseResolver"));
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(KEY_POP_RULES, bytes32("popRules"));
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(KEY_STORE_FACTORY, bytes32("storeFactory"));
    }

    function test_full_registration_flow_after_upgrade() public {
        string memory label = "constantstest";
        bytes32 node = _register(label, userA);

        // Registrar minted the token
        assertEq(registrar.ownerOf(uint256(node)), userA);

        // Registry has the record
        assertTrue(registry.recordExists(node));
    }

    function test_subnode_creation_after_upgrade() public {
        string memory label = "constantssub";
        bytes32 node = _register(label, userA);

        IDotnsRegistry.SubnodeRecord memory record = IDotnsRegistry.SubnodeRecord({
            parentNode: node, subLabel: "app", parentLabel: label, owner: userB
        });

        vm.prank(userA);
        bytes32 subnode = registry.setSubnodeOwner(record);
        assertEq(registry.owner(subnode), userB);
    }

    function test_resolver_set_after_upgrade() public {
        string memory label = "constantsres";
        bytes32 node = _register(label, userA);

        vm.prank(userA);
        resolver.setAddress(node, userA);
        assertEq(resolver.addressOf(node), userA);
    }

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

        node = keccak256(abi.encodePacked(DotnsConstants.DOT_NODE, keccak256(bytes(label))));
    }
}
