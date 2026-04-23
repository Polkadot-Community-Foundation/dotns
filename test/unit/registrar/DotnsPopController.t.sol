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
        string memory liteLabel = "alice01";
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
        dotnsPopController.reserveBaseName("alice03", ed, "", "");
    }

    function test_reserveBaseName_enqueues_when_reserved_label_provided() public {
        _reservePop(ed, "alice04", hex"aa", "alice");

        (bool reserved, address holder) = dotnsPopController.isReservedForClaim("alice");
        assertTrue(reserved);
        assertEq(holder, ed);
    }

    function test_reserveBaseName_replaces_prior_reservation_when_user_reserves_again() public {
        _reservePop(ed, "alice05", hex"aa", "alice");
        _reservePop(ed, "alice06", hex"bb", "wonder");

        (bool aliceReserved,) = dotnsPopController.isReservedForClaim("alice");
        assertFalse(aliceReserved);

        (bool wonderReserved, address wonderHolder) =
            dotnsPopController.isReservedForClaim("wonder");
        assertTrue(wonderReserved);
        assertEq(wonderHolder, ed);
    }

    function test_registerBaseName_claim_emits_claim_event_and_not_standalone() public {
        _reservePop(ed, "alice20", hex"01", "alicebob");
        _reservePop(tiago, "bob21", hex"02", "alicebob");

        IDotnsPopController.Link memory link = _linkWithLite("alice20");

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
        _reservePop(tiago, "bob30", hex"01", "alicebob");

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
        _reservePop(ed, "alice40", liteChatKey, "alicebob");

        IDotnsPopController.Link memory link = _linkWithLite("alice40");
        vm.prank(popGateway);
        dotnsPopController.registerBaseName("alicebob", ed, link);

        bytes32 fullNode = _nodeOf("alicebob");
        assertEq(dotnsPopResolver.chatKey(fullNode), liteChatKey);
        assertEq(dotnsPopResolver.liteLink(fullNode), keccak256(bytes("alice40")));
    }

    function test_registerBaseName_claim_wipes_entire_queue() public {
        _reservePop(ed, "alice50", hex"01", "alicebob");
        _reservePop(tiago, "bob51", hex"02", "alicebob");
        _reservePop(leonardo, "carol52", hex"03", "alicebob");

        IDotnsPopController.Link memory link = _linkWithLite("alice50");
        vm.prank(popGateway);
        dotnsPopController.registerBaseName("alicebob", ed, link);

        _reservePop(tiago, "bob53", hex"04", "wonder");
        (, address wonderHolder) = dotnsPopController.isReservedForClaim("wonder");
        assertEq(wonderHolder, tiago);
    }

    function test_registerBaseName_standalone_auto_relinquishes_users_other_reservation() public {
        _reservePop(ed, "alice60", hex"01", "alicebob");

        IDotnsPopController.Link memory link = _linkFresh(hex"02");

        vm.prank(popGateway);
        dotnsPopController.registerBaseName("wonderland01", ed, link);

        (bool reserved,) = dotnsPopController.isReservedForClaim("alicebob");
        assertFalse(reserved);
    }

    function test_registerBaseName_standalone_with_lite_link_silently_relinquishes() public {
        _reservePop(ed, "alice70", hex"01", "alicebob");

        IDotnsPopController.Link memory link = _linkWithLite("alice70");

        vm.recordLogs();
        vm.prank(popGateway);
        dotnsPopController.registerBaseName("wonderland01", ed, link);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertEventEmittedOnce(logs, keccak256("StandaloneNameRegistered(bytes32,address,string)"));
        _assertEventEmittedOnce(logs, keccak256("LiteToFullLinked(bytes32,bytes32)"));
        _assertEventNotEmitted(logs, keccak256("BaseNameClaimed(bytes32,address,string)"));
        _assertEventNotEmitted(logs, keccak256("ReservationRelinquished(bytes32,address)"));

        bytes32 fullNode = _nodeOf("wonderland01");
        assertEq(dotnsPopResolver.liteLink(fullNode), keccak256(bytes("alice70")));

        (bool reserved,) = dotnsPopController.isReservedForClaim("alicebob");
        assertFalse(reserved);
    }

    function test_registerBaseName_reverts_for_non_gateway_caller() public {
        IDotnsPopController.Link memory link = _linkFresh(hex"aa");

        vm.prank(ed);
        vm.expectRevert(abi.encodeWithSelector(IDotnsPopController.NotGateway.selector, ed));
        dotnsPopController.registerBaseName("alicebob", ed, link);
    }

    function test_relinquishReservation_promotes_next_waiter_when_head_leaves() public {
        _reservePop(ed, "alice80", hex"01", "alicebob");
        _reservePop(tiago, "bob81", hex"02", "alicebob");

        vm.prank(ed);
        dotnsPopController.relinquishReservation();

        (bool reserved, address holder) = dotnsPopController.isReservedForClaim("alicebob");
        assertTrue(reserved);
        assertEq(holder, tiago);
    }

    function test_relinquishReservation_removes_non_head_without_promotion() public {
        _reservePop(ed, "alice85", hex"01", "alicebob");
        _reservePop(tiago, "bob86", hex"02", "alicebob");

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

    // The previous test was a write-then-read tautology. This version pins the
    // real governance risk: `_isExpired` reads the CURRENT `reservationDuration`
    // on every check, so shrinking the duration retroactively expires entries
    // that were live under the old window. Documenting this explicitly prevents
    // a silent regression if the field is ever changed to absolute expiry.
    function test_setReservationDuration_shortening_retroactively_expires_live_entries() public {
        // Enqueue alice under the default duration (7 days).
        _reservePop(ed, "alice87", hex"01", "alicebob");

        (bool liveBefore, address holderBefore) = dotnsPopController.isReservedForClaim("alicebob");
        assertTrue(liveBefore);
        assertEq(holderBefore, ed);

        // Warp 2 days forward (still well within the original 7-day window).
        vm.warp(block.timestamp + 2 days);

        // Governance shrinks the window to 1 day. The entry's `joinedAt` plus
        // the new duration is now in the past, so the slot is expired.
        vm.prank(owner);
        dotnsPopController.setReservationDuration(1 days);

        (bool liveAfter,) = dotnsPopController.isReservedForClaim("alicebob");
        assertFalse(liveAfter);
    }

    function test_setReservationDuration_reverts_for_non_owner() public {
        vm.prank(ed);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", ed));
        dotnsPopController.setReservationDuration(14 days);
    }

    // Queue capacity hard-cap must hold: the 65th reservation on a label must
    // revert with `QueueFull`. Unit-level cap never asserted before; relying on
    // the invariant runner alone gives flaky coverage for an O(1) revert.
    function test_enqueueReservation_reverts_when_queue_full() public {
        string memory baseStem = "alicebob";
        uint16 cap = dotnsPopController.MAX_RESERVATION_QUEUE();

        // Fill to capacity. Each reserve call needs a distinct actor (one active
        // reservation per account) and a distinct lite label (ERC721 uniqueness).
        for (uint256 i = 0; i < cap; i++) {
            address actor = makeAddr(string.concat("filler", vm.toString(i)));
            // Lite suffix starts at 10 so `vm.toString` always yields >= 2 digits.
            string memory lite = string.concat("filler", vm.toString(i + 10));
            _reservePop(actor, lite, hex"01", baseStem);
        }

        // One more must revert at the queue-full guard.
        address overflow = makeAddr("overflow");
        vm.prank(popGateway);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsPopController.QueueFull.selector, keccak256(bytes(baseStem))
            )
        );
        dotnsPopController.reserveBaseName("overflow99", overflow, hex"01", baseStem);
    }

    function test_reEnqueue_after_own_expiry_promotes_same_user_to_head() public {
        string memory baseStem = "alicebob";

        _reservePop(ed, "alice80", hex"01", baseStem);

        // Warp past the reservation window and fire the GC so ed's pointer gets
        // cleared by `_advanceExpiredHead`. If the expiry path forgets the
        // per-user pointer, the second reserve call below hits `AlreadyReserved`
        // and the account is permanently stuck.
        vm.warp(block.timestamp + dotnsPopController.reservationDuration() + 1);
        dotnsPopController.expireReservation(baseStem);

        (bool expiredReserved,) = dotnsPopController.isReservedForClaim(baseStem);
        assertFalse(expiredReserved);

        // Same user reserves the same stem again with a fresh lite label.
        _reservePop(ed, "alice81", hex"02", baseStem);

        (bool nowReserved, address holder) = dotnsPopController.isReservedForClaim(baseStem);
        assertTrue(nowReserved);
        assertEq(holder, ed);
    }

    function test_claim_then_reEnqueue_on_same_stem_resets_cleanly() public {
        string memory baseStem = "alicebob";

        _reservePop(ed, "alice82", hex"01", baseStem);

        // Claim wipes the queue via `_clearQueue` which must also drop
        // `_reservedBaseLabel[labelhash]` and release the PopRules slot. Missing
        // any one of those lets the next reservation inherit stale state.
        IDotnsPopController.Link memory link = _linkWithLite("alice82");
        vm.prank(popGateway);
        dotnsPopController.registerBaseName(baseStem, ed, link);

        (bool oldSlot, address oldHolder) = dotnsPopController.isReservedForClaim(baseStem);
        assertFalse(oldSlot);
        assertEq(oldHolder, address(0));

        // Fresh stem, different user. If the previous queue leaked, this enqueue
        // would either revert or land the wrong head address on PopRules.
        _reservePop(tiago, "bob83", hex"02", "wonder");
        (bool newSlot, address newHolder) = dotnsPopController.isReservedForClaim("wonder");
        assertTrue(newSlot);
        assertEq(newHolder, tiago);

        (address popHolder,) = popRules.getBaseNameReservation("wonder");
        assertEq(popHolder, tiago);
    }

    function test_expireReservation_is_permissionless() public {
        _reservePop(ed, "alice84", hex"01", "alicebob");

        vm.warp(block.timestamp + dotnsPopController.reservationDuration() + 1);

        // Anyone can call. Pinning this prevents a future patch from silently
        // adding `onlyGateway` and breaking permissionless garbage collection.
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        dotnsPopController.expireReservation("alicebob");

        (bool reserved,) = dotnsPopController.isReservedForClaim("alicebob");
        assertFalse(reserved);
    }

    function test_head_expires_with_tombstone_in_middle_advances_to_next_live() public {
        string memory baseStem = "alicebob";

        // Three staggered enqueues so each entry's `joinedAt` is distinct. The
        // stagger also guarantees ed expires before leonardo does.
        _reservePop(ed, "alice85", hex"01", baseStem);

        vm.warp(block.timestamp + 1 days);
        _reservePop(tiago, "bob86", hex"02", baseStem);

        vm.warp(block.timestamp + 1 days);
        _reservePop(leonardo, "carol87", hex"03", baseStem);

        // Mid-queue relinquish leaves a zero-owner tombstone at tiago's index.
        vm.prank(tiago);
        dotnsPopController.relinquishReservation();

        // Warp just past ed's window but not leonardo's. ed's joinedAt is t0,
        // leonardo's is t0+2 days. Window is 7 days by default, so t0+8 days
        // expires ed (8 >= 7) but not leonardo (6 < 7). `_advanceExpiredHead`
        // must walk: evict ed, skip the zero-owner tombstone, land on leonardo.
        vm.warp(block.timestamp + dotnsPopController.reservationDuration() - 1 days);
        dotnsPopController.expireReservation(baseStem);

        (bool reserved, address holder) = dotnsPopController.isReservedForClaim(baseStem);
        assertTrue(reserved);
        assertEq(holder, leonardo);

        (address popHolder,) = popRules.getBaseNameReservation(baseStem);
        assertEq(popHolder, leonardo);
    }

    // Format constraints for the two entry points are complementary rather than
    // disjoint: `reserveBaseName` demands a lite label (a DNS label with at
    // least two trailing digits) and `registerBaseName` demands any single DNS
    // label. Labels satisfying both, such as "alice42", are legal to mint via
    // either surface, so collisions are resolved by the ERC721 uniqueness
    // guarantee on the shared registrar. This test pins the rejection ends of
    // each surface: a digitless stem fails `reserveBaseName`, and a dotted
    // label fails `registerBaseName`.
    function test_entry_point_format_rejections() public {
        vm.prank(popGateway);
        vm.expectRevert(IDotnsPopController.InvalidLiteLabel.selector);
        dotnsPopController.reserveBaseName("alice", ed, "", "");

        IDotnsPopController.Link memory link = _linkFresh(hex"aa");
        vm.prank(popGateway);
        vm.expectRevert(IDotnsPopController.InvalidBaseLabel.selector);
        dotnsPopController.registerBaseName("not.valid", ed, link);
    }

    function test_same_stem_lite_and_base_occupy_distinct_registrar_tokens() public {
        _reservePop(ed, "alice42", hex"aa", "");

        IDotnsPopController.Link memory link = _linkFresh(hex"bb");
        vm.prank(popGateway);
        dotnsPopController.registerBaseName("alice", tiago, link);

        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf("alice42"))), ed);
        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf("alice"))), tiago);
    }

    function test_both_controllers_can_mint_on_shared_registrar() public {
        _reservePop(ed, "alice91", hex"01", "");
        _commitAndRegister("longnamebob01", tiago, true);

        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf("alice91"))), ed);
        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf("longnamebob01"))), tiago);
    }

    // Gateway reservation now locks the base name on PopRules, so the public
    // commit-reveal flow rejects another user's attempt to mint the same stem
    // for the lifetime of the reservation.
    function test_gateway_reserved_name_rejects_public_register_by_other_user() public {
        // Gateway reserves the bare stem; PopRules.priceWithCheck strips the two
        // trailing digits from "longnamebob01" and matches against reservations["longnamebob"].
        _reservePop(tiago, "alice92", hex"11", "longnamebob");

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
        _reservePop(tiago, "alice93", hex"11", "longnamebob");

        _commitAndRegister("longnamebob01", tiago, true);
        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf("longnamebob01"))), tiago);
    }

    // A second PoP lite-mint of the same label reverts at the registrar's
    // ERC721 availability check, because the token was already minted.
    function test_second_pop_lite_mint_of_same_label_reverts_at_registrar() public {
        _reservePop(ed, "alice42", hex"aa", "");

        vm.prank(popGateway);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsRegistrar.NameNotAvailable.selector, uint256(_nodeOf("alice42"))
            )
        );
        dotnsPopController.reserveBaseName("alice42", tiago, hex"bb", "");
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
    // controller-specific; the guard is the same whether the parent was
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

        _reservePop(tiago, "alice42", hex"aa", "longnamebob01");

        (bool reserved, address holder) = dotnsPopController.isReservedForClaim("longnamebob01");
        assertTrue(reserved);
        assertEq(holder, tiago);

        IDotnsPopController.Link memory link = _linkWithLite("alice42");
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
        _reservePop(ed, "alice10", hex"aa", "longnamebob");

        (address holder, uint64 expires) = popRules.getBaseNameReservation("longnamebob");
        assertEq(holder, ed);
        assertEq(expires, uint64(block.timestamp + popRules.MAX_RESERVATION_TIME()));
    }

    // Tail enqueue (slot already live for someone else) must not overwrite the
    // PopRules.reservations slot: the first reserver keeps priority.
    function test_enqueue_not_head_does_not_touch_popRules() public {
        _reservePop(ed, "alice11", hex"aa", "longnamebob");
        (, uint64 originalExpiry) = popRules.getBaseNameReservation("longnamebob");

        // Second reserver lands at the tail; no PopRules write should happen.
        _reservePop(tiago, "bob12", hex"bb", "longnamebob");

        (address holder, uint64 expires) = popRules.getBaseNameReservation("longnamebob");
        assertEq(holder, ed);
        assertEq(expires, originalExpiry);
    }

    // Successful claim wipes the queue and releases the PopRules slot so the
    // public commit-reveal flow is unblocked for every other user.
    function test_claim_releases_popRules_slot() public {
        _reservePop(ed, "alice13", hex"aa", "longnamebob");

        IDotnsPopController.Link memory link = _linkWithLite("alice13");
        vm.prank(popGateway);
        dotnsPopController.registerBaseName("longnamebob", ed, link);

        (address holder,) = popRules.getBaseNameReservation("longnamebob");
        assertEq(holder, address(0));
    }

    // Final relinquish (no other queued waiter) releases the PopRules slot.
    function test_relinquish_last_releases_popRules_slot() public {
        _reservePop(ed, "alice14", hex"aa", "longnamebob");

        vm.prank(ed);
        dotnsPopController.relinquishReservation();

        (address holder,) = popRules.getBaseNameReservation("longnamebob");
        assertEq(holder, address(0));
    }

    // Head promotion under relinquish and expiry is covered by the cross-contract
    // sync invariant `invariant_popRules_head_matches_queue_head_or_zero` (and the
    // equivalent fuzz `testFuzz_popRules_head_owner_matches_queue_head`), which
    // walk arbitrary enqueue / relinquish / expire / warp sequences and assert
    // the live-head equivalence between PopRules and the PoP controller's queue.

    // Last-remaining head expires and the queue empties; PopRules slot clears.
    function test_advanceExpiredHead_last_expire_releases_popRules_slot() public {
        _reservePop(ed, "alice19", hex"aa", "longnamebob");

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
        _reservePop(ed, "alice21", hex"aa", "longnamebob01");

        // Slot is written under the raw label.
        (address rawHolder,) = popRules.getBaseNameReservation("longnamebob01");
        assertEq(rawHolder, ed);

        // Stripped-stem slot is empty; public flow for "longnamebob01" is
        // NOT blocked for other users (documented misuse surface).
        (address strippedHolder,) = popRules.getBaseNameReservation("longnamebob");
        assertEq(strippedHolder, address(0));
    }

    // After a claim clears the slot, a different user can mint the stem via
    // the public commit-reveal flow. Exercises release-on-claim end-to-end.
    function test_public_stranger_can_mint_after_claim_clears_reservation() public {
        _reservePop(ed, "alice22", hex"aa", "longnamebob");

        IDotnsPopController.Link memory link = _linkWithLite("alice22");
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
        _reservePop(ed, "alice23", hex"aa", "longnamebob");

        vm.warp(block.timestamp + dotnsPopController.reservationDuration() + 1);
        dotnsPopController.expireReservation("longnamebob");

        _commitAndRegister("longnamebob01", tiago, true);
        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf("longnamebob01"))), tiago);
    }

    // A registered controller on `DotnsRegistrar` that is NOT the PoP gateway
    // must not be able to reach the sync path through the PoP controller's
    // entrypoints; the `onlyGateway` check is independent of controller
    // authorisation on the registrar.
    function test_controller_authorised_but_not_gateway_cannot_enter_pop_flow() public {
        // The public commit-reveal controller is already a registered controller.
        address otherController = address(dotnsRegistrarController);

        vm.prank(otherController);
        vm.expectRevert(
            abi.encodeWithSelector(IDotnsPopController.NotGateway.selector, otherController)
        );
        dotnsPopController.reserveBaseName("alice24", ed, "", "longnamebob");
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

    function test_expireReservation_on_empty_queue_is_noop() public {
        // Permissionless expire against a label with no reservations must be a
        // no-op. The path is cheap enough that a bot can spam it; reverting on
        // empty queues would turn that spam into an accidental DoS against
        // unrelated callers.
        string memory stem = "noqueue";

        (bool reservedBefore,) = dotnsPopController.isReservedForClaim(stem);
        assertFalse(reservedBefore);

        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        dotnsPopController.expireReservation(stem);

        (bool reservedAfter,) = dotnsPopController.isReservedForClaim(stem);
        assertFalse(reservedAfter);
    }

    function test_setReservationDuration_zero_makes_new_reservations_immediately_expired() public {
        // `reservationDuration` has no zero-guard. Setting it to 0 means every
        // freshly enqueued reservation is classified expired by `_isExpired`
        // on the same block. Pin the behaviour so a future patch that adds a
        // zero-guard cannot silently drift this semantic.
        vm.prank(owner);
        dotnsPopController.setReservationDuration(0);

        _reservePop(ed, "alice77", hex"01", "alicebob");

        (bool reserved,) = dotnsPopController.isReservedForClaim("alicebob");
        assertFalse(reserved);
    }
}
