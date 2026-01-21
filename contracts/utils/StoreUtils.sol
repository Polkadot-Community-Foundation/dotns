// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Store} from "../store/Store.sol";
import {IStore} from "../store/IStore.sol";
import {IStoreFactory} from "../store/IStoreFactory.sol";

/// @title DotNS Store Utilities Library
/// @notice Provides Store acquisition and management
///         utilities for any contract that requires a store.
///
/// @dev Store Resolution Strategy:
///      The library implements a three-tier resolution strategy:
///      1. Direct mapping: Store already exists and is mapped to the target owner.
///      2. Controller mapping: Store exists under the controller's address and must be migrated.
///      3. Fresh deployment: No store exists; deploy, authorize, and transfer ownership.
/// @custom:security-contact admin@parity.io
library StoreUtils {
    /// @notice Returns the Store for `owner`, deploying or migrating one if needed.
    /// @dev Unifies Store acquisition across registration flows. Handles three cases:
    ///
    ///      Case 1 - Direct Mapping:
    ///      Store already mapped to `owner` in the factory. Returns immediately.
    ///
    ///      Case 2 - Controller Migration:
    ///      Store mapped to the calling controller in the factory. Transfers the factory
    ///      mapping to `owner` and returns the migrated Store.
    ///
    ///      Case 3 - Fresh Deployment:
    ///      No store exists for either address. Deploys a new Store under the controller,
    ///      authorizes the controller for DotNS writes, transfers Store ownership to `owner`,
    ///      then migrates the factory mapping to `owner`.
    ///
    /// @dev Reentrancy Consideration:
    ///      While no explicit reentrancy guard is applied, the deployed Store contract
    ///      is not expected to call back into this function. Callers should ensure
    ///      the Store implementation does not introduce unexpected callbacks.
    ///       In any case the StoreFactory and Store arent upgradeable nor do they
    ///       Make any external calls that could engender such a scenario
    ///
    /// @param factory The StoreFactory instance used to resolve or deploy Stores.
    /// @param controllers The addresses that should be approved for writes
    /// @param owner The target Store owner address
    /// @return store The resolved or newly deployed Store instance.
    function getOrCreateStore(
        IStoreFactory factory,
        address[] memory controllers,
        address owner
    )
        internal
        returns (Store store)
    {
        IStore existing = factory.getDeployedStore(owner);
        if (address(existing) != address(0)) {
            return Store(address(existing));
        }

        IStore controllerMapped = factory.getDeployedStore(msg.sender);

        if (address(controllerMapped) != address(0) && owner == msg.sender) {
            factory.transferOwnership(owner);

            IStore migrated = factory.getDeployedStore(owner);
            require(address(migrated) != address(0), IStoreFactory.InvalidTransfer(owner));

            return Store(address(migrated));
        }

        store = Store(address(factory.deploy()));
        for (uint256 i; i < controllers.length; i++) {
            store.authorizeDotnsController(controllers[i]);
        }

        store.transferOwnership(owner);
        factory.transferOwnership(owner);
    }

    /// @notice Checks whether a Store exists for the given owner.
    /// @dev Performs a read-only lookup against the factory without any state changes.
    /// @param factory The StoreFactory instance to query.
    /// @param owner The address to check for an existing Store.
    /// @return exists True if a Store is mapped to `owner`, false otherwise.
    function hasStore(IStoreFactory factory, address owner) internal view returns (bool exists) {
        IStore existing = factory.getDeployedStore(owner);
        exists = address(existing) != address(0);
    }

    /// @notice Returns the Store address for an owner without deploying.
    /// @dev Returns zero address if no Store exists. Use `hasStore` for boolean checks.
    /// @param factory The StoreFactory instance to query.
    /// @param owner The address to look up.
    /// @return store The Store address, or zero if none exists.
    function getStore(IStoreFactory factory, address owner) internal view returns (address store) {
        IStore existing = factory.getDeployedStore(owner);
        store = address(existing);
    }
}
