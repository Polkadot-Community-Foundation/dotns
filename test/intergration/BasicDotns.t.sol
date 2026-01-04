// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../base/BaseDotns.t.sol";
import {IPopOracle} from "../../contracts/pop/IPopOracle.sol";
import {IDotnsRegistry} from "../../contracts/registry/IDotnsRegistry.sol";
import {Store} from "../../contracts/store/Store.sol";

contract BasicDotnsIntegration is BaseDotns {
    /// @dev base 7, trailing 1 => PopFull
    string internal constant NAME_POPFULL = "waytall1";
    /// @dev base 8, trailing 2 => PopLite
    string internal constant NAME_POPLITE = "way2tall01";
    /// @dev base 11, trailing 2 => NoStatus
    string internal constant NAME_NOSTATUS = "kitesurfing01";

    /// @dev Valid CIDv1-like bytes
    bytes internal constant CID_A =
        hex"e30101701220aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    bytes internal constant CID_B =
        hex"e30101701220bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

    struct FlowParams {
        address nameOwner;
        string name;
        bool reserved;

        string selfSub;
        string otherSub;
        address otherOwner;

        address transferTo;

        string transferRecipientNewName;
        string transferRecipientSub;
    }

    function test_popfull_end_to_end() public {
        vm.prank(ed);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopFull);

        _flow_end_to_end(
            FlowParams({
                nameOwner: ed,
                name: NAME_POPFULL,
                reserved: true,
                selfSub: "app",
                otherSub: "blog",
                otherOwner: leonardo,
                transferTo: tiago,
                transferRecipientNewName: "transfername01",
                transferRecipientSub: "docs"
            })
        );
    }

    function test_poplite_end_to_end() public {
        vm.prank(leonardo);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopLite);

        _flow_end_to_end(
            FlowParams({
                nameOwner: leonardo,
                name: NAME_POPLITE,
                reserved: true,
                selfSub: "app",
                otherSub: "blog",
                otherOwner: ed,
                transferTo: tiago,
                transferRecipientNewName: "transfername01",
                transferRecipientSub: "docs"
            })
        );
    }

    function test_nostatus_end_to_end() public {
        _flow_end_to_end(
            FlowParams({
                nameOwner: tiago,
                name: NAME_NOSTATUS,
                reserved: false,
                selfSub: "app",
                otherSub: "blog",
                otherOwner: ed,
                transferTo: leonardo,
                transferRecipientNewName: "transfername01",
                transferRecipientSub: "docs"
            })
        );
    }

    function _flow_end_to_end(FlowParams memory flow) internal {
        _commitAndRegister(flow.name, flow.nameOwner, flow.reserved);

        bytes32 labelHash = keccak256(bytes(flow.name));
        bytes32 node = _namehash(dotNode, labelHash);
        uint256 tokenId = uint256(labelHash);

        assertEq(dotnsRegistrar.ownerOf(tokenId), flow.nameOwner);
        assertTrue(dotnsRegistry.recordExists(node));
        assertEq(dotnsRegistry.owner(node), flow.nameOwner);
        assertEq(dotnsRegistry.resolver(node), address(dotnsReverseResolver));

        if (flow.reserved) {
            assertEq(dotnsReverseResolver.nameOf(flow.nameOwner), string.concat(flow.name, ".dot"));
        } else {
            assertEq(dotnsReverseResolver.nameOf(flow.nameOwner), "");
        }

        // store has key + values[] contains the minted name
        Store ownerStore = Store(address(storeFactory.getDeployedStore(flow.nameOwner)));
        assertTrue(address(ownerStore) != address(0));

        string memory fullName = string.concat(flow.name, ".dot");
        bytes32 key = _storeKey(labelHash);

        assertEq(ownerStore.getValueFor(flow.nameOwner, key), fullName);
        assertTrue(ownerStore.isLocked(flow.nameOwner, key));
        _assertStoreContainsValue(flow.nameOwner, ownerStore, fullName);

        // owner can set content for root node
        vm.prank(flow.nameOwner);
        dotnsContentResolver.setContenthash(node, CID_A);
        assertEq(dotnsContentResolver.contenthash(node), CID_A);

        // owner creates a subname for self
        bytes32 selfSubnode =
            _setSubnode(flow.nameOwner, node, flow.selfSub, flow.name, flow.nameOwner);
        assertEq(dotnsRegistry.owner(selfSubnode), flow.nameOwner);
        _assertStoreContainsValue(flow.nameOwner, ownerStore, _fullSubname(flow.selfSub, flow.name));

        // owner creates a subname for someone else (record.owner)
        bytes32 otherSubnode =
            _setSubnode(flow.nameOwner, node, flow.otherSub, flow.name, flow.otherOwner);
        assertEq(dotnsRegistry.owner(otherSubnode), flow.otherOwner);

        Store otherStore = Store(address(storeFactory.getDeployedStore(flow.otherOwner)));
        assertTrue(address(otherStore) != address(0));
        _assertStoreContainsValue(
            flow.otherOwner, otherStore, _fullSubname(flow.otherSub, flow.name)
        );

        vm.prank(flow.otherOwner);
        dotnsContentResolver.setContenthash(otherSubnode, CID_B);
        assertEq(dotnsContentResolver.contenthash(otherSubnode), CID_B);

        vm.prank(flow.nameOwner);
        dotnsRegistrar.transferFrom(flow.nameOwner, flow.transferTo, tokenId);

        assertEq(dotnsRegistrar.ownerOf(tokenId), flow.transferTo);
        assertEq(dotnsRegistry.owner(node), flow.nameOwner);

        if (flow.reserved) {
            assertEq(dotnsReverseResolver.nameOf(flow.nameOwner), fullName);
        }

        _assertStoreContainsValue(flow.nameOwner, ownerStore, fullName);

        // new ERC721 owner can still do "regular processes" for names they actually own in registry:
        // register their own new name, set content, mint subnames, check store values updated.
        _commitAndRegister(flow.transferRecipientNewName, flow.transferTo, false);

        bytes32 tLabelHash = keccak256(bytes(flow.transferRecipientNewName));
        bytes32 tNode = _namehash(dotNode, tLabelHash);

        assertTrue(dotnsRegistry.recordExists(tNode));
        assertEq(dotnsRegistry.owner(tNode), flow.transferTo);

        Store transferStore = Store(address(storeFactory.getDeployedStore(flow.transferTo)));
        assertTrue(address(transferStore) != address(0));

        string memory tFull = string.concat(flow.transferRecipientNewName, ".dot");
        _assertStoreContainsValue(flow.transferTo, transferStore, tFull);

        vm.prank(flow.transferTo);
        dotnsContentResolver.setContenthash(tNode, CID_A);
        assertEq(dotnsContentResolver.contenthash(tNode), CID_A);

        _setSubnode(
            flow.transferTo,
            tNode,
            flow.transferRecipientSub,
            flow.transferRecipientNewName,
            flow.transferTo
        );

        _assertStoreContainsValue(
            flow.transferTo,
            transferStore,
            _fullSubname(flow.transferRecipientSub, flow.transferRecipientNewName)
        );
    }

    function _setSubnode(
        address parentOwner,
        bytes32 parentNode,
        string memory subLabel,
        string memory parentLabel,
        address subOwner
    )
        internal
        returns (bytes32 subnode)
    {
        IDotnsRegistry.SubnodeRecord memory record = IDotnsRegistry.SubnodeRecord({
            parentNode: parentNode, subLabel: subLabel, parentLabel: parentLabel, owner: subOwner
        });

        vm.prank(parentOwner);
        subnode = dotnsRegistry.setSubnodeOwner(record);

        bytes32 expected = keccak256(abi.encodePacked(parentNode, keccak256(bytes(subLabel))));
        assertEq(subnode, expected);

        assertTrue(dotnsRegistry.recordExists(subnode));
        assertEq(dotnsRegistry.resolver(subnode), address(dotnsReverseResolver));
    }

    /// @notice Asserts that `user`'s Store contains `expectedValue` in its values array.
    function _assertStoreContainsValue(
        address user,
        Store store,
        string memory expectedValue
    )
        internal
    {
        vm.prank(user);
        string[] memory values = store.getValues();
        require(_contains(values, expectedValue), "Store value missing");
    }

    function _fullSubname(
        string memory sub,
        string memory parent
    )
        internal
        pure
        returns (string memory)
    {
        return string.concat(string.concat(sub, string.concat(".", parent)), ".dot");
    }
}
