// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../../base/BaseDotns.t.sol";
import {IDotnsPopController} from "../../../contracts/registrars/IDotnsPopController.sol";
import {IDotnsRegistrar} from "../../../contracts/registrars/IDotnsRegistrar.sol";
import {
    IDotnsRegistrarController
} from "../../../contracts/registrars/IDotnsRegistrarController.sol";
import {IDotnsRegistry} from "../../../contracts/registry/IDotnsRegistry.sol";
import {IPopRules} from "../../../contracts/pop/IPopRules.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title DotnsPopControllerTests
/// @notice Behavioural unit tests for the dedicated PoP controller driving the
///         gateway flow. Parameterised coverage (label format, chat-key payload,
///         duration boundary) lives in the sibling fuzz file; these tests assert
///         specific behaviours that do not benefit from input variation.
contract DotnsPopControllerTests is BaseDotns {
    function test_reserveBaseName_mints_and_wires_registry_and_resolver() public {
        string memory liteLabel = "alice.01";
        bytes memory chatKey = hex"01020304";

        _reservePop(ed, liteLabel, chatKey, "");

        bytes32 node = _nodeOf(liteLabel);
        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(node)), ed);
        assertEq(dotnsRegistry.owner(node), ed);
        assertEq(dotnsPopResolver.chatKey(node), chatKey);
    }

    function test_reserveBaseName_reverts_for_non_gateway_caller() public {
        vm.prank(ed);
        vm.expectRevert(abi.encodeWithSelector(IDotnsPopController.NotGateway.selector, ed));
        dotnsPopController.reserveBaseName("alice.03", ed, "", "");
    }

    function test_reserveBaseName_enqueues_when_reserved_label_provided() public {
        _reservePop(ed, "alice.04", hex"aa", "alice");

        (bool reserved, address holder) = dotnsPopController.isReservedForClaim("alice");
        assertTrue(reserved);
        assertEq(holder, ed);
    }

    function test_reserveBaseName_replaces_prior_reservation_when_user_reserves_again() public {
        _reservePop(ed, "alice.05", hex"aa", "alice");
        _reservePop(ed, "alice.06", hex"bb", "wonder");

        (bool aliceReserved,) = dotnsPopController.isReservedForClaim("alice");
        assertFalse(aliceReserved);

        (bool wonderReserved, address wonderHolder) =
            dotnsPopController.isReservedForClaim("wonder");
        assertTrue(wonderReserved);
        assertEq(wonderHolder, ed);
    }

    function test_registerBaseName_claim_emits_claim_event_and_not_standalone() public {
        _reservePop(ed, "alice.20", hex"01", "alicebob");
        _reservePop(tiago, "bob.21", hex"02", "alicebob");

        IDotnsPopController.Link memory link = _linkWithLite("alice.20");

        vm.recordLogs();
        vm.prank(popGateway);
        dotnsPopController.registerBaseName("alicebob", ed, link);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertEventEmittedOnce(logs, keccak256("BaseNameClaimed(bytes32,address,string)"));
        _assertEventNotEmitted(logs, keccak256("StandaloneNameRegistered(bytes32,address,string)"));

        (bool reserved,) = dotnsPopController.isReservedForClaim("alicebob");
        assertFalse(reserved);
    }

    function test_registerBaseName_standalone_emits_standalone_event_and_not_claim() public {
        _reservePop(tiago, "bob.30", hex"01", "alicebob");

        IDotnsPopController.Link memory link = _linkFresh(hex"cafe");

        vm.recordLogs();
        vm.prank(popGateway);
        dotnsPopController.registerBaseName("charlie", ed, link);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertEventEmittedOnce(logs, keccak256("StandaloneNameRegistered(bytes32,address,string)"));
        _assertEventNotEmitted(logs, keccak256("BaseNameClaimed(bytes32,address,string)"));
    }

    function test_registerBaseName_claim_inherits_chat_key_from_lite_node() public {
        bytes memory liteChatKey = hex"aa11bb22cc33";
        _reservePop(ed, "alice.40", liteChatKey, "alicebob");

        IDotnsPopController.Link memory link = _linkWithLite("alice.40");
        vm.prank(popGateway);
        dotnsPopController.registerBaseName("alicebob", ed, link);

        bytes32 fullNode = _nodeOf("alicebob");
        assertEq(dotnsPopResolver.chatKey(fullNode), liteChatKey);
        assertEq(dotnsPopResolver.liteLink(fullNode), keccak256(bytes("alice.40")));
    }

    function test_registerBaseName_claim_wipes_entire_queue() public {
        _reservePop(ed, "alice.50", hex"01", "alicebob");
        _reservePop(tiago, "bob.51", hex"02", "alicebob");
        _reservePop(leonardo, "carol.52", hex"03", "alicebob");

        IDotnsPopController.Link memory link = _linkWithLite("alice.50");
        vm.prank(popGateway);
        dotnsPopController.registerBaseName("alicebob", ed, link);

        _reservePop(tiago, "bob.53", hex"04", "wonder");
        (, address wonderHolder) = dotnsPopController.isReservedForClaim("wonder");
        assertEq(wonderHolder, tiago);
    }

    function test_registerBaseName_standalone_auto_relinquishes_users_other_reservation() public {
        _reservePop(ed, "alice.60", hex"01", "alicebob");

        IDotnsPopController.Link memory link = _linkFresh(hex"02");

        vm.prank(popGateway);
        dotnsPopController.registerBaseName("wonderland01", ed, link);

        (bool reserved,) = dotnsPopController.isReservedForClaim("alicebob");
        assertFalse(reserved);
    }

    function test_registerBaseName_standalone_with_lite_link_silently_relinquishes() public {
        _reservePop(ed, "alice.70", hex"01", "alicebob");

        IDotnsPopController.Link memory link = _linkWithLite("alice.70");

        vm.recordLogs();
        vm.prank(popGateway);
        dotnsPopController.registerBaseName("wonderland01", ed, link);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertEventEmittedOnce(logs, keccak256("StandaloneNameRegistered(bytes32,address,string)"));
        _assertEventEmittedOnce(logs, keccak256("LiteToFullLinked(bytes32,bytes32)"));
        _assertEventNotEmitted(logs, keccak256("BaseNameClaimed(bytes32,address,string)"));
        _assertEventNotEmitted(logs, keccak256("ReservationRelinquished(bytes32,address)"));

        bytes32 fullNode = _nodeOf("wonderland01");
        assertEq(dotnsPopResolver.liteLink(fullNode), keccak256(bytes("alice.70")));

        (bool reserved,) = dotnsPopController.isReservedForClaim("alicebob");
        assertFalse(reserved);
    }

    function test_registerBaseName_reverts_for_non_gateway_caller() public {
        IDotnsPopController.Link memory link = _linkFresh(hex"aa");

        vm.prank(ed);
        vm.expectRevert(abi.encodeWithSelector(IDotnsPopController.NotGateway.selector, ed));
        dotnsPopController.registerBaseName("alicebob", ed, link);
    }

    function test_registerBaseName_reverts_on_base_label_containing_dot() public {
        IDotnsPopController.Link memory link = _linkFresh(hex"aa");

        vm.prank(popGateway);
        vm.expectRevert(IDotnsPopController.InvalidBaseLabel.selector);
        dotnsPopController.registerBaseName("not.valid", ed, link);
    }

    function test_relinquishReservation_promotes_next_waiter_when_head_leaves() public {
        _reservePop(ed, "alice.80", hex"01", "alicebob");
        _reservePop(tiago, "bob.81", hex"02", "alicebob");

        vm.prank(ed);
        dotnsPopController.relinquishReservation();

        (bool reserved, address holder) = dotnsPopController.isReservedForClaim("alicebob");
        assertTrue(reserved);
        assertEq(holder, tiago);
    }

    function test_relinquishReservation_removes_non_head_without_promotion() public {
        _reservePop(ed, "alice.85", hex"01", "alicebob");
        _reservePop(tiago, "bob.86", hex"02", "alicebob");

        vm.prank(tiago);
        dotnsPopController.relinquishReservation();

        (, address holder) = dotnsPopController.isReservedForClaim("alicebob");
        assertEq(holder, ed);
    }

    function test_relinquishReservation_reverts_when_caller_has_no_reservation() public {
        vm.prank(ed);
        vm.expectRevert(
            abi.encodeWithSelector(IDotnsPopController.NoActiveReservation.selector, ed)
        );
        dotnsPopController.relinquishReservation();
    }

    function test_setReservationDuration_updates_value_and_emits() public {
        vm.expectEmit(false, false, false, true, address(dotnsPopController));
        emit IDotnsPopController.ReservationDurationSet(14 days);

        vm.prank(owner);
        dotnsPopController.setReservationDuration(14 days);

        assertEq(dotnsPopController.reservationDuration(), 14 days);
    }

    function test_setReservationDuration_reverts_for_non_owner() public {
        vm.prank(ed);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", ed));
        dotnsPopController.setReservationDuration(14 days);
    }

    function test_lite_and_base_label_formats_are_disjoint() public {
        vm.prank(popGateway);
        vm.expectRevert(IDotnsPopController.InvalidLiteLabel.selector);
        dotnsPopController.reserveBaseName("alice", ed, "", "");

        IDotnsPopController.Link memory link = _linkFresh(hex"aa");
        vm.prank(popGateway);
        vm.expectRevert(IDotnsPopController.InvalidBaseLabel.selector);
        dotnsPopController.registerBaseName("alice.42", ed, link);
    }

    function test_same_stem_lite_and_base_occupy_distinct_registrar_tokens() public {
        _reservePop(ed, "alice.42", hex"aa", "");

        IDotnsPopController.Link memory link = _linkFresh(hex"bb");
        vm.prank(popGateway);
        dotnsPopController.registerBaseName("alice", tiago, link);

        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf("alice.42"))), ed);
        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf("alice"))), tiago);
    }

    function test_both_controllers_can_mint_on_shared_registrar() public {
        _reservePop(ed, "alice.91", hex"01", "");
        _commitAndRegister("longnamebob01", tiago, true);

        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf("alice.91"))), ed);
        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf("longnamebob01"))), tiago);
    }

    // Gateway reservation now locks the base name on PopRules, so the public
    // commit-reveal flow rejects another user's attempt to mint the same stem
    // for the lifetime of the reservation.
    function test_gateway_reserved_name_rejects_public_register_by_other_user() public {
        // Gateway reserves the bare stem; PopRules.priceWithCheck strips the two
        // trailing digits from "longnamebob01" and matches against reservations["longnamebob"].
        _reservePop(tiago, "alice.92", hex"11", "longnamebob");

        (address holder,) = popRules.getBaseNameReservation("longnamebob");
        assertEq(holder, tiago);

        // The revert surface is PopRules.priceWithCheck, reached only when the
        // public controller pulls the price during register. We therefore drive
        // the commit-reveal flow by hand so the expectRevert cheatcode lands on
        // the register call rather than on makeCommitment (a view).
        string memory label = "longnamebob01";
        bytes32 secret = keccak256(abi.encodePacked(label, ed, block.timestamp));
        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label, owner: ed, secret: secret, reserved: true
            });

        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);
        vm.prank(ed);
        dotnsRegistrarController.commit(commitment);
        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPopRules.PopError.selector, "Base name reserved for original Lite registrant"
            )
        );
        vm.prank(ed);
        dotnsRegistrarController.register{value: 1 ether}(registration);
    }

    // Symmetric check: the reservation holder can still commit-reveal the base
    // name themselves. The PopRules guard only rejects OTHER users; the holder
    // owns the slot and passes the `reservation.owner == userAddress` branch.
    function test_gateway_reserved_name_allows_holder_to_register_via_public() public {
        _reservePop(tiago, "alice.93", hex"11", "longnamebob");

        _commitAndRegister("longnamebob01", tiago, true);
        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf("longnamebob01"))), tiago);
    }

    // A second PoP lite-mint of the same label reverts at the registrar's
    // ERC721 availability check, because the token was already minted.
    function test_second_pop_lite_mint_of_same_label_reverts_at_registrar() public {
        _reservePop(ed, "alice.42", hex"aa", "");

        vm.prank(popGateway);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsRegistrar.NameNotAvailable.selector, uint256(_nodeOf("alice.42"))
            )
        );
        dotnsPopController.reserveBaseName("alice.42", tiago, hex"bb", "");
    }

    // After a PoP full-person mint of a base label, a subsequent public
    // commit-reveal registration of the same label reverts on the
    // registrar's availability check rather than any PoP-level guard.
    function test_public_register_after_pop_full_mint_reverts_at_registrar() public {
        IDotnsPopController.Link memory link = _linkFresh(hex"cafe");
        vm.prank(popGateway);
        dotnsPopController.registerBaseName("longnamebob01", ed, link);

        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf("longnamebob01"))), ed);

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: "longnamebob01", owner: tiago, secret: keccak256("secret"), reserved: true
            });

        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);
        vm.prank(tiago);
        dotnsRegistrarController.commit(commitment);
        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        uint256 price = popRules.priceWithCheck("longnamebob01", tiago).price;

        vm.prank(tiago);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsRegistrarController.NameNotAvailable.selector, "longnamebob01"
            )
        );
        dotnsRegistrarController.register{value: price}(registration);
    }

    // The owner of a PoP-minted full-person name can create subnames under
    // it via the existing `DotnsRegistry.setSubnodeOwner` path.
    // Exercises AC #2 of paritytech/dotns#115 ("support issuance of PoP-specific
    // subnames under an existing or protocol-controlled parent"). No new
    // entrypoint on `DotnsPopController` is required: subname creation is
    // authorised by the ERC721 owner of the parent node, and the PoP
    // controller mints the ERC721 the same way the commit-reveal controller
    // does. The subname's Store-write path also uses the canonical
    // `RegistrationUtils.storeControllers` allowlist, so the PoP controller
    // is authorised on the new subname owner's Store.
    function test_owner_of_pop_minted_name_can_create_subname() public {
        IDotnsPopController.Link memory link = _linkFresh(hex"cafe");
        vm.prank(popGateway);
        dotnsPopController.registerBaseName("alicebob", ed, link);

        bytes32 parentNode = _nodeOf("alicebob");
        IDotnsRegistry.SubnodeRecord memory subnodeRecord = IDotnsRegistry.SubnodeRecord({
            parentNode: parentNode, subLabel: "app", parentLabel: "alicebob", owner: leonardo
        });

        vm.prank(ed);
        bytes32 subnode = dotnsRegistry.setSubnodeOwner(subnodeRecord);

        assertEq(dotnsRegistry.owner(subnode), leonardo);
    }

    // A non-owner cannot create subnames under a PoP-minted name.
    // Confirms authorisation on the subname path is ERC721-owner-gated, not
    // controller-specific — the guard is the same whether the parent was
    // minted by the commit-reveal controller or the PoP controller.
    function test_non_owner_cannot_create_subname_under_pop_minted_name() public {
        IDotnsPopController.Link memory link = _linkFresh(hex"cafe");
        vm.prank(popGateway);
        dotnsPopController.registerBaseName("alicebob", ed, link);

        bytes32 parentNode = _nodeOf("alicebob");
        IDotnsRegistry.SubnodeRecord memory subnodeRecord = IDotnsRegistry.SubnodeRecord({
            parentNode: parentNode, subLabel: "app", parentLabel: "alicebob", owner: tiago
        });

        vm.prank(tiago);
        vm.expectRevert(IDotnsRegistry.NotAuthorised.selector);
        dotnsRegistry.setSubnodeOwner(subnodeRecord);
    }

    // A PoP reservation can be queued for a label already minted by the
    // public controller (queue is intra-PoP only). The later claim attempt
    // reverts at the registrar's availability check, surfacing the
    // collision without corrupting queue state.
    function test_pop_reservation_of_already_public_minted_name_fails_on_claim() public {
        _commitAndRegister("longnamebob01", ed, true);

        _reservePop(tiago, "alice.42", hex"aa", "longnamebob01");

        (bool reserved, address holder) = dotnsPopController.isReservedForClaim("longnamebob01");
        assertTrue(reserved);
        assertEq(holder, tiago);

        IDotnsPopController.Link memory link = _linkWithLite("alice.42");
        vm.prank(popGateway);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsRegistrar.NameNotAvailable.selector, uint256(_nodeOf("longnamebob01"))
            )
        );
        dotnsPopController.registerBaseName("longnamebob01", tiago, link);
    }

    // Enqueue that becomes the head writes the holder into PopRules.reservations
    // so the public commit-reveal flow blocks other users on the same stem.
    function test_enqueue_becomesHead_writes_popRules_reservation() public {
        _reservePop(ed, "alice.10", hex"aa", "longnamebob");

        (address holder, uint64 expires) = popRules.getBaseNameReservation("longnamebob");
        assertEq(holder, ed);
        assertEq(expires, uint64(block.timestamp + popRules.MAX_RESERVATION_TIME()));
    }

    // Tail enqueue (slot already live for someone else) must not overwrite the
    // PopRules.reservations slot: the first reserver keeps priority.
    function test_enqueue_not_head_does_not_touch_popRules() public {
        _reservePop(ed, "alice.11", hex"aa", "longnamebob");
        (, uint64 originalExpiry) = popRules.getBaseNameReservation("longnamebob");

        // Second reserver lands at the tail — no PopRules write should happen.
        _reservePop(tiago, "bob.12", hex"bb", "longnamebob");

        (address holder, uint64 expires) = popRules.getBaseNameReservation("longnamebob");
        assertEq(holder, ed);
        assertEq(expires, originalExpiry);
    }

    // Successful claim wipes the queue and releases the PopRules slot so the
    // public commit-reveal flow is unblocked for every other user.
    function test_claim_releases_popRules_slot() public {
        _reservePop(ed, "alice.13", hex"aa", "longnamebob");

        IDotnsPopController.Link memory link = _linkWithLite("alice.13");
        vm.prank(popGateway);
        dotnsPopController.registerBaseName("longnamebob", ed, link);

        (address holder,) = popRules.getBaseNameReservation("longnamebob");
        assertEq(holder, address(0));
    }

    // Final relinquish (no other queued waiter) releases the PopRules slot.
    function test_relinquish_last_releases_popRules_slot() public {
        _reservePop(ed, "alice.14", hex"aa", "longnamebob");

        vm.prank(ed);
        dotnsPopController.relinquishReservation();

        (address holder,) = popRules.getBaseNameReservation("longnamebob");
        assertEq(holder, address(0));
    }

    // Head relinquish promotes the next waiter and re-writes PopRules so the
    // public flow now blocks everyone except the newly promoted head.
    function test_relinquish_head_syncs_popRules_to_new_head() public {
        _reservePop(ed, "alice.15", hex"aa", "longnamebob");
        _reservePop(tiago, "bob.16", hex"bb", "longnamebob");

        vm.prank(ed);
        dotnsPopController.relinquishReservation();

        (address holder,) = popRules.getBaseNameReservation("longnamebob");
        assertEq(holder, tiago);
    }

    // `expireReservation` past duration with a waiter behind promotes the
    // next entry and syncs PopRules to the new head. Tiago enqueues after a
    // half-duration warp so his window extends past ed's, guaranteeing ed
    // expires first and tiago becomes the live successor.
    function test_advanceExpiredHead_promotes_and_syncs_popRules() public {
        _reservePop(ed, "alice.17", hex"aa", "longnamebob");

        vm.warp(block.timestamp + dotnsPopController.reservationDuration() / 2);
        _reservePop(tiago, "bob.18", hex"bb", "longnamebob");

        vm.warp(block.timestamp + dotnsPopController.reservationDuration() / 2 + 1);
        dotnsPopController.expireReservation("longnamebob");

        (address holder,) = popRules.getBaseNameReservation("longnamebob");
        assertEq(holder, tiago);
    }

    // Last-remaining head expires and the queue empties — PopRules slot clears.
    function test_advanceExpiredHead_last_expire_releases_popRules_slot() public {
        _reservePop(ed, "alice.19", hex"aa", "longnamebob");

        vm.warp(block.timestamp + dotnsPopController.reservationDuration() + 1);
        dotnsPopController.expireReservation("longnamebob");

        (address holder,) = popRules.getBaseNameReservation("longnamebob");
        assertEq(holder, address(0));
    }

    // The controller passes `reservedBaseLabel` to PopRules verbatim. If the
    // gateway supplies a label with trailing digits, the public controller's
    // `_stripDigits` check reads the stem and misses the reservation. This
    // locks the current behaviour so gateway-side misuse surfaces loudly.
    function test_controller_does_not_mutate_reservedBaseLabel_string() public {
        // "longnamebob01" has two trailing digits. PopRules stores it as-is,
        // but `priceWithCheck` queries reservations keyed by "longnamebob".
        _reservePop(ed, "alice.21", hex"aa", "longnamebob01");

        // Slot is written under the raw label.
        (address rawHolder,) = popRules.getBaseNameReservation("longnamebob01");
        assertEq(rawHolder, ed);

        // Stripped-stem slot is empty — public flow for "longnamebob01" is
        // NOT blocked for other users (documented misuse surface).
        (address strippedHolder,) = popRules.getBaseNameReservation("longnamebob");
        assertEq(strippedHolder, address(0));
    }

    // After a claim clears the slot, a different user can mint the stem via
    // the public commit-reveal flow. Exercises release-on-claim end-to-end.
    function test_public_stranger_can_mint_after_claim_clears_reservation() public {
        _reservePop(ed, "alice.22", hex"aa", "longnamebob");

        IDotnsPopController.Link memory link = _linkWithLite("alice.22");
        vm.prank(popGateway);
        dotnsPopController.registerBaseName("longnamebob", ed, link);

        // Now the stem is clear on PopRules, so tiago can register the
        // digit-suffixed variant "longnamebob01" via the public flow.
        _commitAndRegister("longnamebob01", tiago, true);
        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf("longnamebob01"))), tiago);
    }

    // After natural expiry of the head the slot must be cleared before the
    // public flow admits a stranger. Exercises release-on-last-expire.
    function test_public_stranger_can_mint_after_reservation_expires() public {
        _reservePop(ed, "alice.23", hex"aa", "longnamebob");

        vm.warp(block.timestamp + dotnsPopController.reservationDuration() + 1);
        dotnsPopController.expireReservation("longnamebob");

        _commitAndRegister("longnamebob01", tiago, true);
        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf("longnamebob01"))), tiago);
    }

    // A registered controller on `DotnsRegistrar` that is NOT the PoP gateway
    // must not be able to reach the sync path through the PoP controller's
    // entrypoints — the `onlyGateway` check is independent of controller
    // authorisation on the registrar.
    function test_controller_authorised_but_not_gateway_cannot_enter_pop_flow() public {
        // The public commit-reveal controller is already a registered controller.
        address otherController = address(dotnsRegistrarController);

        vm.prank(otherController);
        vm.expectRevert(
            abi.encodeWithSelector(IDotnsPopController.NotGateway.selector, otherController)
        );
        dotnsPopController.reserveBaseName("alice.24", ed, "", "longnamebob");
    }

    // Asserts exactly one entry in `logs` matches event signature `sig`.
    // Operates on a cached `Vm.Log[]` because `vm.getRecordedLogs()` drains
    // the buffer. Callers snapshot the logs into a local and pass to both
    // the present-check and absent-check helpers.
    function _assertEventEmittedOnce(Vm.Log[] memory logs, bytes32 sig) internal pure {
        uint256 count;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == sig) count++;
        }
        require(count == 1, "expected exactly one matching event");
    }

    // Asserts no entry in `logs` matches event signature `sig`.
    function _assertEventNotEmitted(Vm.Log[] memory logs, bytes32 sig) internal pure {
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == sig) {
                revert("unexpected event emitted");
            }
        }
    }
}
