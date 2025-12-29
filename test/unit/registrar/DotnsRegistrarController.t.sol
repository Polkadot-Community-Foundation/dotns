// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import {BaseDotns, IDotnsRegistrarController} from "../../base/BaseDotns.t.sol";

import {IPopOracle} from "../../../contracts/pop/IPopOracle.sol";
import {IStore} from "../../../contracts/store/IStore.sol";
import {Store} from "../../../contracts/store/Store.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract DotnsRegistrarControllerTest is BaseDotns {
    bytes32 private constant DOTNS_REGISTERED_PREFIX =
        hex"646f746e732e72656769737465726564000000000000000000000000000000";

    function test_available_returns_true_for_unregistered_label() public view {
        assertTrue(dotnsRegistrarController.available("alicebob"));
    }

    function test_available_returns_false_after_registration() public {
        _register("longnamehere01", ed, IPopOracle.PopStatus.NoStatus);
        assertFalse(dotnsRegistrarController.available("longnamehere01"));
    }

    function test_makecommitment_matches_controller_encoding() public view {
        IDotnsRegistrarController.Registration memory r = IDotnsRegistrarController.Registration({
            label: "alicebob", owner: ed, secret: keccak256("secret")
        });

        bytes32 got = dotnsRegistrarController.makeCommitment(r);

        // Controller uses: keccak256(bytes(label) || bytes32(owner) || bytes32(secret))
        bytes32 expected = keccak256(
            abi.encodePacked(bytes(r.label), bytes32(uint256(uint160(r.owner))), r.secret)
        );

        assertEq(got, expected);
    }

    function test_commit_sets_timestamp_and_emits() public {
        IDotnsRegistrarController.Registration memory r = IDotnsRegistrarController.Registration({
            label: "alicebob", owner: ed, secret: keccak256("secret")
        });

        bytes32 commitment = dotnsRegistrarController.makeCommitment(r);

        vm.expectEmit(true, false, false, false);
        emit IDotnsRegistrarController.NameCommitted(commitment);

        vm.prank(ed);
        dotnsRegistrarController.commit(commitment);

        assertEq(dotnsRegistrarController.commitments(commitment), block.timestamp);
    }

    function test_commit_allows_recommit_after_expiry() public {
        IDotnsRegistrarController.Registration memory r = IDotnsRegistrarController.Registration({
            label: "alicebob", owner: ed, secret: keccak256("secret")
        });

        bytes32 commitment = dotnsRegistrarController.makeCommitment(r);

        vm.prank(ed);
        dotnsRegistrarController.commit(commitment);

        uint256 first = dotnsRegistrarController.commitments(commitment);
        vm.warp(first + dotnsRegistrarController.maxCommitmentAge() + 1);

        vm.prank(ed);
        dotnsRegistrarController.commit(commitment);

        assertEq(dotnsRegistrarController.commitments(commitment), block.timestamp);
    }

    function test_register_registers_popfull_name_and_wires_records() public {
        string memory label = "alicebob";

        vm.prank(ed);
        popOracle.setNamePopStatus(label, IPopOracle.PopStatus.PopFull);

        vm.prank(ed);
        IStore s = storeFactory.deploy();

        vm.prank(ed);
        Store(address(s)).authorizeDotnsController(address(dotnsRegistrarController));

        bytes32 secret = keccak256(abi.encodePacked(label, ed, "s"));
        IDotnsRegistrarController.Registration memory r =
            IDotnsRegistrarController.Registration({label: label, owner: ed, secret: secret});

        bytes32 commitment = dotnsRegistrarController.makeCommitment(r);

        vm.prank(ed);
        dotnsRegistrarController.commit(commitment);

        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        IPopOracle.PriceWithMeta memory priced = popOracle.priceWithCheck(label, ed);

        bytes32 labelhash = keccak256(bytes(label));
        bytes32 node = _namehash(dotNode, labelhash);

        vm.expectEmit(true, true, true, true);
        emit IDotnsRegistrarController.NameRegistered(
            label, labelhash, ed, priced.price, address(s)
        );

        vm.prank(ed);
        dotnsRegistrarController.register{value: priced.price}(r);

        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(labelhash)), ed);
        assertEq(dotnsRegistry.owner(node), ed);
        assertEq(dotnsReverseResolver.nameOf(ed), string.concat(label, ".dot"));

        bytes32 storeKey = keccak256(abi.encodePacked(DOTNS_REGISTERED_PREFIX, labelhash));
        assertEq(Store(address(s)).getValueFor(ed, storeKey), string.concat(label, ".dot"));
        assertTrue(Store(address(s)).isLocked(ed, storeKey));
    }

    function test_register_refunds_excess_value() public {
        vm.txGasPrice(0);

        string memory label = "alicebob";

        vm.prank(ed);
        popOracle.setNamePopStatus(label, IPopOracle.PopStatus.PopFull);

        bytes32 secret = keccak256(abi.encodePacked(label, ed, "refund"));
        IDotnsRegistrarController.Registration memory r =
            IDotnsRegistrarController.Registration({label: label, owner: ed, secret: secret});

        bytes32 commitment = dotnsRegistrarController.makeCommitment(r);

        vm.prank(ed);
        dotnsRegistrarController.commit(commitment);

        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        uint256 price = popOracle.priceWithCheck(label, ed).price;

        uint256 beforeBal = ed.balance;

        vm.prank(ed);
        dotnsRegistrarController.register{value: price + 1}(r);

        assertEq(ed.balance, beforeBal - price);
    }

    function test_register_reserves_base_name_for_poplite_user() public {
        string memory label = "lights01";

        vm.prank(ed);
        popOracle.setNamePopStatus(label, IPopOracle.PopStatus.PopLite);

        bytes32 secret = keccak256(abi.encodePacked(label, ed, "lite"));
        IDotnsRegistrarController.Registration memory r =
            IDotnsRegistrarController.Registration({label: label, owner: ed, secret: secret});

        bytes32 commitment = dotnsRegistrarController.makeCommitment(r);

        vm.prank(ed);
        dotnsRegistrarController.commit(commitment);

        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        uint256 price = popOracle.priceWithCheck(label, ed).price;

        vm.prank(ed);
        dotnsRegistrarController.register{value: price}(r);

        (bool isReserved, address reservationOwner,) = popOracle.isBaseNameReserved("lights");
        assertTrue(isReserved);
        assertEq(reservationOwner, ed);
    }

    function test_registerreserved_registers_and_writes_to_existing_store() public {
        string memory label = "hello";

        vm.prank(ed);
        IStore s = storeFactory.deploy();

        vm.prank(ed);
        Store(address(s)).authorizeDotnsController(address(dotnsRegistrarController));

        bytes32 secret = keccak256(abi.encodePacked(label, ed, "reserved"));
        IDotnsRegistrarController.Registration memory r =
            IDotnsRegistrarController.Registration({label: label, owner: ed, secret: secret});

        bytes32 commitment = dotnsRegistrarController.makeCommitment(r);

        vm.prank(ed);
        dotnsRegistrarController.commit(commitment);

        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        bytes32 labelhash = keccak256(bytes(label));
        bytes32 node = _namehash(dotNode, labelhash);

        vm.expectEmit(true, true, true, true);
        emit IDotnsRegistrarController.NameRegistered(label, labelhash, ed, 0, address(s));

        vm.prank(ed);
        dotnsRegistrarController.registerReserved(r);

        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(labelhash)), ed);
        assertEq(dotnsRegistry.owner(node), ed);
        assertEq(dotnsReverseResolver.nameOf(ed), string.concat(label, ".dot"));

        bytes32 storeKey = keccak256(abi.encodePacked(DOTNS_REGISTERED_PREFIX, labelhash));
        assertEq(Store(address(s)).getValueFor(ed, storeKey), string.concat(label, ".dot"));
    }
}
