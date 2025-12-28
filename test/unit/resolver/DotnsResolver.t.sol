// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../../base/BaseDotns.t.sol";
import {IDotnsResolver} from "../../../contracts/resolvers/IDotnsResolver.sol";
import {IPopOracle} from "../../../contracts/pop/IPopOracle.sol";

contract DotnsResolverTests is BaseDotns {
    function test_setaddress_nostatus() public {
        bytes32 node = _register("longnamehere01", ed, IPopOracle.PopStatus.NoStatus);

        vm.prank(ed);
        dotnsResolver.setAddress(node, leonardo);

        assertEq(dotnsResolver.addressOf(node), leonardo);
    }

    function test_setaddress_poplite() public {
        bytes32 node = _register("lights01", ed, IPopOracle.PopStatus.PopLite);

        vm.prank(ed);
        dotnsResolver.setAddress(node, leonardo);

        assertEq(dotnsResolver.addressOf(node), leonardo);
    }

    function test_setaddress_popfull() public {
        bytes32 node = _register("alicebob", ed, IPopOracle.PopStatus.PopFull);

        vm.prank(ed);
        dotnsResolver.setAddress(node, leonardo);

        assertEq(dotnsResolver.addressOf(node), leonardo);
    }

    function test_setaddress_emits() public {
        bytes32 node = _register("emittestname01", ed, IPopOracle.PopStatus.NoStatus);

        vm.expectEmit(true, true, true, true);
        emit IDotnsResolver.AddressSet(node, leonardo);

        vm.prank(ed);
        dotnsResolver.setAddress(node, leonardo);
    }

    function test_setaddress_overwrite() public {
        bytes32 node = _register("overwriteaddr01", ed, IPopOracle.PopStatus.NoStatus);

        vm.startPrank(ed);
        dotnsResolver.setAddress(node, leonardo);
        dotnsResolver.setAddress(node, tiago);
        vm.stopPrank();

        assertEq(dotnsResolver.addressOf(node), tiago);
    }
}
