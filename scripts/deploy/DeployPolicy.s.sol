// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/Script.sol";
import {BaseDeployer} from "./BaseDeployer.s.sol";
import {DeploymentNetwork} from "./DeploymentNetwork.sol";

import {DotnsRegistrarController} from "../../contracts/registrars/DotnsRegistrarController.sol";
import {IDotnsProtocolRegistry} from "../../contracts/registry/IDotnsProtocolRegistry.sol";

/// @title DeployPolicy
/// @notice Third stage. Deploys the commit-reveal controller, which binds to
///         the protocol registry populated by `DeployCore`.
/// @custom:security-contact admin@parity.io
contract DeployPolicy is BaseDeployer {
    uint64 public constant MIN_COMMITMENT_AGE = 6 seconds;
    uint64 public constant MAX_COMMITMENT_AGE = 1 days;

    function run() external {
        address owner = msg.sender;
        vm.label(owner, "OWNER");

        initDeployment(DeploymentNetwork.folder(block.chainid), vm.toString(block.chainid));

        _deployRegistrarController(owner);

        saveDeployments();

        console.log("=== DeployPolicy complete ===");
    }

    function _deployRegistrarController(address owner) internal returns (address proxy) {
        proxy = _broadcastDeployUups(
            owner,
            "DotnsRegistrarController.sol:DotnsRegistrarController",
            abi.encodeCall(
                DotnsRegistrarController.initialize,
                (
                    IDotnsProtocolRegistry(_readAddress("DotnsProtocolRegistry")),
                    MIN_COMMITMENT_AGE,
                    MAX_COMMITMENT_AGE
                )
            ),
            "DotnsRegistrarController"
        );
    }
}
