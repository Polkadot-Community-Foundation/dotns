// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title DotNS Content Resolver Interface
/// @notice Defines storage and retrieval for content hash and text records for DotNS nodes
/// @dev Content hash and text records point to off-chain content such as IPFS CIDs or future schemes.
///      Interpretation is handled off-chain.
/// @custom:security-contact admin@parity.io
interface IDotnsContentResolver {
    /// @notice Emitted when a node's content hash is updated
    /// @param node The node whose content hash was updated
    /// @param hash The new content hash bytes
    event ContentHashUpdated(bytes32 indexed node, bytes hash);

    /// @notice Emitted when a node's text record is updated
    /// @param node The node whose text record was updated
    /// @param key The text record key
    /// @param value The new text record value
    event TextUpdated(bytes32 indexed node, string indexed key, string value);

    /// @notice Thrown when the caller is not authorised to modify a node
    /// @param node The node being modified
    /// @param caller The address attempting the modification
    error NotAuthorised(bytes32 node, address caller);

    /// @notice Sets the content hash for a node
    /// @dev The caller must own the node in the DotNS registry
    /// @param node The node whose content hash is being set
    /// @param hash Opaque content hash bytes
    function setContenthash(bytes32 node, bytes calldata hash) external;

    /// @notice Returns the content hash associated with a node
    /// @param node The node to query
    /// @return hash The stored content hash bytes, or empty if unset
    function contenthash(bytes32 node) external view returns (bytes memory hash);

    /// @notice Sets a text record for a node
    /// @dev The caller must own the node in the DotNS registry
    /// @param node The node whose text record is being set
    /// @param key Text record key (e.g. "ipfs", "avatar")
    /// @param value Text record value
    function setText(bytes32 node, string calldata key, string calldata value) external;

    /// @notice Returns a text record for a node
    /// @param node The node to query
    /// @param key Text record key
    /// @return value Stored text value, or empty string if unset
    function text(bytes32 node, string calldata key) external view returns (string memory value);
}
