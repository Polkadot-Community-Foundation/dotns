// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {BaseDotns, IDotnsRegistrarController} from "../../base/BaseDotns.t.sol";
import {ILabelStore} from "../../../contracts/store/ILabelStore.sol";
import {DotnsConstants} from "../../../contracts/utils/DotnsConstants.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title DotnsRegistrarControllerFuzzTest
/// @notice Property-based tests for @custom:contract DotnsRegistrarController role administration,
///         payment handling and reverse-record behaviour.
contract DotnsRegistrarControllerFuzzTest is BaseDotns {
    function testFuzz_owner_setrole_matches_hasrole(address account, bool enabled) public {
        vm.assume(account != address(0));

        vm.prank(owner);
        dotnsRegistrarController.setRole(DotnsConstants.WHITELIST_OPERATOR_ROLE, account, enabled);

        assertEq(
            dotnsRegistrarController.hasRole(DotnsConstants.WHITELIST_OPERATOR_ROLE, account),
            enabled
        );
    }

    function testFuzz_non_owner_cannot_setrole(
        address caller,
        address account,
        bool enabled
    )
        public
    {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, caller)
        );
        dotnsRegistrarController.setRole(DotnsConstants.WHITELIST_OPERATOR_ROLE, account, enabled);
    }

    function testFuzz_register_credits_overpayment_to_pull_payment_ledger(
        uint256 extra,
        uint256 salt
    )
        public
    {
        address registrant = ed;
        string memory nameLabel = _labelNoStatusPriced(bound(salt, 0, 64));

        _grantNoStatus(registrant);

        IDotnsRegistrarController.Registration memory registration =
            _commitFor(nameLabel, registrant, true);

        uint256 requiredPrice = popRules.priceWithCheck(nameLabel, registrant).price;
        assertGt(requiredPrice, 0);

        extra = bound(extra, 0, 5 ether);

        vm.startPrank(registrant);
        dotnsRegistrarController.register{value: requiredPrice + extra}(registration);
        vm.stopPrank();

        // Overpayment routes to the escrow's pending-withdrawal ledger so
        // contract receivers with reverting `receive` can still register and
        // pull the refund later. The registrant's wallet balance therefore
        // decreases by the full `value` sent; the surplus is recoverable via
        // `claimWithdrawal`.
        assertEq(
            dotnsNameEscrow.pendingWithdrawal(registrant),
            extra,
            "overpayment must accrue to the payer's pull-payment ledger"
        );

        bytes32 labelhash = keccak256(bytes(nameLabel));
        bytes32 node = _namehash(dotNode, labelhash);
        uint256 tokenId = uint256(node);

        assertEq(dotnsRegistrar.ownerOf(tokenId), registrant);
    }

    function testFuzz_register_accepts_overpayment_when_price_is_zero(
        uint256 extra,
        uint256 salt
    )
        public
    {
        address registrant = tiago;
        string memory nameLabel = _labelPriceZero(bound(salt, 0, 64));

        _grantPopLite(registrant);

        IDotnsRegistrarController.Registration memory registration =
            _commitFor(nameLabel, registrant, false);

        uint256 requiredPrice = popRules.priceWithCheck(nameLabel, registrant).price;
        assertEq(requiredPrice, 0);

        extra = bound(extra, 0, 5 ether);

        vm.startPrank(registrant);
        dotnsRegistrarController.register{value: extra}(registration);
        vm.stopPrank();

        // Zero-priced mint with overpayment: the full `extra` lands on the
        // payer's pull-payment ledger.
        assertEq(
            dotnsNameEscrow.pendingWithdrawal(registrant),
            extra,
            "overpayment must accrue to the payer's pull-payment ledger"
        );

        bytes32 labelhash = keccak256(bytes(nameLabel));
        bytes32 node = _namehash(dotNode, labelhash);
        uint256 tokenId = uint256(node);

        assertEq(dotnsRegistrar.ownerOf(tokenId), registrant);
    }

    function testFuzz_register_credits_overpayment_to_payer_not_owner(
        uint256 extra,
        uint256 salt
    )
        public
    {
        address nameOwner = ed;
        address payer = leonardo;
        string memory nameLabel = _labelPopfull(bound(salt, 0, 64));

        _grantPopFull(nameOwner);
        _grantPopFull(payer);

        IDotnsRegistrarController.Registration memory registration =
            _commitFor(nameLabel, nameOwner, true, payer);

        uint256 requiredPrice = popRules.priceWithCheck(nameLabel, nameOwner).price;
        assertEq(requiredPrice, 0);

        extra = bound(extra, 0, 5 ether);

        uint256 ownerBalanceBefore = nameOwner.balance;

        vm.startPrank(payer);
        dotnsRegistrarController.register{value: requiredPrice + extra}(registration);
        vm.stopPrank();

        // Refund is keyed by `msg.sender`, so the payer (not the owner) is the
        // ledger recipient. Owner's wallet stays untouched.
        assertEq(
            dotnsNameEscrow.pendingWithdrawal(payer),
            extra,
            "payer must be the ledger recipient on cross-payer registrations"
        );
        assertEq(
            dotnsNameEscrow.pendingWithdrawal(nameOwner),
            0,
            "owner must not be credited the payer's refund"
        );
        assertEq(nameOwner.balance, ownerBalanceBefore, "owner wallet is not touched");

        bytes32 labelhash = keccak256(bytes(nameLabel));
        bytes32 node = _namehash(dotNode, labelhash);
        uint256 tokenId = uint256(node);

        assertEq(dotnsRegistrar.ownerOf(tokenId), nameOwner);
    }

    function testFuzz_transfer_writes_label_to_recipient_store(uint256 salt) public {
        address sender = ed;
        address recipient = leonardo;
        string memory nameLabel = _labelPopfull(bound(salt, 0, 64));

        _grantPopFull(sender);

        IDotnsRegistrarController.Registration memory registration =
            _commitFor(nameLabel, sender, true);

        vm.startPrank(sender);
        dotnsRegistrarController.register{value: 0}(registration);
        vm.stopPrank();

        bytes32 labelhash = keccak256(bytes(nameLabel));
        bytes32 node = _namehash(dotNode, labelhash);
        uint256 tokenId = uint256(node);

        uint256 _xferFee = dotnsRegistrar.quoteTransferFee(tokenId, recipient);
        vm.prank(sender);
        dotnsRegistrar.transferFrom{value: _xferFee}(sender, recipient, tokenId);

        assertEq(dotnsRegistrar.ownerOf(tokenId), recipient);

        ILabelStore recipientStore = ILabelStore(storeFactory.getLabelStore(recipient));
        assertTrue(address(recipientStore) != address(0));

        assertEq(recipientStore.getLabel(node), string.concat(nameLabel, ".dot"));
        assertTrue(recipientStore.isLocked(node));
    }

    function testFuzz_third_party_registration_does_not_overwrite_owner_reverse(uint256 salt)
        public
    {
        address payer = leonardo;
        address nameOwner = ed;
        uint256 primarySalt = bound(salt, 0, 63);
        string memory primaryName = _labelPopfull(primarySalt);

        _grantPopFull(nameOwner);

        IDotnsRegistrarController.Registration memory primaryRegistration =
            _commitFor(primaryName, nameOwner, true);

        vm.prank(nameOwner);
        dotnsRegistrarController.register{value: 0}(primaryRegistration);

        assertEq(dotnsReverseResolver.nameOf(nameOwner), string.concat(primaryName, ".dot"));

        string memory giftedName = _labelNoStatusPriced(primarySalt + 1);

        _grantPopFull(payer);

        IDotnsRegistrarController.Registration memory giftedRegistration =
            _commitFor(giftedName, nameOwner, true, payer);

        vm.prank(payer);
        dotnsRegistrarController.register{value: 0}(giftedRegistration);

        assertEq(dotnsReverseResolver.nameOf(nameOwner), string.concat(primaryName, ".dot"));
    }

    function testFuzz_transfer_clears_sender_primary_reverse(uint256 salt) public {
        address sender = ed;
        address recipient = leonardo;
        string memory nameLabel = _labelPopfull(bound(salt, 0, 64));

        _grantPopFull(sender);

        IDotnsRegistrarController.Registration memory registration =
            _commitFor(nameLabel, sender, true);

        vm.prank(sender);
        dotnsRegistrarController.register{value: 0}(registration);

        bytes32 labelhash = keccak256(bytes(nameLabel));
        bytes32 node = _namehash(dotNode, labelhash);
        uint256 tokenId = uint256(node);

        assertEq(dotnsReverseResolver.nameOf(sender), string.concat(nameLabel, ".dot"));

        uint256 _xferFee = dotnsRegistrar.quoteTransferFee(tokenId, recipient);
        vm.prank(sender);
        dotnsRegistrar.transferFrom{value: _xferFee}(sender, recipient, tokenId);

        assertEq(dotnsReverseResolver.nameOf(sender), "");
    }

    /// @notice Build, commit and warp past the minimum commitment age, with `nameOwner` as the
    ///         commitment sender.
    function _commitFor(
        string memory nameLabel,
        address nameOwner,
        bool reserved
    )
        internal
        returns (IDotnsRegistrarController.Registration memory registration)
    {
        return _commitFor(nameLabel, nameOwner, reserved, nameOwner);
    }

    /// @notice Build, commit and warp past the minimum commitment age, with an explicit
    ///         `commitmentSender` distinct from `nameOwner`.
    function _commitFor(
        string memory nameLabel,
        address nameOwner,
        bool reserved,
        address commitmentSender
    )
        internal
        returns (IDotnsRegistrarController.Registration memory registration)
    {
        bytes32 secret =
            keccak256(abi.encodePacked(nameLabel, nameOwner, block.timestamp, address(this)));

        registration = IDotnsRegistrarController.Registration({
            label: nameLabel, owner: nameOwner, secret: secret, reserved: reserved
        });

        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);

        vm.startPrank(commitmentSender);
        dotnsRegistrarController.commit(commitment);
        vm.stopPrank();

        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);
    }

    /// @notice Generate a label that classifies as PopFull (baselength 8, no trailing digits).
    function _labelPopfull(uint256 salt) internal pure returns (string memory label) {
        return string(abi.encodePacked("popful", _uintToAlphaFixed(salt, 2)));
    }

    /// @notice Generate a label that classifies as NoStatus and carries a non-zero price.
    function _labelNoStatusPriced(uint256 salt) internal pure returns (string memory label) {
        return string(abi.encodePacked("nostatus", _uintToAlphaFixed(salt, 2), "01"));
    }

    /// @notice Generate a label that classifies as PopLite and prices to zero.
    function _labelPriceZero(uint256 salt) internal pure returns (string memory label) {
        return string(abi.encodePacked("free", _uintToAlphaFixed(salt, 2), "01"));
    }

    /// @notice Render `value` as a fixed-length lowercase ASCII alphabetic string.
    function _uintToAlphaFixed(
        uint256 value,
        uint256 length
    )
        internal
        pure
        returns (string memory output)
    {
        bytes memory buffer = new bytes(length);
        uint256 remaining = value;

        for (uint256 index = 0; index < length; index++) {
            buffer[index] = bytes1(uint8(97 + (remaining % 26)));
            remaining /= 26;
        }

        return string(buffer);
    }
}
