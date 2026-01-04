// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../../base/BaseDotns.t.sol";
import {IDotnsContentResolver} from "../../../contracts/resolvers/IDotnsContentResolver.sol";
import {IPopOracle} from "../../../contracts/pop/IPopOracle.sol";

contract DotnsContentResolverTests is BaseDotns {
    function test_setContenthash_and_read() public {
        bytes32 node = _register("contenthash01", ed, IPopOracle.PopStatus.NoStatus);
        bytes memory hash =
            hex"e30101701220aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

        vm.expectEmit(true, false, false, true);
        emit IDotnsContentResolver.ContentHashUpdated(node, hash);

        vm.prank(ed);
        dotnsContentResolver.setContenthash(node, hash);

        assertEq(dotnsContentResolver.contenthash(node), hash);
    }

    function test_setText_and_read() public {
        bytes32 node = _register("textrecord01", ed, IPopOracle.PopStatus.NoStatus);

        vm.expectEmit(true, true, false, true);
        emit IDotnsContentResolver.TextUpdated(node, "ipfs", "bafytextcid1");

        vm.prank(ed);
        dotnsContentResolver.setText(node, "ipfs", "bafytextcid1");

        assertEq(dotnsContentResolver.text(node, "ipfs"), "bafytextcid1");
    }

    function test_setMultipleTextKeys() public {
        bytes32 node = _register("multikeys01", ed, IPopOracle.PopStatus.NoStatus);

        vm.startPrank(ed);

        vm.expectEmit(true, true, false, true);
        emit IDotnsContentResolver.TextUpdated(node, "ipfs", "bafy1");
        dotnsContentResolver.setText(node, "ipfs", "bafy1");

        vm.expectEmit(true, true, false, true);
        emit IDotnsContentResolver.TextUpdated(node, "avatar", "bafy2");
        dotnsContentResolver.setText(node, "avatar", "bafy2");

        vm.stopPrank();

        assertEq(dotnsContentResolver.text(node, "ipfs"), "bafy1");
        assertEq(dotnsContentResolver.text(node, "avatar"), "bafy2");
    }

    function test_setText_onMultipleNodes() public {
        bytes32 nodeA = _register("mysepcialnodeA01", ed, IPopOracle.PopStatus.NoStatus);
        bytes32 nodeB = _register("mysepcialnodeB01", ed, IPopOracle.PopStatus.NoStatus);

        vm.startPrank(ed);

        vm.expectEmit(true, true, false, true);
        emit IDotnsContentResolver.TextUpdated(nodeA, "ipfs", "a");
        dotnsContentResolver.setText(nodeA, "ipfs", "a");

        vm.expectEmit(true, true, false, true);
        emit IDotnsContentResolver.TextUpdated(nodeB, "ipfs", "b");
        dotnsContentResolver.setText(nodeB, "ipfs", "b");

        vm.stopPrank();

        assertEq(dotnsContentResolver.text(nodeA, "ipfs"), "a");
        assertEq(dotnsContentResolver.text(nodeB, "ipfs"), "b");
    }

    function test_operatorCanSetRecords() public {
        bytes32 node = _register("operatoor01", ed, IPopOracle.PopStatus.NoStatus);

        vm.prank(ed);
        vm.expectEmit(true, true, false, true);
        emit IDotnsContentResolver.ApprovalForAll(ed, address(this), true);
        dotnsContentResolver.setApprovalForAll(address(this), true);

        vm.expectEmit(true, true, false, true);
        emit IDotnsContentResolver.TextUpdated(node, "ipfs", "operatorCid");
        dotnsContentResolver.setText(node, "ipfs", "operatorCid");

        assertEq(dotnsContentResolver.text(node, "ipfs"), "operatorCid");
    }

    function test_operatorCanSetContenthash() public {
        bytes32 node = _register("operatorContent01", ed, IPopOracle.PopStatus.NoStatus);
        bytes memory hash =
            hex"e30101701220bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

        vm.prank(ed);
        vm.expectEmit(true, true, false, true);
        emit IDotnsContentResolver.ApprovalForAll(ed, address(this), true);
        dotnsContentResolver.setApprovalForAll(address(this), true);

        vm.expectEmit(true, false, false, true);
        emit IDotnsContentResolver.ContentHashUpdated(node, hash);
        dotnsContentResolver.setContenthash(node, hash);

        assertEq(dotnsContentResolver.contenthash(node), hash);
    }
}
