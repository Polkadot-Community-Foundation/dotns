// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {DotnsRegistry} from "../contracts/registry/DotnsRegistry.sol";

/// @title UpgradeDotnsRegistry
/// @notice Upgrades the DotnsRegistry proxy to a new implementation.
/// @dev Fixes Store key derivation: uses subnode hash instead of labelhash
///      to prevent key collisions when the same sublabel is registered
///      under different parent domains owned by the same address.
contract UpgradeDotnsRegistry is Script {
    address constant DOTNS_REGISTRY_PROXY = 0x4Da0d37aBe96C06ab19963F31ca2DC0412057a6f;

    function run() external {
        vm.startBroadcast(msg.sender);

        Options memory opts;
        opts.referenceContract = "DotnsRegistryOld.sol:DotnsRegistryOld";

        Upgrades.upgradeProxy(DOTNS_REGISTRY_PROXY, "DotnsRegistry.sol:DotnsRegistry", "", opts);

        DotnsRegistry proxy = DotnsRegistry(DOTNS_REGISTRY_PROXY);
        string memory newVersion = proxy.version();

        console.log("DotnsRegistry upgraded at", DOTNS_REGISTRY_PROXY);
        console.log("Version:", newVersion);

        require(
            keccak256(bytes(newVersion)) == keccak256(bytes("1.1.0")),
            "Version mismatch: expected 1.1.0"
        );

        vm.stopBroadcast();
    }
}
