// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IDotnsProtocolRegistry} from "./IDotnsProtocolRegistry.sol";

/// @title Dotns Protocol Registry
/// @author Parity
/// @notice Upgradeable address registry for all DotNS protocol contracts.
/// @dev Single source of truth for sibling-contract lookups. All siblings resolve each other via
///      well-known `bytes32` constants in `DotnsConstants` rather than holding direct addresses,
///      so an upgrade or rewire only mutates this contract.
/// @custom:security-contact admin@parity.io
contract DotnsProtocolRegistry is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    IDotnsProtocolRegistry
{
    /// @notice Address stored for each well-known protocol key.
    mapping(bytes32 key => address addr) private _addresses;

    /// @notice Reference count per address, incremented for every key it is registered under.
    /// @dev Lets `isRegisteredAddress` answer in O(1) and survive a contract being mapped to
    ///      multiple keys without being treated as deregistered when only one key is rewired.
    mapping(address addr => uint256 refcount) private _registeredRefcount;

    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialises the protocol registry.
    /// @custom:reverts InvalidInitialization
    function initialize() external initializer {
        __Ownable_init(msg.sender);
    }

    /// @inheritdoc IDotnsProtocolRegistry
    /// @dev Returns `address(0)` for unregistered keys; callers must validate when a non-zero
    ///      address is required.
    function get(bytes32 key) external view override returns (address addr) {
        return _addresses[key];
    }

    /// @inheritdoc IDotnsProtocolRegistry
    /// @dev Maintains `_registeredRefcount` so the same address mapped to multiple keys remains
    ///      reported as registered until every key has been rewired away from it. No-ops when
    ///      `addr` already matches the stored value to keep upgrade scripts idempotent.
    function set(bytes32 key, address addr) external override onlyOwner {
        require(addr != address(0), ZeroAddress());

        address previousAddress = _addresses[key];
        if (previousAddress == addr) return;

        if (previousAddress != address(0)) {
            --_registeredRefcount[previousAddress];
        }
        ++_registeredRefcount[addr];

        _addresses[key] = addr;
        emit AddressUpdated(key, addr);
    }

    /// @inheritdoc IDotnsProtocolRegistry
    /// @dev Treats `address(0)` as unregistered regardless of refcount so callers can use this
    ///      as a simple peer-trust check without zero-address pre-validation.
    function isRegisteredAddress(address addr) external view override returns (bool registered) {
        return addr != address(0) && _registeredRefcount[addr] > 0;
    }

    /// @notice Returns implementation version.
    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.2.0";
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
