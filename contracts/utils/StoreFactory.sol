// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IStoreFactory} from "./IStoreFactory.sol";
import {IStore} from "./IStore.sol";
import {Store} from "./Store.sol";

/// @title StoreFactory
/// @notice Factory contract for deploying and tracking user-specific store instances
/// @dev Uses CREATE opcode for deployment. Each address can deploy exactly one store.
contract StoreFactory is IStoreFactory {
    /// @notice Maps owner addresses to their deployed store contracts
    /// @dev Zero address indicates no store has been deployed for that address
    mapping(address => IStore) private _deployedStores;

    /// @inheritdoc IStoreFactory
    function deploy() external {
        IStore existingStore = _deployedStores[msg.sender];

        require(address(existingStore) == address(0), AlreadyDeployed(address(existingStore)));

        Store newStore = new Store(msg.sender);
        _deployedStores[msg.sender] = IStore(address(newStore));

        emit StoreDeployed(msg.sender, IStore(address(newStore)));
    }

    /// @inheritdoc IStoreFactory
    function getDeployedStore(address who) external view returns (IStore) {
        return _deployedStores[who];
    }
}
