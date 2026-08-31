// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {DotnsFlatPricing} from "../../../contracts/pop/DotnsFlatPricing.sol";
import {IDotnsPricing} from "../../../contracts/pop/IDotnsPricing.sol";

/// @title DotnsFlatPricingTests
/// @notice Unit tests for the flat launch model, its zero-deposit guard, and its version
///         identifier.
contract DotnsFlatPricingTests is Test {
    uint256 internal constant DEPOSIT = 10 ether;

    DotnsFlatPricing internal pricing;

    function setUp() public {
        pricing = new DotnsFlatPricing(DEPOSIT);
    }

    function test_prices_every_base_length_at_the_deposit() public view {
        assertEq(pricing.priceForBaseLength(0), DEPOSIT);
        assertEq(pricing.priceForBaseLength(6), DEPOSIT);
        assertEq(pricing.priceForBaseLength(9), DEPOSIT);
        assertEq(pricing.priceForBaseLength(40), DEPOSIT);
    }

    function testFuzz_price_is_constant(uint256 baseLength) public view {
        assertEq(pricing.priceForBaseLength(baseLength), DEPOSIT);
    }

    function test_constructor_reverts_for_zero_deposit() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsPricing.PricingError.selector, "Deposit must be greater than 0"
            )
        );
        new DotnsFlatPricing(0);
    }

    function test_version_is_stable_for_the_same_deposit() public {
        DotnsFlatPricing twin = new DotnsFlatPricing(DEPOSIT);
        assertEq(pricing.version(), twin.version());
    }

    function test_version_changes_with_the_deposit() public {
        DotnsFlatPricing other = new DotnsFlatPricing(DEPOSIT * 2);
        assertTrue(pricing.version() != other.version());
    }

    function test_version_differs_from_another_model_form() public view {
        // The form identifier is mixed into the version, so a different model shape cannot collide
        // with the flat model at the same amount.
        uint256 scarcityFormId = uint256(keccak256("dotns.pricing.scarcity.v1"));
        assertTrue(pricing.version() != uint256(keccak256(abi.encode(scarcityFormId, DEPOSIT))));
    }
}
