// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/Script.sol";
import {BaseDeployer} from "./BaseDeployer.s.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {DotnsRegistrar} from "../contracts/registrars/DotnsRegistrar.sol";
import {
    DotnsProtocolRegistry,
    IDotnsProtocolRegistry
} from "../contracts/registry/DotnsProtocolRegistry.sol";

/// @title DeployProtocolRegistry
/// @notice Deploys the DotnsProtocolRegistry and wires it with existing deployed contracts.
contract DeployProtocolRegistry is BaseDeployer {
    address constant REGISTRAR = 0x329aAA5b6bEa94E750b2dacBa74Bf41291E6c2BD;
    address constant CONTROLLER = 0xd09e0F1c1E6CE8Cf40df929ef4FC778629573651;
    address constant REGISTRY = 0x4Da0d37aBe96C06ab19963F31ca2DC0412057a6f;
    address constant REVERSE_RESOLVER = 0x95D57363B491CF743970c640fe419541386ac8BF;
    address constant RESOLVER = 0x95645C7fD0fF38790647FE13F87Eb11c1DCc8514;
    address constant CONTENT_RESOLVER = 0x7756DF72CBc7f062e7403cD59e45fBc78bed1cD7;
    address constant STORE_FACTORY = 0x030296782F4d3046B080BcB017f01837561D9702;
    address constant POP_RULES = 0x4e8920B1E69d0cEA9b23CBFC87A17Ee6fE02d2d3;

    function run() external {
        uint256 chainId = block.chainid;

        initDeployment();

        address OWNER = msg.sender;
        vm.startBroadcast(OWNER);

        // Deploy DotnsProtocolRegistry
        address protocolRegistryProxy = Upgrades.deployUUPSProxy(
            "DotnsProtocolRegistry.sol:DotnsProtocolRegistry",
            abi.encodeCall(DotnsProtocolRegistry.initialize, ())
        );
        DotnsProtocolRegistry protocolRegistry = DotnsProtocolRegistry(protocolRegistryProxy);
        vm.label(protocolRegistryProxy, "DotnsProtocolRegistry");
        logDeployment("DotnsProtocolRegistry", protocolRegistryProxy);

        // Wire all existing contract addresses
        protocolRegistry.set(bytes32("registrar"), REGISTRAR);
        protocolRegistry.set(bytes32("controller"), CONTROLLER);
        protocolRegistry.set(bytes32("registry"), REGISTRY);
        protocolRegistry.set(bytes32("reverseResolver"), REVERSE_RESOLVER);
        protocolRegistry.set(bytes32("resolver"), RESOLVER);
        protocolRegistry.set(bytes32("contentResolver"), CONTENT_RESOLVER);
        protocolRegistry.set(bytes32("storeFactory"), STORE_FACTORY);
        protocolRegistry.set(bytes32("popRules"), POP_RULES);

        // Point the registrar to the new protocol registry
        DotnsRegistrar(REGISTRAR).updateProtocolRegistry(
            IDotnsProtocolRegistry(protocolRegistryProxy)
        );

        vm.stopBroadcast();

        saveDeployments(_getDeploymentFolder(), vm.toString(chainId));
    }

    function _getDeploymentFolder() internal view returns (string memory directory) {
        directory = "localhost";
        if (block.chainid == 420420422) {
            directory = "passethub-testnet";
        } else if (block.chainid == 420420417) {
            directory = "paseo-assethub";
        } else if (block.chainid == 420420420) {
            directory = "paseo-local";
        }
    }
}
