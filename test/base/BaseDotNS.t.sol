// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ENSRegistry} from "../../contracts/registry/ENSRegistry.sol";
import {Root} from "../../contracts/root/Root.sol";
import {ReverseRegistrar} from "../../contracts/reverseRegistrar/ReverseRegistrar.sol";
import {
    BaseRegistrarImplementation
} from "../../contracts/ethregistrar/BaseRegistrarImplementation.sol";
import {DummyOracle} from "../../contracts/ethregistrar/DummyOracle.sol";
import {StableOracle} from "../../contracts/ethregistrar/StableOracle.sol";
import {StaticMetadataService} from "../../contracts/wrapper/StaticMetadataService.sol";
import {NameWrapper} from "../../contracts/wrapper/NameWrapper.sol";
import {
    DefaultReverseRegistrar
} from "../../contracts/reverseRegistrar/DefaultReverseRegistrar.sol";
import {DotRegistrarController} from "../../contracts/ethregistrar/DotRegistrarController.sol";
import {StaticBulkRenewal} from "../../contracts/ethregistrar/StaticBulkRenewal.sol";
import {PublicResolver} from "../../contracts/resolvers/PublicResolver.sol";
import {GatewayProvider} from "../../contracts/ccipRead/GatewayProvider.sol";
import {UniversalResolver} from "../../contracts/universalResolver/UniversalResolver.sol";
import {StoreFactory} from "../../contracts/utils/StoreFactory.sol";
import {DotnsRegistrar} from "../../contracts/utils/DotnsRegistrar.sol";
import {Multicall3} from "../../contracts/utils/Multicall3.sol";
import {IMetadataService} from "../../contracts/wrapper/IMetadataService.sol";
import {IDotRegistrarController} from "../../contracts/ethregistrar/IDotRegistrarController.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

abstract contract BaseDotns is Test {
    /// @notice Test user account: ed
    address public ed;

    /// @notice Test user account: leonardo
    address public leonardo;

    /// @notice Test user account: tiago
    address public tiago;

    /// @notice Test user account: owner/admin
    address public owner;

    /// @notice Default balance allocated to test users
    uint256 public immutable DEFAULT_BALANCE = 99999999999999 ether;

    // Core ENS Infrastructure
    /// @notice Central registry mapping domain nodes to owners
    ENSRegistry public ensRegistry;

    /// @notice Root contract managing TLD ownership
    Root public root;

    /// @notice Reverse registrar for address-to-name resolution
    ReverseRegistrar public reverseRegistrar;

    /// @notice Base registrar implementation for .dot TLD
    BaseRegistrarImplementation public baseRegistrar;

    // Pricing and Metadata
    /// @notice Dummy price oracle for testing
    DummyOracle public dummyOracle;

    /// @notice Stable oracle with PoP-based pricing logic
    StableOracle public stableOracle;

    /// @notice Static metadata service for name wrapper
    StaticMetadataService public metadataService;

    // Wrapper and Controllers
    /// @notice Name wrapper for ERC-1155 token representation
    NameWrapper public nameWrapper;

    /// @notice Default reverse registrar
    DefaultReverseRegistrar public defaultReverseRegistrar;

    /// @notice Main ETH registrar controller
    DotRegistrarController public dotRegistrarController;

    // Additional Contracts
    /// @notice Bulk renewal contract
    StaticBulkRenewal public bulkRenewal;

    /// @notice Public resolver for ENS records
    PublicResolver public publicResolver;

    /// @notice Gateway provider for CCIP read
    GatewayProvider public gatewayProvider;

    /// @notice Universal resolver
    UniversalResolver public universalResolver;

    /// @notice Store factory utility
    StoreFactory public storeFactory;

    /// @notice Dotns registrar utility
    DotnsRegistrar public dotnsRegistrar;

    /// @notice Multicall3 utility
    Multicall3 public multicall3;

    // Domain Hashes
    /// @notice Zero hash constant
    bytes32 public constant ZERO_HASH = bytes32(0);

    /// @notice Label hash for 'reverse'
    bytes32 public reverseLabel;

    /// @notice Label hash for 'addr'
    bytes32 public addrLabel;

    /// @notice Label hash for 'dot'
    bytes32 public dotLabel;

    /// @notice Node hash for reverse registry
    bytes32 public reverseNode;

    /// @notice Node hash for .dot TLD
    bytes32 public dotNode;

    /// @notice Default node hash for .dot TLD
    bytes32 private constant DOT_NODE =
        0x3fce7d1364a893e213bc4212792b517ffc88f5b13b86c8ef9c8d390c3a1370ce;

    /// @notice Upgrade options for UUPS proxy deployment
    Options public options;

    function setUp() public virtual noGasMetering {
        // Create test users
        ed = _createUser("ed");
        leonardo = _createUser("leonardo");
        tiago = _createUser("tiago");
        owner = _createUser("owner");
        vm.startPrank(owner);
        // Calculate domain hashes
        reverseLabel = keccak256("reverse");
        addrLabel = keccak256("addr");
        dotLabel = keccak256("dot");
        reverseNode = _namehash(ZERO_HASH, reverseLabel);
        dotNode = _namehash(ZERO_HASH, dotLabel);
        //options.unsafeSkipAllChecks = true;

        // Deploy core ENS infrastructure
        ensRegistry = new ENSRegistry();
        vm.label(address(ensRegistry), "ENSRegistry");

        root = new Root(ensRegistry);
        vm.label(address(root), "Root");

        ensRegistry.setOwner(ZERO_HASH, address(root));
        root.setController(owner, true);

        reverseRegistrar = new ReverseRegistrar(ensRegistry);
        vm.label(address(reverseRegistrar), "ReverseRegistrar");

        root.setSubnodeOwner(reverseLabel, owner);
        ensRegistry.setSubnodeOwner(reverseNode, addrLabel, address(reverseRegistrar));

        // Deploy base registrar
        baseRegistrar = new BaseRegistrarImplementation(ensRegistry, dotNode);
        vm.label(address(baseRegistrar), "BaseRegistrarImplementation");

        root.setSubnodeOwner(dotLabel, address(baseRegistrar));

        // Deploy pricing contracts
        dummyOracle = new DummyOracle(160000000000);
        vm.label(address(dummyOracle), "DummyOracle");

        uint256[] memory rentPrices = new uint256[](5);
        rentPrices[0] = 0;
        rentPrices[1] = 0;
        rentPrices[2] = 3170979200;
        rentPrices[3] = 1585489600;
        rentPrices[4] = 317097920;
        address stableOracleAddress = Upgrades.deployUUPSProxy(
            "StableOracle.sol:StableOracle",
            abi.encodeCall(StableOracle.initialize, (address(dummyOracle), rentPrices))
        );
        stableOracle = StableOracle(stableOracleAddress);
        vm.label(stableOracleAddress, "StableOracle");

        metadataService = new StaticMetadataService("http://localhost:8080/name/0x{id}");
        vm.label(address(metadataService), "StaticMetadataService");

        // Deploy name wrapper and controllers
        nameWrapper =
            new NameWrapper(ensRegistry, baseRegistrar, IMetadataService(address(metadataService)));
        vm.label(address(nameWrapper), "NameWrapper");

        baseRegistrar.addController(address(nameWrapper));

        defaultReverseRegistrar = new DefaultReverseRegistrar();
        vm.label(address(defaultReverseRegistrar), "DefaultReverseRegistrar");

        // Since we using an in memory node which has block.timestamp of 0 we need to increase
        // This to something higher than 0 to prevent a revert MaxCommitmentAgeTooHigh in DotRegistrarController
        vm.warp(1 days);

        dotRegistrarController = new DotRegistrarController(
            baseRegistrar,
            stableOracle,
            6,
            86400,
            reverseRegistrar,
            defaultReverseRegistrar,
            ensRegistry
        );
        vm.label(address(dotRegistrarController), "DotRegistrarController");

        baseRegistrar.addController(address(dotRegistrarController));
        nameWrapper.setController(address(dotRegistrarController), true);
        reverseRegistrar.setController(address(dotRegistrarController), true);

        // Deploy additional contracts
        bulkRenewal = new StaticBulkRenewal(dotRegistrarController);
        vm.label(address(bulkRenewal), "StaticBulkRenewal");

        publicResolver = new PublicResolver(
            ensRegistry, nameWrapper, address(dotRegistrarController), address(reverseRegistrar)
        );
        vm.label(address(publicResolver), "PublicResolver");

        reverseRegistrar.setDefaultResolver(address(publicResolver));

        string[] memory urls = new string[](1);
        urls[0] = "http://universal-offchain-resolver.local/";
        gatewayProvider = new GatewayProvider(urls);
        vm.label(address(gatewayProvider), "GatewayProvider");

        universalResolver = new UniversalResolver(owner, ensRegistry, gatewayProvider);
        vm.label(address(universalResolver), "UniversalResolver");

        ensRegistry.setApprovalForAll(address(dotRegistrarController), true);
        baseRegistrar.setResolver(address(publicResolver));

        // Deploy utilities
        storeFactory = new StoreFactory();
        vm.label(address(storeFactory), "StoreFactory");

        dotnsRegistrar = new DotnsRegistrar(
            address(dotRegistrarController), address(ensRegistry), address(storeFactory)
        );
        vm.label(address(dotnsRegistrar), "DotnsRegistrar");

        multicall3 = new Multicall3();
        vm.label(address(multicall3), "Multicall3");
        stableOracle.updateEthRegistry(address(dotRegistrarController));
        vm.stopPrank();
        vm.warp(block.timestamp + 121 days);
    }

    /// @notice Create a new test user with funded native balance and private key
    /// @param name Label to assign to the created address
    /// @return account Newly created payable address
    /// @return privateKey Private key for the account
    function _createUserWitPrivateKey(string memory name)
        internal
        returns (address payable account, uint256 privateKey)
    {
        (address user, uint256 userPk) = makeAddrAndKey(name);
        vm.deal({account: user, newBalance: DEFAULT_BALANCE});
        vm.label(user, name);
        return (payable(user), userPk);
    }

    /// @notice Create a new test user with funded native balance and label it
    /// @param name Label to assign to the created address
    /// @return user Newly created payable address
    function _createUser(string memory name) internal returns (address payable user) {
        user = payable(makeAddr(name));
        vm.deal({account: user, newBalance: DEFAULT_BALANCE});
        vm.label(user, name);
    }

    /// @notice Calculate namehash for a parent node and label
    /// @param parent Parent node hash
    /// @param label Label hash
    /// @return Node hash
    function _namehash(bytes32 parent, bytes32 label) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(parent, label));
    }
    /// @dev Helper to compute the nodehash the oracle uses

    function _node(string memory label) internal pure returns (bytes32) {
        bytes32 labelhash = keccak256(bytes(label));
        return keccak256(abi.encodePacked(DOT_NODE, labelhash));
    }

    /// @notice Helper function to commit and register a name in a single call
    /// @dev Handles the full registration flow: commit, wait for min commitment age, then register
    /// @param registration Registration struct containing label, owner, duration, and other parameters
    function _commitAndRegister(IDotRegistrarController.Registration memory registration) internal {
        vm.startPrank(registration.owner);
        vm.warp(block.timestamp + 1);
        bytes32 commit = dotRegistrarController.makeCommitment(registration);
        dotRegistrarController.commit(commit);
        vm.warp(block.timestamp + dotRegistrarController.minCommitmentAge() + 2);
        uint256 price =
            dotRegistrarController.rentPrice(registration.label, registration.duration).base;
        dotRegistrarController.register{value: price}(registration);
        vm.stopPrank();
    }

    /// @notice Helper function to commit a name in a single call
    /// @param registration Registration struct containing label, owner, duration, and other parameters
    function _commit(IDotRegistrarController.Registration memory registration) internal {
        vm.startPrank(registration.owner);
        vm.warp(block.timestamp + 1);
        bytes32 commit = dotRegistrarController.makeCommitment(registration);
        dotRegistrarController.commit(commit);
        vm.warp(block.timestamp + dotRegistrarController.minCommitmentAge() + 2);
        vm.stopPrank();
    }
}
