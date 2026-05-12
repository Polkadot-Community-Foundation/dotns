// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {StoreFactory} from "../../../contracts/store/StoreFactory.sol";
import {ILabelStore} from "../../../contracts/store/ILabelStore.sol";
import {IUserStore} from "../../../contracts/store/IUserStore.sol";
import {DotnsProtocolRegistry} from "../../../contracts/registry/DotnsProtocolRegistry.sol";

contract StoreInvariantHandler is Test {
    StoreFactory public immutable FACTORY;
    DotnsProtocolRegistry public immutable REGISTRY;
    address public immutable OWNER;
    address public immutable PROTOCOL_WRITER;

    address[] public users;
    address[] public labelStores;
    address[] public userStores;

    mapping(address store => bytes32[]) internal _writtenLabelhashes;
    mapping(address store => mapping(bytes32 labelhash => bool)) public sawLocked;
    mapping(address store => mapping(bytes32 labelhash => string)) public frozenLabel;

    mapping(address store => address) public userStoreOwnerOf;

    constructor(
        StoreFactory _factory,
        DotnsProtocolRegistry _registry,
        address _owner,
        address _protocolWriter
    ) {
        FACTORY = _factory;
        REGISTRY = _registry;
        OWNER = _owner;
        PROTOCOL_WRITER = _protocolWriter;
    }

    function addUser(uint8 seed) external {
        address user = address(uint160(uint256(keccak256(abi.encode("user", seed)))));
        if (user == address(0)) return;
        users.push(user);
    }

    function deployLabelStore(uint8 userSeed) external {
        if (users.length == 0) return;
        address user = users[userSeed % users.length];
        if (FACTORY.getLabelStore(user) != address(0)) return;

        vm.prank(OWNER);
        address store = FACTORY.deployLabelStoreFor(user);
        labelStores.push(store);
    }

    function storeLabel(uint8 storeSeed, bytes32 labelhash, string calldata label) external {
        if (labelStores.length == 0) return;
        if (labelhash == bytes32(0)) return;
        address store = labelStores[storeSeed % labelStores.length];
        if (ILabelStore(store).isLocked(labelhash)) return;

        vm.prank(PROTOCOL_WRITER);
        ILabelStore(store).storeLabel(labelhash, label);

        _writtenLabelhashes[store].push(labelhash);
        sawLocked[store][labelhash] = true;
        frozenLabel[store][labelhash] = label;
    }

    function claimUserStore(uint8 userSeed) external {
        if (users.length == 0) return;
        address user = users[userSeed % users.length];
        if (FACTORY.getUserStore(user) != address(0)) return;

        vm.prank(user);
        address store = FACTORY.claimUserStore();
        userStores.push(store);
        userStoreOwnerOf[store] = user;
    }

    function setValue(uint8 storeSeed, bytes32 key, bytes calldata value) external {
        if (userStores.length == 0) return;
        if (key == bytes32(0)) return;
        address store = userStores[storeSeed % userStores.length];
        address user = userStoreOwnerOf[store];

        vm.prank(user);
        IUserStore(store).setValue(key, value);
    }

    function labelStoreCount() external view returns (uint256) {
        return labelStores.length;
    }

    function userStoreCount() external view returns (uint256) {
        return userStores.length;
    }

    function userCount() external view returns (uint256) {
        return users.length;
    }

    function writtenLabelhashCount(address store) external view returns (uint256) {
        return _writtenLabelhashes[store].length;
    }

    function writtenLabelhashAt(address store, uint256 index) external view returns (bytes32) {
        return _writtenLabelhashes[store][index];
    }
}
