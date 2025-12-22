// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {PopOracle, IPopOracle} from "../../contracts/pop/PopOracle.sol";
import {DotnsRegistrar, IDotnsRegistrar} from "../../contracts/registrars/DotnsRegistrar.sol";
import {
    DotnsRegistrarController,
    IDotnsRegistrarController
} from "../../contracts/registrars/DotnsRegistrarController.sol";
import {DotnsRegistry, IDotnsRegistry} from "../../contracts/registry/DotnsRegistry.sol";
import {DotnsResolver} from "../../contracts/resolvers/DotnsResolver.sol";
import {DotnsContentResolver} from "../../contracts/resolvers/DotnsContentResolver.sol";
import {
    DotnsReverseResolver,
    IDotnsReverseResolver
} from "../../contracts/resolvers/DotnsReverseResolver.sol";
import {StoreFactory, IStoreFactory} from "../../contracts/store/StoreFactory.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/// @title BaseDotns
/// @notice Common Foundry test base for deploying a DotNS stack behind UUPS proxies.
/// @dev Deploys and wires the core DotNS contracts used by test suites:
///      - StoreFactory: per-user Store instances used for immutable registration writes
///      - DotnsRegistrar: ERC721-backed registrar used to allocate label ownership
///      - DotnsRegistry: forward registry used to set subnode ownership under .dot
///      - DotnsReverseResolver: reverse resolver used to set default reverse records
///      - DotnsContentResolver: resolver used for content records
///      - PopOracle: PoP rules and spam-pricing oracle
///      - DotnsRegistrarController: commit–reveal controller orchestrating registration flow
///
/// @dev Testing conventions:
///      - `setUp()` warps time to a deterministic timestamp and funds pre-defined users.
///      - Deployments are executed under `owner` as the admin address.
///      - Addresses are labeled to improve trace readability.
abstract contract BaseDotns is Test {
    /// @notice Test user account: ed.
    address public ed;

    /// @notice Test user account: leonardo.
    address public leonardo;

    /// @notice Test user account: tiago.
    address public tiago;

    /// @notice Test user account: owner/admin used to deploy and configure contracts.
    address public owner;

    /// @notice Default native balance allocated to test users.
    uint256 public constant DEFAULT_BALANCE = 99_999_999_999_999 ether;

    /// @notice Deployed PoP oracle instance.
    PopOracle public popOracle;

    /// @notice Deployed DotNS registrar instance.
    DotnsRegistrar public dotnsRegistrar;

    /// @notice Deployed registrar controller instance.
    DotnsRegistrarController public dotnsRegistrarController;

    /// @notice Deployed forward registry instance.
    DotnsRegistry public dotnsRegistry;

    /// @notice Deployed forward resolver instance.
    DotnsResolver public dotnsResolver;

    /// @notice Deployed content resolver instance.
    DotnsContentResolver public dotnsContentResolver;

    /// @notice Deployed reverse resolver instance.
    DotnsReverseResolver public dotnsReverseResolver;

    /// @notice Deployed Store factory instance.
    StoreFactory public storeFactory;

    /// @notice Rent price applied to PoP NoStatus users for spam resistance.
    /// @dev This value is passed into PopOracle initialization in this base test.
    uint256 public constant rentPrice = 2e15 wei;

    /// @notice Zero hash constant
    bytes32 public constant ZERO_HASH = bytes32(0);

    /// @notice Label hash for "dot".
    /// @dev Computed during setup as `keccak256(bytes("dot"))`.
    bytes32 public dotLabel;

    /// @notice Node hash for the ".dot" TLD.
    /// @dev Computed during setup as `_namehash(ZERO_HASH, dotLabel)`.
    bytes32 public dotNode;

    /// @notice Default node hash for the ".dot" TLD.
    /// @dev Included to cross-check against computed `dotNode` where relevant.
    bytes32 private constant DOT_NODE =
        0x3fce7d1364a893e213bc4212792b517ffc88f5b13b86c8ef9c8d390c3a1370ce;

    function setUp() public virtual noGasMetering {
        vm.warp(365 days);

        ed = _createUser("ed");
        leonardo = _createUser("leonardo");
        tiago = _createUser("tiago");
        owner = _createUser("owner");

        dotLabel = keccak256(bytes("dot"));
        dotNode = _namehash(ZERO_HASH, dotLabel);

        vm.startPrank(owner);

        storeFactory = new StoreFactory();
        vm.label(address(storeFactory), "StoreFactory");

        address dotnsRegistrarAddress = Upgrades.deployUUPSProxy(
            "DotnsRegistrar.sol:DotnsRegistrar",
            abi.encodeCall(DotnsRegistrar.initialize, ("Dotns", "Dotns"))
        );
        dotnsRegistrar = DotnsRegistrar(dotnsRegistrarAddress);
        vm.label(dotnsRegistrarAddress, "DotnsRegistrar");

        address dotnsRegistryAddress = Upgrades.deployUUPSProxy(
            "DotnsRegistry.sol:DotnsRegistry", abi.encodeCall(DotnsRegistry.initialize, ())
        );
        dotnsRegistry = DotnsRegistry(dotnsRegistryAddress);
        vm.label(dotnsRegistryAddress, "DotnsRegistry");

        address dotnsReverseResolverAddress = Upgrades.deployUUPSProxy(
            "DotnsReverseResolver.sol:DotnsReverseResolver",
            abi.encodeCall(DotnsReverseResolver.initialize, ())
        );
        dotnsReverseResolver = DotnsReverseResolver(dotnsReverseResolverAddress);
        vm.label(dotnsReverseResolverAddress, "DotnsReverseResolver");

        address dotnsContentResolverAddress = Upgrades.deployUUPSProxy(
            "DotnsContentResolver.sol:DotnsContentResolver",
            abi.encodeCall(DotnsContentResolver.initialize, (IDotnsRegistry(dotnsRegistryAddress)))
        );
        dotnsContentResolver = DotnsContentResolver(dotnsContentResolverAddress);
        vm.label(dotnsContentResolverAddress, "DotnsContentResolver");

        address popOracleAddress = Upgrades.deployUUPSProxy(
            "PopOracle.sol:PopOracle", abi.encodeCall(PopOracle.initialize, (rentPrice))
        );
        popOracle = PopOracle(popOracleAddress);
        vm.label(popOracleAddress, "PopOracle");

        address dotnsRegistrarControllerAddress = Upgrades.deployUUPSProxy(
            "DotnsRegistrarController.sol:DotnsRegistrarController",
            abi.encodeCall(
                DotnsRegistrarController.initialize,
                (
                    IDotnsRegistrar(dotnsRegistrarAddress),
                    IDotnsRegistry(dotnsRegistryAddress),
                    IDotnsReverseResolver(dotnsReverseResolverAddress),
                    IPopOracle(popOracleAddress),
                    IStoreFactory(address(storeFactory)),
                    6 seconds,
                    1 days
                )
            )
        );
        dotnsRegistrarController = DotnsRegistrarController(dotnsRegistrarControllerAddress);
        vm.label(dotnsRegistrarControllerAddress, "DotnsRegistrarController");
        dotnsReverseResolver.updateRegistrar(dotnsRegistrarControllerAddress);
        popOracle.updateEthRegistry(dotnsRegistrarControllerAddress);
        dotnsRegistrar.addController(dotnsRegistrarControllerAddress);
        dotnsRegistry.updateRegistrarController(dotnsRegistrarControllerAddress);
        vm.stopPrank();
    }

    /// @notice Computes an namehash for `parent` and `label`.
    /// @dev Equivalent to `keccak256(abi.encodePacked(parent, label))`.
    /// @param parent The parent node hash.
    /// @param label The label hash.
    /// @return node The resulting node hash.
    function _namehash(bytes32 parent, bytes32 label) internal pure returns (bytes32 node) {
        node = keccak256(abi.encodePacked(parent, label));
    }

    /// @notice Creates a new test user and funds it with DEFAULT_BALANCE.
    /// @dev Uses Foundry's `makeAddr` to derive a deterministic address and labels it in traces.
    /// @param name Human-readable label used to derive and label the address.
    /// @return user Newly created payable address.
    function _createUser(string memory name) internal returns (address payable user) {
        user = payable(makeAddr(name));
        vm.deal({account: user, newBalance: DEFAULT_BALANCE});
        vm.label(user, name);
    }

    /// @notice Computes the commitment hash for a registration.
    /// @dev Must match the controller's commitment preimage:
    ///      `keccak256(abi.encode(label, owner, secret))`.
    /// @param registration Registration parameters.
    /// @return commitmentHash Commitment hash.
    function _computeCommitmentHash(IDotnsRegistrarController.Registration memory registration)
        internal
        pure
        returns (bytes32 commitmentHash)
    {
        commitmentHash =
            keccak256(abi.encode(registration.label, registration.owner, registration.secret));
    }

    /// @notice Submits a commitment for a registration.
    /// @dev Uses `registration.owner` as the committing account.
    /// @param registration Registration parameters.
    function _commitRegistration(IDotnsRegistrarController.Registration memory registration)
        internal
    {
        bytes32 commitmentHash = _computeCommitmentHash(registration);
        vm.prank(registration.owner);
        dotnsRegistrarController.commit(commitmentHash);
    }

    /// @notice Submits a commitment and advances time past the controller minimum commitment age.
    /// @param registration Registration parameters.
    function _commitRegistrationAndWaitMinimumAge(
        IDotnsRegistrarController.Registration memory registration
    )
        internal
    {
        _commitRegistration(registration);
        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);
    }

    /// @notice Submits a commitment, waits for the minimum age, then registers with the exact oracle price.
    /// @dev Prices are obtained via `popOracle.priceWithCheck(label, owner)`.
    /// @param registration Registration parameters.
    function _commitRegistrationAndRegister(
        IDotnsRegistrarController.Registration memory registration
    )
        internal
    {
        _commitRegistrationAndWaitMinimumAge(registration);

        IPopOracle.PriceWithMeta memory priceMetadata =
            popOracle.priceWithCheck(registration.label, registration.owner);

        vm.prank(registration.owner);
        dotnsRegistrarController.register{value: priceMetadata.price}(registration);
    }

    /// @notice Minimal commit–reveal helper aligned to IDotnsRegistrarController.
    /// @param label Label to register.
    /// @param nameOwner Address to assign as owner.
    function _commitAndRegister(string memory label, address nameOwner) internal {
        bytes32 secret = keccak256(abi.encodePacked(label, nameOwner, block.timestamp));

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({label: label, owner: nameOwner, secret: secret});

        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);

        vm.prank(nameOwner);
        dotnsRegistrarController.commit(commitment);

        uint256 minAge =
            DotnsRegistrarController(address(dotnsRegistrarController)).minCommitmentAge();
        vm.warp(block.timestamp + minAge + 1);

        uint256 requiredPayment = popOracle.priceWithCheck(label, nameOwner).price;

        vm.prank(nameOwner);
        dotnsRegistrarController.register{value: requiredPayment}(registration);
    }
}
