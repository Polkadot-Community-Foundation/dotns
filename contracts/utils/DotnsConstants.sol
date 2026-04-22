// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title DotNS Constants
/// @notice Protocol-level invariants shared across DotNS contracts.
/// @custom:security-contact admin@parity.io
library DotnsConstants {
    /// @notice Namehash of the .dot TLD node.
    /// @dev keccak256(abi.encodePacked(bytes32(0), keccak256("dot")))
    bytes32 internal constant DOT_NODE =
        0x3fce7d1364a893e213bc4212792b517ffc88f5b13b86c8ef9c8d390c3a1370ce;

    /// @notice TLD suffix appended to labels when building full domain names.
    string internal constant TLD = ".dot";

    /// @notice Store key prefix for DotNS registration entries.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant DOTNS_REGISTERED_KEY = bytes32("dotns.registered");

    // ── Protocol registry well-known keys ────────────────────────────

    /// @notice Well-known key for the ERC721 registrar backing name ownership.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant REGISTRAR = bytes32("registrar");

    /// @notice Well-known key for the registrar controller orchestrating commit-reveal registration.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant CONTROLLER = bytes32("controller");

    /// @notice Well-known key for the forward registry storing node ownership and resolver.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant REGISTRY = bytes32("registry");

    /// @notice Well-known key for the reverse resolver for address-to-name mapping.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant REVERSE_RESOLVER = bytes32("reverseResolver");

    /// @notice Well-known key for the PoP oracle enforcing eligibility and pricing.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant POP_RULES = bytes32("popRules");

    /// @notice Well-known key for the factory deploying per-user Store instances.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant STORE_FACTORY = bytes32("storeFactory");

    /// @notice Well-known key for the forward resolver storing address records.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant RESOLVER = bytes32("resolver");

    /// @notice Well-known key for the content resolver storing content hashes and text records.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant CONTENT_RESOLVER = bytes32("contentResolver");
}
