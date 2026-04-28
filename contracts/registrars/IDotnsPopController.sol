// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDotnsController} from "./IDotnsController.sol";

/// @title IDotnsPopController
/// @notice Interface for the dedicated PoP controller orchestrating lite-person and full-person username issuance on behalf of the PoP gateway pallet.
/// @dev Deliberately disjoint from `IDotnsRegistrarController`. The two controllers coexist
/// on `DotnsRegistrar` via its multi-controller affordance and neither imports the other.
/// Collision handling reduces to the registrar's ERC721 availability check (first-to-mint
/// wins). Reservation queuing for `reservedBaseLabel` is an intra-PoP coordination mechanism
/// only; it does not block public registrations.
///
/// Label formats:
/// Lite-person usernames (first argument to {reserveBaseName} and the `liteLabel` of a
/// `LinkKind.LiteUsername` link) are DNS labels with at least two trailing digits (e.g.
/// `alice42`) per {StringUtils-isLitePersonLabel}. The gateway strips any separator before
/// calling so the on-chain label is flat. Full-person usernames (the `label` of
/// {registerBaseName} and the optional `reservedBaseLabel` of {reserveBaseName}) follow the
/// DNS-label rules enforced by {StringUtils-isSingleLabel} (e.g. `alice`). Lite and public
/// registrations share one namespace; first-to-mint wins at the ERC721 layer. Cross-flow
/// priority on the stripped base stem is arbitrated by {IPopRules.reserveBaseNameForPop}.
/// @custom:security-contact admin@parity.io
interface IDotnsPopController is IDotnsController {
    /// @notice Discriminant for the `Link` union supplied to `registerBaseName`.
    /// @dev Selects the chat-key source for the full-person username. Orthogonal to whether
    /// the registration is a claim or standalone; that is derived from on-chain reservation
    /// state. `None` means the caller supplies a fresh chat key in `link.chatKey`.
    /// `LiteUsername` means the full-person username is linked to a prior lite-person
    /// username (`link.liteLabel`) and inherits its chat key.
    enum LinkKind {
        None,
        LiteUsername
    }

    /// @notice Tagged union selecting the chat-key source for a full-person registration.
    /// @param liteLabel Lite-person `NAMEXX` label (only read when `kind == LiteUsername`).
    /// @param chatKey Chat key bytes (only read when `kind == None`).
    struct Link {
        LinkKind kind;
        string liteLabel;
        bytes chatKey;
    }

    /// @notice Per-user reservation pointer: which queue the user sits in and where.
    /// @param labelhash Non-zero when the user holds a live reservation; zero otherwise.
    /// @param index Monotonic queue index, meaningful only when `labelhash` is non-zero.
    struct UserReservation {
        bytes32 labelhash;
        uint64 index;
    }

    /// @notice Emitted when a lite-person username is registered via the PoP gateway.
    event LiteNameReserved(bytes32 indexed labelhash, address indexed user, string label);

    /// @notice Emitted when a full-person username is claimed out of an existing reservation.
    event BaseNameClaimed(bytes32 indexed labelhash, address indexed user, string label);

    /// @notice Emitted when a standalone full-person username is registered via the PoP gateway.
    event StandaloneNameRegistered(bytes32 indexed labelhash, address indexed user, string label);

    /// @notice Emitted when a reservation entry is added to the queue for a base name.
    /// @param position Position in the queue at the time of joining (0 = active holder).
    event ReservationQueued(
        bytes32 indexed reservedLabelhash, address indexed user, uint64 position
    );

    /// @notice Emitted when a reservation entry is removed due to expiry.
    event ReservationExpired(bytes32 indexed reservedLabelhash, address indexed user);

    /// @notice Emitted when a user voluntarily relinquishes their reservation.
    event ReservationRelinquished(bytes32 indexed reservedLabelhash, address indexed user);

    /// @notice Emitted when a full-person username is linked to a lite-person username.
    event LiteToFullLinked(bytes32 indexed fullLabelhash, bytes32 indexed liteLabelhash);

    /// @notice Emitted when the reservation duration is updated.
    event ReservationDurationSet(uint64 duration);

    /// @notice Emitted when a name is successfully registered via the PoP controller.
    /// @param store The Store instance used to persist the immutable registration record.
    event NameRegistered(
        string indexed label, bytes32 indexed labelhash, address indexed owner, address store
    );

    /// @notice Thrown when the caller is not the PoP gateway.
    error NotGateway(address caller);

    /// @notice Thrown when a supplied lite-person label does not match `NAMEXX`.
    error InvalidLiteLabel();

    /// @notice Thrown when a supplied base label is not a canonical DNS label.
    error InvalidBaseLabel();

    /// @notice Thrown when a user tries to claim or relinquish a reservation that they do not hold.
    error NoActiveReservation(address user);

    /// @notice Thrown when a reservation queue has reached its capacity.
    error QueueFull(bytes32 labelhash);

    /// @notice Thrown when attempting to enqueue a user who already has an active reservation.
    error AlreadyReserved(address user, bytes32 labelhash);

    /// @notice Thrown when someone tries to mint a base label in standalone mode while another user holds the live head-of-queue reservation.
    error NotHolder(address user, bytes32 labelhash);

    /// @notice Registers a lite-person username on behalf of `user` and optionally enqueues a reservation for a base name the user intends to claim as a full person later.
    /// @dev The base-name leg only runs when `reservedBaseLabel` is non-empty, and runs PopRules
    /// `priceWithCheck` BEFORE any queue mutation so a mis-tiered reservation never even touches
    /// the queue. The user is removed from any prior queue position before being enqueued, so a
    /// single user holds at most one live reservation across all labels.
    /// @custom:emits LiteNameReserved
    /// @custom:emits NameRegistered
    /// @custom:emits ReservationQueued
    /// @custom:emits ReservationExpired
    /// @custom:reverts AlreadyReserved
    /// @custom:reverts InvalidBaseLabel
    /// @custom:reverts InvalidLiteLabel
    /// @custom:reverts NotGateway
    /// @custom:reverts QueueFull
    function reserveBaseName(
        string calldata liteLabel,
        address user,
        bytes calldata chatKey,
        string calldata reservedBaseLabel
    )
        external;

    /// @notice Registers a lite-person username on behalf of `user` without touching the base-name reservation queue.
    /// @custom:emits LiteNameReserved
    /// @custom:emits NameRegistered
    /// @custom:reverts InvalidLiteLabel
    /// @custom:reverts NotGateway
    function reserveLiteName(
        string calldata liteLabel,
        address user,
        bytes calldata chatKey
    )
        external;

    /// @notice Registers a full-person username on behalf of `user`.
    /// @dev Two orthogonal axes drive the state machine:
    /// (1) Reservation axis: `user` is "claiming" iff they hold the live head-of-queue
    /// reservation on `label`. A claim wipes the entire queue (`_clearQueue`) and releases
    /// the PopRules slot; a non-claim silently relinquishes any pending entry the user holds
    /// and reverts via `NotHolder` if another live head blocks the mint.
    /// (2) Chat-key axis: `link.kind` decides whether a fresh key is persisted on the resolver
    /// (`None`) or the new entry inherits the key from a prior lite-person username
    /// (`LiteUsername`). The two axes are independent so any combination is reachable.
    /// @custom:emits BaseNameClaimed
    /// @custom:emits LiteToFullLinked
    /// @custom:emits NameRegistered
    /// @custom:emits StandaloneNameRegistered
    /// @custom:emits ReservationExpired
    /// @custom:reverts InvalidBaseLabel
    /// @custom:reverts InvalidLiteLabel
    /// @custom:reverts NotGateway
    /// @custom:reverts NotHolder
    function registerBaseName(string calldata label, address user, Link calldata link) external;

    /// @notice Permissionlessly removes expired entries from the head of a reservation queue.
    /// @dev Permissionless on purpose: anyone (typically a UI or a bot) can poke a stale queue
    /// so the next live head takes over without waiting for the next gateway call.
    /// @custom:emits ReservationExpired
    /// @custom:reverts InvalidBaseLabel
    function expireReservation(string calldata reservedBaseLabel) external;

    /// @notice Lets the caller voluntarily drop their own active reservation.
    /// @custom:emits ReservationRelinquished
    /// @custom:emits ReservationExpired
    /// @custom:reverts NoActiveReservation
    function relinquishReservation() external;

    /// @notice Returns whether a label currently has a live reservation at the queue head.
    /// @custom:reverts InvalidBaseLabel
    function isReservedForClaim(string calldata reservedBaseLabel)
        external
        view
        returns (bool reserved, address holder);

    /// @notice Updates the reservation duration used to decide when queue entries expire.
    /// @custom:emits ReservationDurationSet
    /// @custom:reverts OwnableUnauthorizedAccount
    function setReservationDuration(uint64 duration) external;
}
