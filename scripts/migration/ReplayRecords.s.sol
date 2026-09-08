// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";

import {IDotnsRegistry} from "../../contracts/registry/IDotnsRegistry.sol";
import {IDotnsContentResolver} from "../../contracts/resolvers/IDotnsContentResolver.sol";
import {IDotnsProtocolRegistry} from "../../contracts/registry/IDotnsProtocolRegistry.sol";
import {DotnsConstants} from "../../contracts/utils/DotnsConstants.sol";

/// @title ReplayRecords
/// @notice Replays resolver records from a snapshot for the names the broadcasting account
///         holds: binds the content resolver, sets the contenthash, sets each text record.
/// @dev The resolvers only authorise the node owner, so this must be broadcast by each holder
///      in turn; entries held by other accounts are skipped and reported. Holders whose key is a
///      substrate account with a mapped EVM address sign the same calls through pallet-revive
///      instead (see the runbook), this script covers keystore-held EVM keys.
///      Inputs: MIGRATION_ENTRIES (entries JSON, `.records`), MIGRATION_MANIFEST or
///      PROTOCOL_REGISTRY as in MigrateNames. Idempotent: values already equal are skipped.
contract ReplayRecords is Script {
    /// Alphabetical field order (forge decodes JSON objects positionally by sorted key).
    struct JsonRecord {
        bytes contenthash;
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
        IDotnsRegistry registry = IDotnsRegistry(protocolRegistry.get(DotnsConstants.REGISTRY));
        IDotnsContentResolver content =
            IDotnsContentResolver(protocolRegistry.get(DotnsConstants.CONTENT_RESOLVER));

        string memory json = vm.readFile(vm.envString("MIGRATION_ENTRIES"));
        // `text` is an object with arbitrary keys, so it is read per entry rather than decoded
        // into the struct.
        JsonRecord[] memory records = abi.decode(vm.parseJson(json, ".records"), (JsonRecord[]));

        vm.startBroadcast();
        address me = msg.sender;
        uint256 done;
        for (uint256 i = 0; i < records.length; ++i) {
            JsonRecord memory r = records[i];
            if (r.holder != me) {
                console.log("skip (held by another account):", r.label, r.holder);
                continue;
            }
            if (registry.resolver(r.node) != address(content)) {
                registry.setResolver(r.node, address(content));
                console.log("resolver bound:", r.label);
            }
            if (
                r.contenthash.length != 0
                    && keccak256(content.contenthash(r.node)) != keccak256(r.contenthash)
            ) {
                content.setContenthash(r.node, r.contenthash);
                console.log("contenthash set:", r.label);
            }
            string memory base = string.concat(".records[", vm.toString(i), "].text");
            string[] memory keys = vm.parseJsonKeys(json, base);
            for (uint256 k = 0; k < keys.length; ++k) {
                string memory value = vm.parseJsonString(json, string.concat(base, ".", keys[k]));
                if (keccak256(bytes(content.text(r.node, keys[k]))) != keccak256(bytes(value))) {
                    content.setText(r.node, keys[k], value);
                    console.log("text set:", r.label, keys[k]);
                }
            }
            ++done;
        }
        vm.stopBroadcast();
        console.log("names replayed for", me, ":", done);
    }
}
