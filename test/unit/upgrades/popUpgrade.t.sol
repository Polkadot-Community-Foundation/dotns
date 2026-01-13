// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../../base/BaseDotns.t.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

import {IPopOracle} from "../../../contracts/pop/IPopOracle.sol";
import {PopOracle} from "../../../contracts/pop/PopOracle.sol";

import {IPopRules} from "../../../contracts/pop/IPopRules.sol";
import {PopRules} from "../../../contracts/pop/PopRules.sol";

contract PopRulesUpgradeTest is BaseDotns {
    uint256 internal constant STARTING_PRICE = 1 ether;
    address internal popProxyAddress;

    function setUp() public override {
        super.setUp();
        vm.startPrank(owner);
        popProxyAddress = Upgrades.deployUUPSProxy(
            "PopOracle.sol:PopOracle", abi.encodeCall(PopOracle.initialize, (STARTING_PRICE))
        );
        vm.stopPrank();
    }

    function test_upgrade_preserves_storage_and_updates_pricing() public {
        address popFullUser = ed;
        address noStatusUser = tiago;

        PopOracle popOracleView = PopOracle(popProxyAddress);

        uint256 startingPriceBefore = popOracleView.startingPrice();
        assertEq(startingPriceBefore, STARTING_PRICE);

        vm.prank(popFullUser);
        IPopOracle(popProxyAddress).setUserPopStatus(IPopOracle.PopStatus.PopFull);

        vm.prank(owner);
        IPopOracle(popProxyAddress).updateEthRegistry(address(this));
        assertEq(popOracleView.ethRegistryController(), address(this));

        IPopOracle(popProxyAddress).reserveBaseName("lights01", popFullUser);

        (bool reservedBefore, address reservationOwnerBefore, uint64 expiresBefore) =
            IPopOracle(popProxyAddress).isBaseNameReserved("lights");

        assertTrue(reservedBefore);
        assertEq(reservationOwnerBefore, popFullUser);
        assertTrue(expiresBefore > uint64(block.timestamp));

        string memory popFullPricedName = "abcdefgh1";
        uint256 oldPopFullPrice =
            IPopOracle(popProxyAddress).priceWithCheck(popFullPricedName, popFullUser).price;
        assertTrue(oldPopFullPrice > 0);

        Options memory upgradeOptions;
        upgradeOptions.referenceContract = "PopOracle.sol:PopOracle";

        vm.startPrank(owner);
        Upgrades.upgradeProxy(popProxyAddress, "PopRules.sol:PopRules", bytes(""), upgradeOptions);
        vm.stopPrank();

        PopRules popRulesView = PopRules(popProxyAddress);

        assertEq(popRulesView.startingPrice(), startingPriceBefore);
        assertEq(popRulesView.ethRegistryController(), address(this));

        assertEq(
            uint256(popRulesView.userPopStatus(popFullUser)), uint256(IPopRules.PopStatus.PopFull)
        );

        (bool reservedAfter, address reservationOwnerAfter, uint64 expiresAfter) =
            IPopRules(popProxyAddress).isBaseNameReserved("lights");

        assertTrue(reservedAfter);
        assertEq(reservationOwnerAfter, reservationOwnerBefore);
        assertEq(expiresAfter, expiresBefore);

        // New behavior: PopFull is free.
        uint256 newPopFullPrice =
            IPopRules(popProxyAddress).priceWithCheck(popFullPricedName, popFullUser).price;
        assertEq(newPopFullPrice, 0);

        // NoStatus still pays (2 trailing digits, total length >= 9).
        string memory noStatusPricedName = "kitesurfing01";
        uint256 newNoStatusPrice =
            IPopRules(popProxyAddress).priceWithCheck(noStatusPricedName, noStatusUser).price;
        assertTrue(newNoStatusPrice > 0);
    }
}
