// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DotnsPopController} from "../../../contracts/registrars/DotnsPopController.sol";

/// @title PopControllerHandler
/// @notice Bounded random-action handler for {DotnsPopController} invariant tests.
/// @dev Cycles through a fixed actor set and a fixed base-label set so the fuzzer
///      explores combinations deterministically. Tracks every labelhash that has
///      hosted a reservation so invariants can iterate over the queues that exist.
contract PopControllerHandler is Test {
    DotnsPopController public immutable controller;
    address public immutable gateway;
    uint16 public constant MAX_QUEUE = 64;

    address[] public actors;
    string[] public baseLabels;
    bytes32[] public reservedLabelsSeen;
    mapping(bytes32 labelhash => bool) internal _tracked;
    mapping(address actor => uint64 suffix) internal _liteSuffix;

    constructor(DotnsPopController controller_, address gateway_, address[] memory actors_) {
        controller = controller_;
        gateway = gateway_;
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

    function baseLabelAt(uint256 idx) external view returns (string memory) {
        return baseLabels[idx];
    }

    // Reserves a lite label for an actor, optionally enqueuing on a base label.
    // Swallows known-good reverts (`QueueFull`, `AlreadyReserved`, registrar
    // ERC721 collision) so the invariant runner keeps exploring. The suffix
    // counter starts at 10 so `vm.toString` always yields a two-or-more-digit
    // string satisfying the PoP `NAME.XX` format without a padding helper.
    function reserve(uint256 actorIdx, uint256 baseIdx, bool attachReservation) external {
        address actor = _actor(actorIdx);
        _liteSuffix[actor]++;
        uint256 suffixValue = 10 + uint256(_liteSuffix[actor]);
        string memory liteLabel = string.concat(
            "a", vm.toString(uint256(uint160(actor)) % 1000), ".", vm.toString(suffixValue)
        );
        string memory reservedBase = attachReservation ? _baseLabel(baseIdx) : "";

        vm.prank(gateway);
        try controller.reserveBaseName(liteLabel, actor, "", reservedBase) {
            if (attachReservation) _track(keccak256(bytes(_baseLabel(baseIdx))));
        } catch {}
    }

    // Caller-sovereign: drops whichever reservation the actor currently holds.
    function relinquish(uint256 actorIdx) external {
        vm.prank(_actor(actorIdx));
        try controller.relinquishReservation() {} catch {}
    }

    // Permissionless: advances the head of a tracked queue past expired entries.
    function expire(uint256 baseIdx) external {
        try controller.expireReservation(_baseLabel(baseIdx)) {} catch {}
    }

    // Advances block timestamp to exercise expiry paths.
    function warp(uint256 secondsForward) external {
        vm.warp(block.timestamp + (secondsForward % (30 days)));
    }

    function _actor(uint256 idx) internal view returns (address) {
        return actors[idx % actors.length];
    }

    function _baseLabel(uint256 idx) internal view returns (string memory) {
        return baseLabels[idx % baseLabels.length];
    }

    function _track(bytes32 labelhash) internal {
        if (!_tracked[labelhash]) {
            _tracked[labelhash] = true;
            reservedLabelsSeen.push(labelhash);
        }
    }
}
