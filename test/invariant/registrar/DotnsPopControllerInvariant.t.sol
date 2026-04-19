// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../../base/BaseDotns.t.sol";
import {PopControllerHandler} from "./PopControllerHandler.t.sol";

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

    /// @notice Every tracked queue stays bounded by `MAX_RESERVATION_QUEUE`.
    function invariant_queue_length_bounded() public view {
        uint256 n = handler.reservedLabelsSeenCount();
        for (uint256 i = 0; i < n; i++) {
            bytes32 labelhash = handler.reservedLabelsSeen(i);
            (uint64 head, uint64 tail) = dotnsPopController.reservationMeta(labelhash);
            assertLe(uint256(tail - head), uint256(handler.MAX_QUEUE()));
        }
    }

    /// @notice Per-user reservation pointer is consistent with the queue entry it
    ///         points to: when `userReservation[u]` is non-zero, the entry at
    ///         `userReservationIndex[u]` is owned by `u` and sits in the live range.
    function invariant_one_reservation_per_account_consistent() public view {
        uint256 count = handler.actorsCount();
        for (uint256 i = 0; i < count; i++) {
            address actor = handler.actors(i);
            bytes32 labelhash = dotnsPopController.userReservation(actor);
            if (labelhash == bytes32(0)) continue;

            uint64 index = dotnsPopController.userReservationIndex(actor);
            (uint64 head, uint64 tail) = dotnsPopController.reservationMeta(labelhash);
            assertTrue(index >= head && index < tail, "reservation index out of live range");

            (address entryOwner,) = dotnsPopController.reservationEntry(labelhash, index);
            assertEq(entryOwner, actor, "reservation entry owner mismatch");
        }
    }
}
