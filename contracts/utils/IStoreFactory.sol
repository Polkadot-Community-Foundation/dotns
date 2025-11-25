// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IStore} from "./IStore.sol";

/// @title IStoreFactory
/// @notice Interface defining factory functions for deploying and managing user-specific stores
/// @dev Each address can deploy a single store instance. Subsequent deployment attempts revert.
interface IStoreFactory {
    /// @notice Deploys a new store contract for the caller
    /// @dev Creates a store instance owned by msg.sender. Reverts if caller already has a deployed store.
    /// @custom:reverts AlreadyDeployed if msg.sender has previously deployed a store
    function deploy() external;

    /// @notice Retrieves the store contract address deployed by a specific user
    /// @dev Returns the zero address if no store has been deployed by the specified address
    /// @param who The address of the store owner to query
    /// @return The IStore instance deployed by the specified address, or zero address if none exists
    function getDeployedStore(address who) external view returns (IStore);

    /// @notice Emitted when a store is successfully deployed
    /// @param owner The address that deployed and owns the store
    /// @param store The address of the newly deployed store contract
    event StoreDeployed(address indexed owner, IStore indexed store);

    /// @notice Thrown when attempting to deploy a store for an address that already has one
    /// @param existingStore The address of the store already deployed by the caller
    error AlreadyDeployed(address existingStore);
}
