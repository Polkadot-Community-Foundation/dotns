// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../../base/BaseDotns.t.sol";
import {IDotnsContentResolver} from "../../../contracts/resolvers/IDotnsContentResolver.sol";
import {IPopOracle} from "../../../contracts/pop/IPopOracle.sol";

contract DotnsContentResolverTests is BaseDotns {
    function test_setcontenthash() public {
        bytes32 node = _register("contenthashrecord01", ed, IPopOracle.PopStatus.NoStatus);
        bytes memory h =
            hex"e30101701220aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

        vm.expectEmit(true, false, false, true);
        emit IDotnsContentResolver.ContentHashUpdated(node, h);

        vm.prank(ed);
        dotnsContentResolver.setContenthash(node, h);

        assertEq(dotnsContentResolver.contenthash(node), h);
    }

    function test_setcontenthash_emits() public {
        bytes32 node = _register("contenthashevt01", ed, IPopOracle.PopStatus.NoStatus);
        bytes memory h = hex"e30101701220bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

        vm.expectEmit(true, false, false, true);
        emit IDotnsContentResolver.ContentHashUpdated(node, h);

        vm.prank(ed);
        dotnsContentResolver.setContenthash(node, h);
    }

    function test_contenthash_defaultempty() public {
        bytes32 node = _register("contenthashunset01", ed, IPopOracle.PopStatus.NoStatus);

        bytes memory stored = dotnsContentResolver.contenthash(node);
        assertEq(stored.length, 0);
    }

    function test_setcontenthash_overwrite() public {
        bytes32 node = _register("contenthashovr01", ed, IPopOracle.PopStatus.NoStatus);
        bytes memory a =
            hex"e30101701220aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        bytes memory b = hex"e30101701220cccccccccccccccccccccccccccccccccccccccccccccccccccccccc";

        vm.startPrank(ed);

        vm.expectEmit(true, false, false, true);
        emit IDotnsContentResolver.ContentHashUpdated(node, a);
        dotnsContentResolver.setContenthash(node, a);

        vm.expectEmit(true, false, false, true);
        emit IDotnsContentResolver.ContentHashUpdated(node, b);
        dotnsContentResolver.setContenthash(node, b);

        vm.stopPrank();

        assertEq(dotnsContentResolver.contenthash(node), b);
    }

    function test_settext() public {
        bytes32 node = _register("textrecord01", ed, IPopOracle.PopStatus.NoStatus);

        vm.expectEmit(true, true, false, true);
        emit IDotnsContentResolver.TextUpdated(node, "ipfs", "bafytextcid1");

        vm.prank(ed);
        dotnsContentResolver.setText(node, "ipfs", "bafytextcid1");

        assertEq(dotnsContentResolver.text(node, "ipfs"), "bafytextcid1");
    }

    function test_settext_emits() public {
        bytes32 node = _register("texteventlong01", ed, IPopOracle.PopStatus.NoStatus);

        vm.expectEmit(true, true, false, true);
        emit IDotnsContentResolver.TextUpdated(node, "ipfs", "bafyemittext");

        vm.prank(ed);
        dotnsContentResolver.setText(node, "ipfs", "bafyemittext");
    }

    function test_text_defaultempty() public {
        bytes32 node = _register("textunset01", ed, IPopOracle.PopStatus.NoStatus);

        string memory v = dotnsContentResolver.text(node, "ipfs");
        assertEq(bytes(v).length, 0);
    }

    function test_settext_overwrite() public {
        bytes32 node = _register("textoverwritelong01", ed, IPopOracle.PopStatus.NoStatus);

        vm.startPrank(ed);

        vm.expectEmit(true, true, false, true);
        emit IDotnsContentResolver.TextUpdated(node, "ipfs", "a");
        dotnsContentResolver.setText(node, "ipfs", "a");

        vm.expectEmit(true, true, false, true);
        emit IDotnsContentResolver.TextUpdated(node, "ipfs", "b");
        dotnsContentResolver.setText(node, "ipfs", "b");

        vm.stopPrank();

        assertEq(dotnsContentResolver.text(node, "ipfs"), "b");
    }

    function test_settext_multiplekeys() public {
        bytes32 node = _register("textkeyslongname01", ed, IPopOracle.PopStatus.NoStatus);

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

    function test_settext_isolatednodes() public {
        bytes32 nodeA = _register("nodeisolationa01", ed, IPopOracle.PopStatus.NoStatus);
        bytes32 nodeB = _register("nodeisolationb01", ed, IPopOracle.PopStatus.NoStatus);

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
}
