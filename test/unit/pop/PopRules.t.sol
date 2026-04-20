// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../../base/BaseDotns.t.sol";
import {IPopRules} from "../../../contracts/pop/IPopRules.sol";
import {IDotnsController} from "../../../contracts/registrars/IDotnsController.sol";

contract PopRulesTests is BaseDotns {
    function test_classify_governance() public view {
        (IPopRules.PopStatus classificationStatus, string memory classificationMessage) =
            popRules.classifyName("hello");

        assertEq(uint256(classificationStatus), uint256(IPopRules.PopStatus.Reserved));
        assertEq(classificationMessage, "Reserved for Governance");
    }

    function test_classify_poplite() public view {
        (IPopRules.PopStatus classificationStatus, string memory classificationMessage) =
            popRules.classifyName("lights01");

        assertEq(uint256(classificationStatus), uint256(IPopRules.PopStatus.PopLite));
        assertEq(classificationMessage, "Requires Light personhood verification");
    }

    function test_classify_popfull() public view {
        (IPopRules.PopStatus classificationStatus, string memory classificationMessage) =
            popRules.classifyName("alicebob");

        assertEq(uint256(classificationStatus), uint256(IPopRules.PopStatus.PopFull));
        assertEq(classificationMessage, "Requires Full personhood verification");
    }

    function test_classify_nostatus() public view {
        (IPopRules.PopStatus classificationStatus, string memory classificationMessage) =
            popRules.classifyName("longnamehere01");

        assertEq(uint256(classificationStatus), uint256(IPopRules.PopStatus.NoStatus));
        assertEq(classificationMessage, "Available to all");
    }

    function test_price_with_check_revert_governance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IPopRules.PopError.selector, "Reserved for Governance")
        );
        popRules.priceWithCheck("hello", ed);
    }

    function test_price_with_check_revert_full_needed() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPopRules.PopError.selector, "Requires Full Personhood verification"
            )
        );
        popRules.priceWithCheck("alicebob", ed);
    }

    function test_popfull_user_can_access_poplite_name() public {
        vm.prank(ed);
        popRules.setUserPopStatus(IPopRules.PopStatus.PopFull);

        IPopRules.PriceWithMeta memory priceMetadata = popRules.priceWithCheck("lights01", ed);

        assertEq(uint256(priceMetadata.status), uint256(IPopRules.PopStatus.PopLite));
        assertEq(uint256(priceMetadata.userStatus), uint256(IPopRules.PopStatus.PopFull));
    }

    function test_base_reservation_blocks_others() public {
        // Authorise this test contract as a registrar controller so it may call
        // reserveBaseName (gated by DotnsRegistrar.controllers).
        vm.prank(owner);
        dotnsRegistrar.addController(IDotnsController(address(this)));

        popRules.reserveBaseName("lights01", leonardo);

        (bool isReserved, address reservationOwner, uint64 expiryTimestamp) =
            popRules.isBaseNameReserved("lights");

        assertTrue(isReserved);
        assertEq(reservationOwner, leonardo);
        assertEq(expiryTimestamp, uint64(block.timestamp + 12 weeks));

        vm.expectRevert(
            abi.encodeWithSelector(
                IPopRules.PopError.selector, "Base name reserved for original Lite registrant"
            )
        );
        popRules.priceWithCheck("lights", tiago);
    }

    function test_price_without_check_returns_price_for_reserved() public {
        vm.prank(owner);
        dotnsRegistrar.addController(IDotnsController(address(this)));

        popRules.reserveBaseName("lights01", leonardo);

        IPopRules.PriceWithMeta memory priceMetadata = popRules.priceWithoutCheck("lights", tiago);

        assertEq(uint256(priceMetadata.status), uint256(IPopRules.PopStatus.Reserved));
        assertEq(priceMetadata.price, popRules.price("lights"));
    }

    // `reserveBaseNameForPop` must be gated by registrar-controller authorisation.
    // An address that is not registered as a controller cannot write reservations.
    function test_reserveBaseNameForPop_reverts_for_non_controller() public {
        vm.prank(ed);
        vm.expectRevert(IPopRules.NotRegistry.selector);
        popRules.reserveBaseNameForPop("longnamebob", ed);
    }

    // Same gating for `releaseBaseName`.
    function test_releaseBaseName_reverts_for_non_controller() public {
        vm.prank(ed);
        vm.expectRevert(IPopRules.NotRegistry.selector);
        popRules.releaseBaseName("longnamebob");
    }

    // When the slot is already live for user A, a second call for user B from
    // any authorised controller reverts. Silent no-op would let the caller's
    // local queue bookkeeping diverge from PopRules; reverting propagates the
    // collision back to the caller so both sides stay in lockstep. The existing
    // holder keeps priority either way.
    function test_reserveBaseNameForPop_reverts_when_slot_held_by_other_user() public {
        vm.prank(owner);
        dotnsRegistrar.addController(IDotnsController(address(this)));

        popRules.reserveBaseNameForPop("longnamebob", leonardo);

        vm.expectRevert(
            abi.encodeWithSelector(IPopRules.PopError.selector, "Base name held by another user")
        );
        popRules.reserveBaseNameForPop("longnamebob", tiago);

        (address holder,) = popRules.getBaseNameReservation("longnamebob");
        assertEq(holder, leonardo);
    }

    // Same-owner re-reservation refreshes the expiry timestamp forward.
    function test_reserveBaseNameForPop_refreshes_expiry_for_same_owner() public {
        vm.prank(owner);
        dotnsRegistrar.addController(IDotnsController(address(this)));

        popRules.reserveBaseNameForPop("longnamebob", leonardo);
        (, uint64 firstExpiry) = popRules.getBaseNameReservation("longnamebob");

        vm.warp(block.timestamp + 1 days);

        popRules.reserveBaseNameForPop("longnamebob", leonardo);
        (address holder, uint64 refreshedExpiry) = popRules.getBaseNameReservation("longnamebob");

        assertEq(holder, leonardo);
        assertGt(refreshedExpiry, firstExpiry);
    }

    function test_base_reservation_rolls_forward_after_expiry() public {
        vm.prank(owner);
        dotnsRegistrar.addController(IDotnsController(address(this)));

        popRules.reserveBaseName("lights01", leonardo);

        (bool isReserved, address reservationOwner, uint64 expiryTimestamp) =
            popRules.isBaseNameReserved("lights");

        assertTrue(isReserved);
        assertEq(reservationOwner, leonardo);

        vm.warp(uint256(expiryTimestamp) + 1);

        popRules.reserveBaseName("lights02", tiago);

        (bool rolledReserved, address rolledOwner, uint64 rolledExpiry) =
            popRules.isBaseNameReserved("lights");

        assertTrue(rolledReserved);
        assertEq(rolledOwner, tiago);
        assertGt(rolledExpiry, expiryTimestamp);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPopRules.PopError.selector, "Base name reserved for original Lite registrant"
            )
        );
        popRules.priceWithCheck("lights", leonardo);
    }
}
