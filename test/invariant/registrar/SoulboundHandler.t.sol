// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {DotnsRegistrar} from "../../../contracts/registrars/DotnsRegistrar.sol";

/// @title Soulbound Handler
/// @notice Bounded random-action handler that mints PoP-gateway (soulbound) names and throws every
///         transfer overload at them, so the invariant suite can assert their ownership never
///         moves across a reachable action sequence.
/// @dev Mints are driven by pranking as the address registered under `POP_CONTROLLER`, which is the
///      exact provenance the registrar checks, so the minted tokens are genuinely soulbound. The
///      handler never asserts inline: a transfer that wrongly succeeds leaves observable ownership
///      drift for the invariant view to catch, and expected reverts are swallowed so the campaign
///      keeps a low reject rate.
contract SoulboundHandler is Test {
    /// @notice The base registrar under test.
    DotnsRegistrar public immutable REGISTRAR;

    /// @notice Address registered under `POP_CONTROLLER`; pranked as the soulbound minter.
    address public immutable POP_CONTROLLER_ADDR;

    /// @notice TLD node the suite is rooted at, used to derive token ids the way the protocol does.
    bytes32 private immutable TLD_NODE;

    /// @notice Actor pool the handler mints to and transfers between.
    address[] internal actors;

    /// @notice Every soulbound token id minted through the handler.
    uint256[] internal soulboundIds;

    /// @notice Owner recorded at mint for each soulbound id. Ghost expectation for the invariant.
    mapping(uint256 tokenId => address owner) public soulboundOwner;

    /// @notice Count of soulbound tokens minted, exposed for the non-vacuity guard.
    uint256 public soulboundCount;

    /// @notice Number of transfer attempts driven against soulbound tokens, exposed so the suite
    /// can prove the campaign actually exercised transfers rather than only minting.
    uint256 public transferAttemptCount;

    /// @notice Trips true if any transfer of a soulbound token ever succeeds. A correct gate keeps
    /// this false forever, independent of fees, receivers, or escrow configuration.
    bool public sawSuccessfulTransfer;

    /// @notice Monotonic label suffix so every mint targets a fresh id.
    uint64 internal nonce;

    constructor(DotnsRegistrar registrar, address popController, bytes32 tldNode) {
        REGISTRAR = registrar;
        POP_CONTROLLER_ADDR = popController;
        TLD_NODE = tldNode;
    }

    /// @notice Adds an actor to the pool.
    function addActor(address actor) external {
        actors.push(actor);
    }

    /// @notice Mints one soulbound name to a pool actor. Callable from the suite to guarantee at
    /// least one soulbound token exists before fuzzing.
    function mintSoulbound(uint256 actorSeed) public {
        if (actors.length == 0) return;
        address actor = actors[actorSeed % actors.length];
        uint256 tokenId = _freshTokenId();

        vm.prank(POP_CONTROLLER_ADDR);
        REGISTRAR.register(tokenId, actor, "");

        soulboundIds.push(tokenId);
        soulboundOwner[tokenId] = actor;
        ++soulboundCount;
    }

    /// @notice Attempts to move a soulbound token through one of the transfer overloads, including
    /// an operator-driven move, and swallows the expected revert. Any wrongful success is left for
    /// the invariant view to detect as ownership drift.
    function attemptSoulboundTransfer(uint256 tokenSeed, uint256 toSeed, uint256 variant) external {
        uint256 count = soulboundIds.length;
        if (count == 0) return;

        uint256 tokenId = soulboundIds[tokenSeed % count];
        address from = REGISTRAR.ownerOf(tokenId);
        address to = actors[toSeed % actors.length];
        if (to == from) return;

        ++transferAttemptCount;
        variant %= 4;
        if (variant == 3) {
            address operator = actors[(toSeed + 1) % actors.length];
            vm.prank(from);
            REGISTRAR.setApprovalForAll(operator, true);
            vm.prank(operator);
            try REGISTRAR.transferFrom(from, to, tokenId) {
                sawSuccessfulTransfer = true;
            } catch {}
            return;
        }

        vm.startPrank(from);
        if (variant == 0) {
            try REGISTRAR.transferFrom(from, to, tokenId) {
                sawSuccessfulTransfer = true;
            } catch {}
        } else if (variant == 1) {
            try REGISTRAR.safeTransferFrom(from, to, tokenId) {
                sawSuccessfulTransfer = true;
            } catch {}
        } else {
            try REGISTRAR.safeTransferFrom(from, to, tokenId, "") {
                sawSuccessfulTransfer = true;
            } catch {}
        }
        vm.stopPrank();
    }

    /// @notice Returns every soulbound id minted, for the invariant view to iterate.
    function soulboundIdsList() external view returns (uint256[] memory ids) {
        ids = soulboundIds;
    }

    /// @notice Derives a fresh token id as `namehash(tldNode, keccak256(label))` for a unique
    /// label.
    function _freshTokenId() internal returns (uint256 tokenId) {
        ++nonce;
        bytes32 labelhash = keccak256(bytes(string.concat("sb", vm.toString(nonce))));
        tokenId = uint256(keccak256(abi.encodePacked(TLD_NODE, labelhash)));
    }
}
