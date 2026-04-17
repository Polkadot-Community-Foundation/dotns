// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/Script.sol";
import {BaseDeployer} from "./BaseDeployer.s.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

import {DotnsProtocolRegistry} from "../../contracts/registry/DotnsProtocolRegistry.sol";
import {DotnsRegistry} from "../../contracts/registry/DotnsRegistry.sol";
import {DotnsRegistrar} from "../../contracts/registrars/DotnsRegistrar.sol";
import {DotnsRegistrarController} from "../../contracts/registrars/DotnsRegistrarController.sol";
import {DotnsReverseResolver} from "../../contracts/resolvers/DotnsReverseResolver.sol";
import {DotnsResolver} from "../../contracts/resolvers/DotnsResolver.sol";
import {DotnsContentResolver} from "../../contracts/resolvers/DotnsContentResolver.sol";
import {PopRules} from "../../contracts/pop/PopRules.sol";
import {DotnsConstants} from "../../contracts/utils/DotnsConstants.sol";

/// @title UpgradeProtocolKeys
/// @notice Upgrades all 8 protocol contracts to move well-known keys from
///         DotnsProtocolRegistry constants to DotnsConstants library.
/// @dev Sequence: protocol registry first, then all consumers.
///      The fork test invokes `upgradeAll` directly, so production and test share one code path.
contract UpgradeProtocolKeys is BaseDeployer {
    /// @notice Deployed Paseo AssetHub proxy addresses.
    address public constant PROTOCOL_REGISTRY_PROXY = 0xF8531342444fAC0A75719130eECcf45314584EFe;
    address public constant REGISTRY_PROXY = 0x4Da0d37aBe96C06ab19963F31ca2DC0412057a6f;
    address public constant REGISTRAR_PROXY = 0x329aAA5b6bEa94E750b2dacBa74Bf41291E6c2BD;
    address public constant CONTROLLER_PROXY = 0xd09e0F1c1E6CE8Cf40df929ef4FC778629573651;
    address public constant REVERSE_RESOLVER_PROXY = 0x95D57363B491CF743970c640fe419541386ac8BF;
    address public constant RESOLVER_PROXY = 0x95645C7fD0fF38790647FE13F87Eb11c1DCc8514;
    address public constant CONTENT_RESOLVER_PROXY = 0x7756DF72CBc7f062e7403cD59e45fBc78bed1cD7;
    address public constant POP_RULES_PROXY = 0x4e8920B1E69d0cEA9b23CBFC87A17Ee6fE02d2d3;

    /// @notice Expected versions after upgrade.
    string public constant PROTOCOL_REGISTRY_VERSION = "1.1.0";
    string public constant REGISTRY_VERSION = "1.5.0";
    string public constant REGISTRAR_VERSION = "1.4.0";
    string public constant CONTROLLER_VERSION = "1.5.0";
    string public constant REVERSE_RESOLVER_VERSION = "1.2.0";
    string public constant RESOLVER_VERSION = "1.2.0";
    string public constant CONTENT_RESOLVER_VERSION = "1.2.0";
    string public constant POP_RULES_VERSION = "1.2.0";

    /// @notice Fully-qualified artifact names for new implementations.
    string internal constant _PROTOCOL_REGISTRY_NEW =
        "DotnsProtocolRegistry.sol:DotnsProtocolRegistry";
    string internal constant _REGISTRY_NEW = "DotnsRegistry.sol:DotnsRegistry";
    string internal constant _REGISTRAR_NEW = "DotnsRegistrar.sol:DotnsRegistrar";
    string internal constant _CONTROLLER_NEW =
        "DotnsRegistrarController.sol:DotnsRegistrarController";
    string internal constant _REVERSE_RESOLVER_NEW =
        "DotnsReverseResolver.sol:DotnsReverseResolver";
    string internal constant _RESOLVER_NEW = "DotnsResolver.sol:DotnsResolver";
    string internal constant _CONTENT_RESOLVER_NEW =
        "DotnsContentResolver.sol:DotnsContentResolver";
    string internal constant _POP_RULES_NEW = "PopRules.sol:PopRules";

    /// @notice Fully-qualified artifact names for Old.sol reference contracts.
    string internal constant _PROTOCOL_REGISTRY_OLD =
        "DotnsProtocolRegistryOld.sol:DotnsProtocolRegistryOld";
    string internal constant _REGISTRY_OLD = "DotnsRegistryOld.sol:DotnsRegistryOld";
    string internal constant _REGISTRAR_OLD = "DotnsRegistrarOld.sol:DotnsRegistrarOld";
    string internal constant _CONTROLLER_OLD =
        "DotnsRegistrarControllerOld.sol:DotnsRegistrarControllerOld";
    string internal constant _REVERSE_RESOLVER_OLD =
        "DotnsReverseResolverOld.sol:DotnsReverseResolverOld";
    string internal constant _RESOLVER_OLD = "DotnsResolverOld.sol:DotnsResolverOld";
    string internal constant _CONTENT_RESOLVER_OLD =
        "DotnsContentResolverOld.sol:DotnsContentResolverOld";
    string internal constant _POP_RULES_OLD = "PopRulesOld.sol:PopRulesOld";

    /// @notice Standard run entrypoint — executes in two batches to stay within EVM memory
    ///         limits during OZ storage-layout validation (each referenceContract check is
    ///         an FFI call that loads build info into EVM memory).
    function run() external {
        console.log("=== Protocol Keys Upgrade ===");
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(msg.sender);
        upgradeBatch1(msg.sender);
        upgradeBatch2(msg.sender);
        vm.stopBroadcast();

        verifyUpgrade();
    }

    /// @notice Single-owner overload.
    function upgradeAll(address caller) public {
        _upgrade(PROTOCOL_REGISTRY_PROXY, _PROTOCOL_REGISTRY_NEW, _PROTOCOL_REGISTRY_OLD, caller);
        _upgrade(REGISTRY_PROXY, _REGISTRY_NEW, _REGISTRY_OLD, caller);
        _upgrade(REGISTRAR_PROXY, _REGISTRAR_NEW, _REGISTRAR_OLD, caller);
        _upgrade(CONTROLLER_PROXY, _CONTROLLER_NEW, _CONTROLLER_OLD, caller);
        _upgrade(REVERSE_RESOLVER_PROXY, _REVERSE_RESOLVER_NEW, _REVERSE_RESOLVER_OLD, caller);
        _upgrade(RESOLVER_PROXY, _RESOLVER_NEW, _RESOLVER_OLD, caller);
        _upgrade(CONTENT_RESOLVER_PROXY, _CONTENT_RESOLVER_NEW, _CONTENT_RESOLVER_OLD, caller);
        _upgrade(POP_RULES_PROXY, _POP_RULES_NEW, _POP_RULES_OLD, caller);
    }

    /// @notice Batch 1: protocol registry + core contracts (4 upgrades).
    function upgradeBatch1(address caller) public {
        _upgrade(PROTOCOL_REGISTRY_PROXY, _PROTOCOL_REGISTRY_NEW, _PROTOCOL_REGISTRY_OLD, caller);
        _upgrade(REGISTRY_PROXY, _REGISTRY_NEW, _REGISTRY_OLD, caller);
        _upgrade(REGISTRAR_PROXY, _REGISTRAR_NEW, _REGISTRAR_OLD, caller);
        _upgrade(CONTROLLER_PROXY, _CONTROLLER_NEW, _CONTROLLER_OLD, caller);
    }

    /// @notice Batch 2: resolvers + pop rules (4 upgrades).
    function upgradeBatch2(address caller) public {
        _upgrade(REVERSE_RESOLVER_PROXY, _REVERSE_RESOLVER_NEW, _REVERSE_RESOLVER_OLD, caller);
        _upgrade(RESOLVER_PROXY, _RESOLVER_NEW, _RESOLVER_OLD, caller);
        _upgrade(CONTENT_RESOLVER_PROXY, _CONTENT_RESOLVER_NEW, _CONTENT_RESOLVER_OLD, caller);
        _upgrade(POP_RULES_PROXY, _POP_RULES_NEW, _POP_RULES_OLD, caller);
    }

    /// @notice Post-upgrade verification.
    function verifyUpgrade() public view {
        _requireVersion(
            DotnsProtocolRegistry(PROTOCOL_REGISTRY_PROXY).version(),
            PROTOCOL_REGISTRY_VERSION,
            "ProtocolRegistry"
        );
        _requireVersion(DotnsRegistry(REGISTRY_PROXY).version(), REGISTRY_VERSION, "Registry");
        _requireVersion(DotnsRegistrar(REGISTRAR_PROXY).version(), REGISTRAR_VERSION, "Registrar");
        _requireVersion(
            DotnsRegistrarController(CONTROLLER_PROXY).version(), CONTROLLER_VERSION, "Controller"
        );
        _requireVersion(
            DotnsReverseResolver(REVERSE_RESOLVER_PROXY).version(),
            REVERSE_RESOLVER_VERSION,
            "ReverseResolver"
        );
        _requireVersion(DotnsResolver(RESOLVER_PROXY).version(), RESOLVER_VERSION, "Resolver");
        _requireVersion(
            DotnsContentResolver(CONTENT_RESOLVER_PROXY).version(),
            CONTENT_RESOLVER_VERSION,
            "ContentResolver"
        );
        _requireVersion(PopRules(POP_RULES_PROXY).version(), POP_RULES_VERSION, "PopRules");

        DotnsProtocolRegistry pr = DotnsProtocolRegistry(PROTOCOL_REGISTRY_PROXY);
        require(pr.get(DotnsConstants.REGISTRAR) != address(0), "Key: registrar");
        require(pr.get(DotnsConstants.CONTROLLER) != address(0), "Key: controller");
        require(pr.get(DotnsConstants.REGISTRY) != address(0), "Key: registry");
        require(pr.get(DotnsConstants.REVERSE_RESOLVER) != address(0), "Key: reverseResolver");
        require(pr.get(DotnsConstants.RESOLVER) != address(0), "Key: resolver");
        require(pr.get(DotnsConstants.CONTENT_RESOLVER) != address(0), "Key: contentResolver");
        require(pr.get(DotnsConstants.POP_RULES) != address(0), "Key: popRules");
        require(pr.get(DotnsConstants.STORE_FACTORY) != address(0), "Key: storeFactory");

        console.log("=== Upgrade verification complete ===");
    }

    /// @notice Upgrades a proxy, pinning the reference contract for storage-layout validation.
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
