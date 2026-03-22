// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    ERC721Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

import {IDotnsRegistrar} from "./IDotnsRegistrar.sol";
import {IDotnsRegistrarController} from "./IDotnsRegistrarController.sol";
import {IDotnsProtocolRegistry} from "../registry/IDotnsProtocolRegistry.sol";
import {Store} from "../store/Store.sol";
import {IStoreFactory} from "../store/IStoreFactory.sol";
import {StoreUtils} from "../utils/StoreUtils.sol";
import {StringUtils} from "../utils/StringUtils.sol";

contract DotnsRegistrarOld is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC721Upgradeable,
    IDotnsRegistrar
{
    using StoreUtils for IStoreFactory;
    using StringUtils for *;

    mapping(IDotnsRegistrarController controller => bool exists) public controllers;
    IDotnsProtocolRegistry public protocolRegistry;

    /// @custom:oz-retyped-from mapping(uint256 => bytes32)
    mapping(uint256 tokenId => bytes32 labelhash) private _labelhashes;
    mapping(uint256 tokenId => string label) private _labels;

    bytes32 private constant DOT_NODE =
        0x3fce7d1364a893e213bc4212792b517ffc88f5b13b86c8ef9c8d390c3a1370ce;

    // forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant KEY_STORE_FACTORY = bytes32("storeFactory");
    // forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant KEY_CONTROLLER = bytes32("controller");
    // forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant KEY_REGISTRY = bytes32("registry");

    uint256[47] private __gap;

    modifier onlyController() {
        _onlyController();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string calldata name, string calldata symbol) external initializer {
        __Ownable_init(msg.sender);
        __ERC721_init(name, symbol);
    }

    function updateProtocolRegistry(IDotnsProtocolRegistry registry) external override onlyOwner {
        protocolRegistry = registry;
        emit ProtocolRegistryUpdated(registry);
    }

    function addController(IDotnsRegistrarController controller) external onlyOwner {
        controllers[controller] = true;
        emit ControllerAdded(controller);
    }

    function removeController(IDotnsRegistrarController controller) external onlyOwner {
        controllers[controller] = false;
        emit ControllerRemoved(controller);
    }

    function available(uint256 id) public view override returns (bool isAvailable) {
        return !_exists(id);
    }

    function register(
        uint256 id,
        address owner,
        string calldata label
    )
        external
        override
        onlyController
    {
        require(available(id), NameNotAvailable(id));
        _labels[id] = label;
        _mint(owner, id);
        emit NameRegistered(id, owner);
    }

    function syncLabel(uint256 tokenId, string calldata label) external override {
        require(_exists(tokenId), NameNotAvailable(tokenId));
        require(ownerOf(tokenId) == msg.sender, NotTokenOwner(msg.sender, tokenId));
        require(bytes(_labels[tokenId]).length == 0, LabelAlreadySet(tokenId));
        require(label.isSingleLabel(), InvalidLabel());

        bytes32 labelhash;
        bytes32 node;
        assembly ("memory-safe") {
            let pointer := mload(0x40)
            let len := label.length
            calldatacopy(pointer, label.offset, len)
            labelhash := keccak256(pointer, len)
            mstore(pointer, DOT_NODE)
            mstore(add(pointer, 0x20), labelhash)
            node := keccak256(pointer, 0x40)
        }
        require(uint256(node) == tokenId, LabelMismatch(tokenId));

        _labels[tokenId] = label;
        emit LabelSynced(tokenId, label);
    }

    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.2.0";
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    function _onlyController() internal view {
        require(controllers[IDotnsRegistrarController(msg.sender)], NotController(msg.sender));
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    )
        internal
        override
        returns (address from)
    {
        from = super._update(to, tokenId, auth);

        if (from != address(0) && to != address(0) && address(protocolRegistry) != address(0)) {
            _syncRecipientStore(to, tokenId);
        }

        return from;
    }

    function _syncRecipientStore(address to, uint256 tokenId) internal {
        IStoreFactory factory = IStoreFactory(protocolRegistry.get(KEY_STORE_FACTORY));
        if (address(factory) == address(0)) return;

        Store toStore = Store(address(factory.getDeployedStore(to)));

        if (address(toStore) == address(0)) {
            address[] memory storeControllers = new address[](3);
            storeControllers[0] = address(this);
            storeControllers[1] = protocolRegistry.get(KEY_CONTROLLER);
            storeControllers[2] = protocolRegistry.get(KEY_REGISTRY);

            toStore = factory.getOrCreateStore(storeControllers, to);
        }

        string memory label = _labels[tokenId];
        if (bytes(label).length > 0) {
            bytes32 labelhash;
            assembly ("memory-safe") {
                labelhash := keccak256(add(label, 0x20), mload(label))
            }
            bytes32 storeKey = StoreUtils.storeKey(labelhash);
            if (bytes(toStore.getValueFor(to, storeKey)).length == 0) {
                toStore.setValueFor(to, storeKey, string.concat(label, ".dot"));
            }
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
