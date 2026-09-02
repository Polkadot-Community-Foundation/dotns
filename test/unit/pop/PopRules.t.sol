// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {BaseDotns} from "../../base/BaseDotns.t.sol";
import {PopRules, IPopRules} from "../../../contracts/pop/PopRules.sol";
import {IDotnsController} from "../../../contracts/registrars/IDotnsController.sol";
import {
    DotnsProtocolRegistry,
    IDotnsProtocolRegistry
} from "../../../contracts/registry/DotnsProtocolRegistry.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/// @title PopRulesTests
/// @notice Unit tests for PopRules name classification, pricing checks, and base-name reservation
/// authorisation.
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
        assertEq(classificationMessage, "Requires Lite personhood verification");
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

    function test_classify_nostatus_no_digits() public view {
        (IPopRules.PopStatus classificationStatus, string memory classificationMessage) =
            popRules.classifyName("longnamehere");

        assertEq(uint256(classificationStatus), uint256(IPopRules.PopStatus.NoStatus));
        assertEq(classificationMessage, "Available to all");
    }

    function test_classify_reverts_for_one_digit_suffix() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPopRules.PopError.selector,
                "Name must have no digit suffix or exactly 2 digit suffix"
            )
        );
        popRules.classifyName("andrew1");
    }

    function test_classify_reverts_for_three_digit_suffix() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPopRules.PopError.selector,
                "Name must have no digit suffix or exactly 2 digit suffix"
            )
        );
        popRules.classifyName("andrew123");
    }

    function test_trailing_digits_do_not_change_price() public view {
        assertEq(popRules.price("andrew01"), popRules.price("andrew"));
    }

    function test_verified_person_pays_the_deposit_for_premium() public {
        _grantPopFull(ed);

        assertEq(popRules.priceWithCheck("alicebob", ed).price, BASE_DEPOSIT);
        assertEq(popRules.priceWithCheck("lights", ed).price, BASE_DEPOSIT);
    }

    function test_transfer_reprices_at_own_length() public {
        _grantPopFull(leonardo);

        assertEq(popRules.transferFloor("lights", leonardo, tiago), BASE_DEPOSIT);
        assertEq(popRules.transferFloor("lights", leonardo, leonardo), 0);
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
                IPopRules.PopError.selector, "Requires Full personhood verification"
            )
        );
        popRules.priceWithCheck("alicebob", ed);
    }

    function test_popfull_user_can_access_poplite_name() public {
        _grantPopFull(ed);

        IPopRules.PriceWithMeta memory priceMetadata = popRules.priceWithCheck("lights01", ed);

        assertEq(uint256(priceMetadata.status), uint256(IPopRules.PopStatus.PopLite));
        assertEq(uint256(priceMetadata.userStatus), uint256(IPopRules.PopStatus.PopFull));
        assertEq(priceMetadata.price, BASE_DEPOSIT);
    }

    function test_poplite_user_can_access_nostatus_name() public {
        _grantPopLite(ed);

        IPopRules.PriceWithMeta memory priceMetadata = popRules.priceWithCheck("longnamehere01", ed);

        assertEq(uint256(priceMetadata.status), uint256(IPopRules.PopStatus.NoStatus));
        assertEq(uint256(priceMetadata.userStatus), uint256(IPopRules.PopStatus.PopLite));
        assertEq(priceMetadata.price, BASE_DEPOSIT);
    }

    function test_base_reservation_blocks_others() public {
        // Authorise this test contract as a registrar controller so it may call
        // reserveBaseName (gated by DotnsRegistrar.controllers). Passes the stem
        // directly per the stems-only public boundary.
        _authoriseTestAsController();

        popRules.reserveBaseName("lights", leonardo);

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
        _authoriseTestAsController();

        popRules.reserveBaseName("lights", leonardo);

        IPopRules.PriceWithMeta memory priceMetadata = popRules.priceWithoutCheck("lights", tiago);

        assertEq(uint256(priceMetadata.status), uint256(IPopRules.PopStatus.Reserved));
        assertEq(priceMetadata.price, popRules.price("lights"));
    }

    function test_short_names_closed_reverts_direct_path() public {
        _setShortNames(false);
        _grantPopFull(ed);
        vm.expectRevert(
            abi.encodeWithSelector(IPopRules.PopError.selector, "Short names are not for sale")
        );
        popRules.priceWithCheck("alicebob", ed);
    }

    function test_short_names_closed_reverts_sponsored_path() public {
        _setShortNames(false);
        vm.expectRevert(
            abi.encodeWithSelector(IPopRules.PopError.selector, "Short names are not for sale")
        );
        popRules.priceWithoutCheck("alicebob", ed);
    }

    function test_open_band_priced_while_short_names_closed() public {
        _setShortNames(false);
        _grantPopLite(ed);
        // longnamehere is 12 characters, so the switch never gates it.
        assertEq(popRules.priceWithCheck("longnamehere", ed).price, BASE_DEPOSIT);
    }

    function test_enabling_short_names_opens_the_market() public {
        _setShortNames(false);
        _grantPopFull(ed);
        _setShortNames(true);
        assertEq(popRules.priceWithCheck("alicebob", ed).price, BASE_DEPOSIT);
    }

    function test_setShortNamesEnabled_emits() public {
        _mockOriginIsRoot(true);
        vm.expectEmit(address(popRules));
        emit IPopRules.ShortNamesEnabledUpdated(false);
        popRules.setShortNamesEnabled(false);
    }

    function test_setShortNamesEnabled_requires_root() public {
        // A non-Root origin: originIsRoot returns false, so the setter reverts NotRoot regardless
        // of the caller (owner included).
        _mockOriginIsRoot(false);
        vm.expectRevert(IPopRules.NotRoot.selector);
        vm.prank(ed);
        popRules.setShortNamesEnabled(false);
    }

    function test_setShortNamesEnabled_root_succeeds() public {
        _mockOriginIsRoot(true);
        popRules.setShortNamesEnabled(true);
        assertTrue(popRules.shortNamesEnabled());
    }

    function test_price_matches_model() public view {
        string memory label = "thisisaverylongname";
        uint256 baseLength = bytes(label).length;
        assertEq(popRules.price(label), flatPricing.priceForBaseLength(baseLength));
        assertEq(popRules.price(label), costModelRegistry.priceForBaseLength(baseLength));
    }

    function test_priceWithCheck_matches_model() public view {
        string memory label = "longnamehere";
        IPopRules.PriceWithMeta memory metadata = popRules.priceWithCheck(label, ed);
        assertEq(metadata.price, costModelRegistry.priceForBaseLength(bytes(label).length));
    }

    function test_transferFloor_matches_model() public {
        // A PopFull sender handing a NoStatus name to a NoStatus recipient pays the name's own
        // price, which is the registered model's amount for its base length.
        string memory label = "longnamehere";
        _grantPopFull(ed);
        uint256 floor = popRules.transferFloor(label, ed, leonardo);
        assertEq(floor, costModelRegistry.priceForBaseLength(bytes(label).length));
    }

    function test_pricingVersion_matches_registry() public view {
        assertEq(popRules.pricingVersion(), costModelRegistry.currentVersion());
        assertEq(popRules.pricingVersion(), flatPricing.version());
    }

    function test_price_reverts_when_cost_model_unconfigured() public {
        // A PopRules bound to a registry with no COST_MODEL key fails closed on any pricing read.
        vm.startPrank(owner);
        address freshRegistry = Upgrades.deployUUPSProxy(
            "DotnsProtocolRegistry.sol:DotnsProtocolRegistry",
            abi.encodeCall(DotnsProtocolRegistry.initialize, (TLD_LABEL))
        );
        address freshPopRules = Upgrades.deployUUPSProxy(
            "PopRules.sol:PopRules",
            abi.encodeCall(PopRules.initialize, (IDotnsProtocolRegistry(freshRegistry)))
        );
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(IPopRules.PopError.selector, "Cost model not configured")
        );
        PopRules(freshPopRules).price("longnamehere");
    }

    function test_reserveBaseNameForPop_reverts_for_non_controller() public {
        vm.prank(ed);
        vm.expectRevert(IPopRules.NotRegistry.selector);
        popRules.reserveBaseNameForPop("longnamebob", ed);
    }

    function test_releaseBaseName_reverts_for_non_controller() public {
        vm.prank(ed);
        vm.expectRevert(IPopRules.NotRegistry.selector);
        popRules.releaseBaseName("longnamebob");
    }

    function test_reserveBaseNameForPop_reverts_when_slot_held_by_other_user() public {
        _authoriseTestAsController();

        popRules.reserveBaseNameForPop("longnamebob", leonardo);

        vm.expectRevert(
            abi.encodeWithSelector(IPopRules.PopError.selector, "Base name held by another user")
        );
        popRules.reserveBaseNameForPop("longnamebob", tiago);

        (address holder,) = popRules.getBaseNameReservation("longnamebob");
        assertEq(holder, leonardo);
    }

    function test_reserveBaseNameForPop_refreshes_expiry_for_same_owner() public {
        _authoriseTestAsController();

        popRules.reserveBaseNameForPop("longnamebob", leonardo);
        (, uint64 firstExpiry) = popRules.getBaseNameReservation("longnamebob");

        vm.warp(block.timestamp + 1 days);

        popRules.reserveBaseNameForPop("longnamebob", leonardo);
        (address holder, uint64 refreshedExpiry) = popRules.getBaseNameReservation("longnamebob");

        assertEq(holder, leonardo);
        assertGt(refreshedExpiry, firstExpiry);
    }

    function test_releaseBaseName_reverts_for_non_reserving_controller() public {
        _authoriseTestAsController();
        popRules.reserveBaseNameForPop("longnamebob", leonardo);

        address otherController = makeAddr("otherController");
        vm.prank(owner);
        dotnsRegistrar.addController(IDotnsController(otherController));

        vm.prank(otherController);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPopRules.PopError.selector, "Only reserving controller can release"
            )
        );
        popRules.releaseBaseName("longnamebob");

        (address holder,) = popRules.getBaseNameReservation("longnamebob");
        assertEq(holder, leonardo);
    }

    function test_releaseBaseName_succeeds_for_reserving_controller() public {
        _authoriseTestAsController();
        popRules.reserveBaseNameForPop("longnamebob", leonardo);

        popRules.releaseBaseName("longnamebob");

        (address holder,) = popRules.getBaseNameReservation("longnamebob");
        assertEq(holder, address(0));
    }

    function test_releaseBaseName_expired_slot_cleared_by_any_controller() public {
        _authoriseTestAsController();
        popRules.reserveBaseNameForPop("longnamebob", leonardo);

        vm.warp(block.timestamp + popRules.MAX_RESERVATION_TIME() + 1);

        address otherController = makeAddr("otherController");
        vm.prank(owner);
        dotnsRegistrar.addController(IDotnsController(otherController));

        vm.prank(otherController);
        popRules.releaseBaseName("longnamebob");

        (address holder,) = popRules.getBaseNameReservation("longnamebob");
        assertEq(holder, address(0));
    }

    function test_writeReservation_preserves_original_controller_on_same_owner_refresh() public {
        _authoriseTestAsController();
        popRules.reserveBaseNameForPop("longnamebob", leonardo);

        address otherController = makeAddr("otherController");
        vm.prank(owner);
        dotnsRegistrar.addController(IDotnsController(otherController));

        vm.prank(otherController);
        popRules.reserveBaseNameForPop("longnamebob", leonardo);

        vm.prank(otherController);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPopRules.PopError.selector, "Only reserving controller can release"
            )
        );
        popRules.releaseBaseName("longnamebob");

        popRules.releaseBaseName("longnamebob");
        (address holder,) = popRules.getBaseNameReservation("longnamebob");
        assertEq(holder, address(0));
    }
}
