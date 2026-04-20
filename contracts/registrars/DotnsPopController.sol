// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    ERC165Upgradeable
} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IDotnsPopController} from "./IDotnsPopController.sol";
import {IDotnsProtocolRegistry} from "../registry/IDotnsProtocolRegistry.sol";
import {DotnsProtocolRegistry} from "../registry/DotnsProtocolRegistry.sol";
import {IDotnsPopResolver} from "../resolvers/IDotnsPopResolver.sol";
import {IPopRules} from "../pop/IPopRules.sol";
import {LabelUtils} from "../utils/LabelUtils.sol";
import {RegistrationUtils} from "../utils/RegistrationUtils.sol";
import {StringUtils} from "../utils/StringUtils.sol";

/// @title DotnsPopController
/// @notice Dedicated PoP controller orchestrating lite-person and full-person
///         username issuance on behalf of the PoP gateway pallet.
/// @dev Lives behind its own UUPS proxy with its own storage. Registered on
///      `DotnsRegistrar` via `addController`, which is how multiple controllers
///      coexist on the same registrar without interfering with each other.
///
/// @dev Decoupling:
///      This contract does not import or call `IDotnsRegistrarController`. The
///      public commit-reveal controller is equally unaware of this one. Cross-
///      flow collision handling relies on two distinct properties, neither of
///      which requires the two controllers to know about each other:
///
///      - Lite-person labels (`NAME.XX`) are format-disjoint from the DNS
///        labels the public controller accepts, so labelhashes cannot overlap.
///        Lite names are safe from public registration by construction.
///      - Base-name reservations are synchronised into @custom:contract IPopRules. The head of
///        this controller's reservation queue is written through
///        `IPopRules.reserveBaseNameForPop` on every head transition; the
///        slot is cleared through `IPopRules.releaseBaseName` when the queue
///        empties (claim, final relinquish, final expiry). Because the public
///        commit-reveal controller already routes through
///        `IPopRules.priceWithCheck`, which rejects any registration targeting
///        a base-name stem reserved for another user, the public flow respects
///        gateway reservations without ever importing this contract. PopRules
///        is the single cross-flow authority; the queue here is the intra-PoP
///        ordering layer on top of it.
///
/// @dev Shared primitives:
///      - Labelhash / namehash: {LabelUtils}.
///      - Mint + forward-registry + store-write triad: {RegistrationUtils}.
///      - Chat-key and lite => full link persistence: {IDotnsPopResolver}.
///        Keeping these records on the resolver preserves the "Store = labels only"
///        invariant (Store holds registration records, nothing else).
///
/// @custom:security-contact admin@parity.io
contract DotnsPopController is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC165Upgradeable,
    IDotnsPopController
{
    using StringUtils for *;

    /// @notice Upper bound for the number of simultaneously queued reservations per label.
    /// @dev Keeps `expireReservation` gas bounded.
    uint16 public constant MAX_RESERVATION_QUEUE = 64;

    /// @notice Reservation queue entry: a user and the timestamp they joined the queue.
    /// @dev Packs into a single storage slot (20 + 8 bytes).
    struct ReservationEntry {
        address owner;
        uint64 joinedAt;
    }

    /// @notice Metadata describing the occupied range of a reservation queue.
    /// @dev Uses monotonically increasing indices. Active entries occupy
    ///      `[head, tail)`; `length = tail - head`. Slots past `head` are deleted
    ///      as the head advances so garbage never accumulates.
    struct ReservationQueueMeta {
        uint64 head;
        uint64 tail;
    }

    /// @notice Protocol-level address registry for all DotNS contracts.
    IDotnsProtocolRegistry public protocolRegistry;

    /// @notice Per-label queue metadata (head/tail pointers).
    mapping(bytes32 labelhash => ReservationQueueMeta meta) internal _reservationMeta;

    /// @notice Per-label sparse entries keyed by monotonically-increasing index.
    mapping(bytes32 labelhash => mapping(uint64 index => ReservationEntry entry)) internal
        _reservationEntries;

    /// @notice Tracks which label each user currently holds a reservation for.
    /// @dev A non-zero labelhash means the user is somewhere in the queue for that label.
    ///      Enforces "one active reservation per account".
    mapping(address user => bytes32 labelhash) internal _userReservation;

    /// @notice Records the monotonic index at which a user's reservation lives within
    ///         the queue, so non-head relinquishment can find it in O(1).
    mapping(address user => uint64 index) internal _userReservationIndex;

    /// @notice Remembers the base-label string for each reserved labelhash so the
    ///         PopRules sync path can address the reservation by its original
    ///         string form (PopRules keys its `reservations` mapping by string).
    /// @dev Populated on first enqueue for a label, cleared when the queue empties.
    ///      Exists only to bridge the queue's `bytes32` key space to PopRules'
    ///      `string` key space; nothing else reads it.
    mapping(bytes32 labelhash => string baseLabel) internal _reservedBaseLabel;

    /// @notice Duration (in seconds) after which a reservation entry is considered expired.
    /// @dev Mirrors `pallet_resources::UsernameReservationDuration`. Configurable by
    ///      governance via `setReservationDuration`.
    uint64 public reservationDuration;

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[50] private __gap;

    /// @notice Restricts calls to the privileged PoP gateway address stored in the
    ///         protocol registry under `POP_GATEWAY`.
    modifier onlyGateway() {
        _onlyGateway();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the PoP controller.
    /// @param registry Protocol-level address registry.
    /// @param reservationDuration_ Initial reservation duration in seconds.
    function initialize(
        IDotnsProtocolRegistry registry,
        uint64 reservationDuration_
    )
        external
        initializer
    {
        __Ownable_init(msg.sender);
        __ERC165_init();
        protocolRegistry = registry;
        reservationDuration = reservationDuration_;
        emit ReservationDurationSet(reservationDuration_);
    }

    /// @inheritdoc IDotnsPopController
    function reserveBaseName(
        string calldata liteLabel,
        address user,
        bytes calldata chatKey,
        string calldata reservedBaseLabel
    )
        external
        override
        onlyGateway
    {
        (bytes32 labelhash, bytes32 node) = _validateLiteLabel(liteLabel);

        _advanceExpiredHead(labelhash);

        _completeGatewayRegistration(user, liteLabel, labelhash, node, chatKey, bytes32(0));

        emit LiteNameReserved(labelhash, user, liteLabel);

        if (bytes(reservedBaseLabel).length != 0) {
            bytes32 reservedHash = _validateBaseLabelHash(reservedBaseLabel);
            _advanceExpiredHead(reservedHash);

            // `_removeUserFromQueue` early-returns when the user has no active
            // reservation, so no outer guard is needed.
            _removeUserFromQueue(user);
            _enqueueReservation(reservedHash, reservedBaseLabel, user);
        }
    }

    /// @inheritdoc IDotnsPopController
    function registerBaseName(
        string calldata label,
        address user,
        Link calldata link
    )
        external
        override
        onlyGateway
    {
        (bytes32 labelhash, bytes32 node) = _validateBaseLabel(label);

        _advanceExpiredHead(labelhash);

        // Reservation axis: `user` is claiming iff they hold the live head-of-queue
        // reservation on `label`. Orthogonal to `link.kind`.
        ReservationQueueMeta memory meta = _reservationMeta[labelhash];
        bool isClaim = _userReservation[user] == labelhash && meta.head < meta.tail
            && _reservationEntries[labelhash][meta.head].owner == user;

        if (isClaim) {
            _clearQueue(labelhash);
        } else {
            // Silent relinquish: any pending queue entry the user holds is removed.
            // `_removeUserFromQueue` early-returns when there is nothing to remove.
            _removeUserFromQueue(user);
        }

        // Chat-key axis: `link.kind` selects whether a fresh key is persisted on the
        // resolver or the entry is linked back to (and inherits the key from) a prior
        // lite-person username.
        bytes32 liteLabelhash;
        bytes memory chatKeyToPersist;
        if (link.kind == LinkKind.LiteUsername) {
            liteLabelhash = _validateLiteLabelHash(link.liteLabel);
            bytes32 liteNode = LabelUtils.namehash(liteLabelhash);
            chatKeyToPersist = _popResolver().chatKey(liteNode);
        } else {
            chatKeyToPersist = link.chatKey;
        }

        _completeGatewayRegistration(user, label, labelhash, node, chatKeyToPersist, liteLabelhash);

        if (isClaim) {
            emit BaseNameClaimed(labelhash, user, label);
        } else {
            emit StandaloneNameRegistered(labelhash, user, label);
        }
        if (link.kind == LinkKind.LiteUsername) {
            emit LiteToFullLinked(labelhash, liteLabelhash);
        }
    }

    /// @inheritdoc IDotnsPopController
    function expireReservation(string calldata reservedBaseLabel) external override {
        bytes32 labelhash = _validateBaseLabelHash(reservedBaseLabel);
        _advanceExpiredHead(labelhash);
    }

    /// @inheritdoc IDotnsPopController
    function relinquishReservation() external override {
        bytes32 labelhash = _userReservation[msg.sender];
        require(labelhash != bytes32(0), NoActiveReservation(msg.sender));
        _removeUserFromQueue(msg.sender);
        emit ReservationRelinquished(labelhash, msg.sender);
    }

    /// @inheritdoc IDotnsPopController
    function isReservedForClaim(string calldata reservedBaseLabel)
        external
        view
        override
        returns (bool reserved, address holder)
    {
        bytes32 labelhash = _validateBaseLabelHash(reservedBaseLabel);
        ReservationQueueMeta memory meta = _reservationMeta[labelhash];
        if (meta.head >= meta.tail) return (false, address(0));

        ReservationEntry memory head = _reservationEntries[labelhash][meta.head];
        if (head.owner == address(0)) return (false, address(0));
        if (_isExpired(head.joinedAt)) return (false, address(0));

        return (true, head.owner);
    }

    /// @inheritdoc IDotnsPopController
    function setReservationDuration(uint64 duration) external override onlyOwner {
        reservationDuration = duration;
        emit ReservationDurationSet(duration);
    }

    /// @notice Returns the queue metadata (`head`, `tail`) for `labelhash`.
    /// @dev Read-only accessor used by invariant tests to probe queue bounds.
    ///      Exposing the pair rather than the internal struct keeps the storage
    ///      layout private whilst allowing property checks over live queues.
    /// @param labelhash Keccak256 hash of the reserved base label.
    /// @return head Index of the current queue head.
    /// @return tail One past the last occupied index.
    function reservationMeta(bytes32 labelhash) external view returns (uint64 head, uint64 tail) {
        ReservationQueueMeta memory meta = _reservationMeta[labelhash];
        return (meta.head, meta.tail);
    }

    /// @notice Returns the queue entry at `index` for `labelhash`.
    /// @param labelhash Keccak256 hash of the reserved base label.
    /// @param index Queue index (monotonically-increasing slot).
    /// @return entryOwner Owner of the slot (zero if relinquished or empty).
    /// @return joinedAt Unix timestamp when the entry was enqueued.
    function reservationEntry(
        bytes32 labelhash,
        uint64 index
    )
        external
        view
        returns (address entryOwner, uint64 joinedAt)
    {
        ReservationEntry memory entry = _reservationEntries[labelhash][index];
        return (entry.owner, entry.joinedAt);
    }

    /// @notice Returns the labelhash `user` currently has a reservation on.
    /// @param user Account to query.
    /// @return labelhash Reserved labelhash, or zero if `user` holds no reservation.
    function userReservation(address user) external view returns (bytes32 labelhash) {
        return _userReservation[user];
    }

    /// @notice Returns the queue index `user` currently occupies.
    /// @dev Meaningful only when `userReservation(user)` is non-zero.
    function userReservationIndex(address user) external view returns (uint64 index) {
        return _userReservationIndex[user];
    }

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC165Upgradeable, IERC165)
        returns (bool)
    {
        return interfaceId == type(IDotnsPopController).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /// @notice Returns implementation version.
    /// @return versionString Current version string.
    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.0.0";
    }

    /// @notice Mints a name, wires forward registry, writes the owner's Store, and
    ///         persists PoP-flow records (chat key, lite link) on the PoP resolver.
    /// @dev The mint + forward-registry + store-write triad is delegated to
    ///      {RegistrationUtils-registerAndStore} so this flow and the public
    ///      commit-reveal flow share exactly one implementation of that sequence.
    ///      PoP-flow per-name records live on {IDotnsPopResolver} rather than on the
    ///      Store so the Store stays labels-only.
    function _completeGatewayRegistration(
        address user,
        string calldata label,
        bytes32 labelhash,
        bytes32 node,
        bytes memory chatKeyBytes,
        bytes32 liteLabelhash
    )
        internal
    {
        address storeAddr = address(
            RegistrationUtils.registerAndStore(
                RegistrationUtils.RegistrationContext({
                    protocolRegistry: protocolRegistry,
                    user: user,
                    label: label,
                    labelhash: labelhash,
                    node: node
                })
            )
        );

        IDotnsPopResolver resolver = _popResolver();
        if (chatKeyBytes.length != 0) {
            resolver.setChatKey(node, chatKeyBytes);
        }
        if (liteLabelhash != bytes32(0)) {
            resolver.setLiteLink(node, liteLabelhash);
        }

        emit NameRegistered(label, labelhash, user, storeAddr);
    }

    /// @notice Returns whether a queue entry is expired relative to `block.timestamp`.
    function _isExpired(uint64 joinedAt) internal view returns (bool) {
        return joinedAt + reservationDuration <= block.timestamp;
    }

    /// @notice Appends a new reservation entry to the tail of the queue for `labelhash`.
    /// @dev Reverts if the queue is full or the user already holds a reservation.
    ///      When the enqueued entry is the new head of an empty queue, the
    ///      controller also reserves the base name on PopRules so the public
    ///      commit-reveal flow sees the reservation through its existing
    ///      `priceWithCheck` guard. Subsequent waiters only live in the local
    ///      queue until they are promoted.
    function _enqueueReservation(
        bytes32 labelhash,
        string memory baseLabel,
        address user
    )
        internal
    {
        require(_userReservation[user] == bytes32(0), AlreadyReserved(user, labelhash));

        ReservationQueueMeta memory meta = _reservationMeta[labelhash];
        require(meta.tail - meta.head < MAX_RESERVATION_QUEUE, QueueFull(labelhash));

        uint64 index = meta.tail;
        bool becomesHead = index == meta.head;

        _reservationEntries[labelhash][index] =
            ReservationEntry({owner: user, joinedAt: uint64(block.timestamp)});
        _reservationMeta[labelhash] = ReservationQueueMeta({head: meta.head, tail: index + 1});

        _userReservation[user] = labelhash;
        _userReservationIndex[user] = index;

        if (becomesHead) {
            _reservedBaseLabel[labelhash] = baseLabel;
            _popRules().reserveBaseNameForPop(baseLabel, user);
        }

        emit ReservationQueued(labelhash, user, index - meta.head);
    }

    /// @notice Wipes the entire reservation queue for `labelhash` and releases the
    ///         corresponding PopRules reservation.
    /// @dev Used when a holder claims their reservation: every waiter is evicted and
    ///      their per-user tracking state is cleared, and PopRules is told the
    ///      slot is free so future public registrations are unblocked (the claim
    ///      itself just minted the name, so there is nothing left to reserve).
    function _clearQueue(bytes32 labelhash) internal {
        ReservationQueueMeta memory meta = _reservationMeta[labelhash];
        for (uint64 i = meta.head; i < meta.tail; i++) {
            ReservationEntry memory entry = _reservationEntries[labelhash][i];
            if (entry.owner != address(0)) {
                delete _userReservation[entry.owner];
                delete _userReservationIndex[entry.owner];
            }
            delete _reservationEntries[labelhash][i];
        }
        delete _reservationMeta[labelhash];
        _releasePopRulesSlot(labelhash);
    }

    /// @notice Advances the queue head past every expired entry at the head of the queue.
    /// @dev Bounded by queue length. Emits `ReservationExpired` per removed entry.
    function _advanceExpiredHead(bytes32 labelhash) internal {
        ReservationQueueMeta memory meta = _reservationMeta[labelhash];
        uint64 head = meta.head;
        uint64 tail = meta.tail;

        while (head < tail) {
            ReservationEntry memory entry = _reservationEntries[labelhash][head];
            if (entry.owner == address(0)) {
                delete _reservationEntries[labelhash][head];
                head++;
                continue;
            }
            if (!_isExpired(entry.joinedAt)) break;

            delete _userReservation[entry.owner];
            delete _userReservationIndex[entry.owner];
            delete _reservationEntries[labelhash][head];
            emit ReservationExpired(labelhash, entry.owner);
            head++;
        }

        if (head == tail) {
            delete _reservationMeta[labelhash];
            _releasePopRulesSlot(labelhash);
        } else if (head != meta.head) {
            _reservationMeta[labelhash] = ReservationQueueMeta({head: head, tail: tail});
            address newHead = _reservationEntries[labelhash][head].owner;
            _syncPopRulesToHead(labelhash, newHead);
        }
    }

    /// @notice Removes `user` from whichever reservation queue they currently occupy.
    /// @dev For a head removal, we delete the entry without bumping `meta.head` and
    ///      delegate the advance to `_advanceExpiredHead`. Its existing zero-owner
    ///      skip walks past the freshly-deleted slot, and its `head != meta.head`
    ///      branch fires the PopRules resync in the one place head promotion is
    ///      actually handled. Non-head removals leave the queue shape intact, so
    ///      no advance or resync is needed.
    function _removeUserFromQueue(address user) internal {
        bytes32 labelhash = _userReservation[user];
        if (labelhash == bytes32(0)) return;

        uint64 entryIndex = _userReservationIndex[user];
        ReservationQueueMeta memory queueMeta = _reservationMeta[labelhash];

        delete _userReservation[user];
        delete _userReservationIndex[user];
        delete _reservationEntries[labelhash][entryIndex];

        if (entryIndex == queueMeta.head) {
            _advanceExpiredHead(labelhash);
        }
    }

    /// @notice Validates a lite-person `NAME.XX` label and derives `(labelhash, node)`.
    function _validateLiteLabel(string calldata liteLabel)
        internal
        pure
        returns (bytes32 labelhash, bytes32 node)
    {
        require(liteLabel.isLitePersonLabel(), InvalidLiteLabel());
        (labelhash, node) = LabelUtils.deriveNode(liteLabel);
    }

    /// @notice Validates a lite-person `NAME.XX` label and returns its labelhash.
    /// @dev Node is not needed for every call site; this overload avoids the extra
    ///      keccak when only the labelhash is used.
    function _validateLiteLabelHash(string calldata liteLabel)
        internal
        pure
        returns (bytes32 labelhash)
    {
        require(liteLabel.isLitePersonLabel(), InvalidLiteLabel());
        labelhash = LabelUtils.labelhash(liteLabel);
    }

    /// @notice Validates a base (full-person) DNS label and derives `(labelhash, node)`.
    function _validateBaseLabel(string calldata baseLabel)
        internal
        pure
        returns (bytes32 labelhash, bytes32 node)
    {
        require(baseLabel.isSingleLabel(), InvalidBaseLabel());
        (labelhash, node) = LabelUtils.deriveNode(baseLabel);
    }

    /// @notice Validates a base (full-person) DNS label and returns its labelhash.
    function _validateBaseLabelHash(string calldata baseLabel)
        internal
        pure
        returns (bytes32 labelhash)
    {
        require(baseLabel.isSingleLabel(), InvalidBaseLabel());
        labelhash = LabelUtils.labelhash(baseLabel);
    }

    /// @notice Resolves the PoP resolver via the protocol registry.
    function _popResolver() internal view returns (IDotnsPopResolver) {
        return IDotnsPopResolver(
            protocolRegistry.get(DotnsProtocolRegistry(address(protocolRegistry)).POP_RESOLVER())
        );
    }

    /// @notice Resolves the PopRules contract via the protocol registry.
    function _popRules() internal view returns (IPopRules) {
        return IPopRules(
            protocolRegistry.get(DotnsProtocolRegistry(address(protocolRegistry)).POP_RULES())
        );
    }

    /// @notice Writes the new head of the queue into PopRules so the public
    ///         commit-reveal flow rejects registrations of this base name for
    ///         anyone other than `newHead`.
    function _syncPopRulesToHead(bytes32 labelhash, address newHead) internal {
        string memory baseLabel = _reservedBaseLabel[labelhash];
        if (bytes(baseLabel).length == 0 || newHead == address(0)) return;
        // Release the slot held by the prior head before writing the new one,
        // because PopRules rejects `reserveBaseNameForPop` when the live slot
        // belongs to someone other than the caller-supplied user.
        IPopRules rules = _popRules();
        rules.releaseBaseName(baseLabel);
        rules.reserveBaseNameForPop(baseLabel, newHead);
    }

    /// @notice Clears the PopRules slot and the local label bookkeeping when the
    ///         queue empties (claim, last-relinquish, last-expire).
    function _releasePopRulesSlot(bytes32 labelhash) internal {
        string memory baseLabel = _reservedBaseLabel[labelhash];
        if (bytes(baseLabel).length == 0) return;
        _popRules().releaseBaseName(baseLabel);
        delete _reservedBaseLabel[labelhash];
    }

    /// @notice Internal check enforcing PoP-gateway-only access.
    function _onlyGateway() internal view {
        address gateway =
            protocolRegistry.get(DotnsProtocolRegistry(address(protocolRegistry)).POP_GATEWAY());
        require(msg.sender == gateway, NotGateway(msg.sender));
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
