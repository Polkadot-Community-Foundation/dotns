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

import {IDotnsResolver} from "./IDotnsResolver.sol";
import {IDotnsRegistry} from "../registry/IDotnsRegistry.sol";
import {IDotnsProtocolRegistry} from "../registry/IDotnsProtocolRegistry.sol";

/// @title DotnsResolverOld
/// @notice Pre-migration snapshot for OZ referenceContract validation.
contract DotnsResolverOld is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC165Upgradeable,
    IDotnsResolver
{
    IDotnsRegistry public registry;

    // forge-lint: disable-next-line(mixed-case-variable)
    uint256[50] private __gap;

    mapping(bytes32 node => address owner) private addresses;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(IDotnsRegistry _registry) external initializer {
        __Ownable_init(msg.sender);
        __ERC165_init();
        registry = _registry;
    }

    function setAddress(bytes32, address) external override {}

    function addressOf(bytes32) external pure override returns (address) {
        return address(0);
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return
            interfaceId == type(IDotnsResolver).interfaceId || super.supportsInterface(interfaceId);
    }

    function updateProtocolRegistry(IDotnsProtocolRegistry) external override onlyOwner {}

    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.0.0";
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
