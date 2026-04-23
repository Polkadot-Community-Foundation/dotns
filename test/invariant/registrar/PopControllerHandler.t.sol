// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {
    DotnsPopController,
    IDotnsPopController
} from "../../../contracts/registrars/DotnsPopController.sol";
import {DotnsConstants} from "../../../contracts/utils/DotnsConstants.sol";
import {LabelUtils} from "../../../contracts/utils/LabelUtils.sol";

/// @title PopControllerHandler
/// @notice Bounded random-action handler for {DotnsPopController} invariant tests.
/// @dev Cycles through an actor set and a fixed base-label set so the fuzzer
///      explores combinations deterministically. Tracks every labelhash that has
///      hosted a reservation, every minted lite token, and every successful
///      claim so invariants can iterate over just what exists.
contract PopControllerHandler is Test {
    DotnsPopController public immutable CONTROLLER;
    address public immutable GATEWAY;
    uint16 public constant MAX_QUEUE = 64;

    address[] public actors;
    string[] public baseLabels;
    bytes32[] public reservedLabelsSeen;
    mapping(bytes32 labelhash => bool) internal _tracked;
    mapping(address actor => uint64 suffix) internal _liteSuffix;

    // Lite tokens minted through the handler. Every successful `reserve` push.
    // Used by the labelOf-non-empty invariant to enumerate the token space
    // without scanning the full uint256 id range.
    uint256[] public mintedLiteTokenIds;

    // Full nodes minted through successful claims, captured alongside the lite
    // labelhash they were linked against. Used by the fullClaim/liteLink
    // inverse invariant: for each entry, fullClaim(liteHash) == node.
    bytes32[] public claimedFullNodes;
    bytes32[] public claimedLiteLabelhashes;

    constructor(DotnsPopController controller_, address gateway_, address[] memory actors_) {
        CONTROLLER = controller_;
        GATEWAY = gateway_;
        actors = actors_;
        baseLabels.push("alicebob");
        baseLabels.push("wonderland01");
        baseLabels.push("carolcarol");
    }

    function actorsCount() external view returns (uint256) {
        return actors.length;
    }

    function reservedLabelsSeenCount() external view returns (uint256) {
        return reservedLabelsSeen.length;
    }

    function baseLabelCount() external view returns (uint256) {
        return baseLabels.length;
    }

    function baseLabelAt(uint256 index) external view returns (string memory) {
        return baseLabels[index];
    }

    function mintedLiteTokenCount() external view returns (uint256) {
        return mintedLiteTokenIds.length;
    }

    function claimedCount() external view returns (uint256) {
        return claimedFullNodes.length;
    }

    function reserve(uint256 actorIndex, uint256 baseIndex, bool attachReservation) external {
        // Reserves a lite label for an actor, optionally enqueuing on a base
        // label. Swallows known-good reverts (QueueFull, AlreadyReserved,
        // ERC721 collision) so the runner keeps exploring. Suffix starts at 10
        // so vm.toString always yields >=2 digits matching the NAMEXX format.
        address actor = _actor(actorIndex);
        _liteSuffix[actor]++;
        uint256 suffixValue = 10 + uint256(_liteSuffix[actor]);
        string memory liteLabel = string.concat(
            "a", vm.toString(uint256(uint160(actor)) % 1000), vm.toString(suffixValue)
        );
        string memory reservedBase = attachReservation ? _baseLabel(baseIndex) : "";

        vm.prank(GATEWAY);
        try CONTROLLER.reserveBaseName(liteLabel, actor, "", reservedBase) {
            if (attachReservation) _track(keccak256(bytes(reservedBase)));
            bytes32 node = LabelUtils.namehashUnder(
                DotnsConstants.DOT_NODE, LabelUtils.labelhashMemory(liteLabel)
            );
            mintedLiteTokenIds.push(uint256(node));
        } catch {}
    }

    function claim(uint256 actorIndex, uint256 baseIndex) external {
        // Drives the claim path end-to-end when the actor happens to hold the
        // live head of the queue for the picked base label. Missing preconditions
        // (wrong actor, expired head, empty queue) surface as a revert and are
        // swallowed so the runner keeps exploring. Captures the (liteHash,
        // fullNode) pair behind every successful claim so the inverse-index
        // invariant can replay them.
        address actor = _actor(actorIndex);
        string memory baseLabel = _baseLabel(baseIndex);

        IDotnsPopController.UserReservation memory reservation = CONTROLLER.userReservation(actor);
        if (reservation.labelhash == bytes32(0)) return;
        if (reservation.labelhash != keccak256(bytes(baseLabel))) return;

        _liteSuffix[actor]++;
        uint256 suffixValue = 10 + uint256(_liteSuffix[actor]);
        string memory liteLabel = string.concat(
            "c", vm.toString(uint256(uint160(actor)) % 1000), vm.toString(suffixValue)
        );

        vm.prank(GATEWAY);
        try CONTROLLER.reserveBaseName(liteLabel, actor, "", "") {
            IDotnsPopController.Link memory link = IDotnsPopController.Link({
                kind: IDotnsPopController.LinkKind.LiteUsername, liteLabel: liteLabel, chatKey: ""
            });

            vm.prank(GATEWAY);
            try CONTROLLER.registerBaseName(baseLabel, actor, link) {
                bytes32 liteLabelhash = LabelUtils.labelhashMemory(liteLabel);
                bytes32 fullNode = LabelUtils.namehashUnder(
                    DotnsConstants.DOT_NODE, LabelUtils.labelhashMemory(baseLabel)
                );
                claimedLiteLabelhashes.push(liteLabelhash);
                claimedFullNodes.push(fullNode);
                mintedLiteTokenIds.push(
                    uint256(LabelUtils.namehashUnder(DotnsConstants.DOT_NODE, liteLabelhash))
                );
                mintedLiteTokenIds.push(uint256(fullNode));
            } catch {}
        } catch {}
    }

    function relinquish(uint256 actorIndex) external {
        // Caller-sovereign: drops whichever reservation the actor holds.
        vm.prank(_actor(actorIndex));
        try CONTROLLER.relinquishReservation() {} catch {}
    }

    function expire(uint256 baseIndex) external {
        // Permissionless: advances the head past expired entries on one queue.
        try CONTROLLER.expireReservation(_baseLabel(baseIndex)) {} catch {}
    }

    function warp(uint256 secondsForward) external {
        // Exercises expiry paths. Bounded so state doesn't drift off a cliff.
        vm.warp(block.timestamp + (secondsForward % (30 days)));
    }

    function _actor(uint256 index) internal view returns (address) {
        return actors[index % actors.length];
    }

    function _baseLabel(uint256 index) internal view returns (string memory) {
        return baseLabels[index % baseLabels.length];
    }

    function _track(bytes32 labelhash) internal {
        if (!_tracked[labelhash]) {
            _tracked[labelhash] = true;
            reservedLabelsSeen.push(labelhash);
        }
    }
}
