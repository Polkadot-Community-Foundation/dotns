// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {
    DotnsProtocolRegistry,
    IDotnsProtocolRegistry
} from "../../contracts/registry/DotnsProtocolRegistry.sol";
import {DotnsRegistry, IDotnsRegistry} from "../../contracts/registry/DotnsRegistry.sol";
import {
    DotnsRegistrarController,
    IDotnsRegistrarController
} from "../../contracts/registrars/DotnsRegistrarController.sol";
import {DotnsRegistrar} from "../../contracts/registrars/DotnsRegistrar.sol";
import {DotnsReverseResolver} from "../../contracts/resolvers/DotnsReverseResolver.sol";
import {DotnsResolver} from "../../contracts/resolvers/DotnsResolver.sol";
import {DotnsContentResolver} from "../../contracts/resolvers/DotnsContentResolver.sol";
import {PopRules, IPopRules} from "../../contracts/pop/PopRules.sol";

/// @title UpgradeProtocolRegistryForkTest
/// @notice Fork tests against live Paseo AssetHub that mirror the upgrade script step-by-step.
/// @dev Every upgrade call uses Upgrades.upgradeProxy() with Options.referenceContract
///      so OZ validates storage layout compatibility as part of the test.
contract UpgradeProtocolRegistryForkTest is Test {
    address constant PROTOCOL_REGISTRY = 0xF8531342444fAC0A75719130eECcf45314584EFe;
    address constant CONTROLLER_PROXY = 0xd09e0F1c1E6CE8Cf40df929ef4FC778629573651;
    address constant REGISTRAR_PROXY = 0x329aAA5b6bEa94E750b2dacBa74Bf41291E6c2BD;
    address constant OWNER = 0xD908E5A6C88E9263f8fd0756Bd0b77916008bb72;

    DotnsProtocolRegistry public protocolRegistry;
    DotnsRegistrarController public controller;
    DotnsRegistrar public registrar;
    DotnsRegistry public registry;
    DotnsReverseResolver public reverseResolver;
    DotnsResolver public resolver;
    DotnsContentResolver public contentResolver;
    PopRules public popRules;
    address public storeFactoryAddr;

    bytes32 private constant DOT_NODE =
        0x3fce7d1364a893e213bc4212792b517ffc88f5b13b86c8ef9c8d390c3a1370ce;

    function setUp() public {
        vm.createSelectFork("paseo_local");

        protocolRegistry = DotnsProtocolRegistry(PROTOCOL_REGISTRY);
        controller = DotnsRegistrarController(CONTROLLER_PROXY);
        registrar = DotnsRegistrar(REGISTRAR_PROXY);

        // forge-lint: disable-next-line(unsafe-typecast)
        address registryAddr = protocolRegistry.get(bytes32("registry"));
        // forge-lint: disable-next-line(unsafe-typecast)
        address reverseResolverAddr = protocolRegistry.get(bytes32("reverseResolver"));
        // forge-lint: disable-next-line(unsafe-typecast)
        address popRulesAddr = protocolRegistry.get(bytes32("popRules"));
        // forge-lint: disable-next-line(unsafe-typecast)
        storeFactoryAddr = protocolRegistry.get(bytes32("storeFactory"));

        registry = DotnsRegistry(registryAddr);
        reverseResolver = DotnsReverseResolver(reverseResolverAddr);
        popRules = PopRules(popRulesAddr);
    }

    function _upgradeAll() internal {
        // ProtocolRegistry is NOT upgraded -- it is a generic key-value store
        // and new keys (resolver, contentResolver) are set via existing set().

        // forge-lint: disable-next-line(unsafe-typecast)
        address resolverProxy = protocolRegistry.get(bytes32("resolver"));
        // forge-lint: disable-next-line(unsafe-typecast)
        address contentResolverProxy = protocolRegistry.get(bytes32("contentResolver"));

        resolver = DotnsResolver(resolverProxy);
        contentResolver = DotnsContentResolver(contentResolverProxy);

        Options memory registrarOpts;
        registrarOpts.referenceContract = "DotnsRegistrarOld.sol:DotnsRegistrarOld";
        Upgrades.upgradeProxy(REGISTRAR_PROXY, "DotnsRegistrar.sol:DotnsRegistrar", "", registrarOpts);
        registrar.updateProtocolRegistry(IDotnsProtocolRegistry(PROTOCOL_REGISTRY));

        Options memory controllerOpts;
        controllerOpts.referenceContract =
        "DotnsRegistrarControllerOld.sol:DotnsRegistrarControllerOld";
        Upgrades.upgradeProxy(
            CONTROLLER_PROXY,
            "DotnsRegistrarController.sol:DotnsRegistrarController",
            "",
            controllerOpts
        );
        controller.updateProtocolRegistry(IDotnsProtocolRegistry(PROTOCOL_REGISTRY));

        Options memory registryOpts;
        registryOpts.referenceContract = "DotnsRegistryOld.sol:DotnsRegistryOld";
        Upgrades.upgradeProxy(
            address(registry), "DotnsRegistry.sol:DotnsRegistry", "", registryOpts
        );
        registry.updateProtocolRegistry(IDotnsProtocolRegistry(PROTOCOL_REGISTRY));

        Options memory reverseOpts;
        reverseOpts.referenceContract = "DotnsReverseResolverOld.sol:DotnsReverseResolverOld";
        Upgrades.upgradeProxy(
            address(reverseResolver),
            "DotnsReverseResolver.sol:DotnsReverseResolver",
            "",
            reverseOpts
        );
        reverseResolver.updateProtocolRegistry(IDotnsProtocolRegistry(PROTOCOL_REGISTRY));

        Options memory popOpts;
        popOpts.referenceContract = "PopRulesOld.sol:PopRulesOld";
        Upgrades.upgradeProxy(address(popRules), "PopRules.sol:PopRules", "", popOpts);
        popRules.updateProtocolRegistry(IDotnsProtocolRegistry(PROTOCOL_REGISTRY));

        Options memory resolverOpts;
        resolverOpts.referenceContract = "DotnsResolverOld.sol:DotnsResolverOld";
        Upgrades.upgradeProxy(resolverProxy, "DotnsResolver.sol:DotnsResolver", "", resolverOpts);
        DotnsResolver(resolverProxy)
            .updateProtocolRegistry(IDotnsProtocolRegistry(PROTOCOL_REGISTRY));

        Options memory contentOpts;
        contentOpts.referenceContract = "DotnsContentResolverOld.sol:DotnsContentResolverOld";
        Upgrades.upgradeProxy(
            contentResolverProxy, "DotnsContentResolver.sol:DotnsContentResolver", "", contentOpts
        );
        DotnsContentResolver(contentResolverProxy)
            .updateProtocolRegistry(IDotnsProtocolRegistry(PROTOCOL_REGISTRY));
    }

    function test_upgrade_and_wire_all_contracts() public {
        vm.startPrank(OWNER);
        _upgradeAll();
        vm.stopPrank();

        assertEq(controller.version(), "1.3.0");
        assertEq(registry.version(), "1.2.0");
        assertEq(reverseResolver.version(), "1.1.0");
        assertEq(popRules.version(), "1.1.0");

        assertEq(address(controller.protocolRegistry()), PROTOCOL_REGISTRY);
        assertEq(address(registry.protocolRegistry()), PROTOCOL_REGISTRY);
        assertEq(address(reverseResolver.protocolRegistry()), PROTOCOL_REGISTRY);
        assertEq(address(popRules.protocolRegistry()), PROTOCOL_REGISTRY);
    }

    function test_registration_flow_post_upgrade() public {
        vm.startPrank(OWNER);
        _upgradeAll();
        vm.stopPrank();

        address registrant = makeAddr("registrant");
        vm.deal(registrant, 10 ether);

        vm.prank(registrant);
        popRules.setUserPopStatus(IPopRules.PopStatus.PopFull);

        string memory label = "forktestreg";
        bytes32 secret = keccak256(abi.encodePacked(label, registrant, block.timestamp));

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label, owner: registrant, secret: secret, reserved: true
            });

        bytes32 commitment = controller.makeCommitment(registration);

        vm.prank(registrant);
        controller.commit(commitment);

        vm.warp(block.timestamp + controller.minCommitmentAge() + 1);

        IPopRules.PriceWithMeta memory priced = popRules.priceWithCheck(label, registrant);

        vm.prank(registrant);
        controller.register{value: priced.price}(registration);

        bytes32 labelhash = keccak256(bytes(label));
        bytes32 node = keccak256(abi.encodePacked(DOT_NODE, labelhash));
        uint256 tokenId = uint256(node);

        assertEq(registrar.ownerOf(tokenId), registrant);
        assertEq(registry.owner(node), registrant);
        assertEq(
            keccak256(bytes(reverseResolver.nameOf(registrant))),
            keccak256(bytes(string.concat(label, ".dot")))
        );
    }

    function test_existing_state_preserved() public {
        // forge-lint: disable-next-line(unsafe-typecast)
        address registryAddr = protocolRegistry.get(bytes32("registry"));
        bool rootExists = DotnsRegistry(registryAddr).recordExists(bytes32(0));

        // forge-lint: disable-next-line(unsafe-typecast)
        address controllerAddr = protocolRegistry.get(bytes32("controller"));
        assertEq(controllerAddr, CONTROLLER_PROXY);

        // forge-lint: disable-next-line(unsafe-typecast)
        address registrarAddr = protocolRegistry.get(bytes32("registrar"));
        assertEq(registrarAddr, REGISTRAR_PROXY);

        vm.startPrank(OWNER);
        _upgradeAll();
        vm.stopPrank();

        assertEq(DotnsRegistry(registryAddr).recordExists(bytes32(0)), rootExists);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(protocolRegistry.get(bytes32("controller")), CONTROLLER_PROXY);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(protocolRegistry.get(bytes32("registrar")), REGISTRAR_PROXY);
    }

    function test_protocol_registry_update_propagates() public {
        vm.startPrank(OWNER);
        _upgradeAll();

        address mockStoreFactory = makeAddr("mockStoreFactory");

        // forge-lint: disable-next-line(unsafe-typecast)
        address oldFactory = protocolRegistry.get(bytes32("storeFactory"));
        assertTrue(oldFactory != address(0));

        // forge-lint: disable-next-line(unsafe-typecast)
        protocolRegistry.set(bytes32("storeFactory"), mockStoreFactory);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(protocolRegistry.get(bytes32("storeFactory")), mockStoreFactory);

        // Restore original
        // forge-lint: disable-next-line(unsafe-typecast)
        protocolRegistry.set(bytes32("storeFactory"), oldFactory);

        vm.stopPrank();
    }

    function test_register_reserved_post_upgrade() public {
        vm.startPrank(OWNER);
        _upgradeAll();

        address whitelisted = makeAddr("whitelisted");
        controller.whiteListAddress(whitelisted, true);
        vm.stopPrank();

        assertTrue(controller.isWhiteListed(whitelisted));

        address recipient = makeAddr("reservedRecipient");
        vm.deal(recipient, 10 ether);

        string memory label = "forkrsrvd";
        bytes32 secret = keccak256(abi.encodePacked(label, recipient, block.timestamp));

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label, owner: recipient, secret: secret, reserved: true
            });

        bytes32 commitment = controller.makeCommitment(registration);

        vm.prank(recipient);
        controller.commit(commitment);

        vm.warp(block.timestamp + controller.minCommitmentAge() + 1);

        vm.prank(whitelisted);
        controller.registerReserved(registration);

        bytes32 labelhash = keccak256(bytes(label));
        bytes32 node = keccak256(abi.encodePacked(DOT_NODE, labelhash));

        assertEq(registrar.ownerOf(uint256(node)), recipient);
        assertEq(registry.owner(node), recipient);
        assertEq(
            keccak256(bytes(reverseResolver.nameOf(recipient))),
            keccak256(bytes(string.concat(label, ".dot")))
        );
    }

    function test_subname_registration_post_upgrade() public {
        vm.startPrank(OWNER);
        _upgradeAll();
        vm.stopPrank();

        address nameOwner = makeAddr("subnameOwner");
        vm.deal(nameOwner, 10 ether);

        vm.prank(nameOwner);
        popRules.setUserPopStatus(IPopRules.PopStatus.PopFull);

        string memory parentLabel = "forkparent";
        _commitAndRegister(parentLabel, nameOwner);

        bytes32 parentLabelhash = keccak256(bytes(parentLabel));
        bytes32 parentNode = keccak256(abi.encodePacked(DOT_NODE, parentLabelhash));

        address subnameOwner = makeAddr("subnameChild");

        IDotnsRegistry.SubnodeRecord memory subnodeRecord = IDotnsRegistry.SubnodeRecord({
            parentNode: parentNode, subLabel: "child", parentLabel: parentLabel, owner: subnameOwner
        });

        vm.prank(nameOwner);
        bytes32 subnode = registry.setSubnodeOwner(subnodeRecord);

        assertEq(registry.owner(subnode), subnameOwner);
        assertTrue(registry.recordExists(subnode));
    }

    function test_transfer_preserves_store_post_upgrade() public {
        vm.startPrank(OWNER);
        _upgradeAll();
        vm.stopPrank();

        address sender = makeAddr("transferSender");
        address recipient = makeAddr("transferRecipient");
        vm.deal(sender, 10 ether);
        vm.deal(recipient, 10 ether);

        vm.prank(sender);
        popRules.setUserPopStatus(IPopRules.PopStatus.PopFull);

        string memory label = "forkxfer";
        _commitAndRegister(label, sender);

        bytes32 labelhash = keccak256(bytes(label));
        bytes32 node = keccak256(abi.encodePacked(DOT_NODE, labelhash));
        uint256 tokenId = uint256(node);

        assertEq(registrar.ownerOf(tokenId), sender);

        vm.prank(sender);
        registrar.transferFrom(sender, recipient, tokenId);

        assertEq(registrar.ownerOf(tokenId), recipient);
        assertEq(registry.owner(node), recipient);
    }

    function test_dotted_label_is_rejected_post_upgrade() public {
        vm.startPrank(OWNER);
        _upgradeAll();
        vm.stopPrank();

        vm.expectRevert(IDotnsRegistrarController.InvalidLabel.selector);
        controller.available("app.parity01");
    }

    function test_empty_label_is_rejected_post_upgrade() public {
        vm.startPrank(OWNER);
        _upgradeAll();
        vm.stopPrank();

        vm.expectRevert(IDotnsRegistrarController.InvalidLabel.selector);
        controller.available("");
    }

    function test_third_party_cannot_overwrite_reverse_post_upgrade() public {
        vm.startPrank(OWNER);
        _upgradeAll();
        vm.stopPrank();

        address victim = makeAddr("reverseVictim");
        address attacker = makeAddr("reverseAttacker");
        vm.deal(victim, 10 ether);
        vm.deal(attacker, 10 ether);

        _commitAndRegister("forkvictim01", victim);
        assertEq(reverseResolver.nameOf(victim), "forkvictim01.dot");

        _commitAndRegisterFor("forkgifted01", attacker, victim, true);

        bytes32 labelhash = keccak256(bytes("forkgifted01"));
        bytes32 node = keccak256(abi.encodePacked(DOT_NODE, labelhash));

        assertEq(registrar.ownerOf(uint256(node)), victim);
        assertEq(reverseResolver.nameOf(victim), "forkvictim01.dot");
    }

    function test_transfer_clears_former_primary_reverse_post_upgrade() public {
        vm.startPrank(OWNER);
        _upgradeAll();
        vm.stopPrank();

        address sender = makeAddr("reverseSender");
        address recipient = makeAddr("reverseRecipient");
        vm.deal(sender, 10 ether);
        vm.deal(recipient, 10 ether);

        _commitAndRegister("forkclear01", sender);

        bytes32 labelhash = keccak256(bytes("forkclear01"));
        bytes32 node = keccak256(abi.encodePacked(DOT_NODE, labelhash));
        uint256 tokenId = uint256(node);

        assertEq(reverseResolver.nameOf(sender), "forkclear01.dot");

        vm.prank(sender);
        registrar.transferFrom(sender, recipient, tokenId);

        assertEq(registrar.ownerOf(tokenId), recipient);
        assertEq(reverseResolver.nameOf(sender), "");
    }

    function test_removed_rotation_selectors_are_not_callable_post_upgrade() public {
        IDotnsRegistrarController previousReverseRegistrar = reverseResolver.registrarController();
        IDotnsRegistrarController previousRegistryController = registry.registrarController();
        address previousPopController = popRules.dotRegistryController();

        vm.startPrank(OWNER);
        _upgradeAll();

        (bool reverseSuccess,) =
            address(reverseResolver).call(
                abi.encodeWithSignature("updateRegistrar(address)", makeAddr("newRegistrar"))
            );
        (bool registrySuccess,) =
            address(registry).call(
                abi.encodeWithSignature(
                    "updateRegistrarController(address)", makeAddr("newController")
                )
            );
        (bool popSuccess,) =
            address(popRules).call(
                abi.encodeWithSignature("updateDotRegistry(address)", makeAddr("newPopController"))
            );

        vm.stopPrank();

        assertFalse(reverseSuccess);
        assertFalse(registrySuccess);
        assertFalse(popSuccess);

        assertEq(address(reverseResolver.registrarController()), address(previousReverseRegistrar));
        assertEq(address(registry.registrarController()), address(previousRegistryController));
        assertEq(popRules.dotRegistryController(), previousPopController);
    }

    function test_expired_lite_reservation_rolls_forward_post_upgrade() public {
        vm.startPrank(OWNER);
        _upgradeAll();
        vm.stopPrank();

        address first = makeAddr("liteFirst");
        address second = makeAddr("liteSecond");
        address third = makeAddr("liteThird");
        vm.deal(first, 10 ether);
        vm.deal(second, 10 ether);
        vm.deal(third, 10 ether);

        vm.prank(first);
        popRules.setUserPopStatus(IPopRules.PopStatus.PopLite);
        _commitAndRegister("forklite01", first);

        (bool firstReserved, address firstOwner, uint64 firstExpiry) =
            popRules.isBaseNameReserved("forklite");

        assertTrue(firstReserved);
        assertEq(firstOwner, first);

        vm.warp(uint256(firstExpiry) + 1);

        vm.prank(second);
        popRules.setUserPopStatus(IPopRules.PopStatus.PopLite);
        _commitAndRegister("forklite02", second);

        (bool secondReserved, address secondOwner, uint64 secondExpiry) =
            popRules.isBaseNameReserved("forklite");

        assertTrue(secondReserved);
        assertEq(secondOwner, second);
        assertGt(secondExpiry, firstExpiry);

        vm.prank(third);
        popRules.setUserPopStatus(IPopRules.PopStatus.PopLite);

        bytes32 secret = keccak256(abi.encodePacked("forklite03", third, block.timestamp));
        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: "forklite03", owner: third, secret: secret, reserved: true
            });

        bytes32 commitment = controller.makeCommitment(registration);

        vm.prank(third);
        controller.commit(commitment);

        vm.warp(block.timestamp + controller.minCommitmentAge() + 1);

        vm.prank(third);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPopRules.PopError.selector, "Base name reserved for original Lite registrant"
            )
        );
        controller.register{value: 0}(registration);
    }

    function _commitAndRegister(string memory label, address nameOwner) internal {
        _commitAndRegisterFor(label, nameOwner, nameOwner, true);
    }

    function _commitAndRegisterFor(
        string memory label,
        address caller,
        address nameOwner,
        bool reserved
    )
        internal
    {
        bytes32 secret = keccak256(abi.encodePacked(label, nameOwner, block.timestamp));

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label, owner: nameOwner, secret: secret, reserved: reserved
            });

        bytes32 commitment = controller.makeCommitment(registration);

        vm.prank(caller);
        controller.commit(commitment);

        vm.warp(block.timestamp + controller.minCommitmentAge() + 1);

        IPopRules.PriceWithMeta memory priced = popRules.priceWithCheck(label, nameOwner);

        vm.prank(caller);
        controller.register{value: priced.price}(registration);
    }
}
