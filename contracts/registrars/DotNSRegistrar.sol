// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    ERC721Upgradeable,
    IERC721
} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

import {IDotnsRegistrar} from "./IDotnsRegistrar.sol";

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
    mapping(address => bool) public controllers;

    /// @notice Restricts function access to authorised controllers.
    modifier onlyController() {
        require(controllers[msg.sender], NotController(msg.sender));
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
        __ERC721_init(name, symbol);
        __Ownable_init(msg.sender);
    }

    /// @inheritdoc IDotnsRegistrar
    function addController(address controller) external onlyOwner {
        controllers[controller] = true;
        emit ControllerAdded(controller);
    }

    /// @inheritdoc IDotnsRegistrar
    function removeController(address controller) external onlyOwner {
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

    /// @inheritdoc IERC721
    function transferFrom(
        address,
        address,
        uint256
    )
        public
        virtual
        override(IERC721, ERC721Upgradeable)
    {
        revert NotAllowed();
    }

    /// @notice Returns implementation version
    /// @return versionString Current version string
    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.0.0";
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
