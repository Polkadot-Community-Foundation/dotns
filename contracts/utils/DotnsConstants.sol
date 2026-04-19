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
    /// @dev The Store is intentionally restricted to label-registration records only
    ///      (user-read, protocol-write). Other per-name data (chat keys, lite links,
    ///      content hashes, text records, reverse names) lives in dedicated resolver
    ///      contracts rather than on the Store.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant DOTNS_REGISTERED_KEY = bytes32("dotns.registered");
}
