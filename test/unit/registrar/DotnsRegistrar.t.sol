// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDotnsRegistrar} from "../../../contracts/registrars/IDotnsRegistrar.sol";
import {BaseDotns, IDotnsRegistrarController} from "../../base/BaseDotns.t.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract DotnsRegistrarTests is BaseDotns {
    function test_addController() public {
        address additionalController = makeAddr("additionalController");

        vm.startPrank(owner);

        vm.expectEmit(true, false, false, false, address(dotnsRegistrar));
        emit IDotnsRegistrar.ControllerAdded(IDotnsRegistrarController(additionalController));
        dotnsRegistrar.addController(IDotnsRegistrarController(additionalController));

        vm.stopPrank();

        assertTrue(dotnsRegistrar.controllers(IDotnsRegistrarController(additionalController)));
    }

    function test_removeController() public {
        address temporaryController = makeAddr("temporaryController");

        vm.startPrank(owner);
        dotnsRegistrar.addController(IDotnsRegistrarController(temporaryController));

        vm.expectEmit(true, false, false, false, address(dotnsRegistrar));
        emit IDotnsRegistrar.ControllerRemoved(IDotnsRegistrarController(temporaryController));
        dotnsRegistrar.removeController(IDotnsRegistrarController(temporaryController));
        vm.stopPrank();

        assertFalse(dotnsRegistrar.controllers(IDotnsRegistrarController(temporaryController)));
    }

    function test_registerMintsToOwner() public {
        uint256 tokenId = uint256(keccak256(bytes("alice")));

        vm.expectEmit(true, true, true, true, address(dotnsRegistrar));
        emit IERC721.Transfer(address(0), ed, tokenId);

        vm.expectEmit(true, true, false, true, address(dotnsRegistrar));
        emit IDotnsRegistrar.NameRegistered(tokenId, ed);

        vm.prank(address(dotnsRegistrarController));
        dotnsRegistrar.register(tokenId, ed);

        assertEq(dotnsRegistrar.ownerOf(tokenId), ed);
        assertEq(dotnsRegistrar.balanceOf(ed), 1);
    }

    function test_registerMultipleSameOwner() public {
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

    function test_registerMultipleOwners() public {
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

    function test_availableBeforeAfterRegister() public {
        uint256 tokenId = uint256(keccak256(bytes("availabilityCheck")));

        assertTrue(dotnsRegistrar.available(tokenId));

        vm.prank(address(dotnsRegistrarController));
        dotnsRegistrar.register(tokenId, ed);

        assertFalse(dotnsRegistrar.available(tokenId));
    }

    function test_registerToContractOwner() public {
        address smartContractOwner = address(popOracle);
        uint256 tokenId = uint256(keccak256(bytes("contractOwnedName")));

        vm.prank(address(dotnsRegistrarController));
        dotnsRegistrar.register(tokenId, smartContractOwner);

        assertEq(dotnsRegistrar.ownerOf(tokenId), smartContractOwner);
        assertEq(dotnsRegistrar.balanceOf(smartContractOwner), 1);
    }

    function test_approvalsWork() public {
        uint256 tokenId = uint256(keccak256(bytes("approvalName")));

        vm.prank(address(dotnsRegistrarController));
        dotnsRegistrar.register(tokenId, ed);

        vm.prank(ed);
        dotnsRegistrar.approve(tiago, tokenId);
        assertEq(dotnsRegistrar.getApproved(tokenId), tiago);

        vm.prank(ed);
        dotnsRegistrar.setApprovalForAll(leonardo, true);
        assertTrue(dotnsRegistrar.isApprovedForAll(ed, leonardo));

        assertTrue(dotnsRegistrar.supportsInterface(type(IERC721).interfaceId));
    }
}
