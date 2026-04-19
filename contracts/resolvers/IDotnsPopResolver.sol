// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IDotnsPopResolver
/// @notice Resolver for per-name records produced by the PoP username flow.
/// @dev Holds two record kinds, each keyed by node:
///      - Chat key: ECDH public-key bytes used for end-to-end encrypted messaging.
///      - Lite link: for a full-person node, the labelhash of the lite-person
///        username it was minted from (when the link was made).
///
///      Lives separately from the per-user {Store} so that the Store can remain a
///      labels-only, protocol-write / user-read surface, and follows the project's
///      resolver-per-record-category convention used by {IDotnsContentResolver}
///      and {IDotnsReverseResolver}.
///
///      Write authorisation is delegated to the address registered as
///      `DotnsProtocolRegistry.POP_CONTROLLER` at call time, so rotating the PoP
///      controller is a single `set` on the protocol registry with no resolver
///      upgrade required.
/// @custom:security-contact admin@parity.io
interface IDotnsPopResolver {
    /// @notice Emitted when a node's chat key is set or updated.
    /// @param node The node whose chat key was written.
    /// @param chatKey The new chat key bytes.
    event ChatKeyUpdated(bytes32 indexed node, bytes chatKey);

    /// @notice Emitted when a full-person node's lite link is set or updated.
    /// @param fullNode The full-person node carrying the link.
    /// @param liteLabelhash The labelhash of the linked lite-person username.
    event LiteLinkUpdated(bytes32 indexed fullNode, bytes32 indexed liteLabelhash);

    /// @notice Thrown when the caller is not the authorised PoP controller.
    /// @param caller The address that attempted the write.
    error NotPopController(address caller);

    /// @notice Sets the chat key for `node`.
    /// @dev Callable only by the address registered under
    ///      `DotnsProtocolRegistry.POP_CONTROLLER`. Overwrites any previous value.
    /// @param node The node whose chat key is being written.
    /// @param chatKey ECDH public key bytes (pallet-side type is `[u8; 65]`).
    function setChatKey(bytes32 node, bytes calldata chatKey) external;

    /// @notice Sets the lite-person link for a full-person `node`.
    /// @dev Callable only by the authorised PoP controller. Overwrites any previous link.
    /// @param fullNode The full-person node carrying the link.
    /// @param liteLabelhash The labelhash of the linked lite-person username.
    function setLiteLink(bytes32 fullNode, bytes32 liteLabelhash) external;

    /// @notice Returns the chat key associated with a node.
    /// @param node The node to query.
    /// @return chatKey The stored chat key bytes, or empty if unset.
    function chatKey(bytes32 node) external view returns (bytes memory chatKey);

    /// @notice Returns the lite-person labelhash linked to a full-person node.
    /// @param fullNode The full-person node to query.
    /// @return liteLabelhash The linked lite-person labelhash, or zero if unset.
    function liteLink(bytes32 fullNode) external view returns (bytes32 liteLabelhash);
}
