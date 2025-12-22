// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title DotNS Resolver Interface
/// @notice Defines forward-resolution records for DotNS names
/// @dev A resolver maps a deterministic node identifier to resolution data.
///      This interface is intentionally minimal and forward-only.
/// @custom:security-contact admin@parity.io
interface IDotnsResolver {
    /// @notice Thrown when a caller is not authorised to modify a node
    /// @param node The node being modified
    /// @param caller The address attempting the modification
    error NotAuthorised(bytes32 node, address caller);

    /// @notice Emitted when an address record is updated
    /// @param node The node whose address record changed
    /// @param value The new resolved address
    event AddressSet(bytes32 indexed node, address value);

    /// @notice Emitted when a content reference is updated
    /// @param node The node whose content reference changed
    /// @param value The new content reference
    event ContentSet(bytes32 indexed node, bytes value);

    /// @notice Emitted when a display name is updated
    /// @param node The node whose display name changed
    /// @param value The new display name
    event DisplayNameSet(bytes32 indexed node, string value);

    /// @notice Sets the resolved address for a node
    /// @param node The node identifier
    /// @param value The address to associate with the node
    function setAddress(bytes32 node, address value) external;

    /// @notice Returns the resolved address for a node
    /// @param node The node identifier
    /// @return value The resolved address, or zero if unset
    function addressOf(bytes32 node) external view returns (address value);

    /// @notice Sets the content reference for a node
    /// @param node The node identifier
    /// @param value Opaque content reference (e.g. CID, URL, hash)
    function setContent(bytes32 node, bytes calldata value) external;

    /// @notice Returns the content reference for a node
    /// @param node The node identifier
    /// @return value The stored content reference, or empty if unset
    function contentOf(bytes32 node) external view returns (bytes memory value);

    /// @notice Sets a human-readable display name for a node
    /// @param node The node identifier
    /// @param value The display name (e.g. "alice.dot")
    function setDisplayName(bytes32 node, string calldata value) external;

    /// @notice Returns the display name for a node
    /// @param node The node identifier
    /// @return value The stored display name, or empty if unset
    function displayNameOf(bytes32 node) external view returns (string memory value);
}
