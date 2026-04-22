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

        address[] memory handlerActors = new address[](3);
        handlerActors[0] = ed;
        handlerActors[1] = leonardo;
        handlerActors[2] = tiago;

        handler = new PopControllerHandler(dotnsPopController, popGateway, handlerActors);
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = handler.reserve.selector;
        selectors[1] = handler.relinquish.selector;
        selectors[2] = handler.expire.selector;
        selectors[3] = handler.warp.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // Every tracked queue stays bounded by `MAX_RESERVATION_QUEUE`.
    function invariant_queue_length_bounded() public view {
        uint256 n = handler.reservedLabelsSeenCount();
        for (uint256 i = 0; i < n; i++) {
            bytes32 labelhash = handler.reservedLabelsSeen(i);
            (uint64 head, uint64 tail) = dotnsPopController.reservationMeta(labelhash);
            assertLe(uint256(tail - head), uint256(handler.MAX_QUEUE()));
        }
    }

    // Cross-contract sync invariant: PopRules' reservation for every base
    // label the controller has ever touched matches the controller's live
    // head-of-queue owner, or zero when the queue is empty / fully expired.
    // Exercises the reserveBaseNameForPop / releaseBaseName write path on
    // every head transition (enqueue, claim, relinquish, expire).
    function invariant_popRules_head_matches_queue_head_or_zero() public view {
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

    // Per-user reservation pointer is consistent with the queue entry it
    // points to: when `userReservation(u).labelhash` is non-zero, the entry at
    // `userReservation(u).index` is owned by `u` and sits in the live range.
    function invariant_one_reservation_per_account_consistent() public view {
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
}
