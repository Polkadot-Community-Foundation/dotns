// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IStableOracle} from "./IStableOracle.sol";
import {IPriceOracle} from "./IPriceOracle.sol";
import {StringUtils} from "../utils/StringUtils.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface AggregatorInterface {
    function latestAnswer() external view returns (int256);
}

/// @title StableOracle
/// @notice Implements DotNS classification, PoP-tier validation, base-name reservation rules, and price computation
/// @dev Follows the interface and classification constraints defined in IStableOracle
contract StableOracle is IStableOracle, Ownable {
    using StringUtils for *;

    /// @notice USD rental price for single-character names denominated in attoUSD
    uint256 public immutable price1Letter;

    /// @notice USD rental price for two-character names denominated in attoUSD
    uint256 public immutable price2Letter;

    /// @notice USD rental price for three-character names denominated in attoUSD
    uint256 public immutable price3Letter;

    /// @notice USD rental price for four-character names denominated in attoUSD
    uint256 public immutable price4Letter;

    /// @notice USD rental price for names of length five or more denominated in attoUSD
    uint256 public immutable price5Letter;

    /// @notice Oracle returning PAS/USD exchange rate with 8 decimals
    AggregatorInterface public immutable usdOracle;

    /// @notice Used to keep track of owners of Pop statuses against the hashes to their
    ///         assigned Proof-of-Personhood tier
    /// @dev Hash is keccak256(name)
    mapping(address => mapping(bytes32 => PopStatus)) public namePopStatus;

    /// @notice Mapping of base names to their active reservation details
    /// @dev Base name is the digit-stripped form of a label
    mapping(string => Reservation) public reservations;

    /// @notice Default node hash for .dot TLD
    bytes32 private constant DOT_NODE =
        0x3fce7d1364a893e213bc4212792b517ffc88f5b13b86c8ef9c8d390c3a1370ce;

    address public ethRegistryController;

    /// @notice Used to gate only registry functions
    /// @dev Assumes developer has not passed a zero based address
    ///      for ethRegistryController
    modifier onlyRegistry() {
        if (msg.sender != ethRegistryController) {
            revert NotRegistry();
        }
        _;
    }

    constructor(AggregatorInterface _usdOracle, uint256[] memory _rentPrices) {
        usdOracle = _usdOracle;
        price1Letter = _rentPrices[0];
        price2Letter = _rentPrices[1];
        price3Letter = _rentPrices[2];
        price4Letter = _rentPrices[3];
        price5Letter = _rentPrices[4];
    }

    /// @inheritdoc IStableOracle
    function setNamePopStatus(string calldata name, PopStatus status) external {
        bytes32 labelhash = keccak256(bytes(name));
        bytes32 node = keccak256(abi.encodePacked(DOT_NODE, labelhash));

        namePopStatus[msg.sender][node] = status;
        emit NamePopStatusSet(name, status, msg.sender);
    }

    /// @inheritdoc IStableOracle
    function getNamePopStatus(string calldata name) external view returns (PopStatus) {
        bytes32 labelhash = keccak256(bytes(name));
        bytes32 node = keccak256(abi.encodePacked(DOT_NODE, labelhash));
        return namePopStatus[msg.sender][node];
    }

    /// @inheritdoc IStableOracle
    function classifyName(string calldata name)
        public
        pure
        returns (PopStatus requirement, string memory message)
    {
        uint256 len = name.strlen();
        uint256 suffix = _countTrailingDigits(name);

        if (suffix > 2) {
            revert PopError("Name can have maximum 2 digit suffix");
        }

        if (len <= 5) {
            return (PopStatus.Reserved, "Reserved for Governance");
        }

        if (len >= 6 && len <= 8) {
            if (suffix > 0) {
                return (PopStatus.PopLite, "Requires Light personhood verification");
            }
            return (PopStatus.PopFull, "Requires Full personhood verification");
        }

        if (suffix == 2) {
            return (PopStatus.NoStatus, "Available to all");
        }

        return (PopStatus.PopFull, "Requires Full personhood verification");
    }

    /// @inheritdoc IStableOracle
    function reserveBaseName(string calldata baseName, address user) external onlyRegistry {
        string memory stripped = _stripDigits(baseName);

        Reservation memory reservation = reservations[stripped];
        if (reservation.owner == address(0)) {
            uint64 expiry = uint64(block.timestamp + 12 weeks);
            reservations[stripped] = Reservation(user, expiry);
            emit BaseNameReserved(stripped, user, expiry);
        }
    }

    /// @inheritdoc IStableOracle
    function updateEthRegistry(address ethReg) external onlyOwner {
        emit RegistryUpdated(ethRegistryController, ethReg);
        ethRegistryController = ethReg;
    }

    /// @inheritdoc IStableOracle
    function getBaseNameReservation(string calldata baseName)
        external
        view
        returns (address owner, uint64 expires)
    {
        Reservation memory r = reservations[baseName];
        return (r.owner, r.expires);
    }

    /// @inheritdoc IStableOracle
    function isBaseNameReserved(string calldata baseName)
        external
        view
        returns (bool reservedStatus, address owner, uint64 expires)
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
        address user
    )
        external
        view
        returns (PriceWithMeta memory meta)
    {
        _enforceReservationRules(name, user);

        meta.price = price(name, expires, duration);
        (PopStatus requiredStatus, string memory msg_) = classifyName(name);
        meta.status = requiredStatus;
        meta.message = msg_;

        if (requiredStatus == PopStatus.Reserved) {
            revert PopError(msg_);
        }

        bytes32 labelhash = keccak256(bytes(name));
        bytes32 node = keccak256(abi.encodePacked(DOT_NODE, labelhash));
        PopStatus claimed = namePopStatus[user][node];

        if (requiredStatus == PopStatus.PopFull && claimed != PopStatus.PopFull) {
            revert PopError("Requires Full Personhood verification");
        }

        if (requiredStatus == PopStatus.PopLite) {
            if (claimed != PopStatus.PopLite && claimed != PopStatus.PopFull) {
                revert PopError("Requires Personhood Lite verification");
            }
        }
        return meta;
    }

    function _enforceReservationRules(string calldata name, address user) internal view {
        string memory base = _stripDigits(name);
        Reservation memory r = reservations[base];

        if (r.owner != address(0) && r.expires > block.timestamp) {
            if (r.owner != user) {
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
        returns (IPriceOracle.Price memory)
    {
        uint256 len = name.strlen();
        uint256 basePrice;

        if (len >= 5) basePrice = price5Letter * duration;
        else if (len == 4) basePrice = price4Letter * duration;
        else if (len == 3) basePrice = price3Letter * duration;
        else if (len == 2) basePrice = price2Letter * duration;
        else basePrice = price1Letter * duration;

        return IPriceOracle.Price({
            base: attoUSDToWei(basePrice),
            premium: attoUSDToWei(_premium(name, expires, duration))
        });
    }

    function premium(
        string calldata name,
        uint256 expires,
        uint256 duration
    )
        public
        view
        returns (uint256)
    {
        return attoUSDToWei(_premium(name, expires, duration));
    }

    function _countTrailingDigits(string calldata s) internal pure returns (uint256 count) {
        bytes calldata b = bytes(s);
        uint256 len = b.length;
        for (uint256 i = len; i > 0; i--) {
            if (b[i - 1] >= 0x30 && b[i - 1] <= 0x39) count++;
            else break;
        }
    }

    function _stripDigits(string calldata name) internal pure returns (string memory baseName) {
        bytes calldata b = bytes(name);
        uint256 end = b.length;

        while (end > 0 && b[end - 1] >= 0x30 && b[end - 1] <= 0x39) {
            end--;
        }

        bytes memory out = new bytes(end);
        for (uint256 i = 0; i < end; i++) {
            out[i] = b[i];
        }
        return string(out);
    }

    function attoUSDToWei(uint256 amount) internal view returns (uint256) {
        uint256 pasPrice = uint256(usdOracle.latestAnswer());
        return (amount * 1e8) / pasPrice;
    }

    function weiToAttoUSD(uint256 amount) internal view returns (uint256) {
        uint256 pasPrice = uint256(usdOracle.latestAnswer());
        return (amount * pasPrice) / 1e8;
    }

    function _premium(string memory, uint256, uint256) internal view virtual returns (uint256) {
        return 0;
    }

    function supportsInterface(bytes4 interfaceID) public view virtual returns (bool) {
        return interfaceID == type(IStableOracle).interfaceId
            || interfaceID == type(IPriceOracle).interfaceId || interfaceID == type(IERC165).interfaceId;
    }
}
