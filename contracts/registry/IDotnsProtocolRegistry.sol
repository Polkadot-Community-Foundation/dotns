// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// Lookup keys for IDotnsProtocolRegistry.get / .set.
// casting to 'bytes32' is safe because all key strings fit in 32 bytes.
// forge-lint: disable-next-line(unsafe-typecast)
bytes32 constant KEY_CONTROLLER = bytes32("controller");
// forge-lint: disable-next-line(unsafe-typecast)
bytes32 constant KEY_REGISTRAR = bytes32("registrar");
// forge-lint: disable-next-line(unsafe-typecast)
bytes32 constant KEY_REGISTRY = bytes32("registry");
// forge-lint: disable-next-line(unsafe-typecast)
bytes32 constant KEY_REVERSE_RESOLVER = bytes32("reverseResolver");
// forge-lint: disable-next-line(unsafe-typecast)
bytes32 constant KEY_POP_RULES = bytes32("popRules");
// forge-lint: disable-next-line(unsafe-typecast)
bytes32 constant KEY_STORE_FACTORY = bytes32("storeFactory");
// forge-lint: disable-next-line(unsafe-typecast)
bytes32 constant KEY_RESOLVER = bytes32("resolver");
// forge-lint: disable-next-line(unsafe-typecast)
bytes32 constant KEY_CONTENT_RESOLVER = bytes32("contentResolver");

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
    function set(bytes32 key, address addr) external;
}
