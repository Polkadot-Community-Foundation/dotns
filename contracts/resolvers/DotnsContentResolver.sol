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
/// @notice Stores content hash and text records for DotNS nodes
/// @dev Maintains simple storage for:
///      - `contenthash(node)` as opaque bytes
///      - `text(node, key)` as string key-value records
///      Authorisation is enforced strictly via node ownership in the DotNS registry.
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

    /// @notice Node → content hash mapping
    mapping(bytes32 => bytes) private 
    contenthashes;

    /// @notice Node → (key → value) text records
    mapping(bytes32 => mapping(string => string)) private textRecords;

    /// @dev Reserved storage space to allow for layout changes in the future.
    // forge-lint: disable-next-line(mixed-case-variable)
    uint256[50] private __gap;

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
    function setContenthash(bytes32 node, bytes calldata hash) external override {
        _requireNodeOwner(node);
        contenthashes[node] = hash;
        emit ContentHashUpdated(node, hash);
    }

    /// @inheritdoc IDotnsContentResolver
    function contenthash(bytes32 node) external view override returns (bytes memory hash) {
        return contenthashes[node];
    }

    /// @inheritdoc IDotnsContentResolver
    function setText(bytes32 node, string calldata key, string calldata value) external override {
        _requireNodeOwner(node);
        textRecords[node][key] = value;
        emit TextUpdated(node, key, value);
    }

    /// @inheritdoc IDotnsContentResolver
    function text(
        bytes32 node,
        string calldata key
    )
        external
        view
        override
        returns (string memory value)
    {
        return textRecords[node][key];
    }

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IDotnsContentResolver).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /// @notice Ensures the caller is authorised to modify `node`
    /// @param node Node identifier
    function _requireNodeOwner(bytes32 node) internal view {
        address owner = registry.owner(node);
        require(owner == msg.sender, NotAuthorised(node, msg.sender));
    }

    /// @notice Returns implementation version
    /// @return versionString Current version string
    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.0.0";
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
