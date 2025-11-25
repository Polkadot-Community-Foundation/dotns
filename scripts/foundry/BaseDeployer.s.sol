// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

abstract contract BaseDeployer is Script {
    string private deploymentData;
    bool private isFirstEntry = true;

    function initDeployment(uint256 chainId) internal {
        deploymentData = string(
            abi.encodePacked('{\n  "chain_id": "', vm.toString(chainId), '",\n  "contracts": {\n')
        );
        isFirstEntry = true;
    }

    function logDeployment(string memory name, address addr) internal {
        if (!isFirstEntry) {
            deploymentData = string(abi.encodePacked(deploymentData, ",\n"));
        }
        isFirstEntry = false;

        deploymentData =
            string(abi.encodePacked(deploymentData, '    "', name, '": "', vm.toString(addr), '"'));
    }

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
