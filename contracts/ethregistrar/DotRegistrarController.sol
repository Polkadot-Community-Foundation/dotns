//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {BaseRegistrarImplementation} from "./BaseRegistrarImplementation.sol";
import {StringUtils} from "../utils/StringUtils.sol";
import {Resolver} from "../resolvers/Resolver.sol";
import {ENS} from "../registry/ENS.sol";
import {IReverseRegistrar} from "../reverseRegistrar/IReverseRegistrar.sol";
import {IDefaultReverseRegistrar} from "../reverseRegistrar/IDefaultReverseRegistrar.sol";
import {IDotRegistrarController} from "./IDotRegistrarController.sol";
import {ERC20Recoverable} from "../utils/ERC20Recoverable.sol";
import {IStableOracle} from "./IStableOracle.sol";

/// @dev A registrar controller for registering and renewing names at fixed cost.
contract DotRegistrarController is Ownable, IDotRegistrarController, ERC165, ERC20Recoverable {
    using StringUtils for *;
    /// @notice The bitmask for the Dotns reverse record.

    uint8 constant REVERSE_RECORD_DOT_BIT = 1;

    /// @notice The bitmask for the default reverse record.
    uint8 constant REVERSE_RECORD_DEFAULT_BIT = 2;

    /// @notice The minimum duration for a registration.
    uint256 public constant MIN_REGISTRATION_DURATION = 5 minutes;

    // @notice The node (i.e. namehash) for the dot TLD.
    bytes32 private constant DOT_NODE =
        0x3fce7d1364a893e213bc4212792b517ffc88f5b13b86c8ef9c8d390c3a1370ce;

    /// @notice The maximum expiry time for a registration.
    uint64 private constant MAX_EXPIRY = type(uint64).max;

    /// @notice The ENS registry.
    ENS public immutable registry;

    // @notice The base registrar implementation for the dot TLD.
    BaseRegistrarImplementation immutable baseRegistrar;

    /// @notice The minimum time a commitment must exist to be valid.
    uint256 public immutable minCommitmentAge;

    /// @notice The maximum time a commitment can exist to be valid.
    uint256 public immutable maxCommitmentAge;

    /// @notice The registrar for addr.reverse. (i.e. reverse for coinType 60)
    IReverseRegistrar public immutable reverseRegistrar;

    /// @notice The registrar for default.reverse. (i.e. fallback reverse for all EVM chains)
    IDefaultReverseRegistrar public immutable defaultReverseRegistrar;

    /// @notice The orcale containing POP logic.
    IStableOracle public immutable oracle;

    /// @notice A mapping of commitments to their timestamp.
    mapping(bytes32 => uint256) public commitments;

    /// @notice Constructor for the DotRegistrarController.
    ///
    /// @param _base The base registrar implementation for the dot TLD.
    /// @param _oracle The orcale containing POP logic.
    /// @param _minCommitmentAge The minimum time a commitment must exist to be valid.
    /// @param _maxCommitmentAge The maximum time a commitment can exist to be valid.
    /// @param _reverseRegistrar The registrar for addr.reverse.
    /// @param _defaultReverseRegistrar The registrar for default.reverse.
    /// @param _ens The ENS registry.
    constructor(
        BaseRegistrarImplementation _base,
        IStableOracle _oracle,
        uint256 _minCommitmentAge,
        uint256 _maxCommitmentAge,
        IReverseRegistrar _reverseRegistrar,
        IDefaultReverseRegistrar _defaultReverseRegistrar,
        ENS _ens
    ) {
        require(_maxCommitmentAge > _minCommitmentAge, MaxCommitmentAgeTooLow());
        require(_maxCommitmentAge <= block.timestamp, MaxCommitmentAgeTooHigh());

        registry = _ens;
        baseRegistrar = _base;
        oracle = _oracle;
        minCommitmentAge = _minCommitmentAge;
        maxCommitmentAge = _maxCommitmentAge;
        reverseRegistrar = _reverseRegistrar;
        defaultReverseRegistrar = _defaultReverseRegistrar;
    }

    /// @inheritdoc IDotRegistrarController
    function rentPrice(
        string calldata label,
        uint256 duration
    )
        public
        view
        override
        returns (IStableOracle.Price memory price)
    {
        bytes32 labelhash = keccak256(bytes(label));
        return _rentPrice(label, labelhash, duration);
    }

    /// @inheritdoc IDotRegistrarController
    function valid(string calldata label) public pure returns (bool isValid) {
        return label.strlen() >= 3;
    }

    /// @inheritdoc IDotRegistrarController
    function available(string calldata label) public view override returns (bool isAvailable) {
        bytes32 labelhash = keccak256(bytes(label));
        return _available(label, labelhash);
    }

    /// @inheritdoc IDotRegistrarController
    function makeCommitment(Registration calldata registration)
        public
        pure
        override
        returns (bytes32 commitment)
    {
        require(
            registration.data.length == 0 || registration.resolver != address(0),
            ResolverRequiredWhenDataSupplied()
        );

        require(
            registration.reverseRecord == 0 || registration.resolver != address(0),
            ResolverRequiredForReverseRecord()
        );

        require(
            registration.duration >= MIN_REGISTRATION_DURATION,
            DurationTooShort(registration.duration)
        );

        return keccak256(abi.encode(registration));
    }

    /// @inheritdoc IDotRegistrarController
    function commit(bytes32 commitment) public override {
        require(
            commitments[commitment] + maxCommitmentAge < block.timestamp,
            UnexpiredCommitmentExists(commitment)
        );
        commitments[commitment] = block.timestamp;
    }

    /// @inheritdoc IDotRegistrarController
    function register(Registration calldata registration) public payable override {
        bytes32 labelhash = keccak256(bytes(registration.label));
        IStableOracle.PriceWithMeta memory price = oracle.priceWithCheck(
            registration.label,
            baseRegistrar.nameExpires(uint256(labelhash)),
            registration.duration,
            registration.owner
        );

        uint256 totalCost = price.userStatus == IStableOracle.PopStatus.PopFull
            ? 0
            : price.price.base + price.price.premium;

        require(msg.value >= totalCost, InsufficientValue());
        require(_available(registration.label, labelhash), NameNotAvailable(registration.label));

        bytes32 commitmentHash = makeCommitment(registration);
        uint256 commitmentTimestamp = commitments[commitmentHash];

        require(
            commitmentTimestamp + minCommitmentAge <= block.timestamp,
            CommitmentTooNew(
                commitmentHash, commitmentTimestamp + minCommitmentAge, block.timestamp
            )
        );

        require(commitmentTimestamp != 0, CommitmentNotFound(commitmentHash));

        require(
            commitmentTimestamp + maxCommitmentAge > block.timestamp,
            CommitmentTooOld(
                commitmentHash, commitmentTimestamp + maxCommitmentAge, block.timestamp
            )
        );

        delete commitments[commitmentHash];

        uint256 expirationTime;

        if (registration.resolver == address(0)) {
            expirationTime = baseRegistrar.register(
                uint256(labelhash), registration.owner, registration.duration
            );
        } else {
            expirationTime =
                baseRegistrar.register(uint256(labelhash), address(this), registration.duration);

            bytes32 namehash = keccak256(abi.encodePacked(DOT_NODE, labelhash));
            registry.setRecord(namehash, registration.owner, registration.resolver, 0);

            if (registration.data.length > 0) {
                Resolver(registration.resolver).multicallWithNodeCheck(namehash, registration.data);
            }

            baseRegistrar.transferFrom(address(this), registration.owner, uint256(labelhash));

            if (registration.reverseRecord & REVERSE_RECORD_DOT_BIT != 0) {
                reverseRegistrar.setNameForAddr(
                    msg.sender,
                    msg.sender,
                    registration.resolver,
                    string.concat(registration.label, ".dot")
                );
            }

            if (registration.reverseRecord & REVERSE_RECORD_DEFAULT_BIT != 0) {
                defaultReverseRegistrar.setNameForAddr(
                    msg.sender, string.concat(registration.label, ".dot")
                );
            }
        }

        emit NameRegistered(
            registration.label,
            labelhash,
            registration.owner,
            price.price.base,
            price.price.premium,
            expirationTime,
            registration.referrer
        );

        if (price.userStatus == IStableOracle.PopStatus.PopLite) {
            oracle.reserveBaseName(registration.label, msg.sender);
        }

        if (msg.value > totalCost) {
            (bool success,) = payable(msg.sender).call{value: msg.value - totalCost}("");
            require(success, RefundFailed());
        }
    }

    /// @inheritdoc IDotRegistrarController
    function renew(
        string calldata label,
        uint256 duration,
        bytes32 referrer
    )
        external
        payable
        override
    {
        bytes32 labelhash = keccak256(bytes(label));
        IStableOracle.Price memory price = _rentPrice(label, labelhash, duration);

        require(msg.value >= price.base, InsufficientValue());

        uint256 expirationTime = baseRegistrar.renew(uint256(labelhash), duration);

        emit NameRenewed(label, labelhash, price.base, expirationTime, referrer);

        if (msg.value > price.base) {
            (bool success,) = payable(msg.sender).call{value: msg.value - price.base}("");
            require(success, RefundFailed());
        }
    }

    /// @inheritdoc IDotRegistrarController
    function withdraw() public override onlyOwner {
        (bool success,) = payable(owner()).call{value: address(this).balance}("");
        require(success, WithdrawalFailed());
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceID) public view override returns (bool supported) {
        return interfaceID == type(IDotRegistrarController).interfaceId
            || super.supportsInterface(interfaceID);
    }

    /// @notice Internal price calculation
    /// @param label Domain label
    /// @param labelhash Keccak256 hash of label
    /// @param duration Registration period
    /// @return price Pricing breakdown
    function _rentPrice(
        string calldata label,
        bytes32 labelhash,
        uint256 duration
    )
        internal
        view
        returns (IStableOracle.Price memory price)
    {
        return oracle.price(label, baseRegistrar.nameExpires(uint256(labelhash)), duration);
    }

    /// @notice Internal availability check
    /// @param label Domain label
    /// @param labelhash Keccak256 hash of label
    /// @return isAvailable True if available
    function _available(
        string calldata label,
        bytes32 labelhash
    )
        internal
        view
        returns (bool isAvailable)
    {
        return valid(label) && baseRegistrar.available(uint256(labelhash));
    }
}
