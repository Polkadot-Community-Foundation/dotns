// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {console} from "forge-std/Script.sol";
import {BaseDeployer} from "./BaseDeployer.s.sol";
import {ENSRegistry} from "../contracts/registry/ENSRegistry.sol";
import {Root} from "../contracts/root/Root.sol";
import {ReverseRegistrar} from "../contracts/reverseRegistrar/ReverseRegistrar.sol";
import {
    BaseRegistrarImplementation
} from "../contracts/ethregistrar/BaseRegistrarImplementation.sol";
import {StableOracle, IStableOracle} from "../contracts/ethregistrar/StableOracle.sol";
import {StaticMetadataService} from "../contracts/wrapper/StaticMetadataService.sol";
import {NameWrapper} from "../contracts/wrapper/NameWrapper.sol";
import {DotRegistrarController} from "../contracts/ethregistrar/DotRegistrarController.sol";
import {StaticBulkRenewal} from "../contracts/ethregistrar/StaticBulkRenewal.sol";
import {PublicResolver} from "../contracts/resolvers/PublicResolver.sol";
import {GatewayProvider} from "../contracts/ccipRead/GatewayProvider.sol";
import {UniversalResolver} from "../contracts/universalResolver/UniversalResolver.sol";
import {IMetadataService} from "../contracts/wrapper/IMetadataService.sol";
import {DefaultReverseRegistrar} from "../contracts/reverseRegistrar/DefaultReverseRegistrar.sol";
import {StoreFactory} from "../contracts/utils/StoreFactory.sol";
import {DotnsRegistrar} from "../contracts/utils/DotnsRegistrar.sol";
import {Multicall3} from "../contracts/utils/MultiCall3.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/// @title DotnsDeployer
contract DotnsDeployer is BaseDeployer {
    bytes32 constant ZERO_HASH = bytes32(0);

    ENSRegistry public ensRegistry;
    Root public root;
    ReverseRegistrar public reverseRegistrar;
    BaseRegistrarImplementation public baseRegistrarImplementation;
    DummyOracle public dummyOracle;
    StableOracle public stableOracle;
    StaticMetadataService public staticMetadataService;
    NameWrapper public nameWrapper;
    DotRegistrarController public dotRegistrarController;
    StaticBulkRenewal public staticBulkRenewal;
    PublicResolver public publicResolver;
    GatewayProvider public gatewayProvider;
    UniversalResolver public universalResolver;
    DefaultReverseRegistrar public defaultReverseRegistrar;
    StoreFactory public storeFactory;
    DotnsRegistrar public dotnsRegistrar;
    Multicall3 public multicall3;

    /// @notice Executes deployment following the exact BaseDotns test sequence
    function run() external {
        uint256 chainId = block.chainid;
        vm.warp(block.timestamp + 1 weeks);
        console.log("Current blocktime");
        console.logUint(block.timestamp);
        initDeployment();

        address OWNER = msg.sender;
        vm.startBroadcast(OWNER);
        vm.label(OWNER, "OWNER");

        // ENS Registry
        ensRegistry = new ENSRegistry();
        vm.label(address(ensRegistry), "ENSRegistry");
        logDeployment("ENSRegistry", address(ensRegistry));

        // Root
        root = new Root(ensRegistry);
        vm.label(address(root), "Root");
        logDeployment("Root", address(root));

        ensRegistry.setOwner(ZERO_HASH, address(root));
        root.setController(OWNER, true);

        // Reverse registrar
        reverseRegistrar = new ReverseRegistrar(ensRegistry);
        vm.label(address(reverseRegistrar), "ReverseRegistrar");
        logDeployment("ReverseRegistrar", address(reverseRegistrar));

        bytes32 reverseLabel = keccak256("reverse");
        bytes32 addrLabel = keccak256("addr");
        bytes32 reverseNode = keccak256(abi.encodePacked(ZERO_HASH, reverseLabel));

        root.setSubnodeOwner(reverseLabel, OWNER);
        ensRegistry.setSubnodeOwner(reverseNode, addrLabel, address(reverseRegistrar));

        // Base registrar for .dot
        bytes32 dotLabel = keccak256("dot");
        bytes32 dotNode = keccak256(abi.encodePacked(ZERO_HASH, dotLabel));

        baseRegistrarImplementation = new BaseRegistrarImplementation(ensRegistry, dotNode);
        vm.label(address(baseRegistrarImplementation), "BaseRegistrarImplementation");
        logDeployment("BaseRegistrarImplementation", address(baseRegistrarImplementation));

        root.setSubnodeOwner(dotLabel, address(baseRegistrarImplementation));

        // Rent prices
        uint256[] memory rentPrices = new uint256[](5);
        rentPrices[0] = 0;
        rentPrices[1] = 0;
        rentPrices[2] = 3170979200;
        rentPrices[3] = 1585489600;
        rentPrices[4] = 317097920;

        // StableOracle
        address stableOracleAddress = Upgrades.deployUUPSProxy(
            "StableOracle.sol:StableOracle", abi.encodeCall(StableOracle.initialize, (rentPrices))
        );
        stableOracle = StableOracle(stableOracleAddress);
        vm.label(stableOracleAddress, "StableOracle");
        logDeployment("StableOracle", stableOracleAddress);

        // Metadata Service
        staticMetadataService = new StaticMetadataService("http://localhost:8080/name/0x{id}");
        vm.label(address(staticMetadataService), "StaticMetadataService");
        logDeployment("StaticMetadataService", address(staticMetadataService));

        // NameWrapper
        nameWrapper = new NameWrapper(
            ensRegistry,
            baseRegistrarImplementation,
            IMetadataService(address(staticMetadataService))
        );
        vm.label(address(nameWrapper), "NameWrapper");
        logDeployment("NameWrapper", address(nameWrapper));

        baseRegistrarImplementation.addController(address(nameWrapper));

        // Default Reverse Registrar
        defaultReverseRegistrar = new DefaultReverseRegistrar();
        vm.label(address(defaultReverseRegistrar), "DefaultReverseRegistrar");
        logDeployment("DefaultReverseRegistrar", address(defaultReverseRegistrar));

        // Dot Registrar Controller
        dotRegistrarController = new DotRegistrarController(
            baseRegistrarImplementation,
            stableOracle,
            6,
            86400,
            reverseRegistrar,
            defaultReverseRegistrar,
            ensRegistry
        );
        vm.label(address(dotRegistrarController), "DotRegistrarController");
        logDeployment("DotRegistrarController", address(dotRegistrarController));

        baseRegistrarImplementation.addController(address(dotRegistrarController));
        nameWrapper.setController(address(dotRegistrarController), true);
        reverseRegistrar.setController(address(dotRegistrarController), true);

        // Bulk Renewal
        staticBulkRenewal = new StaticBulkRenewal(dotRegistrarController);
        vm.label(address(staticBulkRenewal), "StaticBulkRenewal");
        logDeployment("StaticBulkRenewal", address(staticBulkRenewal));

        // Public Resolver
        publicResolver = new PublicResolver(
            ensRegistry, nameWrapper, address(dotRegistrarController), address(reverseRegistrar)
        );
        vm.label(address(publicResolver), "PublicResolver");
        logDeployment("PublicResolver", address(publicResolver));

        reverseRegistrar.setDefaultResolver(address(publicResolver));

        // Gateway Provider
        string[] memory urls = new string[](1);
        urls[0] = "http://universal-offchain-resolver.local/";
        gatewayProvider = new GatewayProvider(urls);
        vm.label(address(gatewayProvider), "GatewayProvider");
        logDeployment("GatewayProvider", address(gatewayProvider));

        // Universal Resolver
        universalResolver = new UniversalResolver(OWNER, ensRegistry, gatewayProvider);
        vm.label(address(universalResolver), "UniversalResolver");
        logDeployment("UniversalResolver", address(universalResolver));

        // Set approvals
        ensRegistry.setApprovalForAll(address(dotRegistrarController), true);
        baseRegistrarImplementation.setResolver(address(publicResolver));

        // Store Factory
        storeFactory = new StoreFactory();
        vm.label(address(storeFactory), "StoreFactory");
        logDeployment("StoreFactory", address(storeFactory));

        // DotnsRegistrar
        dotnsRegistrar = new DotnsRegistrar(
            address(dotRegistrarController), address(ensRegistry), address(storeFactory)
        );
        vm.label(address(dotnsRegistrar), "DotnsRegistrar");
        logDeployment("DotnsRegistrar", address(dotnsRegistrar));

        // Multicall3
        multicall3 = new Multicall3();
        vm.label(address(multicall3), "Multicall3");
        logDeployment("Multicall3", address(multicall3));

        stableOracle.updateEthRegistry(address(dotRegistrarController));

        vm.stopBroadcast();
        saveDeployments(_getDeploymentFolder(), vm.toString(chainId));
        getNamePopStatus();
    }

    function getNamePopStatus() public view {
        (IStableOracle.PopStatus status, string memory message) = stableOracle.classifyName("hello");

        require(uint256(status) == uint256(IStableOracle.PopStatus.Reserved));
    }

    /// @notice Returns deployment folder location based on chain ID
    function _getDeploymentFolder() internal view returns (string memory directory) {
        directory = "localhost";
        if (block.chainid == 420420422) {
            directory = "paseo";
        } else if (block.chainid == 420420420) {
            directory = "paseo-local";
        }
    }
}
