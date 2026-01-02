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

import {IDotnsRegistrar} from "./IDotnsRegistrar.sol";
import {IDotnsRegistrarController} from "./IDotnsRegistrarController.sol";

/// @title DotNS Base Registrar
/// @author DotNS
/// @notice ERC721-backed registrar implementing permanent name ownership.
/// @dev This contract is deliberately policy-free
/// @custom:security-contact admin@parity.io
contract DotnsRegistrar is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC721Upgradeable,
    IDotnsRegistrar
{
    /// @notice Mapping of authorised controller addresses.
    /// @dev Controllers may call `register`.
    mapping(IDotnsRegistrarController controller => bool exists) public controllers;

    /// @dev Reserved storage space to allow for layout changes in the future.
    // forge-lint: disable-next-line(mixed-case-variable)
    uint256[50] private __gap;

    /// @notice Restricts function access to authorised controllers.
    modifier onlyController() {
        _onlyController();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the registrar.
    /// @dev Uses OpenZeppelin upgradeable initializers.
    /// @param name ERC721 token name.
    /// @param symbol ERC721 token symbol.
    function initialize(string calldata name, string calldata symbol) external initializer {
        __Ownable_init(msg.sender);
        __ERC721_init(name, symbol);
    }

    /// @inheritdoc IDotnsRegistrar
    function addController(IDotnsRegistrarController controller) external onlyOwner {
        controllers[controller] = true;
        emit ControllerAdded(controller);
    }

    /// @inheritdoc IDotnsRegistrar
    function removeController(IDotnsRegistrarController controller) external onlyOwner {
        controllers[controller] = false;
        emit ControllerRemoved(controller);
    }

    /// @notice Checks whether a token ID exists.
    /// @param tokenId Token identifier.
    /// @return exists True if the token exists.
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    /// @inheritdoc IDotnsRegistrar
    function available(uint256 id) public view override returns (bool isAvailable) {
        return !_exists(id);
    }

    /// @inheritdoc IDotnsRegistrar
    function register(uint256 id, address owner) external override onlyController {
        require(available(id), NameNotAvailable(id));
        _mint(owner, id);
        emit NameRegistered(id, owner);
    }

    /// @notice Returns implementation version
    /// @return versionString Current version string
    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.0.0";
    }

    /// @notice Internal function to check for controller access.
    /// @dev Done this way to redue code size
    function _onlyController() internal view {
        require(controllers[IDotnsRegistrarController(msg.sender)], NotController(msg.sender));
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
