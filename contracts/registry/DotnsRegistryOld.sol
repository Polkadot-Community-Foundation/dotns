// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IDotnsRegistry} from "./IDotnsRegistry.sol";
import {IDotnsRegistrarController} from "../registrars/IDotnsRegistrarController.sol";
import {IDotnsRegistrar} from "../registrars/IDotnsRegistrar.sol";
import {IDotnsReverseResolver} from "../resolvers/IDotnsReverseResolver.sol";
import {IStoreFactory} from "../store/IStoreFactory.sol";
import {Store} from "../store/Store.sol";
import {StoreUtils} from "../utils/StoreUtils.sol";
import {IDotnsProtocolRegistry} from "./IDotnsProtocolRegistry.sol";

/// @title DotnsRegistryOld
/// @notice Pre-migration snapshot for OZ referenceContract validation.
contract DotnsRegistryOld is Initializable, UUPSUpgradeable, OwnableUpgradeable, IDotnsRegistry {
    using StoreUtils for IStoreFactory;

    mapping(bytes32 node => Record record) private records;
    IDotnsRegistrarController public registrarController;
    IDotnsRegistrar public dotnsRegistrar;
    IDotnsReverseResolver public reverseResolver;
    IStoreFactory public storeFactory;

    /// casting to 'bytes32' is safe because this is safe
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant DOTNS_REGISTERED_KEY = bytes32("dotns.registered");

    uint256[50] private __gap;

    modifier authorised(bytes32) {
        _;
    }

    modifier onlyRegistrarController() {
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        IDotnsRegistrar _registrar,
        IDotnsReverseResolver _reverseResolver,
        IStoreFactory _factory
    )
        external
        initializer
    {
        __Ownable_init(msg.sender);
        dotnsRegistrar = _registrar;
        reverseResolver = _reverseResolver;
        storeFactory = _factory;
        records[bytes32(0)] = Record({owner: msg.sender, resolver: address(0), exists: true});
    }

    function updateRegistrarController(IDotnsRegistrarController newRegistrarController)
        external
        override
        onlyOwner
    {
        registrarController = newRegistrarController;
    }

    function setSubnodeOwner(SubnodeRecord calldata) external override returns (bytes32) {
        return bytes32(0);
    }

    function setOwner(bytes32, address, address) external override {}

    function setResolver(bytes32, address) external override {}

    function owner(bytes32) external pure override returns (address) {
        return address(0);
    }

    function resolver(bytes32) external pure override returns (address) {
        return address(0);
    }

    function recordExists(bytes32) external pure override returns (bool) {
        return false;
    }

    function updateProtocolRegistry(IDotnsProtocolRegistry) external override onlyOwner {}

    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.1.0";
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
