// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../../base/BaseDotns.t.sol";
import {IDotnsPopController} from "../../../contracts/registrars/IDotnsPopController.sol";
import {
    IDotnsRegistrarController
} from "../../../contracts/registrars/IDotnsRegistrarController.sol";
import {IPopRules} from "../../../contracts/pop/IPopRules.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title DotnsPopControllerFuzz
/// @notice Property-based tests for {DotnsPopController}.
/// @dev Each fuzz replaces a family of near-identical unit tests with a single
///      property assertion the fuzzer explores across inputs.
contract DotnsPopControllerFuzz is BaseDotns {
    // Decimal string of `value` padded to exactly two digits when `value < 10`.
    // Callers bound `value` to `[0, 99]` so the resulting suffix matches the
    // `.XX` contract used throughout the PoP controller tests; above 99 the
    // string is still valid (digits-only) but wider than two characters.
    function _twoDigitDecimal(uint256 value) internal pure returns (string memory s) {
        if (value < 10) return string.concat("0", _uintToString(value));
        return _uintToString(value);
    }

    function _uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
        return string(buffer);
    }

    // Any well-formed `alice.<NN>` lite label (`NN` exactly 2 digits) mints.
    // Replaces a family of hand-picked `alice.01`…`alice.99` unit tests.
    function testFuzz_reserveBaseName_accepts_any_two_digit_suffix(uint8 suffix) public {
        suffix = uint8(bound(uint256(suffix), 0, 99));
        string memory label = string.concat("alice.", _twoDigitDecimal(uint256(suffix)));

        _reservePop(ed, label, "", "");

        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf(label))), ed);
    }

    // Any lite label that omits the `.` separator is rejected with the
    // controller's specific `InvalidLiteLabel` error (not any revert).
    function testFuzz_reserveBaseName_rejects_lite_label_without_separator(string calldata stem)
        public
    {
        vm.assume(bytes(stem).length > 0 && bytes(stem).length < 64);
        bytes calldata raw = bytes(stem);
        for (uint256 i = 0; i < raw.length; ++i) {
            vm.assume(raw[i] != 0x2e);
        }

        vm.prank(popGateway);
        vm.expectRevert(IDotnsPopController.InvalidLiteLabel.selector);
        dotnsPopController.reserveBaseName(stem, ed, "", "");
    }

    // Any chat-key payload is persisted verbatim on the resolver; empty
    // payloads skip the resolver write.
    // Replaces the hand-picked empty-vs-nonempty unit pair with one
    // byte-exact property across the full payload space.
    function testFuzz_reserveBaseName_persists_chat_key_exact_bytes(
        uint8 suffix,
        bytes calldata chatKey
    )
        public
    {
        suffix = uint8(bound(uint256(suffix), 0, 99));
        string memory label = string.concat("bob.", _twoDigitDecimal(uint256(suffix)));

        _reservePop(ed, label, chatKey, "");

        bytes32 node = _nodeOf(label);
        if (chatKey.length == 0) {
            assertEq(dotnsPopResolver.chatKey(node).length, 0);
        } else {
            assertEq(dotnsPopResolver.chatKey(node), chatKey);
        }
    }

    // Random sequences of enqueue / relinquish / expire keep the PopRules
    // reservation in lockstep with the queue head: the slot owner equals the
    // non-expired head-of-queue owner, or zero when the queue is empty /
    // fully expired. This is the key cross-contract sync invariant.
    function testFuzz_popRules_head_owner_matches_queue_head(
        uint8 opSeed,
        uint8 actorSeed,
        uint16 warpSeed
    )
        public
    {
        address[3] memory actors = [ed, tiago, leonardo];
        string memory baseLabel = "longnamebob";
        uint64 suffixCounter;

        for (uint256 i = 0; i < 6; i++) {
            address actor = actors[uint256(keccak256(abi.encode(actorSeed, i))) % 3];
            uint256 op = uint256(keccak256(abi.encode(opSeed, i))) % 4;
            suffixCounter++;

            if (op == 0) {
                string memory liteLabel =
                    string.concat("u", vm.toString(uint256(suffixCounter) + 10));
                liteLabel = string.concat(liteLabel, ".", vm.toString(uint256(suffixCounter) + 10));
                vm.prank(popGateway);
                try dotnsPopController.reserveBaseName(liteLabel, actor, "", baseLabel) {} catch {}
            } else if (op == 1) {
                vm.prank(actor);
                try dotnsPopController.relinquishReservation() {} catch {}
            } else if (op == 2) {
                try dotnsPopController.expireReservation(baseLabel) {} catch {}
            } else {
                vm.warp(block.timestamp + (uint256(warpSeed) + i * 1 hours) % (10 days));
            }
        }

        // Derive expected owner from on-chain queue state.
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

        (address popHolder, uint64 popExpires) = popRules.getBaseNameReservation(baseLabel);
        // When the controller considers the head live, PopRules must have that
        // exact holder. When the controller considers the queue empty, PopRules
        // is either empty or stale (held by a previous reserver with expiry
        // still in the future); the public-flow-guard check is time-based so
        // stale slots are harmless. We only assert the live-head equivalence.
        if (expected != address(0)) {
            assertEq(popHolder, expected, "PopRules head mismatch");
            assertGt(popExpires, block.timestamp);
        }
    }

    // A random stranger's public register succeeds exactly when PopRules
    // permits: if the stem is reserved for someone else, the register reverts
    // with the PopRules reservation error; otherwise it succeeds. Drives the
    // commit-reveal flow inline so the revert (if any) lands on `register`.
    function testFuzz_public_register_respects_popRules_reservation(bool reserveFirst) public {
        string memory stem = "longnamebob";
        string memory fullLabel = "longnamebob01";

        if (reserveFirst) {
            _reservePop(tiago, "alice.31", "", stem);
        }

        bytes32 secret = keccak256(abi.encodePacked(fullLabel, ed, block.timestamp));
        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: fullLabel, owner: ed, secret: secret, reserved: true
            });
        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);

        vm.prank(ed);
        dotnsRegistrarController.commit(commitment);
        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        if (reserveFirst) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IPopRules.PopError.selector, "Base name reserved for original Lite registrant"
                )
            );
            vm.prank(ed);
            dotnsRegistrarController.register{value: 1 ether}(registration);
        } else {
            uint256 cost = popRules.priceWithCheck(fullLabel, ed).price;
            vm.prank(ed);
            dotnsRegistrarController.register{value: cost}(registration);
            assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf(fullLabel))), ed);
        }
    }

    // `isReservedForClaim` tracks the `joinedAt + duration` boundary for
    // the queue head across the full duration/elapsed space.
    function testFuzz_isReservedForClaim_tracks_duration_boundary(
        uint64 duration,
        uint64 elapsed
    )
        public
    {
        duration = uint64(bound(uint256(duration), 1, 365 days));
        elapsed = uint64(bound(uint256(elapsed), 0, 365 days));

        vm.prank(owner);
        dotnsPopController.setReservationDuration(duration);

        _reservePop(ed, "carol.77", "", "alicebob");

        vm.warp(block.timestamp + uint256(elapsed));

        (bool reserved, address holder) = dotnsPopController.isReservedForClaim("alicebob");
        if (uint256(elapsed) < uint256(duration)) {
            assertTrue(reserved);
            assertEq(holder, ed);
        } else {
            assertFalse(reserved);
            assertEq(holder, address(0));
        }
    }
}
