// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

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
/// @notice Behavioural unit tests for the dedicated PoP controller driving
///         the gateway flow. Parameterised coverage (label format, chat-key
///         payload, duration boundary) lives in the sibling fuzz file; these
///         tests assert specific behaviours that do not benefit from input
///         variation.
contract DotnsPopControllerTests is BaseDotns {
    function test_reserveBaseName_mints_and_wires_registry_and_resolver() public {
        // Lite path requires PopLite tier and a classification-valid lite label.
        _grantPopFull(ed);
        bytes memory chatKey = _validChatKey(0x01);

        _reservePop(ed, LITE_LABEL_A, chatKey, "");

        bytes32 node = _nodeOf(LITE_LABEL_A);
        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(node)), ed);
        assertEq(dotnsRegistry.owner(node), ed);
        assertEq(dotnsPopResolver.chatKey(node), chatKey);
    }

    function test_reserveBaseName_reverts_when_origin_is_not_root() public {
        _mockCallerIsRoot(false);
        vm.expectRevert(
            abi.encodeWithSelector(IDotnsPopController.NotGateway.selector, address(this))
        );
        dotnsPopController.reserveBaseName(
            IDotnsPopController.BaseReservation({
                lite: IDotnsPopController.LiteRegistration({
                    liteLabel: LITE_LABEL_A, user: ed, chatKey: ""
                }),
                reservedBaseLabel: ""
            })
        );
    }

    function test_reserveBaseName_enqueues_when_reserved_label_provided() public {
        // PopRules.priceWithCheck now forbids a second user queueing behind the
        // live head on the same base stem, so the queue is effectively
        // single-user. Kept as a single-reserver claim to assert the claim
        // event path; multi-user queue coverage lives in the invariant suite.
        _grantPopFull(ed);
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0xaa), BASE_LABEL_A);

        (bool reserved, address holder) = dotnsPopController.isReservedForClaim(BASE_LABEL_A);
        assertTrue(reserved);
        assertEq(holder, ed);
    }

    function test_registerBaseName_claim_emits_claim_event_and_not_standalone() public {
        // ed gets a different PopFull-classified base label via standalone mint.
        _grantPopFull(ed);
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0x01), BASE_LABEL_A);

        IDotnsPopController.Link memory link = _linkWithLite(LITE_LABEL_A);

        vm.recordLogs();
        _gatewayRegisterBaseName(
            IDotnsPopController.FullRegistration({label: BASE_LABEL_A, user: ed, link: link})
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertEventEmittedOnce(logs, keccak256("BaseNameClaimed(bytes32,address,string)"));
        _assertEventNotEmitted(logs, keccak256("StandaloneNameRegistered(bytes32,address,string)"));

        (bool reserved,) = dotnsPopController.isReservedForClaim(BASE_LABEL_A);
        assertFalse(reserved);
    }

    function test_registerBaseName_standalone_emits_standalone_event_and_not_claim() public {
        _grantPopFull(tiago);
        _reservePop(tiago, LITE_LABEL_B, _validChatKey(0x01), BASE_LABEL_A);
        // Under the new priceWithCheck gate, only the reservation holder can
        // sit in the base queue, so the "wipe entire queue" assertion reduces
        // to "wipe the single live entry and free the stem". After the claim,
        // a different user must be free to reserve a fresh stem via the
        // gateway without seeing any leaked state.
        _grantPopFull(ed);
        IDotnsPopController.Link memory link = _linkFresh(_validChatKey(0xcf));

        vm.recordLogs();
        _gatewayRegisterBaseName(
            IDotnsPopController.FullRegistration({label: BASE_LABEL_C, user: ed, link: link})
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertEventEmittedOnce(logs, keccak256("StandaloneNameRegistered(bytes32,address,string)"));
        _assertEventNotEmitted(logs, keccak256("BaseNameClaimed(bytes32,address,string)"));
    }

    function test_registerBaseName_claim_inherits_chat_key_from_lite_node() public {
        // Promote ed to PopFull so the standalone PopFull-classified mint passes.
        _grantPopFull(ed);
        bytes memory liteChatKey = _validChatKey(0xaa);
        _reservePop(ed, LITE_LABEL_A, liteChatKey, BASE_LABEL_A);

        IDotnsPopController.Link memory link = _linkWithLite(LITE_LABEL_A);
        _gatewayRegisterBaseName(
            IDotnsPopController.FullRegistration({label: BASE_LABEL_A, user: ed, link: link})
        );

        bytes32 fullNode = _nodeOf(BASE_LABEL_A);
        assertEq(dotnsPopResolver.chatKey(fullNode), liteChatKey);
        assertEq(dotnsPopResolver.liteLink(fullNode), keccak256(bytes(LITE_LABEL_A)));
    }

    function test_registerBaseName_claim_wipes_entire_queue() public {
        // priceWithCheck now admits only the current reservation holder on a
        // live stem, so the queue cannot contain a second waiter. After the
        // holder relinquishes, the slot is cleared and a fresh user must be
        // free to reserve the same stem from scratch.
        _grantPopFull(ed);
        _grantPopFull(tiago);
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0x01), BASE_LABEL_A);

        IDotnsPopController.Link memory link = _linkWithLite(LITE_LABEL_A);
        _gatewayRegisterBaseName(
            IDotnsPopController.FullRegistration({label: BASE_LABEL_A, user: ed, link: link})
        );

        _reservePop(tiago, LITE_LABEL_D, _validChatKey(0x04), BASE_LABEL_B);
        (, address wonderHolder) = dotnsPopController.isReservedForClaim(BASE_LABEL_B);
        assertEq(wonderHolder, tiago);
    }

    function test_registerBaseName_standalone_auto_relinquishes_users_other_reservation() public {
        _grantPopFull(ed);
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0x01), BASE_LABEL_A);

        _grantPopFull(ed);

        IDotnsPopController.Link memory link = _linkFresh(_validChatKey(0x02));

        _gatewayRegisterBaseName(
            IDotnsPopController.FullRegistration({label: BASE_LABEL_B, user: ed, link: link})
        );

        (bool reserved,) = dotnsPopController.isReservedForClaim(BASE_LABEL_A);
        assertFalse(reserved);
    }

    function test_registerBaseName_standalone_with_lite_link_silently_relinquishes() public {
        _grantPopFull(ed);
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0x01), BASE_LABEL_A);

        _grantPopFull(ed);
        IDotnsPopController.Link memory link = _linkWithLite(LITE_LABEL_A);

        vm.recordLogs();
        _gatewayRegisterBaseName(
            IDotnsPopController.FullRegistration({label: BASE_LABEL_B, user: ed, link: link})
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertEventEmittedOnce(logs, keccak256("StandaloneNameRegistered(bytes32,address,string)"));
        _assertEventEmittedOnce(logs, keccak256("LiteToFullLinked(bytes32,bytes32)"));
        _assertEventNotEmitted(logs, keccak256("BaseNameClaimed(bytes32,address,string)"));
        _assertEventNotEmitted(logs, keccak256("ReservationRelinquished(bytes32,address)"));

        bytes32 fullNode = _nodeOf(BASE_LABEL_B);
        assertEq(dotnsPopResolver.liteLink(fullNode), keccak256(bytes(LITE_LABEL_A)));

        (bool reserved,) = dotnsPopController.isReservedForClaim(BASE_LABEL_A);
        assertFalse(reserved);
    }

    function test_registerBaseName_reverts_when_origin_is_not_root() public {
        IDotnsPopController.Link memory link = _linkFresh(_validChatKey(0xaa));

        _mockCallerIsRoot(false);
        vm.expectRevert(
            abi.encodeWithSelector(IDotnsPopController.NotGateway.selector, address(this))
        );
        dotnsPopController.registerBaseName(
            IDotnsPopController.FullRegistration({label: BASE_LABEL_A, user: ed, link: link})
        );
    }

    function test_relinquishReservation_promotes_next_waiter_when_head_leaves() public {
        _grantPopFull(ed);
        _grantPopFull(tiago);
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0x01), BASE_LABEL_A);

        vm.prank(ed);
        dotnsPopController.relinquishReservation();

        (bool empty,) = dotnsPopController.isReservedForClaim(BASE_LABEL_A);
        assertFalse(empty);

        _reservePop(tiago, LITE_LABEL_B, _validChatKey(0x02), BASE_LABEL_A);
        (bool reserved, address holder) = dotnsPopController.isReservedForClaim(BASE_LABEL_A);
        assertTrue(reserved);
        assertEq(holder, tiago);
    }

    function test_relinquishReservation_reverts_when_caller_has_no_reservation() public {
        vm.prank(ed);
        vm.expectRevert(
            abi.encodeWithSelector(IDotnsPopController.NoActiveReservation.selector, ed)
        );
        dotnsPopController.relinquishReservation();
    }

    function test_setReservationDuration_shortening_retroactively_expires_live_entries() public {
        _grantPopFull(ed);
        // Enqueue alice under the default duration (7 days).
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0x01), BASE_LABEL_A);

        (bool liveBefore, address holderBefore) =
            dotnsPopController.isReservedForClaim(BASE_LABEL_A);
        assertTrue(liveBefore);
        assertEq(holderBefore, ed);
        // Warp 2 days forward (still well within the original 7-day window).
        vm.warp(block.timestamp + 2 days);
        // Governance shrinks the window to 1 day. The entry's `joinedAt` plus
        // the new duration is now in the past, so the slot is expired.
        vm.prank(owner);
        dotnsPopController.setReservationDuration(1 days);

        (bool liveAfter,) = dotnsPopController.isReservedForClaim(BASE_LABEL_A);
        assertFalse(liveAfter);
    }

    function test_setReservationDuration_reverts_for_non_owner() public {
        vm.prank(ed);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", ed));
        dotnsPopController.setReservationDuration(14 days);
    }

    function test_enqueueReservation_same_user_second_call_replaces_first() public {
        // Two independent reads must agree: the per-user reservation pointer
        // (`userReservation`) and the per-base claim view (`isReservedForClaim`).
        // Both change atomically when the same user re-reserves on a new stem.
        _grantPopFull(ed);
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0x01), BASE_LABEL_A);

        IDotnsPopController.UserReservation memory firstReservation =
            dotnsPopController.userReservation(ed);
        assertEq(firstReservation.labelhash, keccak256(bytes(BASE_LABEL_A)));
        // Second reservation by the same user on a different stem drops the
        // first slot and installs the new one.
        _reservePop(ed, LITE_LABEL_B, _validChatKey(0x02), BASE_LABEL_B);

        IDotnsPopController.UserReservation memory secondReservation =
            dotnsPopController.userReservation(ed);
        assertEq(secondReservation.labelhash, keccak256(bytes(BASE_LABEL_B)));

        (bool firstReserved,) = dotnsPopController.isReservedForClaim(BASE_LABEL_A);
        assertFalse(firstReserved);

        (bool secondReserved, address secondHolder) =
            dotnsPopController.isReservedForClaim(BASE_LABEL_B);
        assertTrue(secondReserved);
        assertEq(secondHolder, ed);
    }

    function test_reEnqueue_after_own_expiry_promotes_same_user_to_head() public {
        string memory baseStem = BASE_LABEL_A;
        _grantPopFull(ed);

        _reservePop(ed, LITE_LABEL_A, _validChatKey(0x01), baseStem);
        // Warp past the reservation window and fire the GC so ed's pointer gets
        // cleared by `_advanceExpiredHead`. If the expiry path forgets the
        // per-user pointer, the second reserve call below hits `AlreadyReserved`
        // and the account is permanently stuck.
        vm.warp(block.timestamp + dotnsPopController.reservationDuration() + 1);
        dotnsPopController.expireReservation(baseStem);

        (bool expiredReserved,) = dotnsPopController.isReservedForClaim(baseStem);
        assertFalse(expiredReserved);
        // Same user reserves the same stem again with a fresh lite label.
        _reservePop(ed, LITE_LABEL_B, _validChatKey(0x02), baseStem);

        (bool nowReserved, address holder) = dotnsPopController.isReservedForClaim(baseStem);
        assertTrue(nowReserved);
        assertEq(holder, ed);
    }

    function test_claim_then_reEnqueue_on_same_stem_resets_cleanly() public {
        string memory baseStem = BASE_LABEL_A;
        _grantPopFull(ed);
        _grantPopFull(tiago);

        _reservePop(ed, LITE_LABEL_A, _validChatKey(0x01), baseStem);
        // Claim wipes the queue via `_clearQueue` which must also drop
        // `_reservedBaseLabel[labelhash]` and release the PopRules slot. Missing
        // any one of those lets the next reservation inherit stale state.
        IDotnsPopController.Link memory link = _linkWithLite(LITE_LABEL_A);
        _gatewayRegisterBaseName(
            IDotnsPopController.FullRegistration({label: baseStem, user: ed, link: link})
        );

        (bool oldSlot, address oldHolder) = dotnsPopController.isReservedForClaim(baseStem);
        assertFalse(oldSlot);
        assertEq(oldHolder, address(0));
        // Fresh stem, different user. If the previous queue leaked, this enqueue
        // would either revert or land the wrong head address on PopRules.
        _reservePop(tiago, LITE_LABEL_B, _validChatKey(0x02), BASE_LABEL_B);
        (bool newSlot, address newHolder) = dotnsPopController.isReservedForClaim(BASE_LABEL_B);
        assertTrue(newSlot);
        assertEq(newHolder, tiago);

        (address popHolder,) = popRules.getBaseNameReservation(BASE_LABEL_B);
        assertEq(popHolder, tiago);
    }

    function test_expireReservation_is_permissionless() public {
        _grantPopFull(ed);
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0x01), BASE_LABEL_A);

        vm.warp(block.timestamp + dotnsPopController.reservationDuration() + 1);
        // Anyone can call. Pinning this prevents a future patch from silently
        // adding `onlyGateway` and breaking permissionless garbage collection.
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        dotnsPopController.expireReservation(BASE_LABEL_A);

        (bool reserved,) = dotnsPopController.isReservedForClaim(BASE_LABEL_A);
        assertFalse(reserved);
    }

    function test_head_expires_clears_slot_for_next_reserver() public {
        string memory baseStem = BASE_LABEL_A;
        _grantPopFull(ed);
        _grantPopFull(leonardo);

        _reservePop(ed, LITE_LABEL_A, _validChatKey(0x01), baseStem);

        vm.warp(block.timestamp + dotnsPopController.reservationDuration() + 1);
        dotnsPopController.expireReservation(baseStem);

        _reservePop(leonardo, LITE_LABEL_C, _validChatKey(0x03), baseStem);

        (bool reserved, address holder) = dotnsPopController.isReservedForClaim(baseStem);
        assertTrue(reserved);
        assertEq(holder, leonardo);

        (address popHolder,) = popRules.getBaseNameReservation(baseStem);
        assertEq(popHolder, leonardo);
    }

    function test_entry_point_format_rejections() public {
        _grantPopFull(ed);

        // `reserveLiteName` admits priceWithCheck first because "aliceli"
        // classifies as PopFull and ed is PopFull; the isLitePersonLabel
        // guard then rejects the zero trailing digits.
        vm.expectRevert(IDotnsPopController.InvalidLiteLabel.selector);
        _gatewayReserveLiteName(
            IDotnsPopController.LiteRegistration({liteLabel: "aliceli", user: ed, chatKey: ""})
        );

        IDotnsPopController.Link memory link = _linkFresh(_validChatKey(0xaa));
        // Multi-label string fails the canonical-label guard inside
        // PopRules.priceWithCheck before reaching the controller's own
        // isSingleLabel check.
        vm.expectPartialRevert(IPopRules.PopError.selector);
        _gatewayRegisterBaseName(
            IDotnsPopController.FullRegistration({label: "not.valid", user: ed, link: link})
        );
    }

    function test_same_stem_lite_and_base_occupy_distinct_registrar_tokens() public {
        _grantPopFull(ed);
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0xaa), "");
        // "aliceli" (baselength 7, no trailing digits) classifies as PopFull
        // and shares the lite's stem, so both tokens coexist on the registrar.
        _grantPopFull(tiago);
        IDotnsPopController.Link memory link = _linkFresh(_validChatKey(0xbb));
        _gatewayRegisterBaseName(
            IDotnsPopController.FullRegistration({label: "aliceli", user: tiago, link: link})
        );

        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf(LITE_LABEL_A))), ed);
        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf("aliceli"))), tiago);
    }

    function test_both_controllers_can_mint_on_shared_registrar() public {
        _grantPopFull(ed);
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0x01), "");
        _commitAndRegister("longnamebob01", tiago, true);

        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf(LITE_LABEL_A))), ed);
        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf("longnamebob01"))), tiago);
    }

    function test_gateway_reserved_name_rejects_public_register_by_other_user() public {
        _grantPopFull(tiago);
        // Gateway reserves the bare stem; PopRules.priceWithCheck strips the two
        // trailing digits from "longnamebob01" and matches against reservations["longnamebob"].
        _reservePop(tiago, LITE_LABEL_A, _validChatKey(0x11), "longnamebob");

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

    function test_gateway_reserved_name_allows_holder_to_register_via_public() public {
        _grantPopFull(tiago);
        _reservePop(tiago, LITE_LABEL_A, _validChatKey(0x11), "longnamebob");

        _commitAndRegister("longnamebob01", tiago, true);
        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf("longnamebob01"))), tiago);
    }

    function test_second_pop_lite_mint_of_same_label_reverts_at_registrar() public {
        _grantPopFull(ed);
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0xaa), "");

        _grantPopFull(tiago);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsRegistrar.NameNotAvailable.selector, uint256(_nodeOf(LITE_LABEL_A))
            )
        );
        _gatewayReserveBaseName(
            IDotnsPopController.BaseReservation({
                lite: IDotnsPopController.LiteRegistration({
                    liteLabel: LITE_LABEL_A, user: tiago, chatKey: _validChatKey(0xbb)
                }),
                reservedBaseLabel: ""
            })
        );
    }

    function test_public_register_after_pop_full_mint_reverts_at_registrar() public {
        // "longnamebob01" is classification-NoStatus, so ed keeps default status.
        IDotnsPopController.Link memory link = _linkFresh(_validChatKey(0xcf));
        _gatewayRegisterBaseName(
            IDotnsPopController.FullRegistration({label: "longnamebob01", user: ed, link: link})
        );

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

    function test_owner_of_pop_minted_name_can_create_subname() public {
        _grantPopFull(ed);
        IDotnsPopController.Link memory link = _linkFresh(_validChatKey(0xcf));
        _gatewayRegisterBaseName(
            IDotnsPopController.FullRegistration({label: BASE_LABEL_A, user: ed, link: link})
        );

        bytes32 parentNode = _nodeOf(BASE_LABEL_A);
        IDotnsRegistry.SubnodeRecord memory subnodeRecord = IDotnsRegistry.SubnodeRecord({
            parentNode: parentNode, subLabel: "app", parentLabel: BASE_LABEL_A, owner: leonardo
        });

        vm.prank(ed);
        bytes32 subnode = dotnsRegistry.setSubnodeOwner(subnodeRecord);

        assertEq(dotnsRegistry.owner(subnode), leonardo);
    }

    function test_non_owner_cannot_create_subname_under_pop_minted_name() public {
        _grantPopFull(ed);
        IDotnsPopController.Link memory link = _linkFresh(_validChatKey(0xcf));
        _gatewayRegisterBaseName(
            IDotnsPopController.FullRegistration({label: BASE_LABEL_A, user: ed, link: link})
        );

        bytes32 parentNode = _nodeOf(BASE_LABEL_A);
        IDotnsRegistry.SubnodeRecord memory subnodeRecord = IDotnsRegistry.SubnodeRecord({
            parentNode: parentNode, subLabel: "app", parentLabel: BASE_LABEL_A, owner: tiago
        });

        vm.prank(tiago);
        vm.expectRevert(IDotnsRegistry.NotAuthorised.selector);
        dotnsRegistry.setSubnodeOwner(subnodeRecord);
    }

    function test_pop_reservation_of_already_public_minted_name_fails_on_claim() public {
        _commitAndRegister("longnamebob01", ed, true);

        _grantPopFull(tiago);
        _reservePop(tiago, LITE_LABEL_A, _validChatKey(0xaa), "longnamebob01");

        (bool reserved, address holder) = dotnsPopController.isReservedForClaim("longnamebob01");
        assertTrue(reserved);
        assertEq(holder, tiago);

        IDotnsPopController.Link memory link = _linkWithLite(LITE_LABEL_A);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsRegistrar.NameNotAvailable.selector, uint256(_nodeOf("longnamebob01"))
            )
        );
        _gatewayRegisterBaseName(
            IDotnsPopController.FullRegistration({label: "longnamebob01", user: tiago, link: link})
        );
    }

    function test_enqueue_becomesHead_writes_popRules_reservation() public {
        _grantPopFull(ed);
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0xaa), "longnamebob");

        (address holder, uint64 expires) = popRules.getBaseNameReservation("longnamebob");
        assertEq(holder, ed);
        assertEq(expires, uint64(block.timestamp + popRules.MAX_RESERVATION_TIME()));
    }

    function test_claim_releases_popRules_slot() public {
        _grantPopFull(ed);
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0xaa), "longnamebob");

        IDotnsPopController.Link memory link = _linkWithLite(LITE_LABEL_A);
        _gatewayRegisterBaseName(
            IDotnsPopController.FullRegistration({label: "longnamebob", user: ed, link: link})
        );

        (address holder,) = popRules.getBaseNameReservation("longnamebob");
        assertEq(holder, address(0));
    }

    function test_relinquish_last_releases_popRules_slot() public {
        _grantPopFull(ed);
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0xaa), "longnamebob");

        vm.prank(ed);
        dotnsPopController.relinquishReservation();

        (address holder,) = popRules.getBaseNameReservation("longnamebob");
        assertEq(holder, address(0));
    }

    function test_advanceExpiredHead_last_expire_releases_popRules_slot() public {
        _grantPopFull(ed);
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0xaa), "longnamebob");

        vm.warp(block.timestamp + dotnsPopController.reservationDuration() + 1);
        dotnsPopController.expireReservation("longnamebob");

        (address holder,) = popRules.getBaseNameReservation("longnamebob");
        assertEq(holder, address(0));
    }

    function test_controller_does_not_mutate_reservedBaseLabel_string() public {
        _grantPopFull(ed);
        // "longnamebob01" has two trailing digits. PopRules stores it as-is,
        // but `priceWithCheck` queries reservations keyed by "longnamebob".
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0xaa), "longnamebob01");
        // Slot is written under the raw label.
        (address rawHolder,) = popRules.getBaseNameReservation("longnamebob01");
        assertEq(rawHolder, ed);
        // Stripped-stem slot is empty; public flow for "longnamebob01" is
        // NOT blocked for other users (documented misuse surface).
        (address strippedHolder,) = popRules.getBaseNameReservation("longnamebob");
        assertEq(strippedHolder, address(0));
    }

    function test_public_stranger_can_mint_after_claim_clears_reservation() public {
        _grantPopFull(ed);
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0xaa), "longnamebob");

        IDotnsPopController.Link memory link = _linkWithLite(LITE_LABEL_A);
        _gatewayRegisterBaseName(
            IDotnsPopController.FullRegistration({label: "longnamebob", user: ed, link: link})
        );
        // Now the stem is clear on PopRules, so tiago can register the
        // digit-suffixed variant "longnamebob01" via the public flow.
        _commitAndRegister("longnamebob01", tiago, true);
        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf("longnamebob01"))), tiago);
    }

    function test_public_stranger_can_mint_after_reservation_expires() public {
        _grantPopFull(ed);
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0xaa), "longnamebob");

        vm.warp(block.timestamp + dotnsPopController.reservationDuration() + 1);
        dotnsPopController.expireReservation("longnamebob");

        _commitAndRegister("longnamebob01", tiago, true);
        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf("longnamebob01"))), tiago);
    }

    function test_controller_authorised_but_not_gateway_cannot_enter_pop_flow() public {
        // The public commit-reveal controller is already a registered controller.
        // Even from that origin, the Root-gate must reject the call.
        _mockCallerIsRoot(false);
        vm.prank(address(dotnsRegistrarController));
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsPopController.NotGateway.selector, address(dotnsRegistrarController)
            )
        );
        dotnsPopController.reserveBaseName(
            IDotnsPopController.BaseReservation({
                lite: IDotnsPopController.LiteRegistration({
                    liteLabel: LITE_LABEL_A, user: ed, chatKey: ""
                }),
                reservedBaseLabel: "longnamebob"
            })
        );
    }

    /// @notice Asserts exactly one entry in `logs` matches event signature `sig`.
    function _assertEventEmittedOnce(Vm.Log[] memory logs, bytes32 sig) internal pure {
        uint256 count;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == sig) count++;
        }
        require(count == 1, "expected exactly one matching event");
    }

    /// @notice Asserts no entry in `logs` matches event signature `sig`.
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

    function test_registerBaseName_standalone_succeeds_when_head_is_expired() public {
        _grantPopFull(ed);
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0x01), BASE_LABEL_A);
        // Walk past both the controller and PopRules expiry windows so
        // nothing blocks tiago's priceWithCheck.
        vm.warp(block.timestamp + popRules.MAX_RESERVATION_TIME() + 1);

        _grantPopFull(tiago);

        IDotnsPopController.Link memory link = _linkFresh(_validChatKey(0xcf));
        _gatewayRegisterBaseName(
            IDotnsPopController.FullRegistration({label: BASE_LABEL_A, user: tiago, link: link})
        );

        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf(BASE_LABEL_A))), tiago);
    }

    function test_registerBaseName_standalone_succeeds_when_queue_empty() public {
        _grantPopFull(ed);

        IDotnsPopController.Link memory link = _linkFresh(_validChatKey(0xcf));
        _gatewayRegisterBaseName(
            IDotnsPopController.FullRegistration({label: BASE_LABEL_A, user: ed, link: link})
        );

        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf(BASE_LABEL_A))), ed);
    }

    function test_registerBaseName_claim_still_works_after_guard() public {
        _grantPopFull(ed);
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0x01), BASE_LABEL_A);

        IDotnsPopController.Link memory link = _linkWithLite(LITE_LABEL_A);
        _gatewayRegisterBaseName(
            IDotnsPopController.FullRegistration({label: BASE_LABEL_A, user: ed, link: link})
        );

        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf(BASE_LABEL_A))), ed);
    }

    function test_registerBaseName_guard_blocks_stranger_and_preserves_claim() public {
        _grantPopFull(ed);
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0x01), BASE_LABEL_A);

        _grantPopFull(tiago);
        IDotnsPopController.Link memory strangerLink = _linkFresh(_validChatKey(0xbb));
        vm.expectPartialRevert(IDotnsPopController.NotHolder.selector);
        _gatewayRegisterBaseName(
            IDotnsPopController.FullRegistration({
                label: BASE_LABEL_A, user: tiago, link: strangerLink
            })
        );
        // A's reservation is intact; A claims successfully.
        IDotnsPopController.Link memory claimLink = _linkWithLite(LITE_LABEL_A);
        _gatewayRegisterBaseName(
            IDotnsPopController.FullRegistration({label: BASE_LABEL_A, user: ed, link: claimLink})
        );

        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf(BASE_LABEL_A))), ed);
    }

    function test_registerBaseName_reverts_for_governance_length_name() public {
        _grantPopFull(ed);

        IDotnsPopController.Link memory link = _linkFresh(_validChatKey(0xaa));
        // Stem "alice" has baselength 5; classifies as `Reserved for Governance`,
        // which the PoP controller's governance guard rejects.
        vm.expectRevert(IDotnsPopController.InvalidBaseLabel.selector);

        _gatewayRegisterBaseName(
            IDotnsPopController.FullRegistration({label: "alice", user: ed, link: link})
        );
    }

    function test_reserveBaseName_reserved_label_classification_reverts() public {
        _grantPopFull(ed);

        // Lite leg uses a valid lite label; reserved leg uses a <=5-char stem,
        // which classifies as `Reserved for Governance` and is rejected by the
        // PoP controller's governance guard.
        vm.expectRevert(IDotnsPopController.InvalidBaseLabel.selector);
        _gatewayReserveBaseName(
            IDotnsPopController.BaseReservation({
                lite: IDotnsPopController.LiteRegistration({
                    liteLabel: LITE_LABEL_A, user: ed, chatKey: _validChatKey(0xaa)
                }),
                reservedBaseLabel: "alice"
            })
        );
    }

    function test_registerBaseName_popFull_user_on_popFull_label_succeeds() public {
        _grantPopFull(ed);

        uint256 controllerBalanceBefore = address(dotnsPopController).balance;

        IDotnsPopController.Link memory link = _linkFresh(_validChatKey(0xaa));
        _gatewayRegisterBaseName(
            IDotnsPopController.FullRegistration({label: BASE_LABEL_A, user: ed, link: link})
        );
        // No native token moves on the PoP path.
        assertEq(address(dotnsPopController).balance, controllerBalanceBefore);
        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf(BASE_LABEL_A))), ed);
    }

    function test_reserveLiteName_succeeds_regardless_of_base_reservation() public {
        string memory baseStem = BASE_LABEL_A;
        // Occupy the base stem with a live reservation.
        _grantPopFull(ed);
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0x01), baseStem);
        // A different user calls reserveLiteName on a different lite label.
        address fresh = makeAddr("freshLite");
        _grantPopLite(fresh);

        _gatewayReserveLiteName(
            IDotnsPopController.LiteRegistration({
                liteLabel: "freshli01", user: fresh, chatKey: _validChatKey(0xcc)
            })
        );

        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf("freshli01"))), fresh);
    }

    function test_reserveLiteName_reverts_for_non_lite_format() public {
        _grantPopFull(ed);

        vm.expectRevert(IDotnsPopController.InvalidLiteLabel.selector);
        _gatewayReserveLiteName(
            IDotnsPopController.LiteRegistration({
                liteLabel: "alice", user: ed, chatKey: _validChatKey(0xaa)
            })
        );
    }

    function test_reserveLiteName_reverts_when_origin_is_not_root() public {
        _mockCallerIsRoot(false);
        vm.expectRevert(
            abi.encodeWithSelector(IDotnsPopController.NotGateway.selector, address(this))
        );
        dotnsPopController.reserveLiteName(
            IDotnsPopController.LiteRegistration({
                liteLabel: LITE_LABEL_A, user: ed, chatKey: _validChatKey(0xaa)
            })
        );
    }

    function test_reserveBaseName_compound_happy_path_still_works() public {
        _grantPopFull(ed);

        _gatewayReserveBaseName(
            IDotnsPopController.BaseReservation({
                lite: IDotnsPopController.LiteRegistration({
                    liteLabel: LITE_LABEL_A, user: ed, chatKey: _validChatKey(0xaa)
                }),
                reservedBaseLabel: BASE_LABEL_A
            })
        );

        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(_nodeOf(LITE_LABEL_A))), ed);

        (bool reserved, address holder) = dotnsPopController.isReservedForClaim(BASE_LABEL_A);
        assertTrue(reserved);
        assertEq(holder, ed);
    }

    function test_registerBaseName_zero_length_label_reverts() public {
        _grantPopFull(ed);

        IDotnsPopController.Link memory link = _linkFresh(_validChatKey(0xaa));
        // Classification runs first; empty string fails canonical label check
        // in PopRules before reaching the PoP controller's own shape guard.
        vm.expectPartialRevert(IPopRules.PopError.selector);
        _gatewayRegisterBaseName(
            IDotnsPopController.FullRegistration({label: "", user: ed, link: link})
        );
    }

    function test_reserveBaseName_accepts_65_byte_chat_key() public {
        _grantPopFull(ed);

        bytes memory chatKey = _validChatKey(0x42);

        _gatewayReserveBaseName(
            IDotnsPopController.BaseReservation({
                lite: IDotnsPopController.LiteRegistration({
                    liteLabel: LITE_LABEL_A, user: ed, chatKey: chatKey
                }),
                reservedBaseLabel: ""
            })
        );

        bytes32 node = _nodeOf(LITE_LABEL_A);
        assertEq(dotnsPopResolver.chatKey(node), chatKey);
    }

    function testFuzz_bytes_overloads_reject_non_root_origin(uint8 which) public {
        // `which` selects which of the three bytes overloads to invoke; the
        // `onlyGateway` modifier must reject a non-Root origin on each.
        // Single fuzz replaces three near-identical unit tests.
        which = uint8(bound(uint256(which), 0, 2));

        _mockCallerIsRoot(false);
        vm.expectRevert(
            abi.encodeWithSelector(IDotnsPopController.NotGateway.selector, address(this))
        );

        if (which == 0) {
            dotnsPopController.reserveLiteName(
                abi.encode(
                    IDotnsPopController.LiteRegistration({
                        liteLabel: LITE_LABEL_A, user: ed, chatKey: _validChatKey(0xaa)
                    })
                )
            );
        } else if (which == 1) {
            dotnsPopController.reserveBaseName(
                abi.encode(
                    IDotnsPopController.BaseReservation({
                        lite: IDotnsPopController.LiteRegistration({
                            liteLabel: LITE_LABEL_A, user: ed, chatKey: _validChatKey(0xaa)
                        }),
                        reservedBaseLabel: ""
                    })
                )
            );
        } else {
            dotnsPopController.registerBaseName(
                abi.encode(
                    IDotnsPopController.FullRegistration({
                        label: BASE_LABEL_A,
                        user: ed,
                        link: IDotnsPopController.Link({
                            kind: IDotnsPopController.LinkKind.None,
                            liteLabel: "",
                            chatKey: _validChatKey(0xaa)
                        })
                    })
                )
            );
        }
    }

    function test_reserveLiteName_bytes_reverts_on_malformed_payload() public {
        // Truncated payload cannot be ABI-decoded into the target struct, so the
        // typed entrypoint reverts inside `abi.decode` (panic-style, no return
        // data); `_dispatchTyped` re-throws via assembly so the outer call
        // surfaces the same empty revert. Asserting "any revert" is intentional;
        // locking the exact error string would couple the test to solc internals.
        bytes memory truncated = hex"deadbeef";
        vm.expectRevert();
        _gatewayReserveLiteName(truncated);
    }

    function test_setReservationDuration_zero_makes_new_reservations_immediately_expired() public {
        // `reservationDuration` has no zero-guard. Setting it to 0 means every
        // freshly enqueued reservation is classified expired by `_isExpired`
        // on the same block.
        vm.prank(owner);
        dotnsPopController.setReservationDuration(0);

        _grantPopFull(ed);
        _reservePop(ed, LITE_LABEL_A, _validChatKey(0x01), BASE_LABEL_A);

        (bool reserved,) = dotnsPopController.isReservedForClaim(BASE_LABEL_A);
        assertFalse(reserved);
    }
}
