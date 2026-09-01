// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {DotnsScarcityPricing} from "../../../contracts/pop/DotnsScarcityPricing.sol";
import {IDotnsPricing} from "../../../contracts/pop/IDotnsPricing.sol";

/// @title DotnsScarcityPricingTests
/// @notice Unit tests for the scarcity curve, its constructor guards, and its version identifier.
contract DotnsScarcityPricingTests is Test {
    uint256 internal constant BASE_FEE = 10 ether;
    uint256 internal constant FLOOR = 0.1 ether;

    DotnsScarcityPricing internal pricing;

    function setUp() public {
        pricing = new DotnsScarcityPricing(BASE_FEE, FLOOR);
    }

    function test_pivot_at_nine_is_base_fee() public view {
        assertEq(pricing.priceForBaseLength(9), BASE_FEE);
    }

    function test_doubles_below_nine() public view {
        assertEq(pricing.priceForBaseLength(8), BASE_FEE * 2);
        assertEq(pricing.priceForBaseLength(7), BASE_FEE * 4);
        // Base length 0 (an all-digit label) reaches the 2**9 multiplier.
        assertEq(pricing.priceForBaseLength(0), BASE_FEE * 512);
    }

    function test_halves_above_nine() public view {
        assertEq(pricing.priceForBaseLength(10), BASE_FEE / 2);
        assertEq(pricing.priceForBaseLength(11), BASE_FEE / 4);
    }

    function test_floor_binds_for_long_names() public view {
        // Far enough up the curve that the halved amount falls below the floor.
        assertEq(pricing.priceForBaseLength(40), FLOOR);
    }

    function test_constructor_reverts_for_zero_base_fee() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsPricing.PricingError.selector, "Base fee must be greater than 0"
            )
        );
        new DotnsScarcityPricing(0, FLOOR);
    }

    function test_constructor_reverts_for_zero_floor() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsPricing.PricingError.selector, "Floor must be greater than 0"
            )
        );
        new DotnsScarcityPricing(BASE_FEE, 0);
    }

    function test_constructor_reverts_when_floor_exceeds_base_fee() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsPricing.PricingError.selector, "Floor cannot exceed the base fee"
            )
        );
        new DotnsScarcityPricing(BASE_FEE, BASE_FEE + 1);
    }

    function test_constructor_reverts_above_ceiling() public {
        uint256 tooHigh = type(uint256).max / 512 + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsPricing.PricingError.selector, "Base fee exceeds the scarcity-curve ceiling"
            )
        );
        new DotnsScarcityPricing(tooHigh, FLOOR);
    }

    function test_ceiling_boundary_is_exactly_safe() public {
        // At the exact ceiling the base length 0 multiplier of 512 must still not overflow.
        uint256 ceiling = type(uint256).max / 512;
        DotnsScarcityPricing atCeiling = new DotnsScarcityPricing(ceiling, FLOOR);
        assertEq(atCeiling.priceForBaseLength(0), ceiling * 512);
    }

    function test_version_stable_on_identical_redeploy() public {
        DotnsScarcityPricing twin = new DotnsScarcityPricing(BASE_FEE, FLOOR);
        assertEq(pricing.version(), twin.version());
    }

    function test_version_differs_on_differing_params() public {
        DotnsScarcityPricing otherFee = new DotnsScarcityPricing(BASE_FEE * 2, FLOOR);
        DotnsScarcityPricing otherFloor = new DotnsScarcityPricing(BASE_FEE, FLOOR * 2);
        assertTrue(pricing.version() != otherFee.version());
        assertTrue(pricing.version() != otherFloor.version());
    }
}
