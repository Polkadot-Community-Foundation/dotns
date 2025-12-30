// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../base/BaseDotns.t.sol";
import {IPopOracle} from "../../contracts/pop/PopOracle.sol";

contract BasicDotns is BaseDotns {
    function test_register_pop_full_8_chars_no_digits_no_reservation() public {
        string memory label = "way2tall";

        vm.prank(ed);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopFull);

        _commitAndRegister(label, ed, true);

        uint256 tokenId = uint256(keccak256(bytes(label)));
        assertEq(dotnsRegistrar.ownerOf(tokenId), ed);

        (bool isReserved,,) = popOracle.isBaseNameReserved(label);
        assertFalse(isReserved);
    }

    function test_register_pop_full_8_chars_single_digit_no_reservation() public {
        string memory label = "waytall1";
        string memory baseLabel = "waytall";

        vm.prank(ed);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopFull);

        _commitAndRegister(label, ed, true);

        uint256 tokenId = uint256(keccak256(bytes(label)));
        assertEq(dotnsRegistrar.ownerOf(tokenId), ed);

        (bool isReserved,,) = popOracle.isBaseNameReserved(baseLabel);
        assertFalse(isReserved);
    }

    function test_register_pop_lite_8_chars_two_suffix_digits_creates_reservation() public {
        string memory label = "way2tall01";
        string memory baseLabel = "way2tall";

        vm.prank(ed);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopLite);

        _commitAndRegister(label, ed, true);

        uint256 tokenId = uint256(keccak256(bytes(label)));
        assertEq(dotnsRegistrar.ownerOf(tokenId), ed);

        (bool isReserved, address reservationOwner, uint64 expires) =
            popOracle.isBaseNameReserved(baseLabel);

        assertTrue(isReserved);
        assertEq(reservationOwner, ed);
        assertEq(expires, uint64(block.timestamp + 12 weeks));
    }

    function test_register_no_status_16_chars_two_suffix_digits_no_reservation() public {
        string memory label = "kitesurfing_guru01";
        string memory baseLabel = "kitesurfing_guru";

        // For NoStatus, do not set any status. Registration should succeed.
        _commitAndRegister(label, tiago, true);

        uint256 tokenId = uint256(keccak256(bytes(label)));
        assertEq(dotnsRegistrar.ownerOf(tokenId), tiago);

        (bool isReserved, address reservationOwner,) = popOracle.isBaseNameReserved(baseLabel);
        assertFalse(isReserved);
        assertEq(reservationOwner, address(0));
    }

    function test_register_pop_full_16_chars_no_digits_no_reservation() public {
        string memory label = "kitesurfing_guru";

        vm.prank(ed);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopFull);

        _commitAndRegister(label, ed, true);

        uint256 tokenId = uint256(keccak256(bytes(label)));
        assertEq(dotnsRegistrar.ownerOf(tokenId), ed);

        (bool isReserved,,) = popOracle.isBaseNameReserved(label);
        assertFalse(isReserved);
    }

    function test_original_registrant_can_claim_reserved_base_name() public {
        string memory suffixLabel = "upgrade99";
        string memory baseLabel = "upgrade";

        vm.prank(ed);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopLite);

        _commitAndRegister(suffixLabel, ed, true);

        (bool isReserved, address reservationOwner,) = popOracle.isBaseNameReserved(baseLabel);
        assertTrue(isReserved);
        assertEq(reservationOwner, ed);

        vm.prank(ed);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopFull);

        vm.warp(block.timestamp + 1);

        _commitAndRegister(baseLabel, ed, true);

        uint256 tokenId = uint256(keccak256(bytes(baseLabel)));
        assertEq(dotnsRegistrar.ownerOf(tokenId), ed);
    }

    function test_base_name_available_after_12_week_reservation_expires() public {
        string memory suffixLabel = "expired99";
        string memory baseLabel = "expired";

        vm.prank(leonardo);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopLite);

        _commitAndRegister(suffixLabel, leonardo, true);

        (bool isReserved, address reservationOwner, uint64 expires) =
            popOracle.isBaseNameReserved(baseLabel);

        assertTrue(isReserved);
        assertEq(reservationOwner, leonardo);

        vm.warp(uint256(expires) + 1);

        (bool stillReserved,,) = popOracle.isBaseNameReserved(baseLabel);
        assertFalse(stillReserved);

        vm.prank(tiago);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopFull);

        _commitAndRegister(baseLabel, tiago, true);

        uint256 tokenId = uint256(keccak256(bytes(baseLabel)));
        assertEq(dotnsRegistrar.ownerOf(tokenId), tiago);
    }

    function test_get_name_pop_status_returns_correct_status() public {
        vm.prank(ed);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopFull);

        IPopOracle.PopStatus status = popOracle.userPopStatus(ed);

        assertEq(uint256(status), uint256(IPopOracle.PopStatus.PopFull));
    }
}
