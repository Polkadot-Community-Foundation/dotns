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

import {IDotnsPopResolver} from "./IDotnsPopResolver.sol";
import {IDotnsProtocolRegistry} from "../registry/IDotnsProtocolRegistry.sol";
import {DotnsProtocolRegistry} from "../registry/DotnsProtocolRegistry.sol";

/// @title DotnsPopResolver
/// @notice Per-node resolver holding records produced by the PoP username flow.
/// @dev Authorised writer is the `POP_CONTROLLER` address on the protocol registry;
///      rotating the PoP controller requires no resolver upgrade.
/// @custom:security-contact admin@parity.io
contract DotnsPopResolver is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC165Upgradeable,
    IDotnsPopResolver
{
    /// @notice Protocol-level address registry used to resolve the authorised writer.
    IDotnsProtocolRegistry public protocolRegistry;

    /// @notice Stored chat-key bytes keyed by node.
    mapping(bytes32 node => bytes chatKey) private _chatKeys;

    /// @notice Stored lite-person labelhash keyed by full-person node.
    mapping(bytes32 fullNode => bytes32 liteLabelhash) private _liteLinks;

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[50] private __gap;

    /// @notice Restricts writes to the address registered as `POP_CONTROLLER`.
    modifier onlyPopController() {
        _onlyPopController();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the PoP resolver.
    /// @param registry Protocol-level address registry used for writer resolution.
    function initialize(IDotnsProtocolRegistry registry) external initializer {
        __Ownable_init(msg.sender);
        __ERC165_init();
        protocolRegistry = registry;
    }

    /// @inheritdoc IDotnsPopResolver
    function setChatKey(
        bytes32 node,
        bytes calldata chatKeyBytes
    )
        external
        override
        onlyPopController
    {
        _chatKeys[node] = chatKeyBytes;
        emit ChatKeyUpdated(node, chatKeyBytes);
    }

    /// @inheritdoc IDotnsPopResolver
    function setLiteLink(
        bytes32 fullNode,
        bytes32 liteLabelhash
    )
        external
        override
        onlyPopController
    {
        _liteLinks[fullNode] = liteLabelhash;
        emit LiteLinkUpdated(fullNode, liteLabelhash);
    }

    /// @inheritdoc IDotnsPopResolver
    function chatKey(bytes32 node) external view override returns (bytes memory) {
        return _chatKeys[node];
    }

    /// @inheritdoc IDotnsPopResolver
    function liteLink(bytes32 fullNode) external view override returns (bytes32) {
        return _liteLinks[fullNode];
    }

    /// @notice Returns implementation version.
    /// @return versionString Current version string.
    function version() external pure virtual returns (string memory versionString) {
        versionString = "1.0.0";
    }

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return
            interfaceId == type(IDotnsPopResolver).interfaceId
                || super.supportsInterface(interfaceId);
    }

    /// @notice Internal check enforcing PoP-controller-only access.
    function _onlyPopController() internal view {
        address popController =
            protocolRegistry.get(DotnsProtocolRegistry(address(protocolRegistry)).POP_CONTROLLER());
        require(msg.sender == popController, NotPopController(msg.sender));
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
