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
///      the registrar writes the label to the recipient's Store using the label stored in `_labels`.
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

    /// @notice DEPRECATED as of v1.2.0: Previously stored labelhashes per token ID.
    /// @dev Retained for UUPS storage layout compatibility. No longer written to.
    ///      The labelhash is now derived on-the-fly from `_labels[tokenId]` via `keccak256(bytes(label))`.
    ///      REMOVE this mapping when deploying to a new environment (fresh deploy, not upgrade).
    /// @custom:oz-retyped-from mapping(uint256 => bytes32)
    mapping(uint256 tokenId => bytes32 labelhash) private _labelhashes;

    /// @notice Human-readable label per token ID. Single source of truth for name data.
    /// @dev Stored at registration time. Used during transfers to write the label directly
    ///      to the recipient's Store without needing to read from the sender's Store.
    ///      The labelhash can always be derived as `keccak256(bytes(label))`.
    mapping(uint256 tokenId => string label) private _labels;

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
    uint256[47] private __gap;

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

    /// @notice Returns implementation version.
    /// @return versionString Current version string.
    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.2.0";
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
            string memory label = _labels[tokenId];
            if (bytes(label).length > 0) {
                bytes32 labelhash = keccak256(bytes(label));
                _writeToRecipientStore(to, labelhash, label);
            }
        }

        return from;
    }

    /// @notice Writes the label to the recipient's Store during an ERC721 transfer.
    /// @dev Silently returns (no revert) if the store factory is not set.
    ///      This ensures transfers never fail due to missing stores.
    /// @param to Address of the new token owner (recipient).
    /// @param labelhash keccak256 of the label, used to compute the Store key.
    /// @param label The human-readable label string to write.
    function _writeToRecipientStore(address to, bytes32 labelhash, string memory label) internal {
        IStoreFactory factory = IStoreFactory(protocolRegistry.get(KEY_STORE_FACTORY));
        if (address(factory) == address(0)) return;

        bytes32 storeKey = StoreUtils.storeKey(labelhash);

        address[] memory storeControllers = new address[](3);
        storeControllers[0] = address(this);
        storeControllers[1] = protocolRegistry.get(KEY_CONTROLLER);
        storeControllers[2] = protocolRegistry.get(KEY_REGISTRY);

        Store toStore = factory.getOrCreateStore(storeControllers, to);

        if (bytes(toStore.getValueFor(to, storeKey)).length == 0) {
            toStore.setValueFor(to, storeKey, string.concat(label, ".dot"));
        }
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
