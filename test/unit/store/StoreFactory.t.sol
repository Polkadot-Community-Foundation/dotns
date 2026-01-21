// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../../base/BaseDotns.t.sol";
import {Store, IStore} from "../../../contracts/store/Store.sol";
import {IStoreFactory} from "../../../contracts/store/StoreFactory.sol";

contract StoreFactoryTests is BaseDotns {
    function test_deploy_reverts_when_already_deployed() public {
        vm.startPrank(ed);
        IStore deployed = storeFactory.deploy();

        vm.expectRevert(
            abi.encodeWithSelector(IStoreFactory.AlreadyDeployed.selector, address(deployed))
        );
        storeFactory.deploy();
        vm.stopPrank();
    }

    function test_transferownership_moves_mapping_and_emits() public {
        vm.startPrank(ed);
        IStore deployed = storeFactory.deploy();

        vm.expectEmit(true, true, true, false);
        emit IStoreFactory.OwnershipTransfered(ed, leonardo);

        storeFactory.transferOwnership(leonardo);
        vm.stopPrank();

        assertEq(address(storeFactory.getDeployedStore(ed)), address(0));
        assertEq(address(storeFactory.getDeployedStore(leonardo)), address(deployed));
        assertEq(Store(address(deployed)).owner(), ed);
    }

    function test_transferownership_reverts_when_caller_has_no_store() public {
        vm.startPrank(tiago);
        vm.expectRevert(abi.encodeWithSelector(IStoreFactory.InvalidTransfer.selector, tiago));
        storeFactory.transferOwnership(leonardo);
        vm.stopPrank();
    }

    function test_transferownership_reverts_when_new_owner_already_has_store() public {
        vm.startPrank(ed);
        storeFactory.deploy();
        vm.stopPrank();

        vm.startPrank(leonardo);
        storeFactory.deploy();
        vm.stopPrank();

        vm.startPrank(ed);
        vm.expectRevert(abi.encodeWithSelector(IStoreFactory.InvalidTransfer.selector, leonardo));
        storeFactory.transferOwnership(leonardo);
        vm.stopPrank();
    }

    function test_transferownership_to_zero_address_updates_mapping() public {
        vm.startPrank(ed);
        IStore deployed = storeFactory.deploy();

        vm.expectEmit(true, true, true, false);
        emit IStoreFactory.OwnershipTransfered(ed, address(0));

        storeFactory.transferOwnership(address(0));
        vm.stopPrank();

        assertEq(address(storeFactory.getDeployedStore(ed)), address(0));
        assertEq(address(storeFactory.getDeployedStore(address(0))), address(deployed));
        assertEq(Store(address(deployed)).owner(), ed);
    }

    function test_deploy_after_transferownership_creates_new_store_for_old_owner() public {
        vm.startPrank(ed);
        IStore first = storeFactory.deploy();
        storeFactory.transferOwnership(leonardo);
        IStore second = storeFactory.deploy();
        vm.stopPrank();

        assertEq(address(storeFactory.getDeployedStore(ed)), address(second));
        assertEq(address(storeFactory.getDeployedStore(leonardo)), address(first));
        assertEq(Store(address(first)).owner(), ed);
        assertEq(Store(address(second)).owner(), ed);
        assertTrue(address(first) != address(second));
    }
}
