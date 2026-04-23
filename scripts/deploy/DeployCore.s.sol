// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/Script.sol";
import {BaseDeployer} from "./BaseDeployer.s.sol";
import {DeploymentNetwork} from "./DeploymentNetwork.sol";

import {StoreFactory} from "../../contracts/store/StoreFactory.sol";
import {DotnsRegistrar} from "../../contracts/registrars/DotnsRegistrar.sol";
import {DotnsReverseResolver} from "../../contracts/resolvers/DotnsReverseResolver.sol";
import {DotnsRegistry} from "../../contracts/registry/DotnsRegistry.sol";
import {DotnsProtocolRegistry} from "../../contracts/registry/DotnsProtocolRegistry.sol";
import {IDotnsProtocolRegistry} from "../../contracts/registry/IDotnsProtocolRegistry.sol";

/// @title DeployCore
/// @notice First stage of the DotNS fresh-deploy pipeline. Deploys the
///         protocol registry first, then the foundational name-ownership
///         layer: the Store factory and three UUPS proxies (registrar,
///         reverse resolver, forward registry) that all bind to the protocol
///         registry at init.
/// @dev Runs in its own `forge script` process; the OpenZeppelin validator's
///      per-call memory never crosses the process boundary into later stages.
/// @custom:security-contact admin@parity.io
contract DeployCore is BaseDeployer {
    function run() external {
        address owner = msg.sender;
        vm.label(owner, "OWNER");

        initDeployment(DeploymentNetwork.folder(block.chainid), vm.toString(block.chainid));

        address protocolRegistry = _deployProtocolRegistry(owner);
        _deployStoreFactory(owner);
        _deployRegistrar(owner, protocolRegistry);
        _deployReverseResolver(owner, protocolRegistry);
        _deployRegistry(owner, protocolRegistry);

        saveDeployments();

        console.log("=== DeployCore complete ===");
    }

    function _deployProtocolRegistry(address owner) internal returns (address proxy) {
        proxy = _broadcastDeployUups(
            owner,
            "DotnsProtocolRegistry.sol:DotnsProtocolRegistry",
            abi.encodeCall(DotnsProtocolRegistry.initialize, ()),
            "DotnsProtocolRegistry"
        );
    }

    function _deployStoreFactory(address owner) internal {
        vm.startBroadcast(owner);
        StoreFactory factory = new StoreFactory();
        vm.stopBroadcast();
        vm.label(address(factory), "StoreFactory");
        logDeployment("StoreFactory", address(factory));
    }

    function _deployRegistrar(
        address owner,
        address protocolRegistry
    )
        internal
        returns (address proxy)
    {
        proxy = _broadcastDeployUups(
            owner,
            "DotnsRegistrar.sol:DotnsRegistrar",
            abi.encodeCall(
                DotnsRegistrar.initialize,
                ("Dotns", "Dotns", IDotnsProtocolRegistry(protocolRegistry))
            ),
            "DotnsRegistrar"
        );
    }

    function _deployReverseResolver(
        address owner,
        address protocolRegistry
    )
        internal
        returns (address proxy)
    {
        proxy = _broadcastDeployUups(
            owner,
            "DotnsReverseResolver.sol:DotnsReverseResolver",
            abi.encodeCall(
                DotnsReverseResolver.initialize, (IDotnsProtocolRegistry(protocolRegistry))
            ),
            "DotnsReverseResolver"
        );
    }

    function _deployRegistry(
        address owner,
        address protocolRegistry
    )
        internal
        returns (address proxy)
    {
        proxy = _broadcastDeployUups(
            owner,
            "DotnsRegistry.sol:DotnsRegistry",
            abi.encodeCall(DotnsRegistry.initialize, (IDotnsProtocolRegistry(protocolRegistry))),
            "DotnsRegistry"
        );
    }
}
