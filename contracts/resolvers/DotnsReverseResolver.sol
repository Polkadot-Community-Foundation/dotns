// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    ERC165Upgradeable
} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {IDotnsReverseResolver} from "./IDotnsReverseResolver.sol";
import {IDotnsProtocolRegistry} from "../registry/IDotnsProtocolRegistry.sol";
import {DotnsConstants} from "../utils/DotnsConstants.sol";

/// @title Dotns Reverse Resolver
/// @notice Resolves an address to its associated .dot name.
/// @dev Writes are gated on a fixed writer address resolved from the protocol
///      registry (the registrar or its controller), not on node ownership.
///      Reverse records bind to an EOA rather than a registry node, so authority
///      is delegated to the contract that mints names on the user's behalf.
/// @custom:security-contact admin@parity.io
contract DotnsReverseResolver is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC165Upgradeable,
    IDotnsReverseResolver
{
    /// @dev Mapping from address to its reverse name. An empty string indicates
    ///      that no reverse name is set.
    mapping(address owner => string name) private reverseNames;

    /// @notice Protocol-level address registry for all DotNS contracts.
    IDotnsProtocolRegistry public protocolRegistry;

    /// @dev Reserved storage space to allow for layout changes in the future.
    // forge-lint: disable-next-line(mixed-case-variable)
    uint256[50] private __gap;

    /// @notice Restricts access to the configured registrar.
    modifier onlyRegistrar() {
        _onlyRegistrar();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialises the reverse resolver.
    /// @dev May only be called once per proxy.
    /// @param registry Protocol-level address registry used to resolve sibling contracts.
    /// @custom:emits OwnershipTransferred
    /// @custom:emits Initialized
    /// @custom:reverts InvalidInitialization
    function initialize(IDotnsProtocolRegistry registry) external initializer {
        __Ownable_init(msg.sender);
        __ERC165_init();
        protocolRegistry = registry;
    }

    /// @inheritdoc IDotnsReverseResolver
    function setReverseName(address addr, string calldata name) external override onlyRegistrar {
        reverseNames[addr] = name;
        emit ReverseNameSet(addr, name);
    }

    /// @inheritdoc IDotnsReverseResolver
    function nameOf(address addr) external view override returns (string memory name) {
        return reverseNames[addr];
    }

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC165Upgradeable)
        returns (bool supported)
    {
        return interfaceId == type(IDotnsReverseResolver).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /// @notice Internal check enforcing registrar-only access.
    function _onlyRegistrar() internal view {
        address controller = protocolRegistry.get(DotnsConstants.CONTROLLER);
        address registrar = protocolRegistry.get(DotnsConstants.REGISTRAR);
        require(
            msg.sender == controller || msg.sender == registrar, NotRegistrarController(msg.sender)
        );
    }

    /// @notice Returns implementation version.
    /// @return versionString Current version string.
    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.0.0";
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
