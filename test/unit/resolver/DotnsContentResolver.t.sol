// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../../base/BaseDotns.t.sol";
import {IDotnsContentResolver} from "../../../contracts/resolvers/IDotnsContentResolver.sol";
import {IPopRules} from "../../../contracts/pop/IPopRules.sol";

contract DotnsContentResolverTests is BaseDotns {
    function test_set_contenthash_and_read() public {
        address nameOwner = ed;

        bytes32 node = _register("contenthash01", nameOwner, IPopRules.PopStatus.NoStatus);

        bytes memory contentHash =
            hex"e30101701220aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

        vm.expectEmit(true, false, false, true);
        emit IDotnsContentResolver.ContentHashUpdated(node, contentHash);

        vm.startPrank(nameOwner);
        dotnsContentResolver.setContenthash(node, contentHash);
        vm.stopPrank();

        assertEq(dotnsContentResolver.contenthash(node), contentHash);
    }

    function test_set_text_and_read() public {
        address nameOwner = ed;

        bytes32 node = _register("textrecord01", nameOwner, IPopRules.PopStatus.NoStatus);

        string memory textKey = "ipfs";
        string memory textValue = "bafytextcid1";

        vm.expectEmit(true, true, false, true);
        emit IDotnsContentResolver.TextUpdated(node, textKey, textValue);

        vm.startPrank(nameOwner);
        dotnsContentResolver.setText(node, textKey, textValue);
        vm.stopPrank();

        assertEq(dotnsContentResolver.text(node, textKey), textValue);
    }

    function test_set_multiple_text_keys() public {
        address nameOwner = ed;

        bytes32 node = _register("multikeys01", nameOwner, IPopRules.PopStatus.NoStatus);

        string memory firstKey = "ipfs";
        string memory firstValue = "bafy1";
        string memory secondKey = "avatar";
        string memory secondValue = "bafy2";

        vm.startPrank(nameOwner);

        vm.expectEmit(true, true, false, true);
        emit IDotnsContentResolver.TextUpdated(node, firstKey, firstValue);
        dotnsContentResolver.setText(node, firstKey, firstValue);

        vm.expectEmit(true, true, false, true);
        emit IDotnsContentResolver.TextUpdated(node, secondKey, secondValue);
        dotnsContentResolver.setText(node, secondKey, secondValue);

        vm.stopPrank();

        assertEq(dotnsContentResolver.text(node, firstKey), firstValue);
        assertEq(dotnsContentResolver.text(node, secondKey), secondValue);
    }

    function test_set_text_on_multiple_nodes() public {
        address nameOwner = ed;

        bytes32 firstNode = _register("myspecialnodea01", nameOwner, IPopRules.PopStatus.NoStatus);
        bytes32 secondNode = _register("myspecialnodeb01", nameOwner, IPopRules.PopStatus.NoStatus);

        string memory textKey = "ipfs";
        string memory firstValue = "a";
        string memory secondValue = "b";

        vm.startPrank(nameOwner);

        vm.expectEmit(true, true, false, true);
        emit IDotnsContentResolver.TextUpdated(firstNode, textKey, firstValue);
        dotnsContentResolver.setText(firstNode, textKey, firstValue);

        vm.expectEmit(true, true, false, true);
        emit IDotnsContentResolver.TextUpdated(secondNode, textKey, secondValue);
        dotnsContentResolver.setText(secondNode, textKey, secondValue);

        vm.stopPrank();

        assertEq(dotnsContentResolver.text(firstNode, textKey), firstValue);
        assertEq(dotnsContentResolver.text(secondNode, textKey), secondValue);
    }

    function test_operator_can_set_text_records() public {
        address nameOwner = ed;
        address operator = address(this);

        bytes32 node = _register("operatorrr01", nameOwner, IPopRules.PopStatus.NoStatus);

        vm.startPrank(nameOwner);

        vm.expectEmit(true, true, false, true);
        emit IDotnsContentResolver.ApprovalForAll(nameOwner, operator, true);
        dotnsContentResolver.setApprovalForAll(operator, true);

        vm.stopPrank();

        string memory textKey = "ipfs";
        string memory textValue = "operatorCid";

        vm.startPrank(operator);

        vm.expectEmit(true, true, false, true);
        emit IDotnsContentResolver.TextUpdated(node, textKey, textValue);
        dotnsContentResolver.setText(node, textKey, textValue);

        vm.stopPrank();

        assertEq(dotnsContentResolver.text(node, textKey), textValue);
    }

    function test_operator_can_set_contenthash() public {
        address nameOwner = ed;
        address operator = address(this);

        bytes32 node = _register("operatorcontent01", nameOwner, IPopRules.PopStatus.NoStatus);

        bytes memory contentHash =
            hex"e30101701220bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

        vm.startPrank(nameOwner);

        vm.expectEmit(true, true, false, true);
        emit IDotnsContentResolver.ApprovalForAll(nameOwner, operator, true);
        dotnsContentResolver.setApprovalForAll(operator, true);

        vm.stopPrank();

        vm.startPrank(operator);

        vm.expectEmit(true, false, false, true);
        emit IDotnsContentResolver.ContentHashUpdated(node, contentHash);
        dotnsContentResolver.setContenthash(node, contentHash);

        vm.stopPrank();

        assertEq(dotnsContentResolver.contenthash(node), contentHash);
    }
}
