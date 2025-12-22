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
import {IPopOracle} from "../pop/IPopOracle.sol";
import {StringUtils} from "../utils/StringUtils.sol";
import {IDotnsRegistrarController} from "./IDotnsRegistrarController.sol";
import {Store} from "../store/Store.sol";
import {IStoreFactory} from "../store/IStoreFactory.sol";

/// @title DotNS Registrar Controller
/// @notice Allocates .dot labels using a commit–reveal scheme.
/// @dev Orchestrates allocation, PoP validation, pricing enforcement, forward registry wiring,
///      default reverse resolution, and immutable store writing.
///
/// @dev Commit–reveal:
///      - Commitments are stored as timestamps.
///      - A reveal is valid only if `minCommitmentAge <= now - committedAt < maxCommitmentAge`.
///
/// @dev Store writing:
///      - On successful registration, the controller writes the full name `<label>.dot` to the user’s Store.
///      - The Store is expected to permanently lock DotNS-written entries, preventing deletion or overwrite.
/// @custom:security-contact admin@parity.io
contract DotnsRegistrarController is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC165Upgradeable,
    IDotnsRegistrarController
{
    using StringUtils for *;

    /// @notice Namehash of the .dot TLD.
    bytes32 private constant DOT_NODE =
        0x3fce7d1364a893e213bc4212792b517ffc88f5b13b86c8ef9c8d390c3a1370ce;

    /// @notice Upper bound for commitment validity to cap storage griefing risk.
    uint256 public constant MAX_ALLOWED_COMMITMENT_AGE = 7 days;

    /// @notice Base registrar responsible for minting name ownership.
    IDotnsRegistrar public dotnsRegistrar;

    /// @notice Forward registry storing node ownership.
    IDotnsRegistry public dotnsRegistry;

    /// @notice Reverse resolver for address → primary name mapping.
    IDotnsReverseResolver public reverseResolver;

    /// @notice Oracle enforcing PoP rules and pricing.
    IPopOracle public oracle;

    /// @notice Factory for per-user Store instances.
    IStoreFactory public storeFactory;

    /// @notice Minimum age a commitment must reach before reveal.
    uint256 public minCommitmentAge;

    /// @notice Maximum age after which a commitment expires.
    uint256 public maxCommitmentAge;

    /// @notice Commitment hash => timestamp when committed.
    mapping(bytes32 => uint256) public commitments;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the registrar controller.
    /// @dev Validates commitment window bounds and wires dependencies.
    /// @param registrar The base registrar used to allocate/mint ownership.
    /// @param registry The forward registry used to assign subnode ownership.
    /// @param reverse The reverse resolver used to set a default reverse record.
    /// @param popOracle The PoP oracle used for classification and pricing.
    /// @param factory The Store factory used to persist immutable registration records.
    /// @param minAge Minimum time (in seconds) after commit before reveal is allowed.
    /// @param maxAge Maximum time (in seconds) after commit before reveal expires.
    function initialize(
        IDotnsRegistrar registrar,
        IDotnsRegistry registry,
        IDotnsReverseResolver reverse,
        IPopOracle popOracle,
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
        oracle = popOracle;
        storeFactory = factory;

        minCommitmentAge = minAge;
        maxCommitmentAge = maxAge;
    }

    /// @inheritdoc IDotnsRegistrarController
    function available(string calldata label) public view override returns (bool) {
        require(label.strlen() >= 3, NameNotAvailable(label));
        bytes32 labelhash = keccak256(bytes(label));
        return dotnsRegistrar.available(uint256(labelhash));
    }

    /// @inheritdoc IDotnsRegistrarController
    function makeCommitment(Registration calldata registration)
        public
        pure
        override
        returns (bytes32)
    {
        return keccak256(abi.encode(registration.label, registration.owner, registration.secret));
    }

    /// @inheritdoc IDotnsRegistrarController
    function commit(bytes32 commitment) external override {
        require(
            commitments[commitment] == 0
                || commitments[commitment] + maxCommitmentAge < block.timestamp,
            UnexpiredCommitmentExists(commitment)
        );

        commitments[commitment] = block.timestamp;
        emit NameCommitted(commitment);
    }

    /// @inheritdoc IDotnsRegistrarController
    function register(Registration calldata registration) external payable override {
        require(available(registration.label), NameNotAvailable(registration.label));

        bytes32 labelhash = keccak256(bytes(registration.label));
        bytes32 commitment = makeCommitment(registration);
        uint256 committedAt = commitments[commitment];

        require(committedAt != 0, CommitmentNotFound(commitment));

        require(
            committedAt + minCommitmentAge <= block.timestamp,
            CommitmentTooNew(commitment, committedAt + minCommitmentAge, block.timestamp)
        );

        require(
            committedAt + maxCommitmentAge > block.timestamp,
            CommitmentTooOld(commitment, committedAt + maxCommitmentAge, block.timestamp)
        );

        delete commitments[commitment];

        IPopOracle.PriceWithMeta memory priced =
            oracle.priceWithCheck(registration.label, registration.owner);

        uint256 totalCost = priced.price;
        require(msg.value >= totalCost, InsufficientValue());

        dotnsRegistrar.register(uint256(labelhash), registration.owner);

        bytes32 node = keccak256(abi.encodePacked(DOT_NODE, labelhash));
        dotnsRegistry.setOwner(node, registration.owner, address(reverseResolver));

        reverseResolver.setReverseName(
            registration.owner, string.concat(registration.label, ".dot")
        );

        Store store = Store(address(storeFactory.getDeployedStore(registration.owner)));
        if (address(store) == address(0)) {
            store = Store(address(storeFactory.deploy()));
            store.authorizeDotnsController(address(this));
            store.transferOwnership(registration.owner);
            storeFactory.transferOwnership(registration.owner);
        }

        bytes32 storeKey = keccak256(abi.encodePacked("dotns.registered", labelhash));
        store.setValueFor(registration.owner, storeKey, string.concat(registration.label, ".dot"));

        emit NameRegistered(
            registration.label, labelhash, registration.owner, priced.price, address(store)
        );

        if (
            priced.status == IPopOracle.PopStatus.PopLite
                && priced.userStatus == IPopOracle.PopStatus.PopLite
        ) {
            oracle.reserveBaseName(registration.label, registration.owner);
        }

        if (msg.value > totalCost) {
            (bool ok,) = payable(msg.sender).call{value: msg.value - totalCost}("");
            require(ok, RefundFailed());
        }
    }

    /// @inheritdoc IDotnsRegistrarController
    function registerReserved(Registration calldata registration) external payable override {
        require(available(registration.label), NameNotAvailable(registration.label));

        bytes32 labelhash = keccak256(bytes(registration.label));
        bytes32 node = keccak256(abi.encodePacked(DOT_NODE, labelhash));
        bytes32 commitment = makeCommitment(registration);
        uint256 committedAt = commitments[commitment];

        require(committedAt != 0, CommitmentNotFound(commitment));

        require(
            committedAt + minCommitmentAge <= block.timestamp,
            CommitmentTooNew(commitment, committedAt + minCommitmentAge, block.timestamp)
        );

        require(
            committedAt + maxCommitmentAge > block.timestamp,
            CommitmentTooOld(commitment, committedAt + maxCommitmentAge, block.timestamp)
        );

        delete commitments[commitment];

        dotnsRegistrar.register(uint256(labelhash), registration.owner);

        dotnsRegistry.setOwner(node, registration.owner, address(reverseResolver));

        reverseResolver.setReverseName(
            registration.owner, string.concat(registration.label, ".dot")
        );

        Store store = Store(address(storeFactory.getDeployedStore(registration.owner)));
        if (address(store) == address(0)) {
            store = Store(address(storeFactory.deploy()));
            store.authorizeDotnsController(address(this));
            store.transferOwnership(registration.owner);
        }

        bytes32 storeKey = keccak256(abi.encodePacked("dotns.registered", labelhash));
        store.setValueFor(registration.owner, storeKey, string.concat(registration.label, ".dot"));

        emit NameRegistered(registration.label, labelhash, registration.owner, 0, address(store));
    }

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IDotnsRegistrarController).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /// @notice Returns implementation version
    /// @return versionString Current version string
    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.0.0";
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
