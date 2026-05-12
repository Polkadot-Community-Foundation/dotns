// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns, IDotnsRegistrarController} from "../../base/BaseDotns.t.sol";

import {IPopRules} from "../../../contracts/pop/IPopRules.sol";
import {ILabelStore} from "../../../contracts/store/ILabelStore.sol";
import {DotnsConstants} from "../../../contracts/utils/DotnsConstants.sol";
import {IDotnsRoleManager} from "../../../contracts/access/IDotnsRoleManager.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract DotnsRegistrarControllerTest is BaseDotns {
    function test_available_state_transitions() public {
        assertTrue(dotnsRegistrarController.available("longnamehere01"));

        _register("longnamehere01", ed, IPopRules.PopStatus.NoStatus);

        assertFalse(dotnsRegistrarController.available("longnamehere01"));
    }

    function test_available_reverts_for_dotted_label() public {
        vm.expectRevert(IDotnsRegistrarController.InvalidLabel.selector);
        dotnsRegistrarController.available("app.parity01");
    }

    function test_available_reverts_for_empty_label() public {
        vm.expectRevert(IDotnsRegistrarController.InvalidLabel.selector);
        dotnsRegistrarController.available("");
    }

    function test_commit_sets_timestamp() public {
        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: "alicebob", owner: ed, secret: keccak256("secret"), reserved: true
            });

        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);

        vm.startPrank(ed);
        dotnsRegistrarController.commit(commitment);
        vm.stopPrank();

        assertEq(dotnsRegistrarController.commitments(commitment), block.timestamp);
    }

    function test_commit_allows_recommit_after_expiry() public {
        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: "alicebob", owner: ed, secret: keccak256("secret"), reserved: true
            });

        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);

        vm.startPrank(ed);
        dotnsRegistrarController.commit(commitment);

        uint256 firstCommitTimestamp = dotnsRegistrarController.commitments(commitment);
        vm.warp(firstCommitTimestamp + dotnsRegistrarController.maxCommitmentAge() + 1);

        dotnsRegistrarController.commit(commitment);
        vm.stopPrank();

        assertEq(dotnsRegistrarController.commitments(commitment), block.timestamp);
    }

    function test_register_popfull_wires_all_records() public {
        string memory nameLabel = "web2summit";
        address nameOwner = ed;

        _grantPopFull(nameOwner);

        vm.prank(owner);
        storeFactory.deployLabelStoreFor(nameOwner);

        vm.startPrank(nameOwner);

        bytes32 secret = keccak256(abi.encodePacked(nameLabel, nameOwner, "store"));
        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: nameLabel, owner: nameOwner, secret: secret, reserved: true
            });

        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);
        dotnsRegistrarController.commit(commitment);

        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        dotnsRegistrarController.register{value: 0}(registration);
        vm.stopPrank();

        bytes32 labelHash = keccak256(bytes(nameLabel));
        bytes32 node = _namehash(dotNode, labelHash);

        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(node)), nameOwner);
        assertEq(dotnsRegistry.owner(node), nameOwner);
        assertEq(dotnsReverseResolver.nameOf(nameOwner), string.concat(nameLabel, ".dot"));

        ILabelStore ownerStore = ILabelStore(storeFactory.getLabelStore(nameOwner));
        assertEq(ownerStore.getLabel(node), string.concat(nameLabel, ".dot"));
        assertTrue(ownerStore.isLocked(node));
    }

    function test_register_poplite_reserves_base_name() public {
        string memory nameLabel = "lights01";
        address nameOwner = ed;

        _grantPopLite(nameOwner);
        vm.startPrank(nameOwner);

        bytes32 secret = keccak256(abi.encodePacked(nameLabel, nameOwner, "lite"));
        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: nameLabel, owner: nameOwner, secret: secret, reserved: true
            });

        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);
        dotnsRegistrarController.commit(commitment);

        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        dotnsRegistrarController.register{value: 0}(registration);
        vm.stopPrank();

        (bool isReserved, address reservationOwner,) = popRules.isBaseNameReserved("lights");
        assertTrue(isReserved);
        assertEq(reservationOwner, nameOwner);
    }

    function test_register_does_not_overwrite_third_party_reverse_record() public {
        string memory victimLabel = "victimname01";
        string memory giftedLabel = "hijackname01";

        _register(victimLabel, tiago, IPopRules.PopStatus.NoStatus);
        assertEq(dotnsReverseResolver.nameOf(tiago), "victimname01.dot");

        bytes32 secret = keccak256(abi.encodePacked(giftedLabel, tiago, ed, block.timestamp));
        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: giftedLabel, owner: tiago, secret: secret, reserved: true
            });

        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);

        vm.prank(ed);
        dotnsRegistrarController.commit(commitment);

        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        uint256 price = popRules.priceWithCheck(giftedLabel, tiago).price;

        vm.prank(ed);
        dotnsRegistrarController.register{value: price}(registration);

        assertEq(dotnsRegistrar.ownerOf(_tokenIdForLabel(giftedLabel)), tiago);
        assertEq(dotnsReverseResolver.nameOf(tiago), "victimname01.dot");
    }

    function test_registerreserved_writes_to_store() public {
        string memory nameLabel = "hello";
        address nameOwner = ed;

        vm.startPrank(owner);

        bytes32 secret = keccak256(abi.encodePacked(nameLabel, nameOwner, "reserved"));
        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: nameLabel, owner: nameOwner, secret: secret, reserved: true
            });

        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);
        dotnsRegistrarController.commit(commitment);

        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        dotnsRegistrarController.registerReserved(registration);
        vm.stopPrank();

        bytes32 labelHash = keccak256(bytes(nameLabel));
        bytes32 node = _namehash(dotNode, labelHash);

        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(node)), nameOwner);
        assertEq(dotnsRegistry.owner(node), nameOwner);

        ILabelStore edStore = ILabelStore(storeFactory.getLabelStore(nameOwner));
        assertEq(edStore.getLabel(node), string.concat(nameLabel, ".dot"));
    }

    function test_registerreserved_revertnon_owner() public {
        string memory nameLabel = "hello";
        address nameOwner = ed;

        vm.startPrank(owner);

        bytes32 secret = keccak256(abi.encodePacked(nameLabel, nameOwner, "reserved"));
        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: nameLabel, owner: nameOwner, secret: secret, reserved: true
            });

        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);
        dotnsRegistrarController.commit(commitment);

        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);
        vm.stopPrank();

        vm.prank(ed);
        vm.expectRevert(
            abi.encodeWithSelector(IDotnsRegistrarController.NotWhiteListedOrOwner.selector, ed)
        );
        dotnsRegistrarController.registerReserved(registration);
    }

    function test_whitelistaddress_reverts_without_owner_or_operator() public {
        vm.prank(ed);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsRoleManager.NotRoleOrOwner.selector,
                ed,
                DotnsConstants.WHITELIST_OPERATOR_ROLE
            )
        );
        dotnsRegistrarController.whiteListAddress(ed, true);
    }

    function test_owner_can_grant_and_revoke_whitelist_operator() public {
        vm.startPrank(owner);
        dotnsRegistrarController.grantRole(DotnsConstants.WHITELIST_OPERATOR_ROLE, leonardo);
        assertTrue(
            dotnsRegistrarController.hasRole(DotnsConstants.WHITELIST_OPERATOR_ROLE, leonardo)
        );

        dotnsRegistrarController.revokeRole(DotnsConstants.WHITELIST_OPERATOR_ROLE, leonardo);
        vm.stopPrank();

        assertFalse(
            dotnsRegistrarController.hasRole(DotnsConstants.WHITELIST_OPERATOR_ROLE, leonardo)
        );
    }

    function test_whitelist_operator_can_whitelist_address() public {
        _grantWhitelistOperator(leonardo);

        vm.prank(leonardo);
        dotnsRegistrarController.whiteListAddress(ed, true);

        assertTrue(dotnsRegistrarController.isWhiteListed(ed));
    }

    function test_setrole_reverts_for_zero_address() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IDotnsRoleManager.InvalidRoleAccount.selector, address(0))
        );
        dotnsRegistrarController.setRole(DotnsConstants.WHITELIST_OPERATOR_ROLE, address(0), true);
    }

    function test_setrole_reverts_for_unsupported_role() public {
        bytes32 unsupportedRole = keccak256("DOTNS_UNSUPPORTED_ROLE");

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IDotnsRoleManager.UnsupportedRole.selector, unsupportedRole)
        );
        dotnsRegistrarController.setRole(unsupportedRole, leonardo, true);
    }

    function test_non_owner_cannot_grant_role() public {
        vm.prank(ed);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, ed)
        );
        dotnsRegistrarController.grantRole(DotnsConstants.WHITELIST_OPERATOR_ROLE, leonardo);
    }

    function test_non_owner_cannot_revoke_role() public {
        _grantWhitelistOperator(leonardo);

        vm.prank(ed);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, ed)
        );
        dotnsRegistrarController.revokeRole(DotnsConstants.WHITELIST_OPERATOR_ROLE, leonardo);
    }

    function test_supports_idotnsrolemanager_interface() public view {
        assertTrue(dotnsRegistrarController.supportsInterface(type(IDotnsRoleManager).interfaceId));
    }

    function test_whitelisted_can_register_reserved() public {
        string memory nameLabel = "reserved01";
        address nameOwner = ed;

        vm.prank(owner);
        dotnsRegistrarController.whiteListAddress(ed, true);
        assertTrue(dotnsRegistrarController.isWhiteListed(ed));

        vm.startPrank(ed);

        bytes32 secret = keccak256(abi.encodePacked(nameLabel, nameOwner, "whitelisted"));
        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: nameLabel, owner: nameOwner, secret: secret, reserved: true
            });

        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);
        dotnsRegistrarController.commit(commitment);

        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        dotnsRegistrarController.registerReserved(registration);
        vm.stopPrank();

        bytes32 labelHash = keccak256(bytes(nameLabel));
        bytes32 node = _namehash(dotNode, labelHash);

        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(node)), nameOwner);
        assertEq(dotnsRegistry.owner(node), nameOwner);
    }

    function test_removed_from_whitelist_cannot_register_reserved() public {
        string memory nameLabel = "reserved02";
        address nameOwner = ed;

        vm.startPrank(owner);
        dotnsRegistrarController.whiteListAddress(ed, true);
        dotnsRegistrarController.whiteListAddress(ed, false);
        vm.stopPrank();

        assertFalse(dotnsRegistrarController.isWhiteListed(ed));

        vm.startPrank(ed);

        bytes32 secret = keccak256(abi.encodePacked(nameLabel, nameOwner, "removed"));
        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: nameLabel, owner: nameOwner, secret: secret, reserved: true
            });

        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);
        dotnsRegistrarController.commit(commitment);

        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IDotnsRegistrarController.NotWhiteListedOrOwner.selector, ed)
        );
        dotnsRegistrarController.registerReserved(registration);
        vm.stopPrank();
    }

    function test_register_reverts_for_dotted_label() public {
        string memory nameLabel = "app.parity01";
        address nameOwner = ed;

        vm.startPrank(nameOwner);

        bytes32 secret = keccak256(abi.encodePacked(nameLabel, nameOwner, "dotted"));
        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: nameLabel, owner: nameOwner, secret: secret, reserved: false
            });

        bytes32 commitment = dotnsRegistrarController.makeCommitment(registration);
        dotnsRegistrarController.commit(commitment);

        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);

        vm.expectRevert(IDotnsRegistrarController.InvalidLabel.selector);
        dotnsRegistrarController.register{value: 0}(registration);
        vm.stopPrank();
    }

    function test_transfer_writes_label_and_creates_store() public {
        string memory nameLabel = "alicetransfer01";

        _register(nameLabel, ed, IPopRules.PopStatus.PopFull);

        assertEq(storeFactory.getLabelStore(leonardo), address(0));

        uint256 tokenId = _tokenIdForLabel(nameLabel);

        uint256 fee = dotnsRegistrar.quoteTransferFee(tokenId, leonardo);
        vm.prank(ed);
        dotnsRegistrar.transferFrom{value: fee}(ed, leonardo, tokenId);

        assertEq(dotnsRegistrar.ownerOf(tokenId), leonardo);

        address leonardoStoreAddr = storeFactory.getLabelStore(leonardo);
        assertTrue(leonardoStoreAddr != address(0));

        ILabelStore leonardoStore = ILabelStore(leonardoStoreAddr);

        assertEq(leonardoStore.getLabel(bytes32(tokenId)), string.concat(nameLabel, ".dot"));
        assertTrue(leonardoStore.isLocked(bytes32(tokenId)));
    }

    function test_transfer_back_skips_locked_entry() public {
        string memory nameLabel = "carolreturn01";

        _register(nameLabel, ed, IPopRules.PopStatus.PopFull);

        uint256 tokenId = _tokenIdForLabel(nameLabel);

        uint256 outboundFee = dotnsRegistrar.quoteTransferFee(tokenId, leonardo);
        vm.prank(ed);
        dotnsRegistrar.transferFrom{value: outboundFee}(ed, leonardo, tokenId);

        uint256 returnFee = dotnsRegistrar.quoteTransferFee(tokenId, ed);
        vm.prank(leonardo);
        dotnsRegistrar.transferFrom{value: returnFee}(leonardo, ed, tokenId);

        ILabelStore edStore = ILabelStore(storeFactory.getLabelStore(ed));
        assertEq(edStore.getLabel(bytes32(tokenId)), string.concat(nameLabel, ".dot"));
        assertTrue(edStore.isLocked(bytes32(tokenId)));

        assertEq(dotnsRegistrar.ownerOf(tokenId), ed);
    }

    function test_transfer_clears_primary_reverse_name_when_current_name_is_moved() public {
        string memory nameLabel = "primarymove01";

        _register(nameLabel, ed, IPopRules.PopStatus.PopFull);

        uint256 tokenId = _tokenIdForLabel(nameLabel);
        assertEq(dotnsReverseResolver.nameOf(ed), "primarymove01.dot");

        uint256 _xferFee = dotnsRegistrar.quoteTransferFee(tokenId, leonardo);
        vm.prank(ed);
        dotnsRegistrar.transferFrom{value: _xferFee}(ed, leonardo, tokenId);

        assertEq(dotnsRegistrar.ownerOf(tokenId), leonardo);
        assertEq(dotnsReverseResolver.nameOf(ed), "");
    }

    function test_mint_does_not_trigger_store_write() public {
        string memory nameLabel = "daveminting01";

        assertEq(storeFactory.getLabelStore(address(0)), address(0));

        _register(nameLabel, tiago, IPopRules.PopStatus.PopFull);

        ILabelStore tiagoStore = ILabelStore(storeFactory.getLabelStore(tiago));
        uint256 tokenId = _tokenIdForLabel(nameLabel);
        assertEq(tiagoStore.getLabel(bytes32(tokenId)), string.concat(nameLabel, ".dot"));

        assertEq(storeFactory.getLabelStore(address(0)), address(0));
    }

    function test_safe_transfer_writes_to_store() public {
        string memory nameLabel = "safexfer01";

        _register(nameLabel, ed, IPopRules.PopStatus.PopFull);

        uint256 tokenId = _tokenIdForLabel(nameLabel);

        uint256 _xferFee = dotnsRegistrar.quoteTransferFee(tokenId, leonardo);
        vm.prank(ed);
        dotnsRegistrar.safeTransferFrom{value: _xferFee}(ed, leonardo, tokenId);

        assertEq(dotnsRegistrar.ownerOf(tokenId), leonardo);

        ILabelStore leonardoStore = ILabelStore(storeFactory.getLabelStore(leonardo));
        assertTrue(address(leonardoStore) != address(0));

        assertEq(leonardoStore.getLabel(bytes32(tokenId)), string.concat(nameLabel, ".dot"));
        assertTrue(leonardoStore.isLocked(bytes32(tokenId)));
    }

    function test_transfer_via_approved_operator_writes_to_store() public {
        string memory nameLabel = "opxfer01";

        _register(nameLabel, ed, IPopRules.PopStatus.PopFull);

        uint256 tokenId = _tokenIdForLabel(nameLabel);

        vm.prank(ed);
        dotnsRegistrar.setApprovalForAll(tiago, true);

        vm.prank(tiago);
        dotnsRegistrar.transferFrom(ed, leonardo, tokenId);

        assertEq(dotnsRegistrar.ownerOf(tokenId), leonardo);

        ILabelStore leonardoStore = ILabelStore(storeFactory.getLabelStore(leonardo));
        assertTrue(address(leonardoStore) != address(0));

        assertEq(leonardoStore.getLabel(bytes32(tokenId)), string.concat(nameLabel, ".dot"));
        assertTrue(leonardoStore.isLocked(bytes32(tokenId)));
    }

    function test_transfer_deploys_store_without_label() public {
        string memory nameLabel = "nolabel01";
        bytes32 labelhash = keccak256(bytes(nameLabel));
        bytes32 node = _namehash(dotNode, labelhash);
        uint256 tokenId = uint256(node);

        vm.prank(address(dotnsRegistrarController));
        dotnsRegistrar.register(tokenId, ed, "");

        assertEq(storeFactory.getLabelStore(leonardo), address(0));

        uint256 _xferFee = dotnsRegistrar.quoteTransferFee(tokenId, leonardo);
        vm.prank(ed);
        dotnsRegistrar.transferFrom{value: _xferFee}(ed, leonardo, tokenId);

        assertEq(dotnsRegistrar.ownerOf(tokenId), leonardo);
        assertTrue(storeFactory.getLabelStore(leonardo) != address(0));

        ILabelStore leonardoStore = ILabelStore(storeFactory.getLabelStore(leonardo));
        assertEq(leonardoStore.getLabel(bytes32(tokenId)), "");
    }
}
