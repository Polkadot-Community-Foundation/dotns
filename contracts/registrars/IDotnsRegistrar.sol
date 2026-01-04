// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC721} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {IDotnsRegistrarController} from "./IDotnsRegistrarController.sol";

/// @title DotNS Registrar Interface
/// @author DotNS
/// @notice ERC721-backed ownership for DotNS names with controller-gated registration.
/// @dev This interface is intentionally minimal and deliberately policy-free.
///      It provides:
///      - ERC721 ownership for registered name token IDs.
///      - Controller-gated registration.
/// @custom:security-contact admin@parity.io
interface IDotnsRegistrar is IERC721 {
    /// @notice Thrown when a name is already registered.
    /// @param tokenId The token identifier derived from the label.
    error NameNotAvailable(uint256 tokenId);

    /// @notice Thrown when the caller is not an authorised controller.
    /// @param caller The caller address.
    error NotController(address caller);
    /// @notice Thrown when any of the transfer functions are called
    /// @dev We do this to prevent any transfer of NFTs given their
    ///         They are tied to a wallets POP
    error NotAllowed();

    /// @notice Emitted when a name is registered.
    /// @param id Token identifier.
    /// @param owner Owner of the name.
    event NameRegistered(uint256 indexed id, address indexed owner);

    /// @notice Emitted when a controller is added.
    /// @param controller Address granted controller permissions.
    event ControllerAdded(IDotnsRegistrarController indexed controller);

    /// @notice Emitted when a controller is removed.
    /// @param controller Address whose controller permissions were revoked.
    event ControllerRemoved(IDotnsRegistrarController indexed controller);

    /// @notice Returns whether a name is available for registration.
    /// @dev A name is available if and only if it has not been registered yet.
    /// @param id Token identifier.
    /// @return isAvailable True if the name can be registered.
    function available(uint256 id) external view returns (bool isAvailable);

    /// @notice Registers a name permanently.
    /// @dev Callable only by an authorised controller.
    ///      Registration mints the ERC721 token to `owner`.
    /// @param id Token identifier.
    /// @param owner Owner of the name.
    function register(uint256 id, address owner) external;

    /// @notice Adds an authorised controller.
    /// @dev Can only be called by an owner
    /// @param controller Address to authorise.
    function addController(IDotnsRegistrarController controller) external;

    /// @notice Removes an authorised controller.
    /// @dev Can only be called by an owner
    /// @param controller Address to deauthorise.
    function removeController(IDotnsRegistrarController controller) external;
}
