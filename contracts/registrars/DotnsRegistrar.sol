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

/// @title Dotns Registrar
/// @notice ERC721-backed registrar implementing permanent name ownership.
/// @dev This contract is deliberately policy-free.
///      Transfers are supported to allow ownership changes without registry hooks.
///
/// @dev Store writes on transfer:
///      When an ERC721 name token is transferred between non-zero addresses (i.e. not mint or burn),
///      the registrar reads the label from the sender's Store and writes it to the recipient's Store.
///      This ensures the recipient's Store contains a record of every name they have received.
///      Stores are immutable (locked by DotNS controllers), so the sender's entry is not removed.
///
/// @custom:security-contact admin@parity.io
contract DotnsRegistrar is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC721Upgradeable,
    IDotnsRegistrar
{
    using StoreUtils for IStoreFactory;

    /// @notice Mapping of authorised controller addresses.
    /// @dev Controllers may call `register`.
    mapping(IDotnsRegistrarController controller => bool exists) public controllers;

    /// @notice Protocol-level address registry for all DotNS contracts.
    /// @dev Used to resolve sibling contract addresses (store factory, controller, registry)
    ///      without storing individual references.
    IDotnsProtocolRegistry public protocolRegistry;

    /// @notice Mapping from token ID to the labelhash stored at registration time.
    /// @dev Required because the token ID is `uint256(namehash(DOT_NODE, labelhash))`, a one-way
    ///      derivation that cannot be reversed. The labelhash is needed at transfer time to compute
    ///      the Store key and read the label string from the sender's Store.
    mapping(uint256 tokenId => bytes32 labelhash) private _labelhashes;

    /// @notice Well-known protocol registry key for the store factory.
    /// casting to 'bytes32' is safe because the string fits in 32 bytes.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant KEY_STORE_FACTORY = bytes32("storeFactory");

    /// @notice Well-known protocol registry key for the registrar controller.
    /// casting to 'bytes32' is safe because the string fits in 32 bytes.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant KEY_CONTROLLER = bytes32("controller");

    /// @notice Well-known protocol registry key for the forward registry.
    /// casting to 'bytes32' is safe because the string fits in 32 bytes.
    /// forge-lint: disable-next-line(unsafe-typecast)
    bytes32 internal constant KEY_REGISTRY = bytes32("registry");

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[48] private __gap;

    /// @notice Restricts function access to authorised controllers.
    modifier onlyController() {
        _onlyController();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the registrar.
    /// @dev Uses OpenZeppelin upgradeable initializers.
    /// @param name ERC721 token name.
    /// @param symbol ERC721 token symbol.
    function initialize(string calldata name, string calldata symbol) external initializer {
        __Ownable_init(msg.sender);
        __ERC721_init(name, symbol);
    }

    /// @inheritdoc IDotnsRegistrar
    function updateProtocolRegistry(IDotnsProtocolRegistry registry) external override onlyOwner {
        protocolRegistry = registry;
        emit ProtocolRegistryUpdated(registry);
    }

    /// @inheritdoc IDotnsRegistrar
    function addController(IDotnsRegistrarController controller) external onlyOwner {
        controllers[controller] = true;
        emit ControllerAdded(controller);
    }

    /// @inheritdoc IDotnsRegistrar
    function removeController(IDotnsRegistrarController controller) external onlyOwner {
        controllers[controller] = false;
        emit ControllerRemoved(controller);
    }

    /// @inheritdoc IDotnsRegistrar
    function available(uint256 id) public view override returns (bool isAvailable) {
        return !_exists(id);
    }

    /// @inheritdoc IDotnsRegistrar
    function register(
        uint256 id,
        address owner,
        bytes32 labelhash
    )
        external
        override
        onlyController
    {
        require(available(id), NameNotAvailable(id));
        _labelhashes[id] = labelhash;
        _mint(owner, id);
        emit NameRegistered(id, owner);
    }

    /// @notice Returns implementation version.
    /// @return versionString Current version string.
    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.1.0";
    }

    /// @notice Checks whether a token ID exists.
    /// @param tokenId Token identifier.
    /// @return exists True if the token exists.
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    /// @notice Internal function to check for controller access.
    function _onlyController() internal view {
        require(controllers[IDotnsRegistrarController(msg.sender)], NotController(msg.sender));
    }

    /// @inheritdoc ERC721Upgradeable
    /// @dev Additionally writes the transferred label to the recipient's Store when both `from`
    ///      and `to` are non-zero and a protocol registry has been configured.
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
            bytes32 labelhash = _labelhashes[tokenId];
            if (labelhash != bytes32(0)) {
                _writeToRecipientStore(from, to, labelhash);
            }
        }

        return from;
    }

    /// @notice Reads the label from the sender's Store and writes it to the recipient's Store.
    /// @dev Silently returns (no revert) if the store factory is not set, the sender has no store,
    ///      or the label cannot be read. This ensures transfers never fail due to missing stores.
    /// @param from Address of the current token owner (sender).
    /// @param to Address of the new token owner (recipient).
    /// @param labelhash keccak256 of the label, used to compute the Store key.
    function _writeToRecipientStore(address from, address to, bytes32 labelhash) internal {
        IStoreFactory factory = IStoreFactory(protocolRegistry.get(KEY_STORE_FACTORY));
        if (address(factory) == address(0)) return;

        bytes32 storeKey = StoreUtils.storeKey(labelhash);

        address fromStoreAddr = address(factory.getDeployedStore(from));
        if (fromStoreAddr == address(0)) return;

        Store fromStore = Store(fromStoreAddr);
        string memory label = fromStore.getValueFor(from, storeKey);
        if (bytes(label).length == 0) return;

        address[] memory storeControllers = new address[](3);
        storeControllers[0] = address(this);
        storeControllers[1] = protocolRegistry.get(KEY_CONTROLLER);
        storeControllers[2] = protocolRegistry.get(KEY_REGISTRY);

        Store toStore = factory.getOrCreateStore(storeControllers, to);

        if (bytes(toStore.getValueFor(to, storeKey)).length == 0) {
            toStore.setValueFor(to, storeKey, label);
        }
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
