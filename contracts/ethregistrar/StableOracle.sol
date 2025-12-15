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
import {IStableOracle} from "./IStableOracle.sol";
import {IPriceOracle} from "./IPriceOracle.sol";
import {StringUtils} from "../utils/StringUtils.sol";

/// @title Oralce Containing Custom Pricing and POP logic
/// @notice Returns latest USD price with 8 decimals
interface AggregatorInterface {
    /// @notice Retrieves latest price answer
    /// @return price Latest price with 8 decimal places
    function latestAnswer() external view returns (int256 price);
}

/// @title Stable Oracle
/// @notice Implements DotNS pricing with PoP-tier validation and base-name reservations
/// @dev Upgradeable via UUPS - manages classification and pricing for .dot domains
/// @custom:security-contact admin@parity.io
contract StableOracle is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC165Upgradeable,
    IStableOracle
{
    using StringUtils for *;

    /// @notice USD rental price for single-character names in attoUSD
    uint256 public price1Letter;

    /// @notice USD rental price for two-character names in attoUSD
    uint256 public price2Letter;

    /// @notice USD rental price for three-character names in attoUSD
    uint256 public price3Letter;

    /// @notice USD rental price for four-character names in attoUSD
    uint256 public price4Letter;

    /// @notice USD rental price for names of five+ characters in attoUSD
    uint256 public price5Letter;

    /// @notice Static price oracle for PAS/USD exchange rate
    AggregatorInterface public usdOracle;

    /// @notice Tracks PoP status assignments per user and name
    /// @dev Mapping: user => node => PopStatus
    mapping(address => mapping(bytes32 => PopStatus)) public namePopStatus;

    /// @notice Active reservations for base names
    /// @dev Base name is digit-stripped form of label
    mapping(string => Reservation) public reservations;

    /// @notice This represents the currently set
    ///.        Time that a given base name is reserved for
    uint256 public constant MAX_RESERVATION_TIME = 12 weeks;

    /// @notice Namehash of .dot TLD
    bytes32 private constant DOT_NODE =
        0x3fce7d1364a893e213bc4212792b517ffc88f5b13b86c8ef9c8d390c3a1370ce;

    /// @notice Authorized registry controller address
    address public ethRegistryController;

    /// @notice UUPS interface version for OpenZeppelin upgrade detection
    /// @dev This constant allows upgrade tooling to detect the UUPS interface version
    string public constant UPGRADE_INTERFACE_VERSION = "5.0.0";

    /// @notice Restricts function to registry controller
    modifier onlyRegistry() {
        if (msg.sender != ethRegistryController) {
            revert NotRegistry();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the oracle with pricing parameters
    /// @param oracleAddress Price feed with static prices
    /// @param rentPrices Array of base prices [1char, 2char, 3char, 4char, 5+char]
    function __StableOracle_init(
        address oracleAddress,
        uint256[] memory rentPrices
    )
        internal
        onlyInitializing
    {
        __UUPSUpgradeable_init();
        __Ownable_init();
        __ERC165_init();
        usdOracle = AggregatorInterface(oracleAddress);
        price1Letter = rentPrices[0];
        price2Letter = rentPrices[1];
        price3Letter = rentPrices[2];
        price4Letter = rentPrices[3];
        price5Letter = rentPrices[4];
    }

    /// @notice Initializes the oracle (public entry point)
    /// @param oracleAddress Price feed with static prices
    /// @param rentPrices Array of base prices [1char, 2char, 3char, 4char, 5+char]
    function initialize(address oracleAddress, uint256[] memory rentPrices) public initializer {
        __StableOracle_init(oracleAddress, rentPrices);
    }

    /// @inheritdoc IStableOracle
    function setNamePopStatus(string calldata name, PopStatus status) external override {
        bytes32 labelhash = keccak256(bytes(name));
        bytes32 node = keccak256(abi.encodePacked(DOT_NODE, labelhash));

        namePopStatus[msg.sender][node] = status;
        emit NamePopStatusSet(name, status, msg.sender);
    }

    /// @inheritdoc IStableOracle
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

    /// @inheritdoc IStableOracle
    function classifyName(string calldata name)
        public
        pure
        override
        returns (PopStatus requirement, string memory message)
    {
        uint256 nameLength = name.strlen();
        uint256 digitSuffix = _countTrailingDigits(name);

        require(digitSuffix <= 2, PopError("Name can have maximum 2 digit suffix"));

        if (nameLength <= 5) {
            return (PopStatus.Reserved, "Reserved for Governance");
        }

        if (nameLength >= 6 && nameLength <= 8) {
            if (digitSuffix > 0) {
                return (PopStatus.PopLite, "Requires Light personhood verification");
            }
            return (PopStatus.PopFull, "Requires Full personhood verification");
        }

        if (digitSuffix == 2) {
            return (PopStatus.NoStatus, "Available to all");
        }

        return (PopStatus.PopFull, "Requires Full personhood verification");
    }

    /// @inheritdoc IStableOracle
    function reserveBaseName(
        string calldata name,
        address userAddress
    )
        external
        override
        onlyRegistry
    {
        string memory strippedBase = _stripDigits(name);
        PopStatus userStatus = getNamePopStatus(name, userAddress);
        require(userStatus == PopStatus.PopLite, PopError("Only Personhood lite can reserve names"));
        Reservation memory existingReservation = reservations[strippedBase];
        if (existingReservation.owner == address(0)) {
            uint64 expiryTime = uint64(block.timestamp + MAX_RESERVATION_TIME);
            reservations[strippedBase] = Reservation(userAddress, expiryTime);
            emit BaseNameReserved(strippedBase, userAddress, expiryTime);
        }
    }

    /// @inheritdoc IStableOracle
    function updateEthRegistry(address newRegistry) external override onlyOwner {
        emit RegistryUpdated(ethRegistryController, newRegistry);
        ethRegistryController = newRegistry;
    }

    /// @inheritdoc IStableOracle
    function isBaseName(string calldata baseName) public view override returns (bool isBase) {
        uint256 digits = _countTrailingDigits(baseName);
        return digits == 0;
    }

    /// @inheritdoc IStableOracle
    function getBaseNameReservation(string calldata baseName)
        external
        view
        override
        returns (address reservationOwner, uint64 expiryTimestamp)
    {
        Reservation memory reserved = reservations[baseName];
        return (reserved.owner, reserved.expires);
    }

    /// @inheritdoc IStableOracle
    function isBaseNameReserved(string calldata baseName)
        external
        view
        override
        returns (bool isReserved, address reservationOwner, uint64 expiryTimestamp)
    {
        Reservation memory r = reservations[baseName];
        if (r.owner != address(0) && r.expires > block.timestamp) {
            return (true, r.owner, r.expires);
        }
        return (false, r.owner, r.expires);
    }

    /// @inheritdoc IStableOracle
    function priceWithCheck(
        string calldata name,
        uint256 expires,
        uint256 duration,
        address userAddress
    )
        external
        view
        override
        returns (PriceWithMeta memory metadata)
    {
        // We call this to ensure we dont allow
        // Querying of any names that have been
        // Reserved so we fail fast
        _enforceReservationRules(name, userAddress);

        metadata.price = price(name, expires, duration);
        (PopStatus requiredStatus, string memory classification) = classifyName(name);
        PopStatus userStatus = getNamePopStatus(name, userAddress);
        metadata.status = requiredStatus;
        metadata.message = classification;
        metadata.userStatus = userStatus;
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
        }
        return metadata;
    }

    /// @notice Enforces base name reservation rules
    /// @param name Domain label
    /// @param userAddress Registering user
    function _enforceReservationRules(string calldata name, address userAddress) internal view {
        string memory baseName = _stripDigits(name);
        Reservation memory r = reservations[baseName];

        if (r.owner != address(0) && r.expires > block.timestamp) {
            if (r.owner != userAddress) {
                revert PopError("Base name reserved for original Lite registrant");
            }
        }
    }

    /// @inheritdoc IPriceOracle
    function price(
        string calldata name,
        uint256 expires,
        uint256 duration
    )
        public
        view
        virtual
        returns (IPriceOracle.Price memory pricing)
    {
        uint256 nameLength = name.strlen();
        uint256 basePrice;

        if (nameLength >= 5) basePrice = price5Letter * duration;
        else if (nameLength == 4) basePrice = price4Letter * duration;
        else if (nameLength == 3) basePrice = price3Letter * duration;
        else if (nameLength == 2) basePrice = price2Letter * duration;
        else basePrice = price1Letter * duration;

        return IPriceOracle.Price({
            base: attoUSDToWei(basePrice), premium: attoUSDToWei(_premium(name, expires, duration))
        });
    }

    /// @inheritdoc IPriceOracle
    function premium(
        string calldata name,
        uint256 expires,
        uint256 duration
    )
        public
        view
        returns (uint256 premiumWei)
    {
        return attoUSDToWei(_premium(name, expires, duration));
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

    /// @notice Converts attoUSD to wei using oracle price
    /// @param amount Amount in attoUSD
    /// @return weiAmount Amount in wei
    function attoUSDToWei(uint256 amount) internal view returns (uint256 weiAmount) {
        uint256 pasPrice = uint256(usdOracle.latestAnswer());
        return (amount * 1e8) / pasPrice;
    }

    /// @notice Converts wei to attoUSD using oracle price
    /// @param amount Amount in wei
    /// @return attoUSDAmount Amount in attoUSD
    function weiToAttoUSD(uint256 amount) internal view returns (uint256 attoUSDAmount) {
        uint256 pasPrice = uint256(usdOracle.latestAnswer());
        return (amount * pasPrice) / 1e8;
    }

    /// @notice Calculates premium for expired domains
    /// @return premiumAmount Premium in attoUSD
    /// @dev Override in derived contracts for custom premium logic
    function _premium(
        string memory,
        /*name*/
        uint256,
        /*expires*/
        uint256 /*duration*/
    )
        internal
        view
        virtual
        returns (uint256 premiumAmount)
    {
        return 0;
    }

    /// @notice Checks interface support
    /// @param interfaceID Interface identifier
    /// @return supported True if interface is supported
    function supportsInterface(bytes4 interfaceID)
        public
        view
        virtual
        override
        returns (bool supported)
    {
        return interfaceID == type(IStableOracle).interfaceId
            || interfaceID == type(IPriceOracle).interfaceId || super.supportsInterface(interfaceID);
    }

    /// @notice Authorizes upgrade to new implementation
    /// @param newImplementation Address of new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice Returns implementation version
    /// @return versionString Current version string
    function version() external pure virtual returns (string memory versionString) {
        return "1.0.0";
    }
}
