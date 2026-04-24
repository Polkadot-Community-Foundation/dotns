// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IDotnsProtocolRegistry
/// @notice Interface for the DotNS protocol-level address registry.
/// @custom:security-contact admin@parity.io
interface IDotnsProtocolRegistry {
    /// @notice Emitted when a protocol address is set or updated.
    /// @param key The well-known key identifying the contract role.
    /// @param addr The new address assigned to that key.
    event AddressUpdated(bytes32 indexed key, address indexed addr);

    /// @notice Thrown when a zero address is provided where one is not allowed.
    error ZeroAddress();

    /// @notice Returns the address stored for a given key.
    /// @dev Returns `address(0)` if the key has not been set.
    /// @param key The well-known key identifying the contract role.
    /// @return addr The stored address.
    function get(bytes32 key) external view returns (address addr);

    /// @notice Sets or updates the address for a given key.
    /// @dev Callable only by the contract owner.
    /// @param key The well-known key identifying the contract role.
    /// @param addr The address to assign. Must not be the zero address.
    /// @custom:reverts OwnableUnauthorizedAccount
    /// @custom:reverts ZeroAddress
    /// @custom:emits AddressUpdated
    function set(bytes32 key, address addr) external;

    /// @notice Returns true iff `addr` is currently registered under at least one well-known key.
    /// @dev O(1) refcount-backed lookup. Canonical auth check consumed by LabelStore writes and
    ///      StoreFactory label-store deploys. Governance-controlled: only addresses governance
    ///      has actively registered return true.
    /// @param addr The address to check.
    /// @return registered True iff `addr != 0` and at least one registry key points to `addr`.
    function isRegisteredAddress(address addr) external view returns (bool registered);
}
