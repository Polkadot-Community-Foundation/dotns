// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IDotnsController} from "../../contracts/registrars/IDotnsController.sol";
import {IDotnsRegistrar} from "../../contracts/registrars/IDotnsRegistrar.sol";
import {IDotnsRegistry} from "../../contracts/registry/IDotnsRegistry.sol";
import {IDotnsProtocolRegistry} from "../../contracts/registry/IDotnsProtocolRegistry.sol";
import {DotnsConstants} from "../../contracts/utils/DotnsConstants.sol";
import {LabelUtils} from "../../contracts/utils/LabelUtils.sol";

/// @title DotnsMigrationController
/// @notice One-off registrar controller that re-mints names recorded on a previous DotNS
///         deployment onto a fresh one, to their existing holders, keeping their token ids.
/// @dev Deployment-time tool, not part of the protocol surface. The registrar owner adds it
///      with `addController`, the migration owner replays the snapshot in batches, and the
///      registrar owner removes it again. Each entry is minted through the registrar's
///      controller path exactly as a public registration would be, then the registry node is
///      bound to the holder; the registry resets the node's resolver to the default on that
///      call, so resolver binding and records are replayed afterwards by the holders, who are
///      the only parties the resolvers authorise. Token ids are `uint256(namehash)` under the
///      network TLD in both the old and the new deployment, so an entry's id is recomputed
///      from its label and must match: a snapshot taken under a different TLD cannot be
///      replayed here by accident.
/// @custom:security-contact admin@polkadotcommunity.foundation
contract DotnsMigrationController is IDotnsController, Ownable {
    using LabelUtils for string;

    /// @notice One name to re-mint.
    /// @param id Token id on the previous deployment, `uint256(namehash)`.
    /// @param holder Address that held the name on the previous deployment.
    /// @param label Bare label without the TLD.
    struct Entry {
        uint256 id;
        address holder;
        string label;
    }

    /// @notice Thrown when an entry's id is not the namehash of its label under this TLD.
    error IdMismatch(uint256 id, string label);
    /// @notice Thrown when an entry names the zero address as holder.
    error ZeroHolder(uint256 id);

    /// @notice Emitted for every name re-minted.
    event NameMigrated(uint256 indexed id, address indexed holder, string label);

    /// @notice Protocol registry of the target deployment.
    IDotnsProtocolRegistry public immutable protocolRegistry;

    constructor(IDotnsProtocolRegistry protocolRegistry_, address owner_) Ownable(owner_) {
        protocolRegistry = protocolRegistry_;
    }

    /// @notice Re-mints `entries` to their holders and binds each registry node.
    /// @dev Reverts on the first entry the registrar refuses (already minted, invalid label),
    ///      so a batch is all-or-nothing and can be resumed by dropping the entries that
    ///      already landed. Requires this contract to be a registrar controller.
    function migrate(Entry[] calldata entries) external onlyOwner {
        IDotnsRegistrar registrar = IDotnsRegistrar(protocolRegistry.get(DotnsConstants.REGISTRAR));
        IDotnsRegistry registry = IDotnsRegistry(protocolRegistry.get(DotnsConstants.REGISTRY));
        bytes32 tldNode = protocolRegistry.tldNode();
        for (uint256 i = 0; i < entries.length; ++i) {
            Entry calldata entry = entries[i];
            require(entry.holder != address(0), ZeroHolder(entry.id));
            bytes32 node = LabelUtils.namehashUnder(tldNode, entry.label.labelhash());
            require(uint256(node) == entry.id, IdMismatch(entry.id, entry.label));
            registrar.register(entry.id, entry.holder, entry.label);
            registry.setOwner(node, entry.holder);
            emit NameMigrated(entry.id, entry.holder, entry.label);
        }
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IDotnsController).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
}
