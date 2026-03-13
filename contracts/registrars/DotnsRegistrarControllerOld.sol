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

import {IDotnsRegistrar} from "./IDotnsRegistrar.sol";
import {IDotnsRegistry} from "../registry/IDotnsRegistry.sol";
import {IDotnsReverseResolver} from "../resolvers/IDotnsReverseResolver.sol";
import {IPopRules} from "../pop/IPopRules.sol";
import {StringUtils} from "../utils/StringUtils.sol";
import {IDotnsRegistrarController} from "./IDotnsRegistrarController.sol";
import {IDotnsProtocolRegistry} from "../registry/IDotnsProtocolRegistry.sol";
import {Store} from "../store/Store.sol";
import {IStoreFactory} from "../store/IStoreFactory.sol";
import {StoreUtils} from "../utils/StoreUtils.sol";

/// @title DotnsRegistrarControllerOld
/// @notice Pre-migration snapshot for OZ referenceContract validation.
contract DotnsRegistrarControllerOld is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC165Upgradeable,
    IDotnsRegistrarController
{
    using StringUtils for *;
    using StoreUtils for IStoreFactory;

    bytes32 private constant DOT_NODE =
        0x3fce7d1364a893e213bc4212792b517ffc88f5b13b86c8ef9c8d390c3a1370ce;

    uint256 public constant MAX_ALLOWED_COMMITMENT_AGE = 7 days;

    IDotnsRegistrar public dotnsRegistrar;
    IDotnsRegistry public dotnsRegistry;
    IDotnsReverseResolver public reverseResolver;
    IPopRules public popRules;
    IStoreFactory public storeFactory;
    uint256 public minCommitmentAge;
    uint256 public maxCommitmentAge;
    mapping(bytes32 hash => uint256 timestamp) public commitments;

    /// casting to 'bytes32' is safe because this is safe
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant DOTNS_REGISTERED_KEY = bytes32("dotns.registered");

    mapping(address user => bool isWhiteListed) public whiteList;

    uint256[49] private __gap;

    modifier onlyRegistry() {
        _;
    }

    modifier onlyWhiteListedOrOwner() {
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        IDotnsRegistrar registrar,
        IDotnsRegistry registry,
        IDotnsReverseResolver reverse,
        IPopRules rules,
        IStoreFactory factory,
        uint256 minAge,
        uint256 maxAge
    )
        external
        initializer
    {
        __Ownable_init(msg.sender);
        __ERC165_init();
        require(maxAge > minAge, MaxCommitmentAgeTooLow());
        require(maxAge <= MAX_ALLOWED_COMMITMENT_AGE, MaxCommitmentAgeTooHigh());
        dotnsRegistrar = registrar;
        dotnsRegistry = registry;
        reverseResolver = reverse;
        popRules = rules;
        storeFactory = factory;
        minCommitmentAge = minAge;
        maxCommitmentAge = maxAge;
    }

    function available(string calldata) public pure override returns (bool) {
        return false;
    }

    function makeCommitment(Registration calldata) public pure override returns (bytes32) {
        return bytes32(0);
    }

    function commit(bytes32) external override {}

    function register(Registration calldata) external payable override {}

    function isWhiteListed(address who) external view override returns (bool) {
        return whiteList[who];
    }

    function whiteListAddress(address, bool) external override onlyOwner {}

    function registerReserved(Registration calldata) external override {}

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IDotnsRegistrarController).interfaceId
            || super.supportsInterface(interfaceId);
    }

    function updateProtocolRegistry(IDotnsProtocolRegistry) external override onlyOwner {}

    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.2.0";
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
