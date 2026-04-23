// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC721} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {IDotnsController} from "./IDotnsController.sol";

/// @title Dotns Registrar
/// @notice ERC721-backed ownership for DotNS names with controller-gated registration.
/// @dev This interface is intentionally minimal and deliberately policy-free.
///      It provides:
///      - ERC721 ownership for registered name token IDs.
///      - Controller-gated registration.
/// @custom:security-contact admin@parity.io
interface IDotnsRegistrar is IERC721 {
    /// @notice Thrown when a name is already registered.
    /// @param tokenId The token identifier derived from the node.
    error NameNotAvailable(uint256 tokenId);

    /// @notice Thrown when the caller is not an authorised controller.
    /// @param caller The caller address.
    error NotController(address caller);

    /// @notice Emitted when a name is registered.
    /// @param id Token identifier.
    /// @param owner Owner of the name.
    event NameRegistered(uint256 indexed id, address indexed owner);

    /// @notice Emitted when a controller is added.
    /// @dev Typed as the shared baseline {IDotnsController} so the commit-reveal
    ///      controller and the PoP controller (and any future controller) all fit
    ///      the same signature without the registrar depending on any specific
    ///      controller interface.
    /// @param controller Controller granted permissions.
    event ControllerAdded(IDotnsController indexed controller);

    /// @notice Emitted when a controller is removed.
    /// @param controller Controller whose permissions were revoked.
    event ControllerRemoved(IDotnsController indexed controller);

    /// @notice Returns whether a name is available for registration.
    /// @dev A name is available if and only if it has not been registered yet.
    /// @param id Token identifier.
    /// @return isAvailable True if the name can be registered.
    function available(uint256 id) external view returns (bool isAvailable);

    /// @notice Registers a name permanently.
    /// @dev Callable only by an authorised controller.
    ///      Registration mints the ERC721 token to `owner` and stores both the human-readable
    ///      label and its keccak256 hash for use during transfer store writes.
    /// @param id Token identifier.
    /// @param owner Owner of the name.
    /// @param label The human-readable label string (e.g. "alice").
    function register(uint256 id, address owner, string calldata label) external;

    /// @notice Adds an authorised controller.
    /// @dev Callable only by the contract owner. Typed as the shared baseline
    ///      {IDotnsController} so that the commit-reveal controller, the PoP
    ///      controller, and any future controller all pass without the registrar
    ///      depending on a specific controller shape.
    /// @param controller Controller to authorise.
    function addController(IDotnsController controller) external;

    /// @notice Removes an authorised controller.
    /// @dev Callable only by the contract owner.
    /// @param controller Controller to deauthorise.
    function removeController(IDotnsController controller) external;

    /// @notice Returns the human-readable label a token was registered with.
    /// @dev Canonical state source for the label string; any client that holds
    ///      a node or tokenId can resolve the original label in one view call
    ///      without scanning registration events. Returns the empty string
    ///      when the token does not exist.
    /// @param tokenId The token identifier (equal to `uint256(node)` for base names).
    /// @return label The label the token was registered with.
    function labelOf(uint256 tokenId) external view returns (string memory label);
}
