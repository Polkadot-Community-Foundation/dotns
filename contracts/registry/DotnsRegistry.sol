// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IDotnsRegistry} from "./IDotnsRegistry.sol";

/// @title Dot Registry
/// @notice Upgradeable on-chain registry for hierarchical name ownership and resolution.
/// @dev Stores ownership and resolver data for DotNS nodes.
///      Authorisation is enforced strictly via node ownership, except for privileged ownership writes
///      performed by a designated `registrarController`.
/// @custom:security-contact admin@parity.io
contract DotnsRegistry is Initializable, UUPSUpgradeable, OwnableUpgradeable, IDotnsRegistry {
    /// @notice Mapping of node identifiers to records.
    mapping(bytes32 => Record) private records;

    /// @notice Address authorised to perform privileged ownership writes
    /// @dev Typically the DotnsRegistrarController proxy address.
    address public registrarController;

    /// @notice Restricts access to the current owner of `node`.
    /// @param node Node identifier.
    modifier authorised(bytes32 node) {
        require(records[node].owner == msg.sender, NotAuthorised());
        _;
    }

    /// @notice Restricts access to the configured registrar controller.
    modifier onlyRegistrarController() {
        require(msg.sender == registrarController, NotAuthorised());
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the registry.
    /// @dev Sets the deployer as the owner and initializes the root node (bytes32(0)).
    ///      Root node owner is set to the initializer caller.
    function initialize() external initializer {
        __Ownable_init(msg.sender);

        records[bytes32(0)] = Record({owner: msg.sender, resolver: address(0), exists: true});
    }

    /// @inheritdoc IDotnsRegistry
    function updateRegistrarController(address newRegistrarController) external override onlyOwner {
        require(newRegistrarController != address(0), NotAuthorised());
        emit RegistrarControllerUpdated(registrarController, newRegistrarController);
        registrarController = newRegistrarController;
    }

    /// @inheritdoc IDotnsRegistry
    function setSubnodeOwner(
        bytes32 node,
        bytes32 label,
        address newOwner
    )
        external
        override
        authorised(node)
        returns (bytes32 subnode)
    {
        require(newOwner != address(0), NotAuthorised());

        subnode = keccak256(abi.encodePacked(node, label));
        require(!records[subnode].exists, NodeAlreadyExists(subnode));

        records[subnode].owner = newOwner;
        records[subnode].resolver = address(0);
        records[subnode].exists = true;

        emit NewOwner(node, label, newOwner);
    }

    /// @inheritdoc IDotnsRegistry
    function setOwner(
        bytes32 node,
        address newOwner,
        address resolver
    )
        external
        override
        onlyRegistrarController
    {
        require(newOwner != address(0), NotRegistryController());
        require(!records[node].exists, NodeAlreadyOwned(node));

        records[node].owner = newOwner;
        records[node].resolver = resolver;
        records[node].exists = true;

        emit NodeTransferred(node, newOwner);
    }

    /// @inheritdoc IDotnsRegistry
    function setResolver(bytes32 node, address newResolver) external override authorised(node) {
        records[node].resolver = newResolver;
        emit NewResolver(node, newResolver);
    }

    /// @inheritdoc IDotnsRegistry
    function owner(bytes32 node) external view override returns (address) {
        return records[node].owner;
    }

    /// @inheritdoc IDotnsRegistry
    function resolver(bytes32 node) external view override returns (address) {
        return records[node].resolver;
    }

    /// @inheritdoc IDotnsRegistry
    function recordExists(bytes32 node) external view override returns (bool) {
        return records[node].exists;
    }

    /// @notice Returns implementation version
    /// @return versionString Current version string
    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.0.0";
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
