// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns, IDotnsRegistrarController} from "../../base/BaseDotns.t.sol";
import {IPopRules} from "../../../contracts/pop/IPopRules.sol";

contract DotnsRegistrarControllerFuzzTest is BaseDotns {
    function testFuzz_register_zero_price_zero_payment(uint256 salt) public {
        address nameOwner = ed;

        vm.startPrank(nameOwner);
        popRules.setUserPopStatus(IPopRules.PopStatus.PopFull);
        vm.stopPrank();

        string memory nameLabel = _labelPriceZero(bytes32(salt));
        IDotnsRegistrarController.Registration memory registration =
            _registration(nameLabel, nameOwner, salt, false);

        _commit(registration, nameOwner);
        _waitMinAge();

        uint256 quotedPrice = popRules.priceWithCheck(nameLabel, nameOwner).price;
        assertEq(quotedPrice, 0);

        uint256 balanceBefore = nameOwner.balance;
        vm.startPrank(nameOwner);
        dotnsRegistrarController.register{value: 0}(registration);
        vm.stopPrank();
        uint256 balanceAfter = nameOwner.balance;

        assertEq(balanceBefore, balanceAfter);
    }

    function testFuzz_register_zero_price_refund_overpay(
        uint256 salt,
        uint256 paymentExtra
    )
        public
    {
        address nameOwner = ed;

        vm.startPrank(nameOwner);
        popRules.setUserPopStatus(IPopRules.PopStatus.PopFull);
        vm.stopPrank();

        string memory nameLabel = _labelPriceZero(bytes32(salt));
        IDotnsRegistrarController.Registration memory registration =
            _registration(nameLabel, nameOwner, salt, false);

        _commit(registration, nameOwner);
        _waitMinAge();

        uint256 quotedPrice = popRules.priceWithCheck(nameLabel, nameOwner).price;
        assertEq(quotedPrice, 0);

        paymentExtra = bound(paymentExtra, 0, 10 ether);

        uint256 balanceBefore = nameOwner.balance;
        vm.startPrank(nameOwner);
        dotnsRegistrarController.register{value: paymentExtra}(registration);
        vm.stopPrank();
        uint256 balanceAfter = nameOwner.balance;

        assertEq(balanceBefore, balanceAfter);
    }

    function testFuzz_register_refund_overpay(uint256 salt, uint256 paymentExtra) public {
        address nameOwner = ed;

        vm.startPrank(nameOwner);
        popRules.setUserPopStatus(IPopRules.PopStatus.NoStatus);
        vm.stopPrank();

        string memory nameLabel = _labelNoStatusPriced(bytes32(salt));
        IDotnsRegistrarController.Registration memory registration =
            _registration(nameLabel, nameOwner, salt, false);

        _commit(registration, nameOwner);
        _waitMinAge();

        uint256 requiredPrice = popRules.priceWithCheck(nameLabel, nameOwner).price;
        assertGt(requiredPrice, 0);

        paymentExtra = bound(paymentExtra, 0, 10 ether);

        uint256 balanceBefore = nameOwner.balance;
        vm.startPrank(nameOwner);
        dotnsRegistrarController.register{value: requiredPrice + paymentExtra}(registration);
        vm.stopPrank();
        uint256 balanceAfter = nameOwner.balance;

        assertEq(balanceBefore - balanceAfter, requiredPrice);
    }

    function testFuzz_register_refund_payer_other(uint256 salt, uint256 paymentExtra) public {
        address nameOwner = ed;
        address payer = tiago;

        vm.startPrank(nameOwner);
        popRules.setUserPopStatus(IPopRules.PopStatus.NoStatus);
        vm.stopPrank();

        vm.startPrank(payer);
        popRules.setUserPopStatus(IPopRules.PopStatus.NoStatus);
        vm.stopPrank();

        string memory nameLabel = _labelNoStatusPriced(bytes32(salt));
        IDotnsRegistrarController.Registration memory registration =
            _registration(nameLabel, nameOwner, salt, false);

        _commit(registration, payer);
        _waitMinAge();

        uint256 requiredPrice = popRules.priceWithCheck(nameLabel, nameOwner).price;
        assertGt(requiredPrice, 0);

        paymentExtra = bound(paymentExtra, 0, 10 ether);

        uint256 payerBalanceBefore = payer.balance;
        vm.startPrank(payer);
        dotnsRegistrarController.register{value: requiredPrice + paymentExtra}(registration);
        vm.stopPrank();
        uint256 payerBalanceAfter = payer.balance;

        assertEq(payerBalanceBefore - payerBalanceAfter, requiredPrice);
    }

    function testFuzz_register_revert_insufficient(uint256 salt) public {
        address nameOwner = ed;

        vm.startPrank(nameOwner);
        popRules.setUserPopStatus(IPopRules.PopStatus.NoStatus);
        vm.stopPrank();

        string memory nameLabel = _labelNoStatusPriced(bytes32(salt));
        IDotnsRegistrarController.Registration memory registration =
            _registration(nameLabel, nameOwner, salt, false);

        _commit(registration, nameOwner);
        _waitMinAge();

        uint256 requiredPrice = popRules.priceWithCheck(nameLabel, nameOwner).price;
        assertGt(requiredPrice, 0);

        vm.expectRevert(IDotnsRegistrarController.InsufficientValue.selector);
        vm.startPrank(nameOwner);
        dotnsRegistrarController.register{value: requiredPrice - 1}(registration);
        vm.stopPrank();
    }

    function testFuzz_register_exact_payment(uint256 salt) public {
        address nameOwner = ed;

        vm.startPrank(nameOwner);
        popRules.setUserPopStatus(IPopRules.PopStatus.NoStatus);
        vm.stopPrank();

        string memory nameLabel = _labelNoStatusPriced(bytes32(salt));
        IDotnsRegistrarController.Registration memory registration =
            _registration(nameLabel, nameOwner, salt, false);

        _commit(registration, nameOwner);
        _waitMinAge();

        uint256 requiredPrice = popRules.priceWithCheck(nameLabel, nameOwner).price;
        assertGt(requiredPrice, 0);

        uint256 balanceBefore = nameOwner.balance;
        vm.startPrank(nameOwner);
        dotnsRegistrarController.register{value: requiredPrice}(registration);
        vm.stopPrank();
        uint256 balanceAfter = nameOwner.balance;

        assertEq(balanceBefore - balanceAfter, requiredPrice);
    }

    function _registration(
        string memory nameLabel,
        address owner_,
        uint256 salt,
        bool reserved
    )
        internal
        view
        returns (IDotnsRegistrarController.Registration memory registration)
    {
        bytes32 secret = keccak256(abi.encodePacked(nameLabel, owner_, salt, block.timestamp));
        registration = IDotnsRegistrarController.Registration({
            label: nameLabel, owner: owner_, secret: secret, reserved: reserved
        });
    }

    function _commit(
        IDotnsRegistrarController.Registration memory registration,
        address committer
    )
        internal
    {
        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);
        vm.startPrank(committer);
        dotnsRegistrarController.commit(commitment);
        vm.stopPrank();
    }

    function _waitMinAge() internal {
        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);
    }

    function _labelPriceZero(bytes32 seed) internal pure returns (string memory) {
        return _makeName(seed, 6, 2);
    }

    function _labelNoStatusPriced(bytes32 seed) internal pure returns (string memory) {
        return _makeName(seed, 9, 2);
    }

    function _makeName(
        bytes32 seed,
        uint256 baseLength,
        uint256 suffixDigits
    )
        internal
        pure
        returns (string memory name)
    {
        bytes memory output = new bytes(baseLength + suffixDigits);

        for (uint256 baseIndex = 0; baseIndex < baseLength; baseIndex++) {
            output[baseIndex] =
                bytes1(uint8(97 + (uint256(keccak256(abi.encodePacked(seed, baseIndex))) % 26)));
        }

        for (uint256 suffixIndex = 0; suffixIndex < suffixDigits; suffixIndex++) {
            uint256 charIndex = baseLength + suffixIndex;
            output[charIndex] =
                bytes1(uint8(48 + (uint256(keccak256(abi.encodePacked(seed, charIndex))) % 10)));
        }

        return string(output);
    }
}
