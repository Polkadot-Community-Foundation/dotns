// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import {DotnsRegistrarController} from "../contracts/registrars/DotnsRegistrarController.sol";
import {DotnsRegistrar} from "../contracts/registrars/DotnsRegistrar.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/// @title UpgradeControllerAndRegistrar
/// @notice Upgrades both DotnsRegistrarController and DotnsRegistrar proxies to v1.2.0.
/// @dev Fixes selector mismatch: the previous controller was compiled against the old
///      IDotnsRegistrar.register(uint256,address,bytes32) interface. The new registrar
///      accepts register(uint256,address,string) and stores the human-readable label.
contract UpgradeController is Script {
    address constant CONTROLLER_PROXY = 0xd09e0F1c1E6CE8Cf40df929ef4FC778629573651;
    address constant REGISTRAR_PROXY = 0x329aAA5b6bEa94E750b2dacBa74Bf41291E6c2BD;

    function run() external {
        Options memory registrarOpts;
        registrarOpts.referenceContract = "DotnsRegistrarOld.sol:DotnsRegistrarOld";

        Options memory controllerOpts;
        controllerOpts.referenceContract = "DotnsRegistrarControllerOld.sol:DotnsRegistrarControllerOld";

        vm.startBroadcast(msg.sender);

        Upgrades.upgradeProxy(
            REGISTRAR_PROXY,
            "DotnsRegistrar.sol:DotnsRegistrar",
            "",
            registrarOpts
        );
        console.log("Registrar upgraded. Version:", DotnsRegistrar(REGISTRAR_PROXY).version());

        Upgrades.upgradeProxy(
            CONTROLLER_PROXY,
            "DotnsRegistrarController.sol:DotnsRegistrarController",
            "",
            controllerOpts
        );
        console.log("Controller upgraded. Version:", DotnsRegistrarController(CONTROLLER_PROXY).version());

        vm.stopBroadcast();
    }
}
