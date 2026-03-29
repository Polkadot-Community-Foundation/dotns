// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {
    IDotnsProtocolRegistry,
    KEY_REGISTRAR,
    KEY_CONTROLLER,
    KEY_REGISTRY,
    KEY_REVERSE_RESOLVER,
    KEY_POP_RULES,
    KEY_STORE_FACTORY,
    KEY_RESOLVER,
    KEY_CONTENT_RESOLVER
} from "./IDotnsProtocolRegistry.sol";

/// @title Dotns Protocol Registry
/// @notice Upgradeable address registry for all DotNS protocol contracts.
/// @dev Consolidates protocol contract addresses behind a single `bytes32 -> address` mapping.
///      Individual contracts query this registry instead of storing sibling references,
///      reducing storage fragmentation and simplifying upgrades.
/// @custom:security-contact admin@parity.io
contract DotnsProtocolRegistry is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    IDotnsProtocolRegistry
{
    bytes32 public constant REGISTRAR = KEY_REGISTRAR;
    bytes32 public constant CONTROLLER = KEY_CONTROLLER;
    bytes32 public constant REGISTRY = KEY_REGISTRY;
    bytes32 public constant REVERSE_RESOLVER = KEY_REVERSE_RESOLVER;
    bytes32 public constant POP_RULES = KEY_POP_RULES;
    bytes32 public constant STORE_FACTORY = KEY_STORE_FACTORY;
    bytes32 public constant RESOLVER = KEY_RESOLVER;
    bytes32 public constant CONTENT_RESOLVER = KEY_CONTENT_RESOLVER;

    /// @dev Internal mapping from well-known key to contract address.
    mapping(bytes32 key => address addr) private _addresses;

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the protocol registry.
    function initialize() external initializer {
        __Ownable_init(msg.sender);
    }

    /// @inheritdoc IDotnsProtocolRegistry
    function get(bytes32 key) external view override returns (address addr) {
        return _addresses[key];
    }

    /// @inheritdoc IDotnsProtocolRegistry
    function set(bytes32 key, address addr) external override onlyOwner {
        require(addr != address(0), ZeroAddress());

        _addresses[key] = addr;
        emit AddressUpdated(key, addr);
    }

    /// @notice Returns implementation version.
    /// @return versionString Current version string.
    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.0.0";
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
