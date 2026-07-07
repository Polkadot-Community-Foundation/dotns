// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Vm} from "forge-std/Vm.sol";

/// @title DeploymentNetwork
/// @notice Maps the current chain ID to the subdirectory under
///         `deployments/` every stage script reads from and writes to.
/// @dev Shared by every stage so the manifest path stays consistent across
///      the pipeline. Adding a new network is a single-line change here.
///      Chains that share an EVM chain id (e.g. paseo-next and summit both
///      report 420420417) are disambiguated with the DOTNS_DEPLOYMENT_FOLDER
///      env override, which takes precedence over the chain-id mapping.
/// @custom:security-contact admin@parity.io
library DeploymentNetwork {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function folder(uint256 chainId) internal view returns (string memory name) {
        name = "localhost";
        if (chainId == 420420422) name = "passethub-testnet";
        if (chainId == 420420417) name = "summit-asset-hub";
        if (chainId == 420420420) name = "paseo-local";
        name = vm.envOr("DOTNS_DEPLOYMENT_FOLDER", name);
    }
}
