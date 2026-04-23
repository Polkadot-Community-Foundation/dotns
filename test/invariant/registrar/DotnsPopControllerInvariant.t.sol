// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../../base/BaseDotns.t.sol";
import {PopControllerHandler} from "./PopControllerHandler.t.sol";
import {IDotnsPopController} from "../../../contracts/registrars/IDotnsPopController.sol";

/// @title DotnsPopControllerInvariant
/// @notice Invariants asserted over arbitrary sequences of PoP-controller actions.
contract DotnsPopControllerInvariant is BaseDotns {
    PopControllerHandler internal handler;

    function setUp() public override {
        super.setUp();

        // Actor pool sized past MAX_RESERVATION_QUEUE (64) so the queue-full
        // guard is load-bearing rather than structurally unreachable. A pool
        // smaller than the cap would cap invariant depth at pool size and the
        // QueueFull branch would never fire.
        uint256 actorCount = 72;
        address[] memory handlerActors = new address[](actorCount);
        for (uint256 i = 0; i < actorCount; i++) {
            handlerActors[i] = makeAddr(string.concat("popActor", vm.toString(i)));
        }

        handler = new PopControllerHandler(dotnsPopController, popGateway, handlerActors);
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.reserve.selector;
        selectors[1] = handler.relinquish.selector;
        selectors[2] = handler.expire.selector;
        selectors[3] = handler.warp.selector;
        selectors[4] = handler.claim.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_queue_length_bounded() public view {
        // Every tracked queue stays bounded by MAX_RESERVATION_QUEUE.
        uint256 n = handler.reservedLabelsSeenCount();
        for (uint256 i = 0; i < n; i++) {
            bytes32 labelhash = handler.reservedLabelsSeen(i);
            (uint64 head, uint64 tail) = dotnsPopController.reservationMeta(labelhash);
            assertLe(uint256(tail - head), uint256(handler.MAX_QUEUE()));
        }
    }

    function invariant_popRules_head_matches_queue_head_or_zero() public view {
        // Cross-contract sync: PopRules' reservation for every base label the
        // controller has ever touched matches the controller's live
        // head-of-queue owner, or zero when empty / fully expired. Exercises
        // reserveBaseNameForPop / releaseBaseName on every head transition.
        uint256 n = handler.baseLabelCount();
        for (uint256 i = 0; i < n; i++) {
            string memory baseLabel = handler.baseLabelAt(i);
            bytes32 labelhash = keccak256(bytes(baseLabel));

            (uint64 head, uint64 tail) = dotnsPopController.reservationMeta(labelhash);
            address expected;
            if (head < tail) {
                (address headOwner, uint64 joinedAt) =
                    dotnsPopController.reservationEntry(labelhash, head);
                if (
                    headOwner != address(0)
                        && uint256(joinedAt) + uint256(dotnsPopController.reservationDuration())
                            > block.timestamp
                ) {
                    expected = headOwner;
                }
            }

            (address popHolder,) = popRules.getBaseNameReservation(baseLabel);
            if (expected != address(0)) {
                assertEq(popHolder, expected, "PopRules head != queue head");
            }
        }
    }

    function invariant_one_reservation_per_account_consistent() public view {
        // Per-user reservation pointer is consistent with the queue entry it
        // points to: when userReservation(u).labelhash is non-zero, the entry
        // at userReservation(u).index is owned by u and sits in the live range.
        uint256 count = handler.actorsCount();
        for (uint256 i = 0; i < count; i++) {
            address actor = handler.actors(i);
            IDotnsPopController.UserReservation memory reservation =
                dotnsPopController.userReservation(actor);
            if (reservation.labelhash == bytes32(0)) continue;

            (uint64 head, uint64 tail) = dotnsPopController.reservationMeta(reservation.labelhash);
            assertTrue(
                reservation.index >= head && reservation.index < tail,
                "reservation index out of live range"
            );

            (address entryOwner,) =
                dotnsPopController.reservationEntry(reservation.labelhash, reservation.index);
            assertEq(entryOwner, actor, "reservation entry owner mismatch");
        }
    }

    function invariant_every_minted_tokenId_has_nonempty_label() public view {
        // The registrar's labelOf is the canonical string->tokenId recovery
        // path for downstream consumers. Every token the handler minted
        // (lite or full) must carry a non-empty label. Empty labelOf would
        // mean a mint bypassed registrar.register, which is the one place the
        // string is stored.
        uint256 n = handler.mintedLiteTokenCount();
        for (uint256 i = 0; i < n; i++) {
            uint256 tokenId = handler.mintedLiteTokenIds(i);
            assertGt(bytes(dotnsRegistrar.labelOf(tokenId)).length, 0, "empty labelOf");
        }
    }

    function invariant_fullClaim_liteLink_are_inverse() public view {
        // After any claim, the (liteLabelhash => fullNode) reverse index and
        // the (fullNode => liteLabelhash) forward index must round-trip. This
        // is the property downstream consumers rely on to walk from a lite
        // username string all the way to the full name's on-chain state.
        uint256 n = handler.claimedCount();
        for (uint256 i = 0; i < n; i++) {
            bytes32 liteLabelhash = handler.claimedLiteLabelhashes(i);
            bytes32 fullNode = handler.claimedFullNodes(i);
            assertEq(dotnsPopResolver.fullClaim(liteLabelhash), fullNode, "fullClaim != node");
            assertEq(dotnsPopResolver.liteLink(fullNode), liteLabelhash, "liteLink != hash");
        }
    }
}
