// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IDotnsStore
/// @notice Baseline interface implemented by every per-user DotNS store.
/// @dev Marker interface shared by `ILabelStore` (protocol-written, labels-only) and
///      `IUserStore` (user-written, generic key/value). Every DotNS store type binds
///      to exactly one user forever, so `owner()` is the single shared surface.
///      Identity of a store is proven by its position in the `StoreFactory` mapping,
///      not by interface probing — the factory is the canonical source of truth.
/// @custom:security-contact admin@parity.io
interface IDotnsStore {
    /// @notice Returns the permanent user this store is bound to.
    /// @dev Set once at `initialize`; immutable thereafter.
    /// @return owner_ The bound user address.
    function owner() external view returns (address owner_);
}
