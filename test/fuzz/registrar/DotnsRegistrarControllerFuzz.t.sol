// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns, IDotnsRegistrarController} from "../../base/BaseDotns.t.sol";
import {IPopOracle} from "../../../contracts/pop/IPopOracle.sol";

contract DotnsRegistrarControllerFuzzTest is BaseDotns {
    function testFuzz_register_reverts_when_payment_is_less_than_price(uint256 underpay) public {
        string memory label = _label_popfull(bound(underpay, 0, 64));
        address registrant = ed;

        vm.prank(registrant);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopFull);

        IDotnsRegistrarController.Registration memory r = _commit_for(label, registrant, true);

        uint256 required = popOracle.priceWithCheck(label, registrant).price;
        uint256 pay = underpay % (required + 1);

        vm.prank(registrant);
        vm.expectRevert(IDotnsRegistrarController.InsufficientValue.selector);
        dotnsRegistrarController.register{value: pay}(r);
    }

    function testFuzz_register_succeeds_when_payment_equals_price(uint256 salt) public {
        string memory label = _label_popfull(bound(salt, 0, 64));
        address registrant = ed;

        vm.prank(registrant);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopFull);

        IDotnsRegistrarController.Registration memory r = _commit_for(label, registrant, true);

        uint256 required = popOracle.priceWithCheck(label, registrant).price;

        vm.prank(registrant);
        dotnsRegistrarController.register{value: required}(r);

        assertEq(dotnsRegistrar.ownerOf(uint256(keccak256(bytes(label)))), registrant);
    }

    function testFuzz_register_refunds_overpayment(uint256 extra, uint256 salt) public {
        string memory label = _label_popfull(bound(salt, 0, 64));
        address registrant = ed;

        vm.prank(registrant);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopFull);

        IDotnsRegistrarController.Registration memory r = _commit_for(label, registrant, true);

        uint256 required = popOracle.priceWithCheck(label, registrant).price;
        extra = bound(extra, 1, 5 ether);

        uint256 beforeBalance = registrant.balance;

        vm.prank(registrant);
        dotnsRegistrarController.register{value: required + extra}(r);

        uint256 afterBalance = registrant.balance;
        assertEq(beforeBalance - afterBalance, required);
    }

    function testFuzz_register_accepts_exact_zero_payment_when_price_is_zero(uint256 salt) public {
        string memory label = _label_price_zero(bound(salt, 0, 64));
        address registrant = tiago;

        vm.prank(registrant);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopLite);

        IDotnsRegistrarController.Registration memory r = _commit_for(label, registrant, false);

        uint256 required = popOracle.priceWithCheck(label, registrant).price;
        assertEq(required, 0);

        vm.prank(registrant);
        dotnsRegistrarController.register{value: 0}(r);

        assertEq(dotnsRegistrar.ownerOf(uint256(keccak256(bytes(label)))), registrant);
    }

    function testFuzz_register_accepts_overpayment_when_price_is_zero(
        uint256 extra,
        uint256 salt
    )
        public
    {
        string memory label = _label_price_zero(bound(salt, 0, 64));
        address registrant = tiago;

        vm.prank(registrant);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopLite);

        IDotnsRegistrarController.Registration memory r = _commit_for(label, registrant, false);

        uint256 required = popOracle.priceWithCheck(label, registrant).price;
        assertEq(required, 0);

        extra = bound(extra, 1, 5 ether);
        uint256 beforeBalance = registrant.balance;

        vm.prank(registrant);
        dotnsRegistrarController.register{value: extra}(r);

        uint256 afterBalance = registrant.balance;
        assertEq(beforeBalance, afterBalance);
    }

    function testFuzz_register_refunds_to_payer_not_owner_when_registering_for_other(
        uint256 extra,
        uint256 salt
    )
        public
    {
        string memory label = _label_popfull(bound(salt, 0, 64));

        address nameOwner = ed;
        address payer = leonardo;

        vm.prank(nameOwner);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopFull);

        IDotnsRegistrarController.Registration memory r = _commit_for(label, nameOwner, true);

        uint256 required = popOracle.priceWithCheck(label, nameOwner).price;
        extra = bound(extra, 1, 5 ether);

        uint256 payerBefore = payer.balance;
        uint256 ownerBefore = nameOwner.balance;

        vm.prank(payer);
        dotnsRegistrarController.register{value: required + extra}(r);

        uint256 payerAfter = payer.balance;
        uint256 ownerAfter = nameOwner.balance;

        assertEq(payerBefore - payerAfter, required);
        assertEq(ownerBefore, ownerAfter);
        assertEq(dotnsRegistrar.ownerOf(uint256(keccak256(bytes(label)))), nameOwner);
    }

    function _commit_for(
        string memory label,
        address owner,
        bool reserved
    )
        internal
        returns (IDotnsRegistrarController.Registration memory r)
    {
        bytes32 secret = keccak256(abi.encodePacked(label, owner, block.timestamp, address(this)));
        r = IDotnsRegistrarController.Registration({
            label: label, owner: owner, secret: secret, reserved: reserved
        });

        bytes32 commitment = dotnsRegistrarController.makeCommitment(r);

        vm.prank(owner);
        dotnsRegistrarController.commit(commitment);

        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);
    }

    /// @notice Builds a PopFull-required label for payment-related tests.
    /// @dev Returns a label with base length in PopFull range (6-8) and exactly 1 trailing digit.
    ///      Format: "popfull" + alphabetic(salt) + "9"
    ///      Total: 7 + 2 + 1 = 10 chars, ensuring length >= 9 (priced) and 1 trailing digit (PopFull).
    function _label_popfull(uint256 salt) internal pure returns (string memory label) {
        return string(abi.encodePacked("popfull", _u2a(salt, 2), "9"));
    }

    /// @notice Builds a zero-price label for payment-related tests.
    /// @dev Returns a label with total length < 9 to trigger zero pricing.
    ///      Format: "free" + alphabetic(salt) + "01"
    ///      Total: 4 + 2 + 2 = 8 chars (< 9, so price = 0) with 2 trailing digits.
    function _label_price_zero(uint256 salt) internal pure returns (string memory label) {
        return string(abi.encodePacked("free", _u2a(salt, 2), "01"));
    }

    /// @notice Converts uint256 to fixed-length alphabetic string.
    /// @dev Maps each base-26 digit to 'a'-'z'. Ensures deterministic labels without numeric characters.
    /// @param x Number to encode.
    /// @param len Fixed output length.
    /// @return s Alphabetic string of specified length.
    function _u2a(uint256 x, uint256 len) internal pure returns (string memory s) {
        bytes memory b = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            b[i] = bytes1(uint8(97 + (x % 26)));
            x /= 26;
        }
        return string(b);
    }
}
