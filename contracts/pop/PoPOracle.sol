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
import {IPopOracle} from "./IPopOracle.sol";

/// @title Stable Oracle
/// @notice Implements DotNS pricing with PoP-tier validation and base-name reservations
/// @custom:security-contact admin@parity.io
contract PopOracle is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC165Upgradeable,
    IPopOracle
{
    using StringUtils for *;

    /// @notice Wei price for names with 9 characters and up
    /// @dev Mainly for No status pop users
    uint256 public startingPrice;

    /// @notice Tracks PoP status assignments per user and name
    /// @dev Mapping: user => node => PopStatus
    mapping(address => mapping(bytes32 => PopStatus)) public namePopStatus;

    /// @notice Active reservations for base names
    /// @dev Base name is digit-stripped form of label
    mapping(string => Reservation) public reservations;

    /// @notice Maximum time a base name can be reserved
    uint256 public constant MAX_RESERVATION_TIME = 12 weeks;

    /// @notice Namehash of .dot TLD
    bytes32 private constant DOT_NODE =
        0x3fce7d1364a893e213bc4212792b517ffc88f5b13b86c8ef9c8d390c3a1370ce;

    /// @notice Authorized registry controller address
    address public ethRegistryController;

    /// @notice Restricts function to registry controller
    modifier onlyRegistry() {
        require(msg.sender == ethRegistryController, NotRegistry());
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the oracle with pricing parameters
    /// @param _startingPrice Base price in wei for No pop status users
    function __PopOracle_init(uint256 _startingPrice) internal onlyInitializing {
        __Ownable_init(msg.sender);
        __ERC165_init();
        startingPrice = _startingPrice;
    }

    /// @notice Initializes the oracle (public entry point)
    /// @param _startingPrice Base price in wei for No pop status users
    function initialize(uint256 _startingPrice) public initializer {
        __PopOracle_init(_startingPrice);
    }

    /// @inheritdoc IPopOracle
    function setNamePopStatus(string calldata name, PopStatus status) external override {
        bytes32 labelhash = keccak256(bytes(name));
        bytes32 node = keccak256(abi.encodePacked(DOT_NODE, labelhash));

        namePopStatus[msg.sender][node] = status;
        emit NamePopStatusSet(name, status, msg.sender);
    }

    /// @inheritdoc IPopOracle
    function getNamePopStatus(
        string calldata name,
        address who
    )
        public
        view
        override
        returns (PopStatus status)
    {
        bytes32 labelhash = keccak256(bytes(name));
        bytes32 node = keccak256(abi.encodePacked(DOT_NODE, labelhash));
        return namePopStatus[who][node];
    }

    /// @inheritdoc IPopOracle
    function classifyName(string calldata name)
        public
        pure
        override
        returns (PopStatus requirement, string memory message)
    {
        uint256 totalLen = name.strlen();
        uint256 trailingDigits = _countTrailingDigits(name);

        require(trailingDigits <= 2, PopError("Name can have maximum 2 digit suffix"));

        uint256 baseLen = totalLen - trailingDigits;

        // Governance reservation should not be bypassable with suffix digits
        if (baseLen <= 5) {
            return (PopStatus.Reserved, "Reserved for Governance");
        }

        // Lite-eligible: base length 6–8 with exactly 2 trailing digits
        if (baseLen >= 6 && baseLen <= 8) {
            if (trailingDigits == 2) {
                return (PopStatus.PopLite, "Requires Light personhood verification");
            }
            return (PopStatus.PopFull, "Requires Full personhood verification");
        }

        // 9+ base length
        if (trailingDigits == 2) {
            return (PopStatus.NoStatus, "Available to all");
        }

        return (PopStatus.PopFull, "Requires Full personhood verification");
    }

    /// @inheritdoc IPopOracle
    function reserveBaseName(
        string calldata name,
        address userAddress
    )
        external
        override
        onlyRegistry
    {
        // Reservation only for lite-eligible usernames (base 6–8 + exactly 2 trailing digits).
        (PopStatus requiredStatus,) = classifyName(name);
        require(
            requiredStatus == PopStatus.PopLite,
            PopError("Base reservation requires a lite-eligible name")
        );

        string memory strippedBase = _stripDigits(name);

        Reservation memory existingReservation = reservations[strippedBase];
        if (existingReservation.owner == address(0)) {
            uint64 expiryTime = uint64(block.timestamp + MAX_RESERVATION_TIME);
            reservations[strippedBase] = Reservation(userAddress, expiryTime);
            emit BaseNameReserved(strippedBase, userAddress, expiryTime);
        }
    }

    /// @inheritdoc IPopOracle
    function updateEthRegistry(address newRegistry) external override onlyOwner {
        emit RegistryUpdated(ethRegistryController, newRegistry);
        ethRegistryController = newRegistry;
    }

    /// @inheritdoc IPopOracle
    function isBaseName(string calldata baseName) public pure override returns (bool isBase) {
        uint256 digits = _countTrailingDigits(baseName);
        return digits == 0;
    }

    /// @inheritdoc IPopOracle
    function getBaseNameReservation(string calldata baseName)
        external
        view
        override
        returns (address reservationOwner, uint64 expiryTimestamp)
    {
        Reservation memory reserved = reservations[baseName];
        return (reserved.owner, reserved.expires);
    }

    /// @inheritdoc IPopOracle
    function isBaseNameReserved(string calldata baseName)
        external
        view
        override
        returns (bool isReserved, address reservationOwner, uint64 expiryTimestamp)
    {
        Reservation memory reservation = reservations[baseName];
        if (reservation.owner != address(0) && reservation.expires > block.timestamp) {
            return (true, reservation.owner, reservation.expires);
        }
        return (false, reservation.owner, reservation.expires);
    }

    /// @inheritdoc IPopOracle
    function priceWithCheck(
        string calldata name,
        address userAddress
    )
        external
        view
        override
        returns (PriceWithMeta memory metadata)
    {
        _enforceReservationRules(name, userAddress);

        (PopStatus requiredStatus, string memory classification) = classifyName(name);
        PopStatus userStatus = getNamePopStatus(name, userAddress);

        metadata.price = price(name);
        metadata.status = requiredStatus;
        metadata.userStatus = userStatus;
        metadata.message = classification;

        require(requiredStatus != PopStatus.Reserved, PopError(classification));

        if (requiredStatus == PopStatus.PopFull) {
            require(
                userStatus == PopStatus.PopFull, PopError("Requires Full Personhood verification")
            );
        } else if (requiredStatus == PopStatus.PopLite) {
            require(
                userStatus == PopStatus.PopLite || userStatus == PopStatus.PopFull,
                PopError("Requires Personhood Lite verification")
            );
        } else {
            // NoStatus:
            // keep the “lite cannot take base names” rule for 9+ base names with no suffix.
            // (Long names with a 2-digit suffix remain allowed for PopLite.)
            uint256 trailingDigits = _countTrailingDigits(name);
            if (trailingDigits == 0 && userStatus == PopStatus.PopLite) {
                revert PopError("Personhood Lite cannot register base names");
            }
        }

        return metadata;
    }

    /// @inheritdoc IPopOracle
    function price(string calldata name) public view override returns (uint256) {
        uint256 nameLength = name.strlen();
        if (nameLength < 9) {
            return 0;
        }

        uint256 pricePerSecond;

        if (nameLength >= 15) {
            pricePerSecond = startingPrice / 2;
        } else {
            pricePerSecond = startingPrice * (15 - nameLength);
        }

        return pricePerSecond;
    }

    /// @notice Enforces base name reservation rules
    /// @param name Domain label
    /// @param userAddress Registering user
    function _enforceReservationRules(string calldata name, address userAddress) internal view {
        string memory baseName = _stripDigits(name);
        Reservation memory reservation = reservations[baseName];

        if (reservation.owner != address(0) && reservation.expires > block.timestamp) {
            require(
                reservation.owner == userAddress,
                PopError("Base name reserved for original Lite registrant")
            );
        }
    }

    /// @notice Counts trailing digits in a string
    /// @param s String to analyze
    /// @return digitCount Number of trailing digits
    function _countTrailingDigits(string calldata s) internal pure returns (uint256 digitCount) {
        bytes calldata b = bytes(s);
        uint256 stringLength = b.length;

        for (uint256 i = stringLength; i > 0; i--) {
            if (b[i - 1] >= 0x30 && b[i - 1] <= 0x39) {
                digitCount++;
            } else {
                break;
            }
        }
    }

    /// @notice Strips trailing digits from a name
    /// @param name Domain label
    /// @return baseName Name without trailing digits
    function _stripDigits(string calldata name) internal pure returns (string memory baseName) {
        bytes calldata b = bytes(name);
        uint256 endPosition = b.length;

        while (endPosition > 0 && b[endPosition - 1] >= 0x30 && b[endPosition - 1] <= 0x39) {
            endPosition--;
        }

        bytes memory output = new bytes(endPosition);
        for (uint256 i = 0; i < endPosition; i++) {
            output[i] = b[i];
        }

        return string(output);
    }

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceID)
        public
        view
        virtual
        override
        returns (bool supported)
    {
        return interfaceID == type(IPopOracle).interfaceId || super.supportsInterface(interfaceID);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice Returns implementation version
    /// @return versionString Current version string
    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.0.0";
    }
}
