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

/// @title DotNS Content Resolver
/// @notice Stores off-chain content references for DotNS nodes
/// @dev This resolver maintains a simple mapping from node identifiers to
///      opaque content identifiers. Authorisation is enforced strictly via
///      node ownership in the DotNS registry.
/// @custom:security-contact admin@parity.io
contract DotnsContentResolver is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC165Upgradeable,
    IDotnsContentResolver
{
    /// @notice DotNS registry used for ownership checks
    IDotnsRegistry public registry;

    /// @notice Node → content identifier mapping
    mapping(bytes32 => bytes) private contents;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the content resolver
    /// @param _registry Address of the DotNS registry contract
    function initialize(IDotnsRegistry _registry) external initializer {
        __Ownable_init(msg.sender);

        __ERC165_init();

        registry = _registry;
    }

    /// @inheritdoc IDotnsContentResolver
    function setContent(bytes32 node, bytes calldata content) external {
        address owner = registry.owner(node);
        require(owner == msg.sender, NotAuthorised(node, msg.sender));

        contents[node] = content;
        emit ContentUpdated(node, content);
    }

    /// @inheritdoc IDotnsContentResolver
    function contentOf(bytes32 node) external view returns (bytes memory content) {
        return contents[node];
    }

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IDotnsContentResolver).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /// @notice Returns implementation version
    /// @return versionString Current version string
    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.0.0";
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
