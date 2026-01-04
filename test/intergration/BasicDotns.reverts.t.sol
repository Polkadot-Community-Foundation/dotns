// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../base/BaseDotns.t.sol";
import {IPopOracle} from "../../contracts/pop/IPopOracle.sol";
import {IDotnsRegistry} from "../../contracts/registry/IDotnsRegistry.sol";
import {Store} from "../../contracts/store/Store.sol";
import {IDotnsContentResolver} from "../../contracts/resolvers/IDotnsContentResolver.sol";
import {IDotnsRegistrarController} from "../../contracts/registrars/IDotnsRegistrarController.sol";

contract BasicDotnsIntegrationReverts is BaseDotns {
    ///@dev PopFull required
    string internal constant NAME_POPFULL = "waytall1";
    ///@dev PopLite eligible (reserves base "way2tall")
    string internal constant NAME_POPLITE = "way2tall01";
    ///@dev NoStatus (2 digits) allowed for non-PopLite
    string internal constant NAME_NOSTATUS = "kitesurfing01";

    bytes internal constant CID_A =
        hex"e30101701220aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

    function test_revert_poplite_cannot_register_nostatus_name() public {
        string memory label = NAME_NOSTATUS;

        vm.prank(ed);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopLite);

        bytes32 secret = keccak256(abi.encodePacked(label, ed, block.timestamp));
        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label, owner: ed, secret: secret, reserved: false
            });

        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);

        vm.prank(ed);
        dotnsRegistrarController.commit(commitment);

        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        vm.prank(ed);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPopOracle.PopError.selector, "Personhood Lite cannot register base names"
            )
        );
        dotnsRegistrarController.register(registration);
    }

    function test_revert_poplite_cannot_register_popfull_required() public {
        string memory label = NAME_POPFULL;

        vm.prank(ed);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopLite);

        bytes32 secret = keccak256(abi.encodePacked(label, ed, block.timestamp));
        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label, owner: ed, secret: secret, reserved: true
            });

        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);

        vm.prank(ed);
        dotnsRegistrarController.commit(commitment);

        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        vm.prank(ed);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPopOracle.PopError.selector, "Requires Full Personhood verification"
            )
        );
        dotnsRegistrarController.register(registration);
    }

    function test_revert_non_owner_cannot_create_subdomain_under_someone_elses_name() public {
        vm.prank(ed);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopFull);
        _commitAndRegister(NAME_POPFULL, ed, true);

        bytes32 parentNode = _namehash(dotNode, keccak256(bytes(NAME_POPFULL)));

        IDotnsRegistry.SubnodeRecord memory record = IDotnsRegistry.SubnodeRecord({
            parentNode: parentNode, subLabel: "blog", parentLabel: NAME_POPFULL, owner: tiago
        });

        vm.prank(tiago);
        vm.expectRevert(IDotnsRegistry.NotAuthorised.selector);
        dotnsRegistry.setSubnodeOwner(record);
    }

    function test_revert_cannot_create_same_subdomain_twice() public {
        vm.prank(ed);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopFull);
        _commitAndRegister(NAME_POPFULL, ed, true);

        bytes32 parentNode = _namehash(dotNode, keccak256(bytes(NAME_POPFULL)));

        IDotnsRegistry.SubnodeRecord memory record = IDotnsRegistry.SubnodeRecord({
            parentNode: parentNode, subLabel: "blog", parentLabel: NAME_POPFULL, owner: ed
        });

        vm.prank(ed);
        bytes32 subnode = dotnsRegistry.setSubnodeOwner(record);

        vm.prank(ed);
        vm.expectRevert(abi.encodeWithSelector(IDotnsRegistry.NodeAlreadyExists.selector, subnode));
        dotnsRegistry.setSubnodeOwner(record);
    }

    function test_revert_unapproved_cannot_set_contenthash() public {
        vm.prank(ed);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopFull);
        _commitAndRegister(NAME_POPFULL, ed, true);

        bytes32 node = _namehash(dotNode, keccak256(bytes(NAME_POPFULL)));

        vm.prank(tiago);
        vm.expectRevert(
            abi.encodeWithSelector(IDotnsContentResolver.NotAuthorised.selector, node, tiago)
        );
        dotnsContentResolver.setContenthash(node, CID_A);
    }
}
