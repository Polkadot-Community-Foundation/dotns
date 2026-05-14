// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {BaseDotns} from "../../base/BaseDotns.t.sol";
import {IDotnsController} from "../../../contracts/registrars/IDotnsController.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title DotnsRegistrarTests
/// @notice Unit coverage for the ERC721 registrar's controller authorisation,
///         availability tracking, registration, and approval surfaces.
contract DotnsRegistrarTests is BaseDotns {
    function test_add_controller() public {
        address additionalController = makeAddr("additionalController");

        vm.startPrank(owner);
        dotnsRegistrar.addController(IDotnsController(additionalController));
        vm.stopPrank();

        assertTrue(dotnsRegistrar.controllers(IDotnsController(additionalController)));
    }

    function test_remove_controller() public {
        address temporaryController = makeAddr("temporaryController");

        vm.startPrank(owner);
        dotnsRegistrar.addController(IDotnsController(temporaryController));
        dotnsRegistrar.removeController(IDotnsController(temporaryController));
        vm.stopPrank();

        assertFalse(dotnsRegistrar.controllers(IDotnsController(temporaryController)));
    }

    function test_register_mints_to_owner() public {
        address nameOwner = ed;
        string memory label = "alice";
        uint256 tokenId = _tokenIdForLabel(label);

        vm.startPrank(address(dotnsRegistrarController));
        dotnsRegistrar.register(tokenId, nameOwner, label);
        vm.stopPrank();

        assertEq(dotnsRegistrar.ownerOf(tokenId), nameOwner);
        assertEq(dotnsRegistrar.balanceOf(nameOwner), 1);
    }

    function test_available_before_after_register() public {
        address nameOwner = ed;
        string memory label = "availabilityCheck";
        uint256 tokenId = _tokenIdForLabel(label);

        assertTrue(dotnsRegistrar.available(tokenId));

        vm.startPrank(address(dotnsRegistrarController));
        dotnsRegistrar.register(tokenId, nameOwner, label);
        vm.stopPrank();

        assertFalse(dotnsRegistrar.available(tokenId));
    }

    function test_approvals_work() public {
        address nameOwner = ed;
        address tokenApproval = tiago;
        address operator = leonardo;

        string memory label = "approvalName";
        uint256 tokenId = _tokenIdForLabel(label);

        vm.startPrank(address(dotnsRegistrarController));
        dotnsRegistrar.register(tokenId, nameOwner, label);
        vm.stopPrank();

        vm.startPrank(nameOwner);
        dotnsRegistrar.approve(tokenApproval, tokenId);
        assertEq(dotnsRegistrar.getApproved(tokenId), tokenApproval);

        dotnsRegistrar.setApprovalForAll(operator, true);
        vm.stopPrank();

        assertTrue(dotnsRegistrar.isApprovedForAll(nameOwner, operator));
        assertTrue(dotnsRegistrar.supportsInterface(type(IERC721).interfaceId));
    }
}
