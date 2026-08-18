// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {DotnsRoleManager} from "../access/DotnsRoleManager.sol";
import {IDotnsNameWhitelist} from "./IDotnsNameWhitelist.sol";
import {IDotnsProtocolRegistry} from "../registry/IDotnsProtocolRegistry.sol";
import {LabelUtils} from "../utils/LabelUtils.sol";
import {StringUtils} from "../utils/StringUtils.sol";
import {DotnsConstants} from "../utils/DotnsConstants.sol";

/// @title DotnsNameWhitelist
/// @notice Pre-launch name whitelist that binds a name to the single address permitted to
///         register it, tracking each name from request to decision.
/// @dev Lives behind its own UUPS proxy with its own storage. Callers pass bare labels only; the
///      contract derives the node from the label and the TLD held in the protocol registry, the
///      same derivation the controllers use, so a caller can never supply a mismatched hash. Each
///      entry keeps its label, request and decision timestamps, and status, and the node set is
///      enumerable, so the whitelist is reviewable on-chain. Requests are user-facing; accepting,
///      rejecting, direct granting, batch granting and revoking are operator or owner actions
///      through the inherited @custom:contract DotnsRoleManager, with the owner appointing and
///      removing @custom:function DotnsConstants.WHITELIST_OPERATOR_ROLE holders and keeping
///      super-user access. The public and PoP controllers read the whitelist at mint time and
///      never write to it. Entries are keyed by the node under the active TLD, which the
///      deployment holds immutable for the whitelist's lifetime; a TLD change would strand
///      existing entries under their old node.
/// @custom:security-contact admin@parity.io
contract DotnsNameWhitelist is
    Initializable,
    UUPSUpgradeable,
    DotnsRoleManager,
    IDotnsNameWhitelist
{
    using StringUtils for string;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// @notice Protocol-level address registry for all DotNS contracts.
    IDotnsProtocolRegistry public protocolRegistry;

    /// @notice Entries keyed by the label's namehash under the active TLD.
    mapping(bytes32 node => Grant grant) private _grants;

    /// @notice Nodes with a live entry, kept enumerable so the whitelist can be reviewed.
    EnumerableSet.Bytes32Set private _grantedNodes;

    /// @notice Timestamp requests start being accepted.
    uint64 private _requestOpen;

    /// @notice Timestamp requests stop being accepted.
    uint64 private _requestClose;

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[50] private __gap;

    /// @notice Restricts a call to an operator or the owner.
    modifier onlyOperatorOrOwner() {
        _checkRoleOrOwner(DotnsConstants.WHITELIST_OPERATOR_ROLE);
        _;
    }

    /// @notice Restricts a call to a registrar controller resolved through the registry.
    modifier onlyController() {
        require(
            msg.sender == protocolRegistry.get(DotnsConstants.CONTROLLER)
                || msg.sender == protocolRegistry.get(DotnsConstants.POP_CONTROLLER),
            NotController(msg.sender)
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialises the whitelist.
    /// @dev Callable once through the UUPS proxy; direct calls on the implementation revert with
    ///      @custom:reverts InvalidInitialization. Sets the deployer as owner and wires the
    ///      protocol registry the node derivation reads the TLD from.
    /// @param registry Protocol registry all DotNS contracts resolve through.
    function initialize(IDotnsProtocolRegistry registry) external initializer {
        __Ownable_init(msg.sender);
        _dotnsRoleManagerInit();
        protocolRegistry = registry;
    }

    /// @inheritdoc IDotnsNameWhitelist
    function setWindow(uint64 startsIn, uint64 duration) external override onlyOwner {
        require(duration > 0, BadWindow());
        uint64 openAt = uint64(block.timestamp) + startsIn;
        uint64 closeAt = openAt + duration;
        _requestOpen = openAt;
        _requestClose = closeAt;
        emit WindowSet(openAt, closeAt);
    }

    /// @inheritdoc IDotnsNameWhitelist
    function requestName(string calldata label) external override {
        require(_isWindowOpen(), WindowClosed());
        bytes32 node = _validateNew(label);
        _grants[node] = Grant({
            grantee: msg.sender,
            requestedAt: uint64(block.timestamp),
            status: GrantStatus.Requested,
            decidedAt: 0,
            label: label
        });
        _grantedNodes.add(node);
        emit NameRequested(node, msg.sender, label);
    }

    /// @inheritdoc IDotnsNameWhitelist
    function accept(string calldata label) external override onlyOperatorOrOwner {
        (bytes32 node, address grantee) = _decide(label, GrantStatus.Accepted);
        emit NameAccepted(node, grantee, label);
    }

    /// @inheritdoc IDotnsNameWhitelist
    function reject(string calldata label) external override onlyOperatorOrOwner {
        (bytes32 node, address grantee) = _decide(label, GrantStatus.Rejected);
        emit NameRejected(node, grantee, label);
    }

    /// @inheritdoc IDotnsNameWhitelist
    function grantName(
        string calldata label,
        address grantee
    )
        external
        override
        onlyOperatorOrOwner
    {
        _grant(label, grantee);
    }

    /// @inheritdoc IDotnsNameWhitelist
    function grantNames(
        string[] calldata labels,
        address grantee
    )
        external
        override
        onlyOperatorOrOwner
    {
        for (uint256 i = 0; i < labels.length; i++) {
            _grant(labels[i], grantee);
        }
    }

    /// @inheritdoc IDotnsNameWhitelist
    function revokeName(string calldata label) external override onlyOperatorOrOwner {
        bytes32 node = _nodeOf(label);
        Grant storage grant = _grants[node];
        require(grant.status != GrantStatus.None, NotGranted(node));
        address grantee = grant.grantee;
        _clear(node);
        emit NameRevoked(node, grantee, label);
    }

    /// @inheritdoc IDotnsNameWhitelist
    function consume(string calldata label, address registrant) external override onlyController {
        bytes32 node = _nodeOf(label);
        Grant storage grant = _grants[node];
        require(
            grant.status == GrantStatus.Accepted && grant.grantee == registrant,
            NotGrantee(registrant, node)
        );
        _clear(node);
        emit NameConsumed(node, registrant, label);
    }

    /// @inheritdoc IDotnsNameWhitelist
    function granteeOf(string calldata label) external view override returns (address grantee) {
        Grant storage grant = _grants[_nodeOf(label)];
        return grant.status == GrantStatus.Accepted ? grant.grantee : address(0);
    }

    /// @inheritdoc IDotnsNameWhitelist
    function isGrantedTo(
        string calldata label,
        address account
    )
        external
        view
        override
        returns (bool granted)
    {
        Grant storage grant = _grants[_nodeOf(label)];
        return
            account != address(0) && grant.status == GrantStatus.Accepted
                && grant.grantee == account;
    }

    /// @inheritdoc IDotnsNameWhitelist
    function grantOf(string calldata label) external view override returns (Grant memory grant) {
        return _grants[_nodeOf(label)];
    }

    /// @inheritdoc IDotnsNameWhitelist
    function grantCount() external view override returns (uint256 count) {
        return _grantedNodes.length();
    }

    /// @inheritdoc IDotnsNameWhitelist
    function grants(
        uint256 offset,
        uint256 limit
    )
        external
        view
        override
        returns (Grant[] memory page)
    {
        uint256 total = _grantedNodes.length();
        if (offset >= total) {
            return new Grant[](0);
        }

        uint256 available = total - offset;
        uint256 count = limit < available ? limit : available;

        page = new Grant[](count);
        for (uint256 i; i < count; ++i) {
            page[i] = _grants[_grantedNodes.at(offset + i)];
        }
    }

    /// @inheritdoc IDotnsNameWhitelist
    function window() external view override returns (uint64 openAt, uint64 closeAt) {
        return (_requestOpen, _requestClose);
    }

    /// @inheritdoc IDotnsNameWhitelist
    function isWindowOpen() external view override returns (bool open) {
        return _isWindowOpen();
    }

    /// @notice Writes an `Accepted` entry for `grantee`, rejecting a name that already exists.
    function _grant(string calldata label, address grantee) internal {
        require(grantee != address(0), ZeroGrantee());
        bytes32 node = _validateNew(label);
        uint64 nowTimestamp = uint64(block.timestamp);
        _grants[node] = Grant({
            grantee: grantee,
            requestedAt: nowTimestamp,
            status: GrantStatus.Accepted,
            decidedAt: nowTimestamp,
            label: label
        });
        _grantedNodes.add(node);
        emit NameAccepted(node, grantee, label);
    }

    /// @notice Moves a pending request to a terminal decision and stamps the decision time.
    function _decide(
        string calldata label,
        GrantStatus decision
    )
        internal
        returns (bytes32 node, address grantee)
    {
        node = _nodeOf(label);
        Grant storage grant = _grants[node];
        require(grant.status == GrantStatus.Requested, NotRequested(node));
        grant.status = decision;
        grant.decidedAt = uint64(block.timestamp);
        grantee = grant.grantee;
    }

    /// @notice Validates a canonical, unused label and returns its node.
    function _validateNew(string calldata label) internal view returns (bytes32 node) {
        require(label.isSingleLabel(), InvalidLabel());
        node = _nodeOf(label);
        require(_grants[node].status == GrantStatus.None, AlreadyExists(node));
    }

    /// @notice Derives the namehash of `label` under the active TLD read from the registry.
    function _nodeOf(string calldata label) internal view returns (bytes32 node) {
        (, node) = LabelUtils.deriveNode(protocolRegistry.tldNode(), label);
    }

    /// @notice Returns whether the current time is within the open window.
    function _isWindowOpen() internal view returns (bool open) {
        return block.timestamp >= _requestOpen && block.timestamp < _requestClose;
    }

    /// @notice Removes an entry from both the map and the enumerable set.
    function _clear(bytes32 node) internal {
        delete _grants[node];
        _grantedNodes.remove(node);
    }

    /// @inheritdoc DotnsRoleManager
    function _isSupportedRole(bytes32 role) internal pure override returns (bool supported) {
        return role == DotnsConstants.WHITELIST_OPERATOR_ROLE;
    }

    /// @notice Restricts upgrades to the owner.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
