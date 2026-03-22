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
import {StringUtils} from "../utils/StringUtils.sol";
import {IPopRules} from "./IPopRules.sol";
import {IDotnsProtocolRegistry} from "../registry/IDotnsProtocolRegistry.sol";

/// @title PopRulesOld
/// @notice Pre-migration snapshot for OZ referenceContract validation.
contract PopRulesOld is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC165Upgradeable,
    IPopRules
{
    using StringUtils for *;

    uint256 public startingPrice;
    mapping(address => PopStatus) public userPopStatus;
    mapping(string baseName => Reservation reservation) public reservations;
    uint256 public constant MAX_RESERVATION_TIME = 12 weeks;

    bytes32 private constant DOT_NODE =
        0x3fce7d1364a893e213bc4212792b517ffc88f5b13b86c8ef9c8d390c3a1370ce;

    address public dotRegistryController;

    // forge-lint: disable-next-line(mixed-case-variable)
    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(uint256 _startingPrice) public initializer {
        __Ownable_init(msg.sender);
        __ERC165_init();
        startingPrice = _startingPrice;
    }

    function setUserPopStatus(PopStatus) external override {}

    function classifyName(string calldata) public pure override returns (PopStatus, string memory) {
        return (PopStatus.NoStatus, "");
    }

    function reserveBaseName(string calldata, address) external override {}

    function updateDotRegistry(address newRegistry) external onlyOwner {
        dotRegistryController = newRegistry;
    }

    function isBaseName(string calldata) public pure override returns (bool) {
        return false;
    }

    function getBaseNameReservation(string calldata)
        external
        pure
        override
        returns (address, uint64)
    {
        return (address(0), 0);
    }

    function isBaseNameReserved(string calldata)
        external
        pure
        override
        returns (bool, address, uint64)
    {
        return (false, address(0), 0);
    }

    function priceWithCheck(
        string calldata,
        address
    )
        external
        pure
        override
        returns (PriceWithMeta memory)
    {
        return PriceWithMeta(0, PopStatus.NoStatus, PopStatus.NoStatus, "");
    }

    function priceWithoutCheck(
        string calldata,
        address
    )
        external
        pure
        override
        returns (PriceWithMeta memory)
    {
        return PriceWithMeta(0, PopStatus.NoStatus, PopStatus.NoStatus, "");
    }

    function price(string calldata) public pure override returns (uint256) {
        return 0;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override
        returns (bool supported)
    {
        return interfaceId == type(IPopRules).interfaceId || super.supportsInterface(interfaceId);
    }

    function updateProtocolRegistry(IDotnsProtocolRegistry) external override onlyOwner {}

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.0.0";
    }
}
