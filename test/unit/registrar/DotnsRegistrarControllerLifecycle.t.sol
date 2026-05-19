// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {BaseDotns, IDotnsRegistrarController} from "../../base/BaseDotns.t.sol";

import {IPopRules} from "../../../contracts/pop/IPopRules.sol";
import {IDotnsNameEscrow} from "../../../contracts/escrow/IDotnsNameEscrow.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {RegistrationProbe} from "../../helpers/RegistrationProbe.sol";
import {RefundRejecter} from "../../helpers/RefundRejecter.sol";
import {ReentrantOwner} from "../../helpers/ReentrantOwner.sol";

/// @title DotnsRegistrarControllerLifecycleTest
/// @notice Coverage for the post-mint lifecycle on the public commit-reveal
///         controller: reclaim of a released name, cross-payer routing,
///         escrow-position seeding, callback ordering, pull-payment refunds,
///         and reentrancy guarding.
contract DotnsRegistrarControllerLifecycleTest is BaseDotns {
    function test_register_reclaim_succeeds_for_new_poplite_owner() public {
        string memory label = "lights01";

        address originalOwner = ed;
        address newOwner = leonardo;
        _grantPopLite(originalOwner);
        _grantPopLite(newOwner);

        _commitAndRegister(label, originalOwner, true);

        uint256 tokenId = _tokenIdForLabel(label);

        vm.startPrank(originalOwner);
        dotnsRegistrar.approve(address(dotnsNameEscrow), tokenId);
        dotnsNameEscrow.release(tokenId);
        vm.stopPrank();

        vm.warp(block.timestamp + ESCROW_COOLDOWN + 1);

        vm.prank(originalOwner);
        dotnsNameEscrow.withdraw(tokenId);

        // Inline the new owner's commit-reveal because BaseDotns helpers quote
        // priceWithCheck up-front, which reverts against the stale reservation.
        // The controller's reclaim path is what garbage-collects the slot.
        bytes32 secret = keccak256("new-owner-reclaim");
        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label, owner: newOwner, secret: secret, reserved: true
            });
        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);
        vm.prank(newOwner);
        dotnsRegistrarController.commit(commitment);
        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        vm.prank(newOwner);
        dotnsRegistrarController.register{value: 0}(registration);

        assertEq(dotnsRegistrar.ownerOf(tokenId), newOwner);
        (bool isReserved, address reservationOwner,) = popRules.isBaseNameReserved("lights");
        assertTrue(isReserved, "new owner's reservation must take over");
        assertEq(reservationOwner, newOwner, "stale reservation must not block reclaim");
    }

    function test_register_cross_payer_below_reach_pays_reach_fee_on_priced_label() public {
        string memory label = "alicebo42";
        address payer = leonardo;
        address nameOwner = ed;

        _grantNoStatus(payer);
        _grantNoStatus(nameOwner);

        uint256 ownerPrice = popRules.priceWithoutCheck(label, nameOwner).price;
        uint256 reachFloor = popRules.reachFee(label, payer);
        assertGt(ownerPrice, 0, "scenario requires non-zero owner price");
        assertGt(reachFloor, 0, "scenario requires non-zero reach floor");

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label,
                owner: nameOwner,
                secret: keccak256(abi.encodePacked(label, nameOwner, payer)),
                reserved: true
            });

        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);
        vm.prank(payer);
        dotnsRegistrarController.commit(commitment);
        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        uint256 insuranceBefore = dotnsNameEscrow.insuranceFund();

        vm.prank(payer);
        dotnsRegistrarController.register{value: ownerPrice + reachFloor}(registration);

        // Cross-payer credits both the owner's price and the reach floor to
        // insurance; the refundable-deposit branch is reserved for direct
        // registrants.
        assertEq(
            dotnsNameEscrow.insuranceFund() - insuranceBefore,
            ownerPrice + reachFloor,
            "cross-payer must credit owner price and reach fee to insurance"
        );
    }

    function test_revert_register_cross_payer_when_msg_value_excludes_reach_fee() public {
        string memory label = "alicebo42";
        address payer = leonardo;
        address nameOwner = ed;

        _grantNoStatus(payer);
        _grantNoStatus(nameOwner);

        uint256 ownerPrice = popRules.priceWithoutCheck(label, nameOwner).price;
        uint256 reachFloor = popRules.reachFee(label, payer);
        assertGt(ownerPrice, 0);
        assertGt(reachFloor, 0);

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label,
                owner: nameOwner,
                secret: keccak256(abi.encodePacked(label, nameOwner, payer, "short")),
                reserved: true
            });

        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);
        vm.prank(payer);
        dotnsRegistrarController.commit(commitment);
        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        vm.prank(payer);
        vm.expectRevert(IDotnsRegistrarController.InsufficientValue.selector);
        dotnsRegistrarController.register{value: ownerPrice}(registration);
    }

    function test_register_cross_payer_routes_owner_price_to_insurance() public {
        string memory label = NOSTATUS_LABEL_A;
        address payer = leonardo;
        address nameOwner = ed;

        _grantNoStatus(payer);
        _grantNoStatus(nameOwner);

        uint256 ownerPrice = popRules.priceWithoutCheck(label, nameOwner).price;
        assertGt(ownerPrice, 0, "scenario requires priced label");

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label,
                owner: nameOwner,
                secret: keccak256(abi.encodePacked(label, nameOwner, payer, "ins")),
                reserved: true
            });

        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);
        vm.prank(payer);
        dotnsRegistrarController.commit(commitment);
        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        uint256 insuranceBefore = dotnsNameEscrow.insuranceFund();

        vm.prank(payer);
        dotnsRegistrarController.register{value: ownerPrice}(registration);

        uint256 tokenId = _tokenIdForLabel(label);
        IDotnsNameEscrow.ReleasePosition memory position =
            dotnsNameEscrow.getReleasePosition(tokenId);

        assertEq(position.amount, 0, "cross-payer must not seed a refundable position");
        assertEq(
            dotnsNameEscrow.insuranceFund() - insuranceBefore,
            ownerPrice,
            "cross-payer price must accrue to insurance"
        );
    }

    function test_register_creates_escrow_position_for_zero_priced_registration() public {
        string memory label = BASE_LABEL_A;
        address nameOwner = ed;
        _grantPopFull(nameOwner);

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label,
                owner: nameOwner,
                secret: keccak256(abi.encodePacked(label, nameOwner, "popfull")),
                reserved: true
            });
        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);
        vm.prank(nameOwner);
        dotnsRegistrarController.commit(commitment);
        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        vm.prank(nameOwner);
        dotnsRegistrarController.register{value: 0}(registration);

        uint256 tokenId = _tokenIdForLabel(label);

        IDotnsNameEscrow.ReleasePosition memory atMint = dotnsNameEscrow.getReleasePosition(tokenId);
        assertEq(atMint.recipient, nameOwner, "position must bind the registrant at mint");
        assertEq(atMint.amount, 0, "zero-priced mint seeds a zero-amount position");
        assertFalse(atMint.released, "fresh position is not yet released");
        assertFalse(atMint.claimed, "fresh position is not yet claimed");

        vm.startPrank(nameOwner);
        dotnsRegistrar.approve(address(dotnsNameEscrow), tokenId);
        dotnsNameEscrow.release(tokenId);
        vm.stopPrank();

        IDotnsNameEscrow.ReleasePosition memory atRelease =
            dotnsNameEscrow.getReleasePosition(tokenId);
        assertTrue(atRelease.released, "zero-priced registration must still be releasable");
        assertEq(atRelease.recipient, nameOwner, "release recipient must be the registrant");
    }

    function test_register_reclaim_state_consistent_during_safe_transfer_callback() public {
        string memory label = NOSTATUS_LABEL_A;

        _register(label, ed, IPopRules.PopStatus.NoStatus);
        uint256 tokenId = _tokenIdForLabel(label);

        vm.startPrank(ed);
        dotnsRegistrar.approve(address(dotnsNameEscrow), tokenId);
        dotnsNameEscrow.release(tokenId);
        vm.stopPrank();
        vm.warp(block.timestamp + ESCROW_COOLDOWN + 1);
        vm.prank(ed);
        dotnsNameEscrow.withdraw(tokenId);

        RegistrationProbe probe =
            new RegistrationProbe(address(dotnsRegistry), address(dotnsReverseResolver));
        vm.deal(address(probe), DEFAULT_BALANCE);

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label,
                owner: address(probe),
                secret: keccak256("probe-reclaim"),
                reserved: true
            });
        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);
        vm.prank(address(probe));
        dotnsRegistrarController.commit(commitment);
        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        uint256 ownerPrice = popRules.priceWithCheck(label, address(probe)).price;
        vm.prank(address(probe));
        dotnsRegistrarController.register{value: ownerPrice}(registration);

        assertTrue(probe.callbackFired(), "reclaim must run through onERC721Received");
        bytes32 node = bytes32(tokenId);
        assertEq(
            probe.observedRegistryOwner(),
            address(probe),
            "registry owner must resolve to the new owner during the callback"
        );
        assertEq(
            probe.observedReverseName(),
            string.concat(label, ".dot"),
            "reverse record must be wired before custody moves"
        );
        assertEq(dotnsRegistry.owner(node), address(probe));
    }

    function test_revert_registerreserved_for_already_seeded_label() public {
        string memory label = "hello1234";
        address nameOwner = ed;

        vm.startPrank(owner);
        bytes32 secret = keccak256("seed-reserved");
        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label, owner: nameOwner, secret: secret, reserved: true
            });
        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);
        dotnsRegistrarController.commit(commitment);
        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);
        dotnsRegistrarController.registerReserved(registration);
        vm.stopPrank();

        bytes32 secondSecret = keccak256("seed-reserved-2");
        IDotnsRegistrarController.Registration memory secondRegistration =
            IDotnsRegistrarController.Registration({
                label: label, owner: nameOwner, secret: secondSecret, reserved: true
            });

        vm.startPrank(owner);
        bytes32 secondCommitment = dotnsRegistrarController.makeCommitment(secondRegistration);
        dotnsRegistrarController.commit(secondCommitment);
        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IDotnsRegistrarController.NameNotAvailable.selector, label)
        );
        dotnsRegistrarController.registerReserved(secondRegistration);
        vm.stopPrank();
    }

    function test_register_second_reserved_name_preserves_prior_primary_reverse_record() public {
        string memory firstLabel = "primary01";
        string memory secondLabel = "secondary01";

        _grantPopLite(ed);

        _commitAndRegister(firstLabel, ed, true);
        assertEq(dotnsReverseResolver.nameOf(ed), string.concat(firstLabel, ".dot"));

        _commitAndRegister(secondLabel, ed, true);

        assertEq(
            dotnsReverseResolver.nameOf(ed),
            string.concat(firstLabel, ".dot"),
            "second reserved registration must not silently rewrite the primary"
        );
    }

    function test_register_overpayment_credits_pull_payment_ledger_on_contract_receiver() public {
        string memory label = NOSTATUS_LABEL_A;

        RefundRejecter receiver = new RefundRejecter();
        vm.deal(address(receiver), DEFAULT_BALANCE);
        _grantNoStatus(address(receiver));

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label,
                owner: address(receiver),
                secret: keccak256("contract-overpay"),
                reserved: true
            });
        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);
        vm.prank(address(receiver));
        dotnsRegistrarController.commit(commitment);
        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        uint256 ownerPrice = popRules.priceWithCheck(label, address(receiver)).price;
        uint256 overpayment = 1 ether;

        vm.prank(address(receiver));
        dotnsRegistrarController.register{value: ownerPrice + overpayment}(registration);

        uint256 tokenId = _tokenIdForLabel(label);
        assertEq(dotnsRegistrar.ownerOf(tokenId), address(receiver));

        assertEq(
            dotnsNameEscrow.pendingWithdrawal(address(receiver)),
            overpayment,
            "overpayment must accrue to the payer's pull-payment ledger"
        );
    }

    function test_revert_register_on_reentry_from_onerc721received() public {
        string memory label = NOSTATUS_LABEL_A;

        _register(label, ed, IPopRules.PopStatus.NoStatus);
        uint256 tokenId = _tokenIdForLabel(label);
        vm.startPrank(ed);
        dotnsRegistrar.approve(address(dotnsNameEscrow), tokenId);
        dotnsNameEscrow.release(tokenId);
        vm.stopPrank();
        vm.warp(block.timestamp + ESCROW_COOLDOWN + 1);
        vm.prank(ed);
        dotnsNameEscrow.withdraw(tokenId);

        ReentrantOwner attacker = new ReentrantOwner(dotnsRegistrarController);
        vm.deal(address(attacker), DEFAULT_BALANCE);

        // Stage a second registration the callback will try to replay.
        string memory replayLabel = "reentrancybait01";
        IDotnsRegistrarController.Registration memory replay = IDotnsRegistrarController.Registration({
            label: replayLabel,
            owner: address(attacker),
            secret: keccak256("reentry"),
            reserved: true
        });
        bytes32 replayCommitment = dotnsRegistrarController.makeCommitment(replay);
        vm.prank(address(attacker));
        dotnsRegistrarController.commit(replayCommitment);
        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);
        attacker.arm(replay);

        IDotnsRegistrarController.Registration memory outer = IDotnsRegistrarController.Registration({
            label: label,
            owner: address(attacker),
            secret: keccak256("outer-reclaim"),
            reserved: true
        });
        bytes32 outerCommitment = dotnsRegistrarController.makeCommitment(outer);
        vm.prank(address(attacker));
        dotnsRegistrarController.commit(outerCommitment);
        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        uint256 outerPrice = popRules.priceWithCheck(label, address(attacker)).price;

        vm.prank(address(attacker));
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        dotnsRegistrarController.register{value: outerPrice}(outer);
    }
}
