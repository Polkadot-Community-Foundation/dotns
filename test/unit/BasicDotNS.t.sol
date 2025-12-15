// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../base/BaseDotNS.t.sol";
import {IStableOracle} from "../../contracts/ethregistrar/StableOracle.sol";
import {IDotRegistrarController} from "../../contracts/ethregistrar/IDotRegistrarController.sol";

contract BasicDotns is BaseDotns {
    function test_register_pop_full_8_chars_no_digits() public {
        string memory label = "way2tall";

        vm.prank(ed);
        stableOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopFull);

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
                label: label,
                owner: ed,
                duration: 365 days,
                secret: keccak256(abi.encodePacked(label, block.timestamp)),
                resolver: address(publicResolver),
                data: new bytes[](0),
                reverseRecord: 1,
                referrer: bytes32(0)
            });

        _commitAndRegister(registration);

        assertEq(baseRegistrar.ownerOf(uint256(keccak256(bytes(label)))), ed);

        (bool isReserved,,) = stableOracle.isBaseNameReserved(label);
        assertFalse(isReserved);
    }

    function test_register_pop_full_8_chars_single_digit_no_reservation() public {
        string memory label = "waytall1";

        vm.prank(ed);
        stableOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopFull);

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
                label: label,
                owner: ed,
                duration: 365 days,
                secret: keccak256(abi.encodePacked(label, block.timestamp)),
                resolver: address(publicResolver),
                data: new bytes[](0),
                reverseRecord: 1,
                referrer: bytes32(0)
            });

        _commitAndRegister(registration);

        assertEq(baseRegistrar.ownerOf(uint256(keccak256(bytes(label)))), ed);

        (bool isReserved,,) = stableOracle.isBaseNameReserved("waytall");
        assertFalse(isReserved);
    }

    function test_register_pop_lite_8_chars_two_suffix_digits_creates_reservation() public {
        string memory label = "way2tall01";

        vm.prank(ed);
        stableOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopLite);

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
                label: label,
                owner: ed,
                duration: 365 days,
                secret: keccak256(abi.encodePacked(label, block.timestamp)),
                resolver: address(publicResolver),
                data: new bytes[](0),
                reverseRecord: 1,
                referrer: bytes32(0)
            });

        _commitAndRegister(registration);

        assertEq(baseRegistrar.ownerOf(uint256(keccak256(bytes(label)))), ed);

        (bool isReserved, address owner, uint64 expires) =
            stableOracle.isBaseNameReserved("way2tall");

        assertTrue(isReserved);
        assertEq(owner, ed);
        assertEq(expires, uint64(block.timestamp + 12 weeks));
    }

    function test_register_pop_lite_6_chars_two_suffix_digits_creates_reservation() public {
        string memory label = "light01";

        vm.prank(leonardo);
        stableOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopLite);

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
                label: label,
                owner: leonardo,
                duration: 365 days,
                secret: keccak256(abi.encodePacked(label, block.timestamp)),
                resolver: address(publicResolver),
                data: new bytes[](0),
                reverseRecord: 1,
                referrer: bytes32(0)
            });

        _commitAndRegister(registration);

        assertEq(baseRegistrar.ownerOf(uint256(keccak256(bytes(label)))), leonardo);

        (bool isReserved, address owner, uint64 expires) = stableOracle.isBaseNameReserved("light");

        assertTrue(isReserved);
        assertEq(owner, leonardo);
        assertEq(expires, uint64(block.timestamp + 12 weeks));
    }

    function test_register_no_status_16_chars_two_suffix_digits_no_reservation() public {
        string memory label = "kitesurfing_guru01";

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
                label: label,
                owner: tiago,
                duration: 365 days,
                secret: keccak256(abi.encodePacked(label, block.timestamp)),
                resolver: address(publicResolver),
                data: new bytes[](0),
                reverseRecord: 1,
                referrer: bytes32(0)
            });

        _commitAndRegister(registration);

        assertEq(baseRegistrar.ownerOf(uint256(keccak256(bytes(label)))), tiago);

        (bool isReserved, address reservationOwner,) =
            stableOracle.isBaseNameReserved("kitesurfing_guru");

        assertFalse(isReserved);
        assertEq(reservationOwner, address(0));
    }

    function test_register_pop_full_16_chars_no_digits_no_reservation() public {
        string memory label = "kitesurfing_guru";

        vm.prank(ed);
        stableOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopFull);

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
                label: label,
                owner: ed,
                duration: 365 days,
                secret: keccak256(abi.encodePacked(label, block.timestamp)),
                resolver: address(publicResolver),
                data: new bytes[](0),
                reverseRecord: 1,
                referrer: bytes32(0)
            });

        _commitAndRegister(registration);

        assertEq(baseRegistrar.ownerOf(uint256(keccak256(bytes(label)))), ed);

        (bool isReserved,,) = stableOracle.isBaseNameReserved(label);
        assertFalse(isReserved);
    }

    function test_original_registrant_can_claim_reserved_base_name() public {
        string memory suffixLabel = "upgrade99";
        string memory baseLabel = "upgrade";

        vm.prank(ed);
        stableOracle.setNamePopStatus(suffixLabel, IStableOracle.PopStatus.PopLite);

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
                label: suffixLabel,
                owner: ed,
                duration: 365 days,
                secret: keccak256(abi.encodePacked(suffixLabel, block.timestamp)),
                resolver: address(publicResolver),
                data: new bytes[](0),
                reverseRecord: 1,
                referrer: bytes32(0)
            });

        _commitAndRegister(registration);

        (bool isReserved, address owner,) = stableOracle.isBaseNameReserved(baseLabel);
        assertTrue(isReserved);
        assertEq(owner, ed);

        vm.prank(ed);
        stableOracle.setNamePopStatus(baseLabel, IStableOracle.PopStatus.PopFull);

        IDotRegistrarController.Registration memory baseRegistration =
            IDotRegistrarController.Registration({
                label: baseLabel,
                owner: ed,
                duration: 365 days,
                secret: keccak256(abi.encodePacked(baseLabel, block.timestamp + 1)),
                resolver: address(publicResolver),
                data: new bytes[](0),
                reverseRecord: 1,
                referrer: bytes32(0)
            });

        _commitAndRegister(baseRegistration);

        assertEq(baseRegistrar.ownerOf(uint256(keccak256(bytes(baseLabel)))), ed);
    }

    function test_base_name_available_after_12_week_reservation_expires() public {
        string memory suffixLabel = "expired99";
        string memory baseLabel = "expired";

        vm.prank(leonardo);
        stableOracle.setNamePopStatus(suffixLabel, IStableOracle.PopStatus.PopLite);

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
                label: suffixLabel,
                owner: leonardo,
                duration: 365 days,
                secret: keccak256(abi.encodePacked(suffixLabel, block.timestamp)),
                resolver: address(publicResolver),
                data: new bytes[](0),
                reverseRecord: 1,
                referrer: bytes32(0)
            });

        _commitAndRegister(registration);

        (bool isReserved, address owner, uint64 expires) =
            stableOracle.isBaseNameReserved(baseLabel);
        assertTrue(isReserved);
        assertEq(owner, leonardo);

        vm.warp(expires + 1);

        (bool stillReserved,,) = stableOracle.isBaseNameReserved(baseLabel);
        assertFalse(stillReserved);

        vm.prank(tiago);
        stableOracle.setNamePopStatus(baseLabel, IStableOracle.PopStatus.PopFull);

        IDotRegistrarController.Registration memory baseRegistration =
            IDotRegistrarController.Registration({
                label: baseLabel,
                owner: tiago,
                duration: 365 days,
                secret: keccak256(abi.encodePacked(baseLabel, block.timestamp)),
                resolver: address(publicResolver),
                data: new bytes[](0),
                reverseRecord: 1,
                referrer: bytes32(0)
            });

        _commitAndRegister(baseRegistration);

        assertEq(baseRegistrar.ownerOf(uint256(keccak256(bytes(baseLabel)))), tiago);
    }

    function test_name_expires_after_registration_period() public {
        string memory label = "expiretest";
        uint256 duration = 365 days;

        vm.prank(ed);
        stableOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopFull);

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
                label: label,
                owner: ed,
                duration: duration,
                secret: keccak256(abi.encodePacked(label, block.timestamp)),
                resolver: address(publicResolver),
                data: new bytes[](0),
                reverseRecord: 1,
                referrer: bytes32(0)
            });

        _commitAndRegister(registration);

        uint256 tokenId = uint256(keccak256(bytes(label)));
        assertEq(baseRegistrar.ownerOf(tokenId), ed);

        uint256 expiryTime = baseRegistrar.nameExpires(tokenId);
        assertEq(expiryTime, block.timestamp + duration);

        vm.warp(expiryTime + 1);

        bool isExpired;
        try baseRegistrar.ownerOf(tokenId) returns (address) {
            isExpired = false;
        } catch {
            isExpired = true;
        }
        assertTrue(isExpired);
    }

    function test_name_not_available_during_grace_period() public {
        string memory label = "gracetest";
        uint256 duration = 365 days;

        vm.prank(ed);
        stableOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopFull);

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
                label: label,
                owner: ed,
                duration: duration,
                secret: keccak256(abi.encodePacked(label, block.timestamp)),
                resolver: address(publicResolver),
                data: new bytes[](0),
                reverseRecord: 1,
                referrer: bytes32(0)
            });

        _commitAndRegister(registration);

        uint256 tokenId = uint256(keccak256(bytes(label)));
        uint256 expiryTime = baseRegistrar.nameExpires(tokenId);

        vm.warp(expiryTime + 60 days);

        bool available = baseRegistrar.available(tokenId);
        assertFalse(available);
    }

    function test_name_becomes_available_after_grace_period() public {
        string memory label = "availtest";
        uint256 duration = 365 days;

        vm.prank(ed);
        stableOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopFull);

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
                label: label,
                owner: ed,
                duration: duration,
                secret: keccak256(abi.encodePacked(label, block.timestamp)),
                resolver: address(publicResolver),
                data: new bytes[](0),
                reverseRecord: 1,
                referrer: bytes32(0)
            });

        _commitAndRegister(registration);

        uint256 tokenId = uint256(keccak256(bytes(label)));
        uint256 expiryTime = baseRegistrar.nameExpires(tokenId);

        vm.warp(expiryTime + 120 days + 1);

        bool available = baseRegistrar.available(tokenId);
        assertTrue(available);
    }

    function test_get_name_pop_status_returns_correct_status() public {
        string memory label = "statustest";

        vm.prank(ed);
        stableOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopFull);

        IStableOracle.PopStatus status = stableOracle.getNamePopStatus(label, ed);

        assertEq(uint256(status), uint256(IStableOracle.PopStatus.PopFull));
    }
}
