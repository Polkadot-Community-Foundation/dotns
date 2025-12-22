// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import {IDotnsRegistrar} from "../../../contracts/registrars/DotnsRegistrar.sol";

import {BaseDotns} from "../../base/BaseDotNS.t.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract DotnsRegistrarTests is BaseDotns {
    function test_owner_can_add_controller() public {
        address additionalController = makeAddr("additionalController");

        vm.startPrank(owner);

        vm.expectEmit(true, false, false, false, address(dotnsRegistrar));
        emit IDotnsRegistrar.ControllerAdded(additionalController);
        dotnsRegistrar.addController(additionalController);

        assertTrue(dotnsRegistrar.controllers(additionalController));

        vm.stopPrank();
    }

    function test_owner_can_remove_controller() public {
        address temporaryController = makeAddr("temporaryController");

        vm.startPrank(owner);
        dotnsRegistrar.addController(temporaryController);

        vm.expectEmit(true, false, false, false, address(dotnsRegistrar));
        emit IDotnsRegistrar.ControllerRemoved(temporaryController);
        dotnsRegistrar.removeController(temporaryController);

        vm.stopPrank();

        assertFalse(dotnsRegistrar.controllers(temporaryController));
    }

    function test_controller_can_register_and_mints_token_to_user() public {
        uint256 tokenId = uint256(keccak256(bytes("alice")));

        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(address(0), ed, tokenId);

        vm.expectEmit(true, true, false, true);
        emit IDotnsRegistrar.NameRegistered(tokenId, ed);

        vm.prank(address(dotnsRegistrarController));
        dotnsRegistrar.register(tokenId, ed);

        assertEq(dotnsRegistrar.ownerOf(tokenId), ed);
    }

    function test_register_increases_balance_of_owner() public {
        uint256 firstTokenId = uint256(keccak256(bytes("firstName")));

        assertEq(dotnsRegistrar.balanceOf(ed), 0);

        vm.prank(address(dotnsRegistrarController));
        dotnsRegistrar.register(firstTokenId, ed);

        assertEq(dotnsRegistrar.balanceOf(ed), 1);
    }

    function test_register_multiple_names_to_same_owner() public {
        uint256 firstTokenId = uint256(keccak256(bytes("nameOne")));
        uint256 secondTokenId = uint256(keccak256(bytes("nameTwo")));

        vm.startPrank(address(dotnsRegistrarController));
        dotnsRegistrar.register(firstTokenId, ed);
        dotnsRegistrar.register(secondTokenId, ed);
        vm.stopPrank();

        assertEq(dotnsRegistrar.balanceOf(ed), 2);
        assertEq(dotnsRegistrar.ownerOf(firstTokenId), ed);
        assertEq(dotnsRegistrar.ownerOf(secondTokenId), ed);
    }

    function test_register_names_to_different_owners() public {
        uint256 firstTokenId = uint256(keccak256(bytes("edName")));
        uint256 secondTokenId = uint256(keccak256(bytes("tiagoName")));

        vm.startPrank(address(dotnsRegistrarController));
        dotnsRegistrar.register(firstTokenId, ed);
        dotnsRegistrar.register(secondTokenId, tiago);
        vm.stopPrank();

        assertEq(dotnsRegistrar.balanceOf(ed), 1);
        assertEq(dotnsRegistrar.balanceOf(tiago), 1);
        assertEq(dotnsRegistrar.ownerOf(firstTokenId), ed);
        assertEq(dotnsRegistrar.ownerOf(secondTokenId), tiago);
    }

    function test_available_is_true_before_register_and_false_after_register() public {
        uint256 tokenId = uint256(keccak256(bytes("availabilityCheck")));

        bool availableBefore = dotnsRegistrar.available(tokenId);
        assertTrue(availableBefore);

        vm.prank(address(dotnsRegistrarController));
        dotnsRegistrar.register(tokenId, ed);

        bool availableAfter = dotnsRegistrar.available(tokenId);
        assertFalse(availableAfter);
    }

    function test_register_to_smart_contract_owner_address() public {
        // name ownership could be held by a smart wallet or on-chain account.
        address smartContractOwner = address(popOracle);
        uint256 tokenId = uint256(keccak256(bytes("contractOwnedName")));

        vm.prank(address(dotnsRegistrarController));
        dotnsRegistrar.register(tokenId, smartContractOwner);

        assertEq(dotnsRegistrar.ownerOf(tokenId), smartContractOwner);
        assertEq(dotnsRegistrar.balanceOf(smartContractOwner), 1);
    }

    function test_controller_can_be_removed_and_readded_then_registers_new_name() public {
        address controllerAddress = address(dotnsRegistrarController);
        uint256 tokenId = uint256(keccak256(bytes("readdedControllerName")));

        vm.startPrank(owner);
        dotnsRegistrar.removeController(controllerAddress);
        dotnsRegistrar.addController(controllerAddress);
        vm.stopPrank();

        vm.prank(controllerAddress);
        dotnsRegistrar.register(tokenId, ed);

        assertEq(dotnsRegistrar.ownerOf(tokenId), ed);
    }

    function test_erc721_approvals_work_for_read_access_and_integrations() public {
        // Even though transfers are blocked, approvals can still be used by indexers/wallet UIs.
        uint256 tokenId = uint256(keccak256(bytes("approvalName")));

        vm.prank(address(dotnsRegistrarController));
        dotnsRegistrar.register(tokenId, ed);

        vm.prank(ed);
        dotnsRegistrar.approve(tiago, tokenId);

        assertEq(dotnsRegistrar.getApproved(tokenId), tiago);

        vm.prank(ed);
        dotnsRegistrar.setApprovalForAll(leonardo, true);

        bool isApprovedForAll = dotnsRegistrar.isApprovedForAll(ed, leonardo);
        assertTrue(isApprovedForAll);

        // Sanity: supports IERC721 interface id for tooling compatibility.
        bool supportsErc721 = dotnsRegistrar.supportsInterface(type(IERC721).interfaceId);
        assertTrue(supportsErc721);
    }
}
