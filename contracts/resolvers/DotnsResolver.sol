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

/// @title DotNS Resolver
/// @notice Stores forward-resolution records for DotNS nodes
/// @dev This contract maps node identifiers to resolution data.
///      Write access is restricted to the owner of the node as
///      recorded in the Dot registry.
/// @custom:security-contact admin@parity.io
contract DotnsResolver is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC165Upgradeable,
    IDotnsResolver
{
    /// @notice Registry used to resolve node ownership
    IDotnsRegistry public registry;

    /// @notice Node → resolved address
    mapping(bytes32 => address) private addresses;

    /// @notice Node → content reference
    mapping(bytes32 => bytes) private contents;

    /// @notice Node → display name
    mapping(bytes32 => string) private displayNames;

    /// @notice Restricts access to the owner of `node` as recorded in the registry
    /// @param node Node identifier
    modifier onlyNodeOwner(bytes32 node) {
        _onlyNodeOwner(node);
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the resolver
    /// @param _registry Dot registry used for ownership checks
    function initialize(IDotnsRegistry _registry) external initializer {
        __Ownable_init(msg.sender);
        __ERC165_init();

        registry = _registry;
    }

    /// @inheritdoc IDotnsResolver
    function setAddress(bytes32 node, address value) external onlyNodeOwner(node) {
        addresses[node] = value;
        emit AddressSet(node, value);
    }

    /// @inheritdoc IDotnsResolver
    function addressOf(bytes32 node) external view returns (address) {
        return addresses[node];
    }

    /// @inheritdoc IDotnsResolver
    function setContent(bytes32 node, bytes calldata value) external onlyNodeOwner(node) {
        contents[node] = value;
        emit ContentSet(node, value);
    }

    /// @inheritdoc IDotnsResolver
    function contentOf(bytes32 node) external view returns (bytes memory) {
        return contents[node];
    }

    /// @inheritdoc IDotnsResolver
    function setDisplayName(bytes32 node, string calldata value) external onlyNodeOwner(node) {
        displayNames[node] = value;
        emit DisplayNameSet(node, value);
    }

    /// @inheritdoc IDotnsResolver
    function displayNameOf(bytes32 node) external view returns (string memory) {
        return displayNames[node];
    }

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return
            interfaceId == type(IDotnsResolver).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @notice Internal ownership check for a registry node
    /// @param node Node identifier
    function _onlyNodeOwner(bytes32 node) internal view {
        require(registry.owner(node) == msg.sender, NotAuthorised(node, msg.sender));
    }

    /// @notice Returns implementation version
    /// @return versionString Current version string
    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.0.0";
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
