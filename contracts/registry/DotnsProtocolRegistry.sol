// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IDotnsProtocolRegistry} from "./IDotnsProtocolRegistry.sol";

/// @title Dotns Protocol Registry
/// @notice Upgradeable address registry for all DotNS protocol contracts.
/// @dev Consolidates protocol contract addresses behind a single `bytes32 => address` mapping.
///      Individual contracts query this registry instead of storing sibling references,
///      reducing storage fragmentation and simplifying upgrades.
/// @dev Refcount-backed reverse lookup (`isRegisteredAddress`) supports O(1) "is this address
///      currently trusted by the protocol?" checks. Correct under key reassignment: an address
///      referenced by multiple keys stays registered until the last reference is overwritten.
/// @custom:security-contact admin@parity.io
contract DotnsProtocolRegistry is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    IDotnsProtocolRegistry
{
    /// @dev Internal mapping from well-known key to contract address.
    mapping(bytes32 key => address addr) private _addresses;

    /// @dev Per-address refcount: number of well-known keys currently pointing at `addr`.
    ///      Non-zero iff `addr` is reachable from at least one key. Maintained in `set`.
    mapping(address addr => uint256 refcount) private _registeredRefcount;

    /// @dev Reserved storage space to allow for layout changes in the future.
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
    function get(bytes32 key) external view override returns (address addr) {
        return _addresses[key];
    }

    /// @inheritdoc IDotnsProtocolRegistry
    /// @dev Maintains `_registeredRefcount` invariant:
    ///      sum(_registeredRefcount[a]) over all non-zero a == count of keys whose value is non-zero.
    ///      No-op when the existing mapping already points at `addr` so repeat
    ///      calls don't inflate the refcount.
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
    function isRegisteredAddress(address addr) external view override returns (bool registered) {
        return addr != address(0) && _registeredRefcount[addr] > 0;
    }

    /// @notice Returns implementation version.
    /// @return versionString Current version string.
    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.2.0";
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
