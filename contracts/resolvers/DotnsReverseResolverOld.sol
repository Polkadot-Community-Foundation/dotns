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
import {IDotnsReverseResolver} from "./IDotnsReverseResolver.sol";
import {IDotnsRegistrarController} from "../registrars/IDotnsRegistrarController.sol";
import {IDotnsProtocolRegistry} from "../registry/IDotnsProtocolRegistry.sol";

/// @title DotnsReverseResolverOld
/// @notice Pre-migration snapshot for OZ referenceContract validation.
contract DotnsReverseResolverOld is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC165Upgradeable,
    IDotnsReverseResolver
{
    mapping(address owner => string name) private reverseNames;
    IDotnsRegistrarController public registrarController;

    // forge-lint: disable-next-line(mixed-case-variable)
    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __Ownable_init(msg.sender);
        __ERC165_init();
    }

    function setReverseName(address, string calldata) external override {}

    function nameOf(address) external pure override returns (string memory) {
        return "";
    }

    function updateRegistrar(IDotnsRegistrarController newRegistrar) external onlyOwner {
        registrarController = newRegistrar;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC165Upgradeable)
        returns (bool supported)
    {
        return interfaceId == type(IDotnsReverseResolver).interfaceId
            || super.supportsInterface(interfaceId);
    }

    function updateProtocolRegistry(IDotnsProtocolRegistry) external override onlyOwner {}

    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.0.0";
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
