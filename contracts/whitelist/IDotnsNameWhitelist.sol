// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title IDotnsNameWhitelist
/// @notice Interface for the pre-launch name whitelist that binds a name to the single address
///         permitted to register it, tracking each name from request to decision.
/// @dev The contract never accepts a caller-supplied hash. Every entry point takes the bare
///      label and derives the node itself from the TLD held in the protocol registry, the same
///      derivation the controllers use, so a malformed or mismatched hash cannot be smuggled in.
///      Every entry keeps its bare label, request and decision timestamps, and status, and the
///      node set is enumerable, so the whole whitelist is reviewable on-chain and by event log.
///      Operator appointment and removal, and upgrades, are owner-gated through
///      @custom:contract DotnsRoleManager.
/// @custom:security-contact admin@parity.io
interface IDotnsNameWhitelist {
    /// @notice Lifecycle status of a whitelist entry.
    /// @dev `None` is the zero-value default of an absent entry, so a missing node reads as `None`
    ///      rather than as a live status. `Accepted` is the only status the controllers admit for
    ///      registration; `Requested` and `Rejected` do not reserve the name.
    enum GrantStatus {
        None,
        Requested,
        Accepted,
        Rejected
    }

    /// @notice A whitelist entry and its request-to-decision lifecycle.
    /// @dev `grantee`, `requestedAt` and `status` co-locate in one storage slot (20 + 8 + 1
    ///      bytes); `decidedAt` spills to the next; the dynamic `label` is stored separately.
    /// @param grantee Address permitted to register the name once accepted.
    /// @param requestedAt Timestamp the entry was requested.
    /// @param status Lifecycle status; see GrantStatus.
    /// @param decidedAt Timestamp the entry was accepted or rejected; zero while `Requested`.
    /// @param label Bare label, kept for on-chain review.
    struct Grant {
        address grantee;
        uint64 requestedAt;
        GrantStatus status;
        uint64 decidedAt;
        string label;
    }

    /// @notice Emitted when a name is requested.
    /// @param node Namehash of the label under the active TLD.
    /// @param grantee Address that requested the name.
    /// @param label Bare label requested.
    event NameRequested(bytes32 indexed node, address indexed grantee, string label);

    /// @notice Emitted when a request is accepted, including an operator direct grant.
    /// @param node Namehash of the label under the active TLD.
    /// @param grantee Address permitted to register the name.
    /// @param label Bare label accepted.
    event NameAccepted(bytes32 indexed node, address indexed grantee, string label);

    /// @notice Emitted when a request is rejected.
    /// @param node Namehash of the label under the active TLD.
    /// @param grantee Address whose request was rejected.
    /// @param label Bare label rejected.
    event NameRejected(bytes32 indexed node, address indexed grantee, string label);

    /// @notice Emitted when an entry is cleared.
    /// @param node Namehash of the label under the active TLD.
    /// @param grantee Address whose entry was cleared.
    /// @param label Bare label cleared.
    event NameRevoked(bytes32 indexed node, address indexed grantee, string label);

    /// @notice Emitted when a grantee registers their name and the entry is consumed.
    /// @param node Namehash of the label under the active TLD.
    /// @param grantee Address that registered the name.
    /// @param label Bare label consumed.
    event NameConsumed(bytes32 indexed node, address indexed grantee, string label);

    /// @notice Emitted when the request window is set.
    /// @param openAt Timestamp requests start being accepted.
    /// @param closeAt Timestamp requests stop being accepted.
    event WindowSet(uint64 openAt, uint64 closeAt);

    /// @notice Thrown when a grant is issued to the zero address.
    error ZeroGrantee();

    /// @notice Thrown when a label is not a canonical single DNS label.
    error InvalidLabel();

    /// @notice Thrown when requesting or granting a name that already has a live entry.
    /// @param node Namehash of the label under the active TLD.
    error AlreadyExists(bytes32 node);

    /// @notice Thrown when accepting or rejecting a name that is not in the `Requested` status.
    /// @param node Namehash of the label under the active TLD.
    error NotRequested(bytes32 node);

    /// @notice Thrown when clearing a name that holds no entry.
    /// @param node Namehash of the label under the active TLD.
    error NotGranted(bytes32 node);

    /// @notice Thrown when `consume` is called by any address other than a registrar controller.
    /// @param caller Rejected caller.
    error NotController(address caller);

    /// @notice Thrown when `consume` is called for a name not accepted for the registrant.
    /// @param registrant Address attempting to register the name.
    /// @param node Namehash of the label under the active TLD.
    error NotGrantee(address registrant, bytes32 node);

    /// @notice Thrown when the request window is set with a zero duration.
    error BadWindow();

    /// @notice Thrown when a request is made outside the open window.
    error WindowClosed();

    /// @notice Sets the request window relative to the current time.
    /// @dev Restricted to the owner. The window opens at `block.timestamp + startsIn` and stays
    ///      open for `duration`, so it can never open in the past. Reverts with
    ///      @custom:reverts BadWindow when `duration` is zero. Emits @custom:emits WindowSet with
    ///      the resolved absolute timestamps.
    /// @param startsIn Seconds from now until requests start being accepted.
    /// @param duration Seconds the window stays open.
    function setWindow(uint64 startsIn, uint64 duration) external;

    /// @notice Requests `label` for the caller.
    /// @dev Records a `Requested` entry bound to the caller. Reverts with
    ///      @custom:reverts WindowClosed outside the open window, with
    ///      @custom:reverts AlreadyExists when the name already has a live entry, and with
    ///      @custom:reverts InvalidLabel when `label` is not a canonical single label. Emits
    ///      @custom:emits NameRequested.
    /// @param label Bare label to request.
    function requestName(string calldata label) external;

    /// @notice Accepts the pending request on `label`.
    /// @dev Restricted to an operator or the owner. Moves a `Requested` entry to `Accepted` and
    ///      stamps the decision. Reverts with @custom:reverts NotRequested when the name is not
    ///      pending. Emits @custom:emits NameAccepted.
    /// @param label Bare label to accept.
    function accept(string calldata label) external;

    /// @notice Rejects the pending request on `label`.
    /// @dev Restricted to an operator or the owner. Moves a `Requested` entry to `Rejected` and
    ///      stamps the decision; the entry is kept for review. Reverts with
    ///      @custom:reverts NotRequested when the name is not pending. Emits
    ///      @custom:emits NameRejected.
    /// @param label Bare label to reject.
    function reject(string calldata label) external;

    /// @notice Grants `label` to `grantee` directly, without a prior request.
    /// @dev Restricted to an operator or the owner, and independent of the request window by
    ///      design, so operators can provision names whether or not requests are open. Writes an
    ///      `Accepted` entry with the request and decision timestamps set to now, for provisioning
    ///      names to a chosen address.
    ///      Reverts with @custom:reverts AlreadyExists when the name already has a live entry,
    ///      with @custom:reverts ZeroGrantee on a zero grantee, and with
    ///      @custom:reverts InvalidLabel when `label` is not a canonical single label. Emits
    ///      @custom:emits NameAccepted.
    /// @param label Bare label to grant.
    /// @param grantee Address permitted to register the name.
    function grantName(string calldata label, address grantee) external;

    /// @notice Grants several labels to one `grantee` directly.
    /// @dev Restricted to an operator or the owner. Applies the same rules as
    ///      @custom:function grantName to each entry.
    /// @param labels Bare labels to grant.
    /// @param grantee Address permitted to register each name.
    function grantNames(string[] calldata labels, address grantee) external;

    /// @notice Clears the entry on `label`, whatever its status.
    /// @dev Restricted to an operator or the owner. Reverts with @custom:reverts NotGranted when
    ///      the name holds no entry. Emits @custom:emits NameRevoked.
    /// @param label Bare label to clear.
    function revokeName(string calldata label) external;

    /// @notice Removes the accepted grant on `label` as `registrant` registers it.
    /// @dev Restricted to the registrar controllers resolved through the protocol registry, so
    ///      the entry is consumed exactly when its grantee registers the name. Reverts with
    ///      @custom:reverts NotController for any other caller and @custom:reverts NotGrantee when
    ///      `label` is not accepted for `registrant`. Emits @custom:emits NameConsumed.
    /// @param label Bare label being registered.
    /// @param registrant Address registering the name.
    function consume(string calldata label, address registrant) external;

    /// @notice Returns the address `label` is accepted for, or the zero address otherwise.
    /// @dev Non-zero only for an `Accepted` entry, so a pending or rejected name does not reserve.
    /// @param label Bare label to look up.
    /// @return grantee Address permitted to register the name.
    function granteeOf(string calldata label) external view returns (address grantee);

    /// @notice Returns whether `account` holds an accepted grant for `label`.
    /// @dev The pair check the controllers use to admit a registrant. False for the zero address.
    /// @param label Bare label to look up.
    /// @param account Address to test against the grant.
    /// @return granted True when `account` is the accepted grantee.
    function isGrantedTo(
        string calldata label,
        address account
    )
        external
        view
        returns (bool granted);

    /// @notice Returns the full entry for `label`, including status and timestamps.
    /// @param label Bare label to look up.
    /// @return grant The stored entry; a zeroed struct with `None` status when absent.
    function grantOf(string calldata label) external view returns (Grant memory grant);

    /// @notice Returns the number of entries, of any status.
    /// @return count Entry count.
    function grantCount() external view returns (uint256 count);

    /// @notice Returns a page of entries for review.
    /// @dev Reads the canonical offset and limit window. An `offset` at or beyond
    ///      @custom:function grantCount returns an empty page; `limit` is clamped to the
    ///      remaining entries. Iteration order is not stable across revokes.
    /// @param offset Index of the first entry to return.
    /// @param limit Maximum number of entries to return.
    /// @return page Entries in the window.
    function grants(uint256 offset, uint256 limit) external view returns (Grant[] memory page);

    /// @notice Returns the request window.
    /// @return openAt Timestamp requests start being accepted.
    /// @return closeAt Timestamp requests stop being accepted.
    function window() external view returns (uint64 openAt, uint64 closeAt);

    /// @notice Returns whether requests are currently accepted.
    /// @return open True when the current time is within the window.
    function isWindowOpen() external view returns (bool open);
}
