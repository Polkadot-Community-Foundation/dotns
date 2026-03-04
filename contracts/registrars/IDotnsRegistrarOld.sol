// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC721} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {IDotnsRegistrarController} from "./IDotnsRegistrarController.sol";

/// @title IDotnsRegistrarOld
/// @notice Snapshot of the deployed IDotnsRegistrar interface used as a reference for upgrade safety checks.
interface IDotnsRegistrarOld is IERC721 {
    error NameNotAvailable(uint256 tokenId);
    error NotController(address caller);

    event NameRegistered(uint256 indexed id, address indexed owner);
    event ControllerAdded(IDotnsRegistrarController indexed controller);
    event ControllerRemoved(IDotnsRegistrarController indexed controller);

    function available(uint256 id) external view returns (bool isAvailable);
    function register(uint256 id, address owner) external;
    function addController(IDotnsRegistrarController controller) external;
    function removeController(IDotnsRegistrarController controller) external;
}
