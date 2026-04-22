// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";

/// @title BaseDeployer
/// @notice Shared helper for DotNS deploy scripts that accumulates a JSON
///         manifest of proxy addresses and writes it to `deployments/`.
/// @dev Subclassed by {DotnsDeployer} and future deploy scripts; consumers call
///      `initDeployment` once, `logDeployment` per proxy, then `saveDeployments`.
/// @custom:security-contact admin@parity.io
abstract contract BaseDeployer is Script {
    string private deploymentData;
    bool private isFirstEntry = true;

    /// @notice Resets the in-memory manifest so a new deploy run starts clean.
    function initDeployment() internal {
        deploymentData = string(abi.encodePacked('{\n"contracts": {\n'));
        isFirstEntry = true;
    }

    /// @notice Appends a single `name => address` entry to the manifest.
    /// @param name Label under which the address is recorded.
    /// @param addr Proxy or contract address to record.
    function logDeployment(string memory name, address addr) internal {
        if (!isFirstEntry) {
            deploymentData = string(abi.encodePacked(deploymentData, ",\n"));
        }
        isFirstEntry = false;

        deploymentData =
            string(abi.encodePacked(deploymentData, '    "', name, '": "', vm.toString(addr), '"'));
    }

    /// @notice Closes the manifest object and writes it to
    ///         `deployments/<subdirectory>/<filename>.json`.
    /// @dev Shells out via `vm.ffi` to ensure the target directory exists.
    /// @param subdirectory Network-specific folder under `deployments/`.
    /// @param filename Stem of the output JSON file (without extension).
    function saveDeployments(string memory subdirectory, string memory filename) internal {
        deploymentData = string(abi.encodePacked(deploymentData, "\n  }\n}"));
        string memory deploymentsDir = string(abi.encodePacked("./deployments/", subdirectory));

        string[] memory mkdirInputs = new string[](3);
        mkdirInputs[0] = "mkdir";
        mkdirInputs[1] = "-p";
        mkdirInputs[2] = deploymentsDir;
        vm.ffi(mkdirInputs);

        string memory filepath = string(abi.encodePacked(deploymentsDir, "/", filename, ".json"));
        vm.writeFile(filepath, deploymentData);
    }
}
