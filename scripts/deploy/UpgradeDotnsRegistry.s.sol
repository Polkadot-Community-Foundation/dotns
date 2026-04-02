// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/Script.sol";
import {BaseDeployer} from "./BaseDeployer.s.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

import {DotnsRegistry} from "../../contracts/registry/DotnsRegistry.sol";

/// @title UpgradeDotnsRegistry
/// @notice Upgrades the DotnsRegistry proxy to v1.3.0.
/// @dev Changes: allow parent to reassign existing subnodes, add setSubnodeResolver
///      for parent-level resolver management. Storage layout is unchanged.
contract UpgradeDotnsRegistry is BaseDeployer {
    /// @notice Paseo AssetHub deployed registry proxy.
    address public constant REGISTRY_PROXY = 0x4Da0d37aBe96C06ab19963F31ca2DC0412057a6f;

    function run() external {
        console.log("=== DotnsRegistry Upgrade to v1.3.0 ===");
        console.log("Chain ID:", block.chainid);
        console.log("Registry proxy:", REGISTRY_PROXY);

        string memory versionBefore = DotnsRegistry(REGISTRY_PROXY).version();
        console.log("Version before:", versionBefore);

        vm.startBroadcast(msg.sender);

        upgradeRegistry(REGISTRY_PROXY);

        vm.stopBroadcast();

        verifyUpgrade(REGISTRY_PROXY);
    }

    /// @notice Core upgrade logic -- shared with fork tests for 1:1 parity.
    /// @param registryProxy The UUPS proxy address for DotnsRegistry.
    function upgradeRegistry(address registryProxy) public {
        Options memory opts;
        opts.referenceContract = "DotnsRegistryOld.sol:DotnsRegistryOld";
        Upgrades.upgradeProxy(registryProxy, "DotnsRegistry.sol:DotnsRegistry", "", opts);
    }

    /// @notice Core upgrade logic with explicit caller (for fork tests).
    /// @param registryProxy The UUPS proxy address for DotnsRegistry.
    /// @param caller The address that owns the proxy and authorises the upgrade.
    function upgradeRegistry(address registryProxy, address caller) public {
        Options memory opts;
        opts.referenceContract = "DotnsRegistryOld.sol:DotnsRegistryOld";
        Upgrades.upgradeProxy(registryProxy, "DotnsRegistry.sol:DotnsRegistry", "", opts, caller);
    }

    /// @notice Post-upgrade verification checks.
    /// @param registryProxy The UUPS proxy address for DotnsRegistry.
    function verifyUpgrade(address registryProxy) public view {
        DotnsRegistry registry = DotnsRegistry(registryProxy);

        string memory versionAfter = registry.version();
        console.log("Version after:", versionAfter);

        require(
            keccak256(bytes(versionAfter)) == keccak256(bytes("1.3.0")),
            "Upgrade failed: version mismatch"
        );

        require(registry.recordExists(bytes32(0)), "Upgrade failed: root record missing");

        address rootOwner = registry.owner(bytes32(0));
        require(rootOwner != address(0), "Upgrade failed: root owner is zero");

        console.log("=== Upgrade verification complete ===");
    }
}
