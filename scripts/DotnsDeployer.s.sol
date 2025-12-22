// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/Script.sol";
import {BaseDeployer} from "./BaseDeployer.s.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {PopOracle, IPopOracle} from "../contracts/pop/PopOracle.sol";

import {DotnsRegistrar, IDotnsRegistrar} from "../contracts/registrars/DotnsRegistrar.sol";

import {
    DotnsRegistrarController,
    IDotnsRegistrarController
} from "../contracts/registrars/DotnsRegistrarController.sol";

import {DotnsRegistry, IDotnsRegistry} from "../contracts/registry/DotnsRegistry.sol";

import {
    DotnsReverseResolver,
    IDotnsReverseResolver
} from "../contracts/resolvers/DotnsReverseResolver.sol";

import {DotnsContentResolver} from "../contracts/resolvers/DotnsContentResolver.sol";

import {StoreFactory, IStoreFactory} from "../contracts/store/StoreFactory.sol";

/// @title DotnsDeployer
contract DotnsDeployer is BaseDeployer {
    uint256 public constant rentPrice = 2e15 wei;

    StoreFactory public storeFactory;

    PopOracle public popOracle;
    DotnsRegistrar public dotnsRegistrar;
    DotnsRegistry public dotnsRegistry;
    DotnsReverseResolver public dotnsReverseResolver;
    DotnsContentResolver public dotnsContentResolver;
    DotnsRegistrarController public dotnsRegistrarController;

    function run() external {
        uint256 chainId = block.chainid;

        vm.warp(365 days);

        console.log("Current blocktime");
        console.logUint(block.timestamp);

        initDeployment();

        address OWNER = msg.sender;

        vm.startBroadcast(OWNER);
        vm.label(OWNER, "OWNER");

        // StoreFactory
        storeFactory = new StoreFactory();
        vm.label(address(storeFactory), "StoreFactory");
        logDeployment("StoreFactory", address(storeFactory));

        // DotnsRegistrar
        address dotnsRegistrarProxy = Upgrades.deployUUPSProxy(
            "DotnsRegistrar.sol:DotnsRegistrar",
            abi.encodeCall(DotnsRegistrar.initialize, ("Dotns", "Dotns"))
        );
        dotnsRegistrar = DotnsRegistrar(dotnsRegistrarProxy);
        vm.label(dotnsRegistrarProxy, "DotnsRegistrar");
        logDeployment("DotnsRegistrar", dotnsRegistrarProxy);

        // DotnsRegistry
        address dotnsRegistryProxy = Upgrades.deployUUPSProxy(
            "DotnsRegistry.sol:DotnsRegistry", abi.encodeCall(DotnsRegistry.initialize, ())
        );
        dotnsRegistry = DotnsRegistry(dotnsRegistryProxy);
        vm.label(dotnsRegistryProxy, "DotnsRegistry");
        logDeployment("DotnsRegistry", dotnsRegistryProxy);

        // DotnsReverseResolver
        address dotnsReverseResolverProxy = Upgrades.deployUUPSProxy(
            "DotnsReverseResolver.sol:DotnsReverseResolver",
            abi.encodeCall(DotnsReverseResolver.initialize, ())
        );
        dotnsReverseResolver = DotnsReverseResolver(dotnsReverseResolverProxy);
        vm.label(dotnsReverseResolverProxy, "DotnsReverseResolver");
        logDeployment("DotnsReverseResolver", dotnsReverseResolverProxy);

        // DotnsContentResolver
        address dotnsContentResolverProxy = Upgrades.deployUUPSProxy(
            "DotnsContentResolver.sol:DotnsContentResolver",
            abi.encodeCall(DotnsContentResolver.initialize, (IDotnsRegistry(dotnsRegistryProxy)))
        );
        dotnsContentResolver = DotnsContentResolver(dotnsContentResolverProxy);
        vm.label(dotnsContentResolverProxy, "DotnsContentResolver");
        logDeployment("DotnsContentResolver", dotnsContentResolverProxy);

        // PopOracle
        address popOracleProxy = Upgrades.deployUUPSProxy(
            "PopOracle.sol:PopOracle", abi.encodeCall(PopOracle.initialize, (rentPrice))
        );
        popOracle = PopOracle(popOracleProxy);
        vm.label(popOracleProxy, "PopOracle");
        logDeployment("PopOracle", popOracleProxy);

        // DotnsRegistrarController
        address dotnsRegistrarControllerProxy = Upgrades.deployUUPSProxy(
            "DotnsRegistrarController.sol:DotnsRegistrarController",
            abi.encodeCall(
                DotnsRegistrarController.initialize,
                (
                    IDotnsRegistrar(dotnsRegistrarProxy),
                    IDotnsRegistry(dotnsRegistryProxy),
                    IDotnsReverseResolver(dotnsReverseResolverProxy),
                    IPopOracle(popOracleProxy),
                    IStoreFactory(address(storeFactory)),
                    6 seconds,
                    1 days
                )
            )
        );
        dotnsRegistrarController = DotnsRegistrarController(dotnsRegistrarControllerProxy);
        vm.label(dotnsRegistrarControllerProxy, "DotnsRegistrarController");
        logDeployment("DotnsRegistrarController", dotnsRegistrarControllerProxy);

        dotnsReverseResolver.updateRegistrar(dotnsRegistrarControllerProxy);
        popOracle.updateEthRegistry(dotnsRegistrarControllerProxy);
        dotnsRegistrar.addController(dotnsRegistrarControllerProxy);
        dotnsRegistry.updateRegistrarController(dotnsRegistrarControllerProxy);

        vm.stopBroadcast();

        saveDeployments(_getDeploymentFolder(), vm.toString(chainId));

        _sanity_pop_oracle_reserved();
    }

    function _sanity_pop_oracle_reserved() internal view {
        (IPopOracle.PopStatus status,) = popOracle.classifyName("hello");
        require(uint256(status) == uint256(IPopOracle.PopStatus.Reserved), "unexpected pop status");
    }

    function _getDeploymentFolder() internal view returns (string memory directory) {
        directory = "localhost";
        if (block.chainid == 420420422) {
            directory = "paseo";
        } else if (block.chainid == 420420420) {
            directory = "paseo-local";
        }
    }
}
