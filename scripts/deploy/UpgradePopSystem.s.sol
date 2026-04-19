// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/Script.sol";
import {BaseDeployer} from "./BaseDeployer.s.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

import {
    DotnsProtocolRegistry,
    IDotnsProtocolRegistry
} from "../../contracts/registry/DotnsProtocolRegistry.sol";
import {DotnsRegistry} from "../../contracts/registry/DotnsRegistry.sol";
import {DotnsRegistrar} from "../../contracts/registrars/DotnsRegistrar.sol";
import {DotnsRegistrarController} from "../../contracts/registrars/DotnsRegistrarController.sol";
import {DotnsPopController} from "../../contracts/registrars/DotnsPopController.sol";
import {DotnsPopResolver} from "../../contracts/resolvers/DotnsPopResolver.sol";
import {IDotnsController} from "../../contracts/registrars/IDotnsController.sol";

/// @title UpgradePopSystem
/// @notice Single orchestration script that applies the PoP-controller upgrade in order.
/// @dev Sequence (load-bearing, mirrors the PR #124 pattern):
///      1. Upgrade protocol registry   — exposes POP_GATEWAY, POP_CONTROLLER, POP_RESOLVER keys.
///      2. Deploy PoP resolver (fresh) — needs protocol registry to exist (writer auth queries it).
///      3. Deploy PoP controller (fresh) — needs protocol registry to exist.
///      4. Write POP_RESOLVER, POP_CONTROLLER, POP_GATEWAY slots.
///      5. Upgrade forward registry    — auth delegates to registrar's `controllers` mapping.
///      6. Upgrade registrar           — `controllers` mapping key retyped to {IDotnsController}.
///      7. Upgrade controller          — refactored to use LabelUtils / RegistrationUtils.
///      8. `addController` the PoP controller on the registrar.
///
///      The fork test invokes `upgradeAll` directly, so production and test share one code path.
contract UpgradePopSystem is BaseDeployer {
    /// @notice Deployed Paseo AssetHub proxy addresses. These mirror the canonical
    ///         set used by {UpgradeEscrowSystem} so subsequent upgrades stay aligned.
    address public constant PROTOCOL_REGISTRY_PROXY = 0xF8531342444fAC0A75719130eECcf45314584EFe;
    address public constant REGISTRY_PROXY = 0x4Da0d37aBe96C06ab19963F31ca2DC0412057a6f;
    address public constant REGISTRAR_PROXY = 0x329aAA5b6bEa94E750b2dacBa74Bf41291E6c2BD;
    address public constant CONTROLLER_PROXY = 0xd09e0F1c1E6CE8Cf40df929ef4FC778629573651;

    /// @notice Default reservation duration for fresh PoP-controller deployments.
    uint64 public constant DEFAULT_RESERVATION_DURATION = 7 days;

    /// @notice Expected versions after upgrade. Single source of truth for post-upgrade checks.
    string public constant PROTOCOL_REGISTRY_VERSION = "1.1.0";
    string public constant REGISTRY_VERSION = "1.5.0";
    string public constant REGISTRAR_VERSION = "1.4.0";
    string public constant CONTROLLER_VERSION = "1.5.0";
    string public constant POP_CONTROLLER_VERSION = "1.0.0";
    string public constant POP_RESOLVER_VERSION = "1.0.0";

    /// @notice Fully-qualified artifact names used for OZ reference-contract validation.
    string internal constant _PROTOCOL_REGISTRY_NEW =
        "DotnsProtocolRegistry.sol:DotnsProtocolRegistry";
    string internal constant _PROTOCOL_REGISTRY_OLD =
        "DotnsProtocolRegistryOld.sol:DotnsProtocolRegistryOld";
    string internal constant _REGISTRY_NEW = "DotnsRegistry.sol:DotnsRegistry";
    string internal constant _REGISTRY_OLD = "DotnsRegistryOld.sol:DotnsRegistryOld";
    string internal constant _REGISTRAR_NEW = "DotnsRegistrar.sol:DotnsRegistrar";
    string internal constant _REGISTRAR_OLD = "DotnsRegistrarOld.sol:DotnsRegistrarOld";
    string internal constant _CONTROLLER_NEW =
        "DotnsRegistrarController.sol:DotnsRegistrarController";
    string internal constant _CONTROLLER_OLD =
        "DotnsRegistrarControllerOld.sol:DotnsRegistrarControllerOld";
    string internal constant _POP_RESOLVER_NEW = "DotnsPopResolver.sol:DotnsPopResolver";
    string internal constant _POP_CONTROLLER_NEW = "DotnsPopController.sol:DotnsPopController";

    /// @notice Addresses produced by `upgradeAll`, exposed for post-upgrade verification.
    struct Deployment {
        address popResolverProxy;
        address popControllerProxy;
    }

    /// @notice Standard run entrypoint — executed live against the configured chain.
    /// @param popGateway Privileged gateway address registered under `POP_GATEWAY`.
    function run(address popGateway) external {
        console.log("=== PoP System Upgrade ===");
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(msg.sender);
        Deployment memory deployment = upgradeAll(msg.sender, popGateway);
        vm.stopBroadcast();

        verifyUpgrade(deployment, popGateway);
    }

    /// @notice Single-owner overload used by fork tests and single-signer deployments.
    /// @param caller Owner of all four existing proxies and authorised registry writer.
    /// @param popGateway Privileged gateway address registered under `POP_GATEWAY`.
    /// @return deployment Addresses produced by this upgrade.
    function upgradeAll(
        address caller,
        address popGateway
    )
        public
        returns (Deployment memory deployment)
    {
        return upgradeAll(caller, caller, caller, caller, popGateway);
    }

    /// @notice Per-proxy-owner overload for when admin addresses differ across proxies.
    /// @param protocolRegistryOwner Owner of the protocol-registry proxy.
    /// @param registryOwner Owner of the forward-registry proxy.
    /// @param registrarOwner Owner of the registrar proxy.
    /// @param controllerOwner Owner of the commit-reveal controller proxy.
    /// @param popGateway Privileged gateway address registered under `POP_GATEWAY`.
    /// @return deployment Addresses produced by this upgrade.
    function upgradeAll(
        address protocolRegistryOwner,
        address registryOwner,
        address registrarOwner,
        address controllerOwner,
        address popGateway
    )
        public
        returns (Deployment memory deployment)
    {
        _upgrade(
            PROTOCOL_REGISTRY_PROXY,
            _PROTOCOL_REGISTRY_NEW,
            _PROTOCOL_REGISTRY_OLD,
            protocolRegistryOwner
        );

        deployment.popResolverProxy = Upgrades.deployUUPSProxy(
            _POP_RESOLVER_NEW,
            abi.encodeCall(
                DotnsPopResolver.initialize, (IDotnsProtocolRegistry(PROTOCOL_REGISTRY_PROXY))
            )
        );

        deployment.popControllerProxy = Upgrades.deployUUPSProxy(
            _POP_CONTROLLER_NEW,
            abi.encodeCall(
                DotnsPopController.initialize,
                (IDotnsProtocolRegistry(PROTOCOL_REGISTRY_PROXY), DEFAULT_RESERVATION_DURATION)
            )
        );

        DotnsProtocolRegistry protocolRegistry = DotnsProtocolRegistry(PROTOCOL_REGISTRY_PROXY);
        vm.startPrank(protocolRegistryOwner);
        protocolRegistry.set(protocolRegistry.POP_RESOLVER(), deployment.popResolverProxy);
        protocolRegistry.set(protocolRegistry.POP_CONTROLLER(), deployment.popControllerProxy);
        protocolRegistry.set(protocolRegistry.POP_GATEWAY(), popGateway);
        vm.stopPrank();

        _upgrade(REGISTRY_PROXY, _REGISTRY_NEW, _REGISTRY_OLD, registryOwner);
        _upgrade(REGISTRAR_PROXY, _REGISTRAR_NEW, _REGISTRAR_OLD, registrarOwner);
        _upgrade(CONTROLLER_PROXY, _CONTROLLER_NEW, _CONTROLLER_OLD, controllerOwner);

        vm.startPrank(registrarOwner);
        DotnsRegistrar(REGISTRAR_PROXY)
            .addController(IDotnsController(deployment.popControllerProxy));
        vm.stopPrank();
    }

    /// @notice Post-upgrade verification checks — called by both `run` and fork tests.
    /// @param deployment Addresses returned by `upgradeAll`.
    /// @param popGateway Address registered under `POP_GATEWAY` by this upgrade.
    function verifyUpgrade(Deployment memory deployment, address popGateway) public view {
        DotnsProtocolRegistry protocolRegistry = DotnsProtocolRegistry(PROTOCOL_REGISTRY_PROXY);
        DotnsRegistry registry = DotnsRegistry(REGISTRY_PROXY);
        DotnsRegistrar registrar = DotnsRegistrar(REGISTRAR_PROXY);
        DotnsRegistrarController controller = DotnsRegistrarController(CONTROLLER_PROXY);
        DotnsPopController popController = DotnsPopController(deployment.popControllerProxy);
        DotnsPopResolver popResolver = DotnsPopResolver(deployment.popResolverProxy);

        _requireVersion(protocolRegistry.version(), PROTOCOL_REGISTRY_VERSION, "ProtocolRegistry");
        _requireVersion(registry.version(), REGISTRY_VERSION, "Registry");
        _requireVersion(registrar.version(), REGISTRAR_VERSION, "Registrar");
        _requireVersion(controller.version(), CONTROLLER_VERSION, "Controller");
        _requireVersion(popController.version(), POP_CONTROLLER_VERSION, "PopController");
        _requireVersion(popResolver.version(), POP_RESOLVER_VERSION, "PopResolver");

        require(
            protocolRegistry.get(protocolRegistry.POP_CONTROLLER())
                == deployment.popControllerProxy,
            "POP_CONTROLLER not wired"
        );
        require(
            protocolRegistry.get(protocolRegistry.POP_RESOLVER()) == deployment.popResolverProxy,
            "POP_RESOLVER not wired"
        );
        require(
            protocolRegistry.get(protocolRegistry.POP_GATEWAY()) == popGateway,
            "POP_GATEWAY not wired"
        );
        require(
            registrar.controllers(IDotnsController(deployment.popControllerProxy)),
            "PopController not authorised on registrar"
        );

        console.log("=== Upgrade verification complete ===");
        console.log("ProtocolRegistry:", PROTOCOL_REGISTRY_PROXY);
        console.log("Registry:        ", REGISTRY_PROXY);
        console.log("Registrar:       ", REGISTRAR_PROXY);
        console.log("Controller:      ", CONTROLLER_PROXY);
        console.log("PopController:   ", deployment.popControllerProxy);
        console.log("PopResolver:     ", deployment.popResolverProxy);
    }

    /// @notice Upgrades a proxy, pinning the reference contract for storage-layout validation.
    /// @dev OZ's `referenceContract` check MUST NOT be skipped — it is the upgrade-safety gate.
    function _upgrade(
        address proxy,
        string memory newArtifact,
        string memory oldArtifact,
        address caller
    )
        internal
    {
        Options memory opts;
        opts.referenceContract = oldArtifact;
        Upgrades.upgradeProxy(proxy, newArtifact, "", opts, caller);
    }

    /// @notice Asserts an on-chain version string matches the expected constant.
    function _requireVersion(
        string memory actual,
        string memory expected,
        string memory label
    )
        internal
        pure
    {
        require(
            keccak256(bytes(actual)) == keccak256(bytes(expected)),
            string.concat(label, " version mismatch")
        );
    }
}
