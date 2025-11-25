// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IStore
/// @notice Interface defining a key-value storage for IPFS URIs scoped by user address.
/// @dev Each user maintains an isolated namespace of key-value pairs. Authorized contracts can write on behalf of users.
interface IStore {
    /// @notice Emitted when a new value is stored or updated.
    /// @param user The address whose storage was modified.
    /// @param key The key under which the value is stored.
    /// @param value The stored IPFS URI.
    event ValueStored(address indexed user, bytes32 indexed key, string value);

    /// @notice Emitted when a value is deleted.
    /// @param user The address whose storage was modified.
    /// @param key The key that was deleted.
    event ValueDeleted(address indexed user, bytes32 indexed key);

    /// @notice Emitted when an address is authorized to write on behalf of users.
    /// @param authorizedAddress The address that was granted authorization.
    event StoreAuthorized(address indexed authorizedAddress);

    /// @notice Emitted when an address loses authorization to write on behalf of users.
    /// @param unauthorizedAddress The address that had authorization revoked.
    event StoreUnauthorized(address indexed unauthorizedAddress);

    /// @notice Emitted when ownership is transferred.
    /// @param previousOwner The address of the previous owner.
    /// @param newOwner The address of the new owner.
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Thrown when an unauthorized address attempts a privileged operation.
    /// @param caller The address that attempted the unauthorized operation.
    error NotAuthorised(address caller);

    /// @notice Store or update an IPFS URI under a given key for the caller.
    /// @dev Keys are scoped to msg.sender to prevent collisions across users.
    /// @param key The unique identifier for the stored value.
    /// @param value The IPFS URI to store.
    function setValue(bytes32 key, string calldata value) external;

    /// @notice Store or update an IPFS URI under a given key for a specified user.
    /// @dev Only authorized contracts can call this function. Keys are scoped to the specified user.
    /// @param user The address whose storage will be modified.
    /// @param key The unique identifier for the stored value.
    /// @param value The IPFS URI to store.
    /// @custom:reverts NotAuthorised if caller is not an authorized contract.
    function setValueFor(address user, bytes32 key, string calldata value) external;

    /// @notice Retrieve the IPFS URI for a given key from caller's storage.
    /// @param key The key to look up.
    /// @return The stored IPFS URI, or an empty string if none exists.
    function getValue(bytes32 key) external view returns (string memory);

    /// @notice Retrieve the IPFS URI for a given key from a specified user's storage.
    /// @dev Allows reading any user's stored data regardless of the caller.
    /// @param user The address whose storage to query.
    /// @param key The key to look up.
    /// @return The stored IPFS URI, or an empty string if none exists.
    function getValueFor(address user, bytes32 key) external view returns (string memory);

    /// @notice Delete a value associated with a key from caller's storage.
    /// @param key The key to delete.
    function deleteValue(bytes32 key) external;

    /// @notice Check if a key has a stored value in caller's storage.
    /// @param key The key to check.
    /// @return exists True if the key has a non-empty value.
    function hasValue(bytes32 key) external view returns (bool exists);

    /// @notice Retrieve all stored values for the caller.
    /// @dev Returns values in the order they were added. May include duplicates if setValue was called multiple times.
    /// @return An array of all IPFS URIs stored by the caller.
    function getValues() external view returns (string[] memory);

    /// @notice Check if an address is authorized to write on behalf of users.
    /// @param storeAddress The address to check authorization status.
    /// @return authorized True if the address is authorized.
    function isAuthorized(address storeAddress) external view returns (bool authorized);

    /// @notice Transfers ownership of the store to a new address.
    /// @dev Only the current owner can transfer ownership. Used by factory to transfer control to end user.
    /// @param newOwner The address of the new owner.
    /// @custom:reverts NotAuthorised if caller is not the current owner or if newOwner is zero address.
    function transferOwnership(address newOwner) external;
}
