// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {BaseDotns} from "../../base/BaseDotns.t.sol";
import {PopRulesGovernanceHandler} from "./PopRulesGovernanceHandler.t.sol";

/// @title PopRules Governance Invariant Suite
/// @notice Asserts the curve stays coherent after any reachable sequence of governance updates:
///         the floor stays within the base fee, no name prices at zero, and price never increases
///         with length. This is the on-chain proof that governance cannot reach a broken state.
contract PopRulesGovernanceInvariantTest is BaseDotns {
    /// @notice Handler driving randomised governance updates. Owns PopRules for the campaign.
    PopRulesGovernanceHandler public handler;

    function setUp() public override {
        super.setUp();
        handler = new PopRulesGovernanceHandler(popRules);
        vm.prank(owner);
        popRules.transferOwnership(address(handler));
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.setStartingPrice.selector;
        selectors[1] = handler.setMinPrice.selector;
        selectors[2] = handler.setShortNames.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @notice The floor is always positive and never exceeds the base fee.
    function invariant_floor_within_base_fee() public view {
        assertGt(popRules.minPrice(), 0);
        assertLe(popRules.minPrice(), popRules.startingPrice());
    }

    /// @notice Price never reaches zero and never increases as the base length grows.
    function invariant_price_stays_coherent() public view {
        uint256 p3 = popRules.price("cat");
        uint256 p8 = popRules.price("alicebob");
        uint256 p9 = popRules.price("abcdefghi");
        uint256 p12 = popRules.price("longnamehere");
        uint256 p19 = popRules.price("thisisaverylongname");
        assertGt(p19, 0);
        assertGe(p3, p8);
        assertGe(p8, p9);
        assertGe(p9, p12);
        assertGe(p12, p19);
    }
}
