// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/Script.sol";
import {BaseDeployer} from "./BaseDeployer.s.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {PopRules} from "../contracts/pop/popRules.sol";

/// @title DotnsUpgradesDeployer
contract DotnsUpgrades is BaseDeployer {
    uint256 public constant RENT_PRICE = 2e15 wei;

    address public constant POP_ORACLE_PROXY =
        0xdE40254fF6470CE8b6683d2FCFD0599B2BcfC3Af;

    function run() external {
        address upgrader = msg.sender;
        vm.startBroadcast(upgrader);
        Options memory upgradeOptions;
        upgradeOptions.referenceContract = "PopOracle.sol:PopOracle";

        Upgrades.upgradeProxy(
            POP_ORACLE_PROXY,
            "PopRules.sol:PopRules",
            bytes(""),
            upgradeOptions
        );

        vm.stopBroadcast();
    }

}
