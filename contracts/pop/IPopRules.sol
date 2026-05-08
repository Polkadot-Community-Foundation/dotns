// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title Proof of Personhood Rules for Dotns
/// @notice Proof of personhood interface defining Dotns price calculation, PoP-tier requirements,
/// and base-name reservation rules. @dev Classifies labels into the PoP tier required for
/// registration and exposes reservation metadata.
///      Length <= 5 is reserved for governance; lengths 6-8 require PopFull unless they carry
/// exactly two trailing digits (PopLite); lengths >= 9 require PopFull unless they carry exactly
/// two trailing
///      digits (NoStatus, open). More than two trailing digits is invalid; internal digits do not
/// affect classification. Reservations are keyed by the digit-stripped stem so `alice` and
/// `alice42` share a slot.
/// @dev Pricing is primarily a spam deterrent for NoStatus users; verified PopLite and PopFull
/// users pay zero. @custom:security-contact admin@parity.io
interface IPopRules {
    /// @notice Proof-of-Personhood eligibility tier.
    /// @dev `NoStatus` is the default for unverified users; `PopLite` and `PopFull` are the two
    ///      personhood tiers; `Reserved` covers both governance-held names and base stems held by
    ///      another user through the reservation table.
    enum PopStatus {
        NoStatus,
        PopLite,
        PopFull,
        Reserved
    }

    /// @notice Emitted when a base name receives a reservation.
    /// @param baseName The digit-stripped label receiving the reservation.
    /// @param owner Address obtaining the reservation right.
    /// @param expires UNIX timestamp when the reservation expires.
    event BaseNameReserved(string indexed baseName, address indexed owner, uint64 expires);

    /// @notice Emitted when the spam-deterrent NoStatus starting price is rotated.
    /// @dev Owner-only setter {updateStartingPrice}; the new value is consumed
    ///      by `_priceValidatedName` on the next pricing read.
    /// @param oldPrice Previous wei value.
    /// @param newPrice New wei value.
    event StartingPriceUpdated(uint256 oldPrice, uint256 newPrice);

    /// @notice Thrown when a name violates PoP-tier or reservation requirements.
    /// @param reason Human-readable explanation of the failure condition.
    error PopError(string reason);

    /// @notice Thrown when a caller is not an authorised controller on the registrar.
    error NotRegistry();

    /// @notice Bundle returned from metadata-aware pricing queries.
    /// @param price Registration cost; typically non-zero only for NoStatus users.
    /// @param status Required PoP tier for this name.
    /// @param userStatus Current PoP status recorded for the querying user.
    /// @param message Human-readable classification description.
    struct PriceWithMeta {
        uint256 price;
        PopStatus status;
        PopStatus userStatus;
        string message;
    }

    /// @notice Reservation metadata for a base name (digits removed).
    /// @param owner Address holding exclusive claim rights during the reservation window.
    /// @param expires UNIX timestamp when the reservation expires.
    /// @param controller Address that wrote the reservation; the only address permitted to release
    /// it before expiry.
    struct Reservation {
        address owner;
        uint64 expires;
        address controller;
    }

    /// @notice Classifies a name into a required PoP tier per DotNS naming rules.
    /// @dev Pure; inputs are the label bytes only. Callers use the returned tier to decide which
    ///      pricing and verification branch applies.
    /// @param name The name label being evaluated.
    /// @return requirement Required tier for registration.
    /// @return message Explanation of the classification result.
    /// @custom:reverts PopError
    function classifyName(string calldata name)
        external
        pure
        returns (PopStatus requirement, string memory message);

    /// @notice Updates the spam-deterrent starting price for NoStatus pricing.
    /// @dev Owner-only. The new value flows into `_priceValidatedName` on the next
    ///      pricing read; no redeploy. Emits {StartingPriceUpdated}.
    /// @param newStartingPrice New base price in wei.
    function updateStartingPrice(uint256 newStartingPrice) external;

    /// @notice Creates a reservation entry for the digit-stripped version of a name.
    /// @dev Commit-reveal reservation path. Callable only by an authorised controller on the
    ///      registrar. Reverts unless the label is classified as `PopLite`; no-ops when the slot
    ///      is already live so concurrent registrations cannot stomp the original reserver.
    /// @param baseName The base label with trailing digits removed.
    /// @param user The address receiving reservation rights.
    /// @custom:emits BaseNameReserved
    /// @custom:reverts NotRegistry
    /// @custom:reverts PopError
    function reserveBaseName(string calldata baseName, address user) external;

    /// @notice Emitted when a base-name reservation is cleared.
    /// @param baseName The base label whose reservation was released.
    event BaseNameReleased(string indexed baseName);

    /// @notice Writes or refreshes a reservation for a bare base-name stem.
    /// @dev Gateway-driven reservation path used by the PoP controller. Callable by any controller
    ///      in the registrar's `controllers` set. Does not apply the lite-format classification
    ///      that `reserveBaseName` enforces; the caller supplies the bare stem directly. Reverts
    ///      if the slot is already held by another user and still live so the caller's local
    ///      bookkeeping and PopRules state stay in lockstep. If the slot is already live for the
    ///      same user, refreshes expiry to `block.timestamp + MAX_RESERVATION_TIME`.
    /// @param baseName The base label to reserve (no trailing digits).
    /// @param user The address receiving reservation rights.
    /// @custom:emits BaseNameReserved
    /// @custom:reverts NotRegistry
    /// @custom:reverts PopError
    function reserveBaseNameForPop(string calldata baseName, address user) external;

    /// @notice Clears a reservation for a base-name stem.
    /// @dev Callable by controllers in the registrar's `controllers` set. Live reservations may
    ///      only be cleared by the same controller that wrote them; expired reservations may be
    ///      cleared by any authorised controller. Used by the PoP controller when a reservation is
    ///      claimed, relinquished, or a queue head promotion leaves the slot empty.
    /// @param baseName The base label whose reservation should be cleared.
    /// @custom:emits BaseNameReleased
    /// @custom:reverts NotRegistry
    /// @custom:reverts PopError
    function releaseBaseName(string calldata baseName) external;

    /// @notice Retrieves reservation information for a base name.
    /// @dev Raw accessor: returns the stored slot regardless of expiry. Use {isBaseNameReserved}
    ///      when live-window semantics are needed.
    /// @param baseName The base label without trailing digits.
    /// @return owner The address assigned to the reservation.
    /// @return expires UNIX timestamp when the reservation expires.
    /// @custom:reverts PopError
    function getBaseNameReservation(string calldata baseName)
        external
        view
        returns (address owner, uint64 expires);

    /// @notice Indicates whether a base name is currently reserved.
    /// @dev Applies the live-window predicate to the stored slot so an expired reservation reads
    ///      as free.
    /// @param baseName The base label without trailing digits.
    /// @return reservedStatus True if a live reservation is active.
    /// @return owner The reservation holder (zero when not reserved).
    /// @return expires UNIX timestamp when the reservation expires.
    /// @custom:reverts PopError
    function isBaseNameReserved(string calldata baseName)
        external
        view
        returns (bool reservedStatus, address owner, uint64 expires);

    /// @notice Calculates price with PoP classification and reservation enforcement.
    /// @dev Reverting pricing path used by the commit-reveal controller. Rejects
    /// governance-reserved names and base-name registrations held by another user. Price is a spam
    /// deterrent and
    ///      is significant only for NoStatus users; verified users pay zero.
    /// @param name Domain label.
    /// @param userAddress Registering user for the given label.
    /// @return metadata Price with PoP requirements and classification.
    /// @custom:reverts PopError
    function priceWithCheck(
        string calldata name,
        address userAddress
    )
        external
        view
        returns (PriceWithMeta memory metadata);

    /// @notice Calculates price with PoP classification and reservation metadata, without reverting
    /// on conflicts. @dev Non-reverting counterpart to `priceWithCheck`: surfaces the same fields,
    /// but reports a
    ///      `Reserved` status through `metadata` instead of reverting when the base stem is held
    ///      by another user. Used by front-ends that need to present a price and eligibility
    ///      preview without forcing a transaction attempt. Governance-reserved names are not
    ///      rejected here either; the caller decides what to do.
    /// @param name Domain label.
    /// @param userAddress Registering user for the given label.
    /// @return metadata Price with PoP requirements and classification.
    /// @custom:reverts PopError
    function priceWithoutCheck(
        string calldata name,
        address userAddress
    )
        external
        view
        returns (PriceWithMeta memory metadata);

    /// @notice Friction fee owed when `account` reaches into a label tier above its verification
    /// level. @dev Non-zero only when `account` cannot meet the label's required PoP tier; the
    /// value is the
    ///      length-scaled list price. Acts as cross-payer friction at registration time and as the
    ///      transfer-time floor consumed by `DotnsNameEscrow.chargeTransferFee`.
    /// @param name Domain label being acted on.
    /// @param account Account whose verification reach is being measured.
    /// @custom:reverts PopError
    function reachFee(string calldata name, address account) external view returns (uint256 fee);

    /// @notice Returns whether `name` is a base name under PoP rules.
    /// @dev A base name has no trailing digits; lite-person labels always have at least two
    ///      trailing digits, so the two spaces are disjoint.
    /// @param name The label to check.
    /// @return isBase True when the label has no trailing digits.
    /// @custom:reverts PopError
    function isBaseName(string calldata name) external pure returns (bool isBase);

    /// @notice Calculates registration cost for a label.
    /// @dev Pure length-based pricing; ignores PoP status and reservation state.
    /// @param name Domain label to price.
    /// @return cost Registration cost in wei.
    /// @custom:reverts PopError
    function price(string calldata name) external view returns (uint256 cost);
}
