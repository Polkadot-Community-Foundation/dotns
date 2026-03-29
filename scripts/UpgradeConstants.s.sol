// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/Script.sol";
import {BaseDeployer} from "./BaseDeployer.s.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

import {DotnsRegistry} from "../contracts/registry/DotnsRegistry.sol";
import {DotnsRegistrar} from "../contracts/registrars/DotnsRegistrar.sol";
import {DotnsRegistrarController} from "../contracts/registrars/DotnsRegistrarController.sol";
import {PopRules} from "../contracts/pop/PopRules.sol";
import {DotnsResolver} from "../contracts/resolvers/DotnsResolver.sol";
import {DotnsContentResolver} from "../contracts/resolvers/DotnsContentResolver.sol";
import {DotnsReverseResolver} from "../contracts/resolvers/DotnsReverseResolver.sol";

/// @title UpgradeConstants
/// @notice Upgrades all DotNS contracts to centralised DotnsConstants.
/// @dev Storage layout is unchanged -- only internal constant declarations moved.
contract UpgradeConstants is BaseDeployer {
    // Paseo AssetHub deployed proxy addresses
    address public constant REGISTRY_PROXY = 0x4Da0d37aBe96C06ab19963F31ca2DC0412057a6f;
    address public constant REGISTRAR_PROXY = 0x329aAA5b6bEa94E750b2dacBa74Bf41291E6c2BD;
    address public constant CONTROLLER_PROXY = 0xd09e0F1c1E6CE8Cf40df929ef4FC778629573651;
    address public constant POP_RULES_PROXY = 0x4e8920B1E69d0cEA9b23CBFC87A17Ee6fE02d2d3;
    address public constant RESOLVER_PROXY = 0x95645C7fD0fF38790647FE13F87Eb11c1DCc8514;
    address public constant CONTENT_RESOLVER_PROXY = 0x7756DF72CBc7f062e7403cD59e45fBc78bed1cD7;
    address public constant REVERSE_RESOLVER_PROXY = 0x95D57363B491CF743970c640fe419541386ac8BF;

    function run() external {
        console.log("=== DotNS Constants Centralisation Upgrade ===");
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(msg.sender);

        upgradeAll();

        vm.stopBroadcast();

        verifyAll();
    }

    function upgradeAll() public {
        upgradeRegistry(REGISTRY_PROXY);
        upgradeRegistrar(REGISTRAR_PROXY);
        upgradeController(CONTROLLER_PROXY);
        upgradePopRules(POP_RULES_PROXY);
        upgradeResolver(RESOLVER_PROXY);
        upgradeContentResolver(CONTENT_RESOLVER_PROXY);
        upgradeReverseResolver(REVERSE_RESOLVER_PROXY);
    }

    function upgradeAll(address caller) public {
        upgradeRegistry(REGISTRY_PROXY, caller);
        upgradeRegistrar(REGISTRAR_PROXY, caller);
        upgradeController(CONTROLLER_PROXY, caller);
        upgradePopRules(POP_RULES_PROXY, caller);
        upgradeResolver(RESOLVER_PROXY, caller);
        upgradeContentResolver(CONTENT_RESOLVER_PROXY, caller);
        upgradeReverseResolver(REVERSE_RESOLVER_PROXY, caller);
    }

    function upgradeRegistry(address proxy) public {
        Options memory opts;
        opts.referenceContract = "DotnsRegistryOld.sol:DotnsRegistryOld";
        Upgrades.upgradeProxy(proxy, "DotnsRegistry.sol:DotnsRegistry", "", opts);
    }

    function upgradeRegistry(address proxy, address caller) public {
        Options memory opts;
        opts.referenceContract = "DotnsRegistryOld.sol:DotnsRegistryOld";
        Upgrades.upgradeProxy(proxy, "DotnsRegistry.sol:DotnsRegistry", "", opts, caller);
    }

    function upgradeRegistrar(address proxy) public {
        Options memory opts;
        opts.referenceContract = "DotnsRegistrarOld.sol:DotnsRegistrarOld";
        Upgrades.upgradeProxy(proxy, "DotnsRegistrar.sol:DotnsRegistrar", "", opts);
    }

    function upgradeRegistrar(address proxy, address caller) public {
        Options memory opts;
        opts.referenceContract = "DotnsRegistrarOld.sol:DotnsRegistrarOld";
        Upgrades.upgradeProxy(proxy, "DotnsRegistrar.sol:DotnsRegistrar", "", opts, caller);
    }

    function upgradeController(address proxy) public {
        Options memory opts;
        opts.referenceContract = "DotnsRegistrarControllerOld.sol:DotnsRegistrarControllerOld";
        Upgrades.upgradeProxy(
            proxy, "DotnsRegistrarController.sol:DotnsRegistrarController", "", opts
        );
    }

    function upgradeController(address proxy, address caller) public {
        Options memory opts;
        opts.referenceContract = "DotnsRegistrarControllerOld.sol:DotnsRegistrarControllerOld";
        Upgrades.upgradeProxy(
            proxy, "DotnsRegistrarController.sol:DotnsRegistrarController", "", opts, caller
        );
    }

    function upgradePopRules(address proxy) public {
        Options memory opts;
        opts.referenceContract = "PopRulesOld.sol:PopRulesOld";
        Upgrades.upgradeProxy(proxy, "PopRules.sol:PopRules", "", opts);
    }

    function upgradePopRules(address proxy, address caller) public {
        Options memory opts;
        opts.referenceContract = "PopRulesOld.sol:PopRulesOld";
        Upgrades.upgradeProxy(proxy, "PopRules.sol:PopRules", "", opts, caller);
    }

    function upgradeResolver(address proxy) public {
        Options memory opts;
        opts.referenceContract = "DotnsResolverOld.sol:DotnsResolverOld";
        Upgrades.upgradeProxy(proxy, "DotnsResolver.sol:DotnsResolver", "", opts);
    }

    function upgradeResolver(address proxy, address caller) public {
        Options memory opts;
        opts.referenceContract = "DotnsResolverOld.sol:DotnsResolverOld";
        Upgrades.upgradeProxy(proxy, "DotnsResolver.sol:DotnsResolver", "", opts, caller);
    }

    function upgradeContentResolver(address proxy) public {
        Options memory opts;
        opts.referenceContract = "DotnsContentResolverOld.sol:DotnsContentResolverOld";
        Upgrades.upgradeProxy(proxy, "DotnsContentResolver.sol:DotnsContentResolver", "", opts);
    }

    function upgradeContentResolver(address proxy, address caller) public {
        Options memory opts;
        opts.referenceContract = "DotnsContentResolverOld.sol:DotnsContentResolverOld";
        Upgrades.upgradeProxy(
            proxy, "DotnsContentResolver.sol:DotnsContentResolver", "", opts, caller
        );
    }

    function upgradeReverseResolver(address proxy) public {
        Options memory opts;
        opts.referenceContract = "DotnsReverseResolverOld.sol:DotnsReverseResolverOld";
        Upgrades.upgradeProxy(proxy, "DotnsReverseResolver.sol:DotnsReverseResolver", "", opts);
    }

    function upgradeReverseResolver(address proxy, address caller) public {
        Options memory opts;
        opts.referenceContract = "DotnsReverseResolverOld.sol:DotnsReverseResolverOld";
        Upgrades.upgradeProxy(
            proxy, "DotnsReverseResolver.sol:DotnsReverseResolver", "", opts, caller
        );
    }

    function verifyAll() public view {
        verifyRegistry(REGISTRY_PROXY);
        verifyRegistrar(REGISTRAR_PROXY);
        verifyController(CONTROLLER_PROXY);
        verifyPopRules(POP_RULES_PROXY);
        verifyResolver(RESOLVER_PROXY);
        verifyContentResolver(CONTENT_RESOLVER_PROXY);
        verifyReverseResolver(REVERSE_RESOLVER_PROXY);
        console.log("=== All upgrades verified ===");
    }

    function verifyRegistry(address proxy) public view {
        DotnsRegistry registry = DotnsRegistry(proxy);
        require(registry.recordExists(bytes32(0)), "Registry: root record missing");
        require(registry.owner(bytes32(0)) != address(0), "Registry: root owner is zero");
        console.log("Registry upgrade verified");
    }

    function verifyRegistrar(address proxy) public view {
        DotnsRegistrar registrar = DotnsRegistrar(proxy);
        require(bytes(registrar.name()).length > 0, "Registrar: name is empty");
        console.log("Registrar upgrade verified");
    }

    function verifyController(address proxy) public view {
        DotnsRegistrarController controller = DotnsRegistrarController(proxy);
        require(controller.minCommitmentAge() > 0, "Controller: minCommitmentAge is zero");
        require(controller.maxCommitmentAge() > 0, "Controller: maxCommitmentAge is zero");
        console.log("Controller upgrade verified");
    }

    function verifyPopRules(address proxy) public view {
        PopRules rules = PopRules(proxy);
        require(rules.startingPrice() > 0, "PopRules: startingPrice is zero");
        console.log("PopRules upgrade verified");
    }

    function verifyResolver(address proxy) public view {
        DotnsResolver(proxy).version();
        console.log("Resolver upgrade verified");
    }

    function verifyContentResolver(address proxy) public view {
        DotnsContentResolver(proxy).version();
        console.log("ContentResolver upgrade verified");
    }

    function verifyReverseResolver(address proxy) public view {
        DotnsReverseResolver(proxy).version();
        console.log("ReverseResolver upgrade verified");
    }
}
