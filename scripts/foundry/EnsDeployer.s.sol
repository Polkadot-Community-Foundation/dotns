// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BaseDeployer} from "./BaseDeployer.s.sol";
import {ENSRegistry} from "../../contracts/registry/ENSRegistry.sol";
import {Root} from "../../contracts/root/Root.sol";
import {ReverseRegistrar} from "../../contracts/reverseRegistrar/ReverseRegistrar.sol";
import {BaseRegistrarImplementation} from
    "../../contracts/ethregistrar/BaseRegistrarImplementation.sol";
import {DummyOracle} from "../../contracts/ethregistrar/DummyOracle.sol";
import {ExponentialPremiumPriceOracle} from
    "../../contracts/ethregistrar/ExponentialPremiumPriceOracle.sol";
import {StaticMetadataService} from "../../contracts/wrapper/StaticMetadataService.sol";
import {NameWrapper} from "../../contracts/wrapper/NameWrapper.sol";
import {ETHRegistrarController} from "../../contracts/ethregistrar/ETHRegistrarController.sol";
import {StaticBulkRenewal} from "../../contracts/ethregistrar/StaticBulkRenewal.sol";
import {PublicResolver} from "../../contracts/resolvers/PublicResolver.sol";
import {GatewayProvider} from "../../contracts/ccipRead/GatewayProvider.sol";
import {UniversalResolver} from "../../contracts/universalResolver/UniversalResolver.sol";
import {AggregatorInterface} from "../../contracts/ethregistrar/StablePriceOracle.sol";
import {IMetadataService} from "../../contracts/wrapper/IMetadataService.sol";
import {DefaultReverseRegistrar} from "../../contracts/reverseRegistrar/DefaultReverseRegistrar.sol";
import {StoreFactory} from "../../contracts/utils/StoreFactory.sol";
import {DotnsRegistrar} from "../../contracts/utils/DotnsRegistrar.sol";

contract EnsDeployer is BaseDeployer {
    bytes32 constant ZERO_HASH = bytes32(0);

    ENSRegistry public ensRegistry;
    Root public root;
    ReverseRegistrar public reverseRegistrar;
    BaseRegistrarImplementation public baseRegistrarImplementation;
    DummyOracle public dummyOracle;
    ExponentialPremiumPriceOracle public exponentialPremiumPriceOracle;
    StaticMetadataService public staticMetadataService;
    NameWrapper public nameWrapper;
    ETHRegistrarController public ethRegistrarController;
    StaticBulkRenewal public staticBulkRenewal;
    PublicResolver public publicResolver;
    GatewayProvider public batchGatewayProvider;
    UniversalResolver public universalResolver;
    DefaultReverseRegistrar public defaultReverseRegistrar;
    StoreFactory public storeFactory;
    DotnsRegistrar public dotnsRegistrar;

    function run() external {
        uint256 chainId = block.chainid;

        initDeployment(chainId);
        address OWNER = msg.sender;

        vm.startBroadcast(OWNER);
        vm.label(OWNER, "OWNER");

        ensRegistry = new ENSRegistry();
        logDeployment("ENSRegistry", address(ensRegistry));

        root = new Root(ensRegistry);
        logDeployment("Root", address(root));

        ensRegistry.setOwner(ZERO_HASH, address(root));
        root.setController(OWNER, true);

        reverseRegistrar = new ReverseRegistrar(ensRegistry);
        logDeployment("ReverseRegistrar", address(reverseRegistrar));

        root.setSubnodeOwner(keccak256("reverse"), OWNER);
        ensRegistry.setSubnodeOwner(
            namehash("reverse"), keccak256("addr"), address(reverseRegistrar)
        );

        baseRegistrarImplementation = new BaseRegistrarImplementation(ensRegistry, namehash("dot"));
        logDeployment("BaseRegistrarImplementation", address(baseRegistrarImplementation));

        root.setSubnodeOwner(keccak256("dot"), address(baseRegistrarImplementation));

        dummyOracle = new DummyOracle(160000000000);
        logDeployment("DummyOracle", address(dummyOracle));

        uint256[] memory rentPrices = new uint256[](5);
        rentPrices[0] = 0;
        rentPrices[1] = 0;
        rentPrices[2] = 20294266869609;
        rentPrices[3] = 5073566717402;
        rentPrices[4] = 158548959919;

        exponentialPremiumPriceOracle = new ExponentialPremiumPriceOracle(
            AggregatorInterface(address(dummyOracle)), rentPrices, 100000000000000000000000000, 21
        );
        logDeployment("ExponentialPremiumPriceOracle", address(exponentialPremiumPriceOracle));

        staticMetadataService = new StaticMetadataService("http://localhost:8080/name/0x{id}");
        logDeployment("StaticMetadataService", address(staticMetadataService));

        nameWrapper = new NameWrapper(
            ensRegistry,
            baseRegistrarImplementation,
            IMetadataService(address(staticMetadataService))
        );
        logDeployment("NameWrapper", address(nameWrapper));

        baseRegistrarImplementation.addController(address(nameWrapper));

        defaultReverseRegistrar = new DefaultReverseRegistrar();
        logDeployment("DefaultReverseRegistrar", address(defaultReverseRegistrar));

        ethRegistrarController = new ETHRegistrarController(
            baseRegistrarImplementation,
            exponentialPremiumPriceOracle,
            60,
            86400,
            reverseRegistrar,
            defaultReverseRegistrar,
            ensRegistry
        );
        logDeployment("ETHRegistrarController", address(ethRegistrarController));

        baseRegistrarImplementation.addController(address(ethRegistrarController));
        nameWrapper.setController(address(ethRegistrarController), true);
        reverseRegistrar.setController(address(ethRegistrarController), true);

        staticBulkRenewal = new StaticBulkRenewal(ethRegistrarController);
        logDeployment("StaticBulkRenewal", address(staticBulkRenewal));

        publicResolver = new PublicResolver(
            ensRegistry, nameWrapper, address(ethRegistrarController), address(reverseRegistrar)
        );
        logDeployment("PublicResolver", address(publicResolver));

        reverseRegistrar.setDefaultResolver(address(publicResolver));

        string[] memory urls = new string[](1);
        urls[0] = "http://universal-offchain-resolver.local/";
        batchGatewayProvider = new GatewayProvider(OWNER, urls);
        logDeployment("GatewayProvider", address(batchGatewayProvider));

        universalResolver = new UniversalResolver(OWNER, ensRegistry, batchGatewayProvider);
        logDeployment("UniversalResolver", address(universalResolver));

        ensRegistry.setApprovalForAll(address(ethRegistrarController), true);
        baseRegistrarImplementation.setResolver(address(publicResolver));

        storeFactory = new StoreFactory();
        logDeployment("StoreFactory", address(storeFactory));

        dotnsRegistrar = new DotnsRegistrar(
            address(ethRegistrarController), address(ensRegistry), address(storeFactory)
        );
        logDeployment("DotnsRegistrar", address(storeFactory));

        vm.stopBroadcast();
        require(
            ensRegistry.owner(namehash("dot")) == address(baseRegistrarImplementation),
            ".dot TLD not owned by registrar"
        );
        saveDeployments(_getDeploymentFolder(), vm.toString(chainId));
    }

    function _getDeploymentFolder() internal view returns (string memory directory) {
        directory = "localhost";
        if (block.chainid == 420420420) {
            directory = "paseo";
        }
    }

    function namehash(string memory name) internal pure returns (bytes32) {
        bytes32 node = ZERO_HASH;
        if (bytes(name).length == 0) return node;

        if (keccak256(bytes(name)) == keccak256("reverse")) {
            return keccak256(abi.encodePacked(ZERO_HASH, keccak256("reverse")));
        }
        if (keccak256(bytes(name)) == keccak256("dot")) {
            return keccak256(abi.encodePacked(ZERO_HASH, keccak256("dot")));
        }
        return node;
    }

    function calculateInterfaceId(string memory interfaceName) internal pure returns (bytes4) {
        if (keccak256(bytes(interfaceName)) == keccak256("INameWrapper")) {
            return bytes4(0x00000001);
        }
        if (keccak256(bytes(interfaceName)) == keccak256("IETHRegistrarController")) {
            return bytes4(0x00000002);
        }
        if (keccak256(bytes(interfaceName)) == keccak256("IBulkRenewal")) {
            return bytes4(0x00000003);
        }
        return bytes4(0);
    }
}
