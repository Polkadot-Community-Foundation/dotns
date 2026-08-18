// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {BaseDotns} from "../../base/BaseDotns.t.sol";
import {WhitelistHandler} from "./WhitelistHandler.t.sol";
import {DotnsNameWhitelist} from "../../../contracts/whitelist/DotnsNameWhitelist.sol";
import {IDotnsNameWhitelist} from "../../../contracts/whitelist/IDotnsNameWhitelist.sol";
import {IDotnsProtocolRegistry} from "../../../contracts/registry/IDotnsProtocolRegistry.sol";
import {DotnsConstants} from "../../../contracts/utils/DotnsConstants.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/// @title DotnsNameWhitelist invariants
/// @notice Drives the whitelist through random lifecycle sequences and asserts the review and
///         reservation guarantees hold at every step.
contract DotnsNameWhitelistInvariant is BaseDotns {
    DotnsNameWhitelist internal whitelist;
    WhitelistHandler internal handler;

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
        whitelist.setWindow(0, 3650 days);
        vm.stopPrank();

        address[] memory actors = new address[](4);
        for (uint256 i; i < 4; ++i) {
            actors[i] = makeAddr(string.concat("wlActor", vm.toString(i)));
        }

        handler = new WhitelistHandler(
            whitelist, owner, protocolRegistry.get(DotnsConstants.CONTROLLER), actors
        );
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.request.selector;
        selectors[1] = handler.accept.selector;
        selectors[2] = handler.reject.selector;
        selectors[3] = handler.grant.selector;
        selectors[4] = handler.revoke.selector;
        selectors[5] = handler.consume.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @notice Every entry the paged getter returns is live, so `_grants` and `_grantedNodes`
    ///         never drift apart across grant, revoke and consume.
    function invariant_pagination_returns_only_live_entries() public view {
        uint256 count = whitelist.grantCount();
        IDotnsNameWhitelist.Grant[] memory page = whitelist.grants(0, count == 0 ? 1 : count);
        assertEq(page.length, count);
        for (uint256 i; i < page.length; ++i) {
            assertTrue(page[i].status != IDotnsNameWhitelist.GrantStatus.None);
            assertTrue(page[i].grantee != address(0));
        }
    }

    /// @notice A name reserves an address only while it is `Accepted`.
    function invariant_granteeOf_only_when_accepted() public view {
        uint256 seen = handler.labelsSeenCount();
        for (uint256 i; i < seen; ++i) {
            string memory label = handler.labelsSeen(i);
            if (whitelist.granteeOf(label) != address(0)) {
                assertEq(
                    uint256(whitelist.grantOf(label).status),
                    uint256(IDotnsNameWhitelist.GrantStatus.Accepted)
                );
            }
        }
    }

    /// @notice Any live entry has a non-zero grantee and a request timestamp.
    function invariant_live_entry_is_well_formed() public view {
        uint256 seen = handler.labelsSeenCount();
        for (uint256 i; i < seen; ++i) {
            IDotnsNameWhitelist.Grant memory grant = whitelist.grantOf(handler.labelsSeen(i));
            if (grant.status != IDotnsNameWhitelist.GrantStatus.None) {
                assertTrue(grant.grantee != address(0));
                assertGt(grant.requestedAt, 0);
            }
        }
    }
}
