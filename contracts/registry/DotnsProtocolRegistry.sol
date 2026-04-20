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
/// @custom:security-contact admin@parity.io
contract DotnsProtocolRegistry is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    IDotnsProtocolRegistry
{
    /// @notice Well-known key for the ERC721 registrar backing name ownership.
    /// casting to 'bytes32' is safe because the string fits in 32 bytes.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant REGISTRAR = bytes32("registrar");

    /// @notice Well-known key for the registrar controller orchestrating commit-reveal registration.
    /// casting to 'bytes32' is safe because the string fits in 32 bytes.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant CONTROLLER = bytes32("controller");

    /// @notice Well-known key for the forward registry storing node ownership and resolver.
    /// casting to 'bytes32' is safe because the string fits in 32 bytes.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant REGISTRY = bytes32("registry");

    /// @notice Well-known key for the reverse resolver for address-to-name mapping.
    /// casting to 'bytes32' is safe because the string fits in 32 bytes.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant REVERSE_RESOLVER = bytes32("reverseResolver");

    /// @notice Well-known key for the PoP oracle enforcing eligibility and pricing.
    /// casting to 'bytes32' is safe because the string fits in 32 bytes.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant POP_RULES = bytes32("popRules");

    /// @notice Well-known key for the factory deploying per-user Store instances.
    /// casting to 'bytes32' is safe because the string fits in 32 bytes.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant STORE_FACTORY = bytes32("storeFactory");

    /// @notice Well-known key for the forward resolver storing address records.
    /// casting to 'bytes32' is safe because the string fits in 32 bytes.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant RESOLVER = bytes32("resolver");

    /// @notice Well-known key for the content resolver storing content hashes and text records.
    /// casting to 'bytes32' is safe because the string fits in 32 bytes.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant CONTENT_RESOLVER = bytes32("contentResolver");

    /// @notice Well-known key for the privileged PoP gateway address allowed to drive
    ///         lite/full-person username flows via `DotnsPopController`.
    /// @dev This is the external account or pallet adapter configured by governance; the
    ///      `DotnsPopController` reads it from this registry to gate its privileged entry
    ///      points, so rotating the gateway is a single `set` call with no upgrade needed.
    /// casting to 'bytes32' is safe because the string fits in 32 bytes.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant POP_GATEWAY = bytes32("popGateway");

    /// @notice Well-known key for the dedicated PoP controller orchestrating lite/full-person
    ///         username issuance on behalf of the PoP gateway.
    /// @dev Kept distinct from `CONTROLLER` (the commit-reveal public controller) so the
    ///      two controllers can coexist per `DotnsRegistrar`'s multi-controller affordance.
    ///      `DotnsRegistrarController` also consults `POP_CONTROLLER` from this registry to
    ///      reject public registrations of labels currently reserved for a PoP claim.
    /// casting to 'bytes32' is safe because the string fits in 32 bytes.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant POP_CONTROLLER = bytes32("popController");

    /// @notice Well-known key for the PoP resolver holding per-name records produced
    ///         by the PoP username flow (chat keys, lite => full links).
    /// @dev Separating PoP-flow records into a dedicated resolver preserves the
    ///      `Store = labels only` invariant (Store holds registration records,
    ///      nothing else) and matches the project's resolver-per-record-category
    ///      convention used by the content and reverse resolvers.
    /// casting to 'bytes32' is safe because the string fits in 32 bytes.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant POP_RESOLVER = bytes32("popResolver");

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
        versionString = "1.1.0";
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
