// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title DotNS Constants
/// @notice Protocol-level invariants shared across DotNS contracts.
/// @dev Centralises the namehash of the `.dot` TLD, the TLD suffix string, and the
///      well-known protocol-registry keys that every contract uses to discover its
///      siblings (registrar, controller, registry, resolvers, etc.). Each key is a
///      role address resolved at call time, so rotating an implementation is a
///      single `set` on the protocol registry without redeploying consumers.
/// @custom:security-contact admin@parity.io
library DotnsConstants {
    /// @notice Namehash of the .dot TLD node.
    /// @dev keccak256(abi.encodePacked(bytes32(0), keccak256("dot"))).
    bytes32 internal constant DOT_NODE =
        0x3fce7d1364a893e213bc4212792b517ffc88f5b13b86c8ef9c8d390c3a1370ce;

    /// @notice TLD suffix appended to labels when building full domain names.
    string internal constant TLD = ".dot";

    /// @notice Well-known key for the ERC721 registrar backing name ownership.
    /// @dev Role: token-of-record for `.dot` names. Mints, burns, and tracks the
    ///      `tokenId => label` mapping consumed by the forward registry on
    ///      transfer.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant REGISTRAR = bytes32("registrar");

    /// @notice Well-known key for the registrar controller orchestrating commit-reveal registration.
    /// @dev Role: commit-reveal entry point for the public registration flow.
    ///      Calls `register` on the registrar after pricing and validation.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant CONTROLLER = bytes32("controller");

    /// @notice Well-known key for the forward registry storing node ownership and resolver.
    /// @dev Role: source of truth for `(node => owner, resolver)`. Read by every
    ///      resolver gate that defers authority to the node owner.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant REGISTRY = bytes32("registry");

    /// @notice Well-known key for the reverse resolver for address-to-name mapping.
    /// @dev Role: stores `address => name` reverse records. Writer is the
    ///      registrar/controller, not the address holder.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant REVERSE_RESOLVER = bytes32("reverseResolver");

    /// @notice Well-known key for the PoP oracle enforcing eligibility and pricing.
    /// @dev Role: arbiter of PoP cross-flow priority and pricing. Consulted by
    ///      both the public commit-reveal controller and the PoP controller.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant POP_RULES = bytes32("popRules");

    /// @notice Well-known key for the factory deploying per-user Store instances.
    /// @dev Role: deploy-on-demand provisioning of user `LabelStore` proxies and
    ///      authorisation gate for protocol writes into them.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant STORE_FACTORY = bytes32("storeFactory");

    /// @notice Well-known key for the forward resolver storing address records.
    /// @dev Role: `node => address` records. Writes gated on node ownership.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant RESOLVER = bytes32("resolver");

    /// @notice Well-known key for the content resolver storing content hashes and text records.
    /// @dev Role: `node => contenthash`/`text` records and ERC721-style operator
    ///      approvals. Writes gated on node ownership or operator approval.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant CONTENT_RESOLVER = bytes32("contentResolver");

    /// @notice Well-known key for the privileged PoP gateway address allowed to drive
    ///         lite/full-person username flows via `DotnsPopController`.
    /// @dev External account or pallet adapter configured by governance; the
    ///      `DotnsPopController` reads it to gate its privileged entry points, so
    ///      rotating the gateway is a single `set` call with no upgrade needed.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant POP_GATEWAY = bytes32("popGateway");

    /// @notice Well-known key for the dedicated PoP controller orchestrating lite/full-person
    ///         username issuance on behalf of the PoP gateway.
    /// @dev Kept distinct from `CONTROLLER` (commit-reveal public controller) so the
    ///      two can coexist per `DotnsRegistrar`'s multi-controller affordance.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant POP_CONTROLLER = bytes32("popController");

    /// @notice Well-known key for the PoP resolver holding per-name records produced
    ///         by the PoP username flow (chat keys, lite => full links).
    /// @dev Role: `node => chatKey` and bidirectional `lite <=> full` link index.
    ///      Writer is the `POP_CONTROLLER`, not the node owner.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant POP_RESOLVER = bytes32("popResolver");

    /// @notice Well-known key for the name escrow holding refundable deposits and
    ///         driving the release lifecycle for registered names.
    /// @dev Role: custodial vault for registration deposits and the state machine
    ///      that drives the name release lifecycle.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant NAME_ESCROW = bytes32("nameEscrow");
}
