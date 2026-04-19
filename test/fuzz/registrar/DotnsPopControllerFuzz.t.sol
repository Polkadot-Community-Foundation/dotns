// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../../base/BaseDotns.t.sol";
import {IDotnsPopController} from "../../../contracts/registrars/IDotnsPopController.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title DotnsPopControllerFuzz
/// @notice Property-based tests for {DotnsPopController}.
/// @dev Each fuzz replaces a family of near-identical unit tests with a single
///      property assertion the fuzzer explores across inputs.
contract DotnsPopControllerFuzz is BaseDotns {
    /// @notice Decimal string of `value` padded to exactly two digits when `value < 10`.
    /// @dev Callers bound `value` to `[0, 99]` so the resulting suffix matches the
    ///      `.XX` contract used throughout the PoP controller tests; above 99 the
    ///      string is still valid (digits-only) but wider than two characters.
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

    /// @notice Any well-formed `alice.<NN>` lite label (`NN` exactly 2 digits) mints.
    /// @dev Replaces a family of hand-picked `alice.01`…`alice.99` unit tests.
    function testFuzz_reserveBaseName_accepts_any_two_digit_suffix(uint8 suffix) public {
        suffix = uint8(bound(uint256(suffix), 0, 99));
        string memory label = string.concat("alice.", _twoDigitDecimal(uint256(suffix)));

        _reservePop(ed, label, "", "");

        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf(label))), ed);
    }

    /// @notice Any lite label that omits the `.` separator is rejected with the
    ///         controller's specific `InvalidLiteLabel` error (not any revert).
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

    /// @notice Any chat-key payload is persisted verbatim on the resolver; empty
    ///         payloads skip the resolver write.
    /// @dev Replaces the hand-picked empty-vs-nonempty unit pair with one
    ///      byte-exact property across the full payload space.
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

    /// @notice `isReservedForClaim` tracks the `joinedAt + duration` boundary for
    ///         the queue head across the full duration/elapsed space.
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
