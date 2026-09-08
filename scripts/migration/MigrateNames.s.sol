// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";

import {IDotnsController} from "../../contracts/registrars/IDotnsController.sol";
import {IDotnsRegistrar} from "../../contracts/registrars/IDotnsRegistrar.sol";
import {IDotnsProtocolRegistry} from "../../contracts/registry/IDotnsProtocolRegistry.sol";
import {DotnsConstants} from "../../contracts/utils/DotnsConstants.sol";
import {DotnsMigrationController} from "./DotnsMigrationController.sol";

/// @title MigrateNames
/// @notice Replays a previous deployment's names onto a fresh DotNS deployment through a
///         one-off registrar controller. Run by the registrar owner.
/// @dev Inputs (environment):
///      - MIGRATION_ENTRIES   path to the entries JSON (`{"entries":[{holder,label,node}]}`),
///                            produced from a snapshot by snapshot-to-entries.py.
///      - PROTOCOL_REGISTRY   target protocol registry; defaults to the `DotnsProtocolRegistry`
///                            entry of `MIGRATION_MANIFEST` (default
/// deployments/pcf-devnet/420420417.json). - MIGRATION_CONTROLLER optional, reuse an already
/// deployed controller instead of
///                            deploying one.
///      - MIGRATION_BATCH     names per `migrate` call (default 5; each mint may deploy the
///                            holder's label store, so keep batches small on pallet-revive).
///      - MIGRATION_KEEP_CONTROLLER set to 1 to leave the controller registered (resume later).
///      Idempotent: entries whose id is already minted are skipped, so a partial run can be
///      re-run as is. Without --broadcast this is a full simulation, which is the dry run.
contract MigrateNames is Script {
    /// Field order must stay alphabetical: forge decodes JSON objects positionally by sorted key.
    struct JsonEntry {
        address holder;
        string label;
        bytes32 node;
    }

    function run() external {
        string memory manifest =
            vm.envOr("MIGRATION_MANIFEST", string("deployments/pcf-devnet/420420417.json"));
        address registryAddr = vm.envOr(
            "PROTOCOL_REGISTRY",
            vm.parseJsonAddress(vm.readFile(manifest), ".DotnsProtocolRegistry")
        );
        IDotnsProtocolRegistry protocolRegistry = IDotnsProtocolRegistry(registryAddr);
        IDotnsRegistrar registrar = IDotnsRegistrar(protocolRegistry.get(DotnsConstants.REGISTRAR));

        string memory json = vm.readFile(vm.envString("MIGRATION_ENTRIES"));
        JsonEntry[] memory all = abi.decode(vm.parseJson(json, ".entries"), (JsonEntry[]));
        uint256 batchSize = vm.envOr("MIGRATION_BATCH", uint256(5));

        // Drop entries already minted so a rerun resumes.
        DotnsMigrationController.Entry[] memory pending =
            new DotnsMigrationController.Entry[](all.length);
        uint256 n;
        for (uint256 i = 0; i < all.length; ++i) {
            uint256 id = uint256(all[i].node);
            if (registrar.exists(id)) {
                console.log("skip (already minted):", all[i].label);
                continue;
            }
            pending[n++] = DotnsMigrationController.Entry({
                id: id, holder: all[i].holder, label: all[i].label
            });
        }
        console.log("protocol registry:", registryAddr);
        console.log("registrar:", address(registrar));
        console.log("entries:", all.length, "pending:", n);
        if (n == 0) return;

        vm.startBroadcast();
        address sender = msg.sender;
        address existing = vm.envOr("MIGRATION_CONTROLLER", address(0));
        DotnsMigrationController controller = existing == address(0)
            ? new DotnsMigrationController(protocolRegistry, sender)
            : DotnsMigrationController(existing);
        console.log("migration controller:", address(controller));
        if (!registrar.controllers(IDotnsController(address(controller)))) {
            registrar.addController(IDotnsController(address(controller)));
        }
        for (uint256 start = 0; start < n; start += batchSize) {
            uint256 len = n - start < batchSize ? n - start : batchSize;
            DotnsMigrationController.Entry[] memory batch =
                new DotnsMigrationController.Entry[](len);
            for (uint256 j = 0; j < len; ++j) {
                batch[j] = pending[start + j];
                console.log("migrate:", batch[j].label, batch[j].holder);
            }
            controller.migrate(batch);
        }
        if (!vm.envOr("MIGRATION_KEEP_CONTROLLER", false)) {
            registrar.removeController(IDotnsController(address(controller)));
        }
        vm.stopBroadcast();

        // Post-state check in the same simulation.
        for (uint256 i = 0; i < n; ++i) {
            require(
                registrar.ownerOf(pending[i].id) == pending[i].holder,
                "holder mismatch after migrate"
            );
        }
        console.log("migrated:", n);
    }
}
