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

import {IDotnsRegistry} from "../registry/IDotnsRegistry.sol";
import {IDotnsContentResolver} from "./IDotnsContentResolver.sol";
import {IDotnsProtocolRegistry} from "../registry/IDotnsProtocolRegistry.sol";

/// @title DotnsContentResolverOld
/// @notice Pre-migration snapshot for OZ referenceContract validation.
contract DotnsContentResolverOld is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC165Upgradeable,
    IDotnsContentResolver
{
    IDotnsRegistry public registry;
    mapping(bytes32 node => bytes contentHash) private contenthashes;
    mapping(bytes32 node => mapping(string key => string value)) private textRecords;
    mapping(address owner => mapping(address operator => bool approved)) private operators;

    // forge-lint: disable-next-line(mixed-case-variable)
    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(IDotnsRegistry _registry) external initializer {
        __Ownable_init(msg.sender);
        __ERC165_init();
        registry = _registry;
    }

    function setContenthash(bytes32, bytes calldata) external override {}

    function contenthash(bytes32) external pure override returns (bytes memory) {
        return "";
    }

    function setText(bytes32, string calldata, string calldata) external override {}

    function text(bytes32, string calldata) external pure override returns (string memory) {
        return "";
    }

    function setApprovalForAll(address, bool) external override {}

    function isApprovedForAll(address, address) external pure override returns (bool) {
        return false;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IDotnsContentResolver).interfaceId
            || super.supportsInterface(interfaceId);
    }

    function updateProtocolRegistry(IDotnsProtocolRegistry) external override onlyOwner {}

    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.0.0";
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
