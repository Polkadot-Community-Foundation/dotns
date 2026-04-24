// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../../base/BaseDotns.t.sol";
import {StoreInvariantHandler} from "./StoreInvariantHandler.t.sol";
import {ILabelStore} from "../../../contracts/store/ILabelStore.sol";
import {IUserStore} from "../../../contracts/store/IUserStore.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract StoreInvariantTest is BaseDotns {
    StoreInvariantHandler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new StoreInvariantHandler(
            storeFactory, protocolRegistry, owner, address(dotnsRegistrarController)
        );
        targetContract(address(handler));
    }

    function invariant_locked_labels_never_unlock() public view {
        uint256 stores = handler.labelStoreCount();
        for (uint256 i; i < stores; ++i) {
            address store = handler.labelStores(i);
            uint256 labelhashCount = handler.writtenLabelhashCount(store);
            for (uint256 j; j < labelhashCount; ++j) {
                bytes32 labelhash = handler.writtenLabelhashAt(store, j);
                assertTrue(ILabelStore(store).isLocked(labelhash));
            }
        }
    }

    function invariant_locked_label_text_never_changes() public view {
        uint256 stores = handler.labelStoreCount();
        for (uint256 i; i < stores; ++i) {
            address store = handler.labelStores(i);
            uint256 labelhashCount = handler.writtenLabelhashCount(store);
            for (uint256 j; j < labelhashCount; ++j) {
                bytes32 labelhash = handler.writtenLabelhashAt(store, j);
                assertEq(
                    ILabelStore(store).getLabel(labelhash), handler.frozenLabel(store, labelhash)
                );
            }
        }
    }

    function invariant_at_most_one_store_of_each_type_per_user() public view {
        uint256 userCount = handler.userCount();
        for (uint256 i; i < userCount; ++i) {
            address user = handler.users(i);
            address labelStore = storeFactory.getLabelStore(user);
            address userStore = storeFactory.getUserStore(user);
            // Tautological that at most one exists because mappings are scalar; the
            // property we assert is that observed ghost arrays stay consistent with
            // the factory's canonical lookup.
            if (labelStore != address(0)) {
                assertEq(ILabelStore(labelStore).owner(), user);
            }
            if (userStore != address(0)) {
                assertEq(IUserStore(userStore).owner(), user);
                assertEq(handler.userStoreOwnerOf(userStore), user);
            }
        }
    }

    function invariant_factory_owns_both_beacons() public view {
        assertEq(UpgradeableBeacon(storeFactory.labelStoreBeacon()).owner(), address(storeFactory));
        assertEq(UpgradeableBeacon(storeFactory.userStoreBeacon()).owner(), address(storeFactory));
    }

    function invariant_enumeration_matches_counters() public view {
        assertEq(storeFactory.getLabelStoreCount(), handler.labelStoreCount());
        assertEq(storeFactory.getUserStoreCount(), handler.userStoreCount());
    }
}
