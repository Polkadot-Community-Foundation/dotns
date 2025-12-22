// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title DotNS Content Resolver Interface
/// @notice Defines the storage and retrieval of content identifiers for DotNS nodes
/// @dev A content identifier is an opaque byte sequence that points to off-chain
///      content such as IPFS CIDs, Arweave transaction IDs, or future schemes.
///      Interpretation of the content is handled entirely off-chain.
/// @custom:security-contact admin@parity.io
interface IDotnsContentResolver {
    /// @notice Emitted when a node's content reference is updated
    /// @param node The node whose content was updated
    /// @param content The new content identifier
    event ContentUpdated(bytes32 indexed node, bytes content);

    /// @notice Thrown when the caller is not authorised to modify a node
    /// @param node The node being modified
    /// @param caller The address attempting the modification
    error NotAuthorised(bytes32 node, address caller);

    /// @notice Sets the content identifier for a node
    /// @dev The caller must own the node in the DotNS registry
    /// @param node The node whose content is being set
    /// @param content Opaque content identifier bytes
    function setContent(bytes32 node, bytes calldata content) external;

    /// @notice Returns the content identifier associated with a node
    /// @param node The node to query
    /// @return content The stored content identifier, or empty if unset
    function contentOf(bytes32 node) external view returns (bytes memory content);
}
