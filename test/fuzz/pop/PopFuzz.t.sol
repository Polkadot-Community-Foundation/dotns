// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns, IDotnsRegistrarController} from "../../base/BaseDotns.t.sol";
import {IPopOracle} from "../../../contracts/pop/IPopOracle.sol";

contract DotnsRegistrarControllerFuzzTest is BaseDotns {
    function testFuzz_register_zeroPrice_acceptsZeroPayment(uint256 salt) public {
        address nameOwner = ed;

        vm.prank(nameOwner);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopFull);

        string memory label = _labelPriceZero(bytes32(salt));
        IDotnsRegistrarController.Registration memory r =
            _registration(label, nameOwner, salt, false);

        _commit(r, nameOwner);
        _waitMinAge();

        uint256 quoted = popOracle.priceWithCheck(label, nameOwner).price;
        assertEq(quoted, 0);

        uint256 balBefore = nameOwner.balance;
        vm.prank(nameOwner);
        dotnsRegistrarController.register{value: 0}(r);
        uint256 balAfter = nameOwner.balance;

        assertEq(balBefore, balAfter);
    }

    function testFuzz_register_zeroPrice_refundsOverpayment(uint256 salt, uint256 extra) public {
        address nameOwner = ed;

        vm.prank(nameOwner);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopFull);

        string memory label = _labelPriceZero(bytes32(salt));
        IDotnsRegistrarController.Registration memory r =
            _registration(label, nameOwner, salt, false);

        _commit(r, nameOwner);
        _waitMinAge();

        uint256 quoted = popOracle.priceWithCheck(label, nameOwner).price;
        assertEq(quoted, 0);

        extra = bound(extra, 0, 10 ether);

        uint256 balBefore = nameOwner.balance;
        vm.prank(nameOwner);
        dotnsRegistrarController.register{value: extra}(r);
        uint256 balAfter = nameOwner.balance;

        assertEq(balBefore, balAfter);
    }

    function testFuzz_register_refundsOverpayment(uint256 salt, uint256 extra) public {
        address nameOwner = ed;

        vm.prank(nameOwner);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopFull);

        string memory label = _labelPopFullPriced(bytes32(salt));
        IDotnsRegistrarController.Registration memory r =
            _registration(label, nameOwner, salt, false);

        _commit(r, nameOwner);
        _waitMinAge();

        uint256 price = popOracle.priceWithCheck(label, nameOwner).price;
        assertGt(price, 0);

        extra = bound(extra, 0, 10 ether);

        uint256 balBefore = nameOwner.balance;
        vm.prank(nameOwner);
        dotnsRegistrarController.register{value: price + extra}(r);
        uint256 balAfter = nameOwner.balance;

        assertEq(balBefore - balAfter, price);
    }

    function testFuzz_register_refundsPayerWhenRegisteringForOther(
        uint256 salt,
        uint256 extra
    )
        public
    {
        address nameOwner = ed;
        address payer = tiago;

        vm.prank(nameOwner);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopFull);

        string memory label = _labelPopFullPriced(bytes32(salt));
        IDotnsRegistrarController.Registration memory r =
            _registration(label, nameOwner, salt, false);

        _commit(r, nameOwner);
        _waitMinAge();

        uint256 price = popOracle.priceWithCheck(label, nameOwner).price;
        assertGt(price, 0);

        extra = bound(extra, 0, 10 ether);

        uint256 payerBefore = payer.balance;
        vm.prank(payer);
        dotnsRegistrarController.register{value: price + extra}(r);
        uint256 payerAfter = payer.balance;

        assertEq(payerBefore - payerAfter, price);
    }

    function testFuzz_register_revertsOnInsufficientPayment(uint256 salt) public {
        address nameOwner = ed;

        vm.prank(nameOwner);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopFull);

        string memory label = _labelPopFullPriced(bytes32(salt));
        IDotnsRegistrarController.Registration memory r =
            _registration(label, nameOwner, salt, false);

        _commit(r, nameOwner);
        _waitMinAge();

        uint256 price = popOracle.priceWithCheck(label, nameOwner).price;
        assertGt(price, 0);

        vm.expectRevert(IDotnsRegistrarController.InsufficientValue.selector);
        vm.prank(nameOwner);
        dotnsRegistrarController.register{value: price - 1}(r);
    }

    function testFuzz_register_succeedsOnExactPayment(uint256 salt) public {
        address nameOwner = ed;

        vm.prank(nameOwner);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopFull);

        string memory label = _labelPopFullPriced(bytes32(salt));
        IDotnsRegistrarController.Registration memory r =
            _registration(label, nameOwner, salt, false);

        _commit(r, nameOwner);
        _waitMinAge();

        uint256 price = popOracle.priceWithCheck(label, nameOwner).price;
        assertGt(price, 0);

        uint256 balBefore = nameOwner.balance;
        vm.prank(nameOwner);
        dotnsRegistrarController.register{value: price}(r);
        uint256 balAfter = nameOwner.balance;

        assertEq(balBefore - balAfter, price);
    }

    function _registration(
        string memory label,
        address owner,
        uint256 salt,
        bool reserved
    )
        internal
        view
        returns (IDotnsRegistrarController.Registration memory r)
    {
        bytes32 secret = keccak256(abi.encodePacked(label, owner, salt, block.timestamp));
        r = IDotnsRegistrarController.Registration({
            label: label, owner: owner, secret: secret, reserved: reserved
        });
    }

    function _commit(IDotnsRegistrarController.Registration memory r, address committer) internal {
        bytes32 commitment = dotnsRegistrarController.makeCommitment(r);
        vm.prank(committer);
        dotnsRegistrarController.commit(commitment);
    }

    function _waitMinAge() internal {
        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);
    }

    /// @notice Generates a PopLite-eligible label with zero price under the current pricing rules.
    /// @dev Length is fixed at 8 (< 9) so `PopOracle.price()` returns 0.
    ///      Uses `suffixDigits = 2` to keep a consistent NoStatus/PopLite path while staying within the 2-digit limit.
    function _labelPriceZero(bytes32 seed) internal pure returns (string memory) {
        return _makeName(seed, 6, 2);
    }

    /// @notice Generates a PopFull-required label with non-zero price under the current pricing rules.
    /// @dev Length is fixed at 10 (>= 9) so `PopOracle.price()` returns non-zero.
    ///      Uses `suffixDigits = 1` to stay within the 2-digit limit.
    function _labelPopFullPriced(bytes32 seed) internal pure returns (string memory) {
        return _makeName(seed, 9, 1);
    }

    /// @notice Deterministically generates a lowercase label with an optional numeric suffix.
    /// @dev Produces `baseLength` lowercase letters ('a'..'z') followed by `suffixDigits` digits ('0'..'9').
    ///      Characters are derived from `keccak256(seed, index)` to keep outputs stable across runs.
    ///      Intended for fuzz tests where labels must be unique but reproducible.
    /// @param seed Entropy source used to derive each character.
    /// @param baseLength Number of leading alphabetic characters to generate.
    /// @param suffixDigits Number of trailing numeric characters to generate.
    /// @return name The generated label string.
    function _makeName(
        bytes32 seed,
        uint256 baseLength,
        uint256 suffixDigits
    )
        internal
        pure
        returns (string memory name)
    {
        bytes memory out = new bytes(baseLength + suffixDigits);

        for (uint256 i = 0; i < baseLength; i++) {
            out[i] = bytes1(uint8(97 + (uint256(keccak256(abi.encodePacked(seed, i))) % 26)));
        }

        for (uint256 j = 0; j < suffixDigits; j++) {
            out[baseLength + j] = bytes1(
                uint8(48 + (uint256(keccak256(abi.encodePacked(seed, baseLength + j))) % 10))
            );
        }

        return string(out);
    }
}
