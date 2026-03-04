// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {DotnsRegistrar} from "../../contracts/registrars/DotnsRegistrar.sol";
import {
    DotnsProtocolRegistry,
    IDotnsProtocolRegistry
} from "../../contracts/registry/DotnsProtocolRegistry.sol";

/// @title DeployProtocolRegistryForkTest
/// @notice Simulates the full upgrade against the live paseo-assethub chain.
/// @dev Forks the live chain, upgrades the registrar to the new implementation
///      (which includes `updateProtocolRegistry`), deploys the protocol registry,
///      wires all addresses, and verifies correctness.
contract DeployProtocolRegistryForkTest is Test {
    address constant REGISTRAR = 0x329aAA5b6bEa94E750b2dacBa74Bf41291E6c2BD;
    address constant CONTROLLER = 0xd09e0F1c1E6CE8Cf40df929ef4FC778629573651;
    address constant REGISTRY = 0x4Da0d37aBe96C06ab19963F31ca2DC0412057a6f;
    address constant REVERSE_RESOLVER = 0x95D57363B491CF743970c640fe419541386ac8BF;
    address constant RESOLVER = 0x95645C7fD0fF38790647FE13F87Eb11c1DCc8514;
    address constant CONTENT_RESOLVER = 0x7756DF72CBc7f062e7403cD59e45fBc78bed1cD7;
    address constant STORE_FACTORY = 0x030296782F4d3046B080BcB017f01837561D9702;
    address constant POP_RULES = 0x4e8920B1E69d0cEA9b23CBFC87A17Ee6fE02d2d3;

    DotnsRegistrar public dotnsRegistrar;
    DotnsProtocolRegistry public protocolRegistry;
    address public registrarOwner;

    function setUp() public {
        vm.createSelectFork("paseo");

        dotnsRegistrar = DotnsRegistrar(REGISTRAR);
        registrarOwner = dotnsRegistrar.owner();

        // Step 1: Upgrade the registrar proxy to the new implementation.
        // The deployed registrar does not have `updateProtocolRegistry` yet.
        // Reference the old deployed contract for storage layout validation.
        Options memory opts;
        opts.referenceContract = "DotnsRegistrarOld.sol:DotnsRegistrarOld";
        Upgrades.upgradeProxy(
            REGISTRAR,
            "DotnsRegistrar.sol:DotnsRegistrar",
            "",
            opts,
            registrarOwner
        );

        vm.startPrank(registrarOwner);

        // Step 2: Deploy the protocol registry.
        address protocolRegistryProxy = Upgrades.deployUUPSProxy(
            "DotnsProtocolRegistry.sol:DotnsProtocolRegistry",
            abi.encodeCall(DotnsProtocolRegistry.initialize, ())
        );
        protocolRegistry = DotnsProtocolRegistry(protocolRegistryProxy);

        // Step 3: Wire all existing contract addresses.
        // casting to 'bytes32' is safe because all key strings fit in 32 bytes
        // forge-lint: disable-next-line(unsafe-typecast)
        protocolRegistry.set(bytes32("registrar"), REGISTRAR);
        // forge-lint: disable-next-line(unsafe-typecast)
        protocolRegistry.set(bytes32("controller"), CONTROLLER);
        // forge-lint: disable-next-line(unsafe-typecast)
        protocolRegistry.set(bytes32("registry"), REGISTRY);
        // forge-lint: disable-next-line(unsafe-typecast)
        protocolRegistry.set(bytes32("reverseResolver"), REVERSE_RESOLVER);
        // forge-lint: disable-next-line(unsafe-typecast)
        protocolRegistry.set(bytes32("resolver"), RESOLVER);
        // forge-lint: disable-next-line(unsafe-typecast)
        protocolRegistry.set(bytes32("contentResolver"), CONTENT_RESOLVER);
        // forge-lint: disable-next-line(unsafe-typecast)
        protocolRegistry.set(bytes32("storeFactory"), STORE_FACTORY);
        // forge-lint: disable-next-line(unsafe-typecast)
        protocolRegistry.set(bytes32("popRules"), POP_RULES);

        // Step 4: Point the registrar to the new protocol registry.
        dotnsRegistrar.updateProtocolRegistry(
            IDotnsProtocolRegistry(protocolRegistryProxy)
        );

        vm.stopPrank();
    }

    function test_protocol_registry_returns_correct_addresses() public view {
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(protocolRegistry.get(bytes32("registrar")), REGISTRAR);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(protocolRegistry.get(bytes32("controller")), CONTROLLER);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(protocolRegistry.get(bytes32("registry")), REGISTRY);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(protocolRegistry.get(bytes32("reverseResolver")), REVERSE_RESOLVER);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(protocolRegistry.get(bytes32("resolver")), RESOLVER);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(protocolRegistry.get(bytes32("contentResolver")), CONTENT_RESOLVER);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(protocolRegistry.get(bytes32("storeFactory")), STORE_FACTORY);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(protocolRegistry.get(bytes32("popRules")), POP_RULES);
    }

    function test_registrar_points_to_protocol_registry() public view {
        assertEq(
            address(dotnsRegistrar.protocolRegistry()),
            address(protocolRegistry)
        );
    }

    function test_protocol_registry_owned_by_deployer() public view {
        assertEq(protocolRegistry.owner(), registrarOwner);
    }

    function test_protocol_registry_version() public view {
        assertEq(protocolRegistry.version(), "1.0.0");
    }

    function test_registrar_version_after_upgrade() public view {
        assertEq(dotnsRegistrar.version(), "1.1.0");
    }

    function test_unset_key_returns_zero_address() public view {
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(protocolRegistry.get(bytes32("nonexistent")), address(0));
    }

    function test_non_owner_cannot_set() public {
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert();
        // forge-lint: disable-next-line(unsafe-typecast)
        protocolRegistry.set(bytes32("registrar"), address(1));
    }
}
