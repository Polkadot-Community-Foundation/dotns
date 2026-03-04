// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    ERC721Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

import {IDotnsRegistrarOld} from "./IDotnsRegistrarOld.sol";
import {IDotnsRegistrarController} from "./IDotnsRegistrarController.sol";

/// @title DotnsRegistrarOld
/// @notice Snapshot of the deployed DotnsRegistrar used as a reference for upgrade safety checks.
contract DotnsRegistrarOld is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC721Upgradeable,
    IDotnsRegistrarOld
{
    mapping(IDotnsRegistrarController controller => bool exists) public controllers;

    uint256[50] private __gap;

    modifier onlyController() {
        _onlyController();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string calldata name, string calldata symbol) external initializer {
        __Ownable_init(msg.sender);
        __ERC721_init(name, symbol);
    }

    function addController(IDotnsRegistrarController controller) external onlyOwner {
        controllers[controller] = true;
        emit ControllerAdded(controller);
    }

    function removeController(IDotnsRegistrarController controller) external onlyOwner {
        controllers[controller] = false;
        emit ControllerRemoved(controller);
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    function available(uint256 id) public view override returns (bool isAvailable) {
        return !_exists(id);
    }

    function register(uint256 id, address owner) external override onlyController {
        require(available(id), NameNotAvailable(id));
        _mint(owner, id);
        emit NameRegistered(id, owner);
    }

    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.0.0";
    }

    function _onlyController() internal view {
        require(controllers[IDotnsRegistrarController(msg.sender)], NotController(msg.sender));
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
