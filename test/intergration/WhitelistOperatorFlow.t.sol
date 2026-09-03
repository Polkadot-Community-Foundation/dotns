// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {BaseDotns, IDotnsRegistrarController} from "../base/BaseDotns.t.sol";
import {DotnsConstants} from "../../contracts/utils/DotnsConstants.sol";
import {IDotnsNameWhitelist} from "../../contracts/whitelist/IDotnsNameWhitelist.sol";
import {IDotnsRoleManager} from "../../contracts/access/IDotnsRoleManager.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title WhitelistOperatorFlow
/// @notice End-to-end integration coverage for the whitelist operator role.
/// @dev Asserts the full chain from `setRole` through a name grant on
///      `DotnsNameWhitelist` into a reserved registration on the public
///      controller. Lives in the integration suite because it spans the role
///      manager, the whitelist, and the reserved registration flow rather than
///      any single unit of behaviour.
/// @custom:security-contact admin@parity.io
contract WhitelistOperatorFlow is BaseDotns {
    function test_operator_can_grant_a_name_for_reserved_registration() public {
        address operator = leonardo;
        address user = ed;
        string memory nameLabel = "operatorseed01";

        _grantWhitelistOperator(operator);

        vm.prank(operator);
        dotnsNameWhitelist.grantName(nameLabel, user);
        assertTrue(dotnsNameWhitelist.isGrantedTo(nameLabel, user));

        _registerReserved(nameLabel, user, user);

        bytes32 node = _nodeOf(nameLabel);
        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(node)), user);
        assertEq(dotnsRegistry.owner(node), user);
        // The grant is spent by the mint, so it cannot seed a second registration.
        assertFalse(dotnsNameWhitelist.isGrantedTo(nameLabel, user));
    }

    /// @dev The submitter is not necessarily the beneficiary, and `setReverseName` overwrites
    ///      unconditionally, so the reserved path must not touch the owner's reverse record.
    function test_reserved_registration_leaves_the_reverse_record_untouched() public {
        address user = ed;
        string memory nameLabel = "reverseuntouched01";

        _grantName(nameLabel, user);
        assertEq(dotnsReverseResolver.nameOf(user), "");

        _registerReserved(nameLabel, user, user);

        assertEq(dotnsReverseResolver.nameOf(user), "", "reserved mint must not write reverse");

        // The owner claims it themselves, which is ownership-checked.
        vm.prank(user);
        dotnsReverseResolver.claimReverseRecord(nameLabel);
        assertEq(dotnsReverseResolver.nameOf(user), string.concat(nameLabel, ".dot"));
    }

    /// @dev The gate reads `registration.owner`, so a relayer may submit for the beneficiary.
    function test_a_relayer_can_submit_for_the_granted_beneficiary() public {
        address beneficiary = ed;
        address relayer = tiago;
        string memory nameLabel = "relayed01";

        _grantName(nameLabel, beneficiary);
        _registerReserved(nameLabel, beneficiary, relayer);

        bytes32 node = _nodeOf(nameLabel);
        assertEq(IERC721(address(dotnsRegistrar)).ownerOf(uint256(node)), beneficiary);
    }

    function test_operator_role_revocation_blocks_further_grants() public {
        address operator = leonardo;

        _grantWhitelistOperator(operator);

        vm.prank(operator);
        dotnsNameWhitelist.grantName("granted01", ed);
        assertTrue(dotnsNameWhitelist.isGrantedTo("granted01", ed));

        _revokeWhitelistOperator(operator);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsRoleManager.NotRoleOrOwner.selector,
                operator,
                DotnsConstants.WHITELIST_OPERATOR_ROLE
            )
        );
        dotnsNameWhitelist.grantName("blocked01", tiago);

        assertTrue(dotnsNameWhitelist.isGrantedTo("granted01", ed));
    }

    /// @notice Commit-reveal a reserved registration for `nameOwner`, submitted by `submitter`.
    function _registerReserved(
        string memory nameLabel,
        address nameOwner,
        address submitter
    )
        private
    {
        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: nameLabel,
                owner: nameOwner,
                secret: keccak256(abi.encodePacked(nameLabel, nameOwner, submitter)),
                reserved: true,
                maxPrice: type(uint256).max,
                pricingVersion: popRules.pricingVersion()
            });

        vm.startPrank(submitter);
        dotnsRegistrarController.commit(dotnsRegistrarController.makeCommitment(registration));
        vm.warp(block.timestamp + dotnsRegistrarController.minCommitmentAge() + 1);
        dotnsRegistrarController.registerReserved(registration);
        vm.stopPrank();
    }
}
