// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IStore} from "./IStore.sol";

/// @title Store
/// @notice Key-value storage for IPFS URIs, isolated per user address with authorization support.
/// @dev Each address manages its own mapping of bytes32 keys to string IPFS URIs.
///      Authorized contracts can write on behalf of users to enable atomic multi-contract operations.
contract Store is IStore {
    /// @notice Current owner of this store instance.
    /// @dev Initially set to deployer, then transferred to end user. Owner manages authorizations.
    address public owner;

    /// @dev Primary data structure: user address => (key => IPFS URI)
    mapping(address => mapping(bytes32 => string)) private store;

    /// @dev Secondary structure tracking all values per user in insertion order.
    mapping(address => string[]) private values;

    /// @dev Tracks which addresses are authorized to call setValueFor.
    mapping(address => bool) private authorizedStores;

    /// @notice Restricts function access to authorized contracts only.
    /// @dev Reverts with NotAuthorised if caller is not in the authorized list.
    modifier onlyAuthorizedStore() {
        if (!authorizedStores[msg.sender]) {
            revert NotAuthorised(msg.sender);
        }
        _;
    }

    /// @notice Restricts function access to the store owner only.
    /// @dev Reverts with NotAuthorised if caller is not the owner.
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert NotAuthorised(msg.sender);
        }
        _;
    }

    /// @notice Initializes the store with an initial owner.
    /// @dev The initial owner is typically the factory contract that will authorize operational contracts
    ///      before transferring ownership to the end user.
    /// @param initialOwner The address that will initially own this store instance.
    constructor(address initialOwner) {
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    /// @inheritdoc IStore
    function setValue(bytes32 key, string calldata value) external override {
        store[msg.sender][key] = value;
        values[msg.sender].push(value);
        emit ValueStored(msg.sender, key, value);
    }

    /// @inheritdoc IStore
    function setValueFor(
        address user,
        bytes32 key,
        string calldata value
    )
        external
        override
        onlyAuthorizedStore
    {
        store[user][key] = value;
        values[user].push(value);
        emit ValueStored(user, key, value);
    }

    /// @inheritdoc IStore
    function getValue(bytes32 key) external view override returns (string memory) {
        return store[msg.sender][key];
    }

    /// @inheritdoc IStore
    function getValueFor(address user, bytes32 key) external view override returns (string memory) {
        return store[user][key];
    }

    /// @inheritdoc IStore
    function deleteValue(bytes32 key) external override {
        delete store[msg.sender][key];
        emit ValueDeleted(msg.sender, key);
    }

    /// @inheritdoc IStore
    function hasValue(bytes32 key) external view override returns (bool exists) {
        exists = bytes(store[msg.sender][key]).length > 0;
    }

    /// @inheritdoc IStore
    function getValues() external view override returns (string[] memory) {
        return values[msg.sender];
    }

    /// @inheritdoc IStore
    function isAuthorized(address storeAddress) external view override returns (bool authorized) {
        authorized = authorizedStores[storeAddress];
    }

    /// @notice Authorizes an address to call setValueFor on behalf of users.
    /// @dev Only the store owner can authorize new addresses.
    /// @param storeAddress The address to authorize.
    /// @custom:reverts NotAuthorised if caller is not the owner.
    function authorizeStore(address storeAddress) external onlyOwner {
        authorizedStores[storeAddress] = true;
        emit StoreAuthorized(storeAddress);
    }

    /// @notice Revokes authorization for an address to call setValueFor.
    /// @dev Only the store owner can revoke authorizations.
    /// @param storeAddress The address to unauthorize.
    /// @custom:reverts NotAuthorised if caller is not the owner.
    function unauthorizeStore(address storeAddress) external onlyOwner {
        authorizedStores[storeAddress] = false;
        emit StoreUnauthorized(storeAddress);
    }

    /// @inheritdoc IStore
    /// @notice Transfers ownership of the store to a new address.
    /// @dev Only the current owner can transfer ownership. Typically used by factory to transfer
    ///      ownership to the end user after initial setup and authorization configuration.
    /// @param newOwner The address of the new owner.
    /// @custom:reverts NotAuthorised if caller is not the current owner.
    function transferOwnership(address newOwner) external override onlyOwner {
        if (newOwner == address(0)) {
            revert NotAuthorised(address(0));
        }
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }
}
