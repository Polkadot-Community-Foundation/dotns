// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {
    DotnsProtocolRegistry,
    IDotnsProtocolRegistry
} from "../contracts/registry/DotnsProtocolRegistry.sol";
import {DotnsRegistry} from "../contracts/registry/DotnsRegistry.sol";
import {DotnsRegistrar} from "../contracts/registrars/DotnsRegistrar.sol";
import {DotnsRegistrarController} from "../contracts/registrars/DotnsRegistrarController.sol";
import {DotnsReverseResolver} from "../contracts/resolvers/DotnsReverseResolver.sol";
import {DotnsResolver} from "../contracts/resolvers/DotnsResolver.sol";
import {DotnsContentResolver} from "../contracts/resolvers/DotnsContentResolver.sol";
import {PopRules} from "../contracts/pop/PopRules.sol";

/// @title UpgradeProtocolRegistry
/// @notice Upgrades all DotNS contracts to use the protocol registry for sibling resolution.
/// @dev Reads proxy addresses from the on-chain protocol registry. Each upgrade uses
///      Options.referenceContract for OZ storage layout validation.
contract UpgradeProtocolRegistry is Script {
    address constant PROTOCOL_REGISTRY = 0xF8531342444fAC0A75719130eECcf45314584EFe;
    address constant CONTROLLER_PROXY = 0xd09e0F1c1E6CE8Cf40df929ef4FC778629573651;

    function run() external {
        DotnsProtocolRegistry protocolRegistry = DotnsProtocolRegistry(PROTOCOL_REGISTRY);

        // forge-lint: disable-next-line(unsafe-typecast)
        address registryProxy = protocolRegistry.get(bytes32("registry"));
        // forge-lint: disable-next-line(unsafe-typecast)
        address reverseResolverProxy = protocolRegistry.get(bytes32("reverseResolver"));
        // forge-lint: disable-next-line(unsafe-typecast)
        address popRulesProxy = protocolRegistry.get(bytes32("popRules"));
        // forge-lint: disable-next-line(unsafe-typecast)
        address resolverProxy = protocolRegistry.get(bytes32("resolver"));
        // forge-lint: disable-next-line(unsafe-typecast)
        address contentResolverProxy = protocolRegistry.get(bytes32("contentResolver"));

        vm.startBroadcast(msg.sender);

        // ProtocolRegistry is NOT upgraded -- it is a generic key-value store
        // and new keys (resolver, contentResolver) are set via existing set().

        // 1. Upgrade DotnsRegistrar
        // forge-lint: disable-next-line(unsafe-typecast)
        address registrarProxy = protocolRegistry.get(bytes32("registrar"));

        Options memory registrarOpts;
        registrarOpts.referenceContract = "DotnsRegistrarOld.sol:DotnsRegistrarOld";
        Upgrades.upgradeProxy(
            registrarProxy, "DotnsRegistrar.sol:DotnsRegistrar", "", registrarOpts
        );
        DotnsRegistrar(registrarProxy).updateProtocolRegistry(
            IDotnsProtocolRegistry(PROTOCOL_REGISTRY)
        );
        console.log("Registrar upgraded. Version:", DotnsRegistrar(registrarProxy).version());

        // 2. Upgrade DotnsRegistrarController
        Options memory controllerOpts;
        controllerOpts.referenceContract =
            "DotnsRegistrarControllerOld.sol:DotnsRegistrarControllerOld";
        Upgrades.upgradeProxy(
            CONTROLLER_PROXY,
            "DotnsRegistrarController.sol:DotnsRegistrarController",
            "",
            controllerOpts
        );
        DotnsRegistrarController(CONTROLLER_PROXY).updateProtocolRegistry(
            IDotnsProtocolRegistry(PROTOCOL_REGISTRY)
        );
        console.log(
            "Controller upgraded. Version:",
            DotnsRegistrarController(CONTROLLER_PROXY).version()
        );

        // 3. Upgrade DotnsRegistry
        Options memory registryOpts;
        registryOpts.referenceContract = "DotnsRegistryOld.sol:DotnsRegistryOld";
        Upgrades.upgradeProxy(
            registryProxy, "DotnsRegistry.sol:DotnsRegistry", "", registryOpts
        );
        DotnsRegistry(registryProxy).updateProtocolRegistry(
            IDotnsProtocolRegistry(PROTOCOL_REGISTRY)
        );
        console.log("Registry upgraded. Version:", DotnsRegistry(registryProxy).version());

        // 4. Upgrade DotnsReverseResolver
        Options memory reverseOpts;
        reverseOpts.referenceContract = "DotnsReverseResolverOld.sol:DotnsReverseResolverOld";
        Upgrades.upgradeProxy(
            reverseResolverProxy,
            "DotnsReverseResolver.sol:DotnsReverseResolver",
            "",
            reverseOpts
        );
        DotnsReverseResolver(reverseResolverProxy).updateProtocolRegistry(
            IDotnsProtocolRegistry(PROTOCOL_REGISTRY)
        );
        console.log(
            "ReverseResolver upgraded. Version:",
            DotnsReverseResolver(reverseResolverProxy).version()
        );

        // 5. Upgrade PopRules
        Options memory popOpts;
        popOpts.referenceContract = "PopRulesOld.sol:PopRulesOld";
        Upgrades.upgradeProxy(popRulesProxy, "PopRules.sol:PopRules", "", popOpts);
        PopRules(popRulesProxy).updateProtocolRegistry(
            IDotnsProtocolRegistry(PROTOCOL_REGISTRY)
        );
        console.log("PopRules upgraded. Version:", PopRules(popRulesProxy).version());

        // 6. Upgrade DotnsResolver
        Options memory resolverOpts;
        resolverOpts.referenceContract = "DotnsResolverOld.sol:DotnsResolverOld";
        Upgrades.upgradeProxy(
            resolverProxy, "DotnsResolver.sol:DotnsResolver", "", resolverOpts
        );
        DotnsResolver(resolverProxy).updateProtocolRegistry(
            IDotnsProtocolRegistry(PROTOCOL_REGISTRY)
        );
        console.log(
            "Resolver upgraded. Version:", DotnsResolver(resolverProxy).version()
        );

        // 7. Upgrade DotnsContentResolver
        Options memory contentOpts;
        contentOpts.referenceContract = "DotnsContentResolverOld.sol:DotnsContentResolverOld";
        Upgrades.upgradeProxy(
            contentResolverProxy,
            "DotnsContentResolver.sol:DotnsContentResolver",
            "",
            contentOpts
        );
        DotnsContentResolver(contentResolverProxy).updateProtocolRegistry(
            IDotnsProtocolRegistry(PROTOCOL_REGISTRY)
        );
        console.log(
            "ContentResolver upgraded. Version:",
            DotnsContentResolver(contentResolverProxy).version()
        );

        vm.stopBroadcast();
    }
}
