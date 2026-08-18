// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {BaseDotns} from "../../base/BaseDotns.t.sol";
import {DotnsNameWhitelist} from "../../../contracts/whitelist/DotnsNameWhitelist.sol";
import {IDotnsNameWhitelist} from "../../../contracts/whitelist/IDotnsNameWhitelist.sol";
import {IDotnsProtocolRegistry} from "../../../contracts/registry/IDotnsProtocolRegistry.sol";
import {DotnsConstants} from "../../../contracts/utils/DotnsConstants.sol";
import {StringUtils} from "../../../contracts/utils/StringUtils.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/// @title DotnsNameWhitelist fuzz tests
/// @notice Exercises the grant and lifecycle paths over fuzzed labels, addresses and windows.
contract DotnsNameWhitelistFuzz is BaseDotns {
    DotnsNameWhitelist internal whitelist;

    function setUp() public override {
        super.setUp();
        vm.startPrank(owner);
        whitelist = DotnsNameWhitelist(
            Upgrades.deployUUPSProxy(
                "DotnsNameWhitelist.sol:DotnsNameWhitelist",
                abi.encodeCall(
                    DotnsNameWhitelist.initialize,
                    (IDotnsProtocolRegistry(address(protocolRegistry)))
                )
            )
        );
        whitelist.setWindow(0, 365 days);
        vm.stopPrank();
    }

    /// @notice Builds a canonical single label from a fuzz seed.
    function _label(uint256 seed) internal pure returns (string memory) {
        uint256 value = seed % 100;
        string memory suffix = value < 10
            ? string.concat("0", StringUtils.uintToString(value))
            : StringUtils.uintToString(value);
        return string.concat("fuzzname", suffix);
    }

    function testFuzz_grantName_reserves_only_the_intended_account(
        uint256 seed,
        address grantee,
        address other
    )
        public
    {
        vm.assume(grantee != address(0));
        vm.assume(other != address(0) && other != grantee);
        string memory label = _label(seed);

        vm.prank(owner);
        whitelist.grantName(label, grantee);

        assertEq(whitelist.granteeOf(label), grantee);
        assertTrue(whitelist.isGrantedTo(label, grantee));
        assertFalse(whitelist.isGrantedTo(label, other));
    }

    function testFuzz_request_then_accept_reserves_requester(uint256 seed) public {
        string memory label = _label(seed);

        vm.prank(ed);
        whitelist.requestName(label);
        assertEq(whitelist.granteeOf(label), address(0));

        vm.prank(owner);
        whitelist.accept(label);
        assertEq(whitelist.granteeOf(label), ed);
    }

    function testFuzz_reject_never_reserves(uint256 seed) public {
        string memory label = _label(seed);

        vm.prank(ed);
        whitelist.requestName(label);
        vm.prank(owner);
        whitelist.reject(label);

        assertEq(whitelist.granteeOf(label), address(0));
        assertEq(
            uint256(whitelist.grantOf(label).status),
            uint256(IDotnsNameWhitelist.GrantStatus.Rejected)
        );
    }

    function testFuzz_grantName_reverts_on_duplicate(uint256 seed, address a, address b) public {
        vm.assume(a != address(0) && b != address(0) && a != b);
        string memory label = _label(seed);

        vm.prank(owner);
        whitelist.grantName(label, a);

        vm.expectRevert(
            abi.encodeWithSelector(IDotnsNameWhitelist.AlreadyExists.selector, _nodeOf(label))
        );
        vm.prank(owner);
        whitelist.grantName(label, b);
    }

    function testFuzz_requestName_reverts_before_window_opens(
        uint256 seed,
        uint64 startsIn
    )
        public
    {
        startsIn = uint64(bound(uint256(startsIn), 1 days, 3650 days));
        string memory label = _label(seed);

        vm.prank(owner);
        whitelist.setWindow(startsIn, 1 days);

        vm.expectRevert(IDotnsNameWhitelist.WindowClosed.selector);
        vm.prank(ed);
        whitelist.requestName(label);
    }

    function testFuzz_requestName_reverts_after_window_closes(
        uint256 seed,
        uint64 duration
    )
        public
    {
        duration = uint64(bound(uint256(duration), 1, 3650 days));
        string memory label = _label(seed);

        vm.prank(owner);
        whitelist.setWindow(0, duration);
        vm.warp(block.timestamp + duration);

        vm.expectRevert(IDotnsNameWhitelist.WindowClosed.selector);
        vm.prank(ed);
        whitelist.requestName(label);
    }
}
