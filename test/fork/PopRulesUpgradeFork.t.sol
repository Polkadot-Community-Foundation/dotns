// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {PopRules} from "../../contracts/pop/PopRules.sol";
import {DotnsProtocolRegistry} from "../../contracts/registry/DotnsProtocolRegistry.sol";
import {DotnsConstants} from "../../contracts/utils/DotnsConstants.sol";

import {UpgradePopRules} from "../../scripts/deploy/UpgradePopRules.s.sol";

/// @title PopRules upgrade fork test
/// @notice Exercises the dedicated {UpgradePopRules} script against live Paseo AssetHub.
///         Runs in its own fork simulation so OZ upgrade-safety validation stays inside
///         the per-process memory budget. Keeps the upgrade script and its fork coverage
///         1:1: every action `UpgradePopRules.upgrade` performs is asserted here.
contract PopRulesUpgradeForkTest is Test {
    UpgradePopRules public upgradeScript;

    PopRules public popRules;
    DotnsProtocolRegistry public protocolRegistry;

    address public popRulesOwner;

    string public preUpgradeVersion;
    address public preUpgradeProtocolRegistry;

    function setUp() public {
        vm.createSelectFork("paseo_local");

        upgradeScript = new UpgradePopRules();

        popRules = PopRules(upgradeScript.POP_RULES_PROXY());
        protocolRegistry = DotnsProtocolRegistry(upgradeScript.PROTOCOL_REGISTRY_PROXY());

        popRulesOwner = OwnableUpgradeable(address(popRules)).owner();

        // Snapshot before mutation so post-upgrade assertions can prove the upgrade
        // actually moved state rather than passing vacuously.
        preUpgradeVersion = popRules.version();
        preUpgradeProtocolRegistry = address(popRules.protocolRegistry());

        upgradeScript.upgrade(popRulesOwner);
        upgradeScript.verifyUpgrade();
    }

    function test_version_bumped() public view {
        assertEq(popRules.version(), upgradeScript.POP_RULES_VERSION());
        assertTrue(
            keccak256(bytes(preUpgradeVersion)) != keccak256(bytes(popRules.version())),
            "version should advance across the upgrade"
        );
    }

    function test_protocol_registry_wired() public view {
        assertEq(address(popRules.protocolRegistry()), address(protocolRegistry));
    }

    // Cheap live-state sanity check: the registrar address PopRules resolves through
    // the protocol registry must be the same address that downstream controllers
    // authorise against. An unset pointer silently reverts every cross-flow write.
    function test_registrar_reachable_via_protocol_registry() public view {
        assertTrue(protocolRegistry.get(DotnsConstants.REGISTRAR) != address(0));
    }

    // MAX_RESERVATION_TIME is a pre-upgrade invariant that must survive the bump.
    // A storage-layout regression would shift the slot and read garbage.
    function test_constants_survive_upgrade() public view {
        assertEq(popRules.MAX_RESERVATION_TIME(), 12 weeks);
    }
}
