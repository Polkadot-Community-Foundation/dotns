// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {BaseDotns} from "../../base/BaseDotns.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IDotnsController} from "../../../contracts/registrars/IDotnsController.sol";
import {IDotnsRegistrar} from "../../../contracts/registrars/IDotnsRegistrar.sol";
import {DotnsConstants} from "../../../contracts/utils/DotnsConstants.sol";
import {LabelUtils} from "../../../contracts/utils/LabelUtils.sol";
import {DotnsMigrationController} from "../../../scripts/migration/DotnsMigrationController.sol";

contract DotnsMigrationControllerTest is BaseDotns {
    DotnsMigrationController internal migration;
    address internal migrator;
    address internal holderA;
    address internal holderB;

    /// Token id of browse.dot on the live devnet deployment (snapshot 2026-09-08). Both
    /// deployments derive ids the same way under the same TLD, so it must reproduce here.
    uint256 internal constant LIVE_BROWSE_ID =
        0xc86647248f49fb56449d4e461aa1b783888d868d74103bb8fa0ca17942d0c463;

    function setUp() public override {
        super.setUp();
        migrator = _createUser("migrator");
        holderA = _createUser("holderA");
        holderB = _createUser("holderB");
        migration = new DotnsMigrationController(protocolRegistry, migrator);
        vm.prank(owner);
        dotnsRegistrar.addController(IDotnsController(address(migration)));
    }

    function _node(string memory label) internal view returns (bytes32) {
        return
            LabelUtils.namehashUnder(protocolRegistry.tldNode(), LabelUtils.labelhashMemory(label));
    }

    function _entry(
        string memory label,
        address holder
    )
        internal
        view
        returns (DotnsMigrationController.Entry memory)
    {
        return
            DotnsMigrationController.Entry({
                id: uint256(_node(label)), holder: holder, label: label
            });
    }

    function test_idDerivationMatchesLiveDeployment() public view {
        assertEq(uint256(_node("browse")), LIVE_BROWSE_ID);
    }

    function test_migrateMintsToHoldersAndBindsNodes() public {
        DotnsMigrationController.Entry[] memory entries = new DotnsMigrationController.Entry[](3);
        entries[0] = _entry("browse", holderA);
        entries[1] = _entry("rock-paper-scissors", holderA);
        entries[2] = _entry("collectibles-webview", holderB);

        vm.prank(migrator);
        migration.migrate(entries);

        for (uint256 i = 0; i < entries.length; ++i) {
            bytes32 node = bytes32(entries[i].id);
            assertEq(dotnsRegistrar.ownerOf(entries[i].id), entries[i].holder, "token holder");
            assertEq(dotnsRegistrar.labelOf(entries[i].id), entries[i].label, "label");
            assertFalse(dotnsRegistrar.isSoulbound(entries[i].id), "public names are not soulbound");
            assertEq(dotnsRegistry.owner(node), entries[i].holder, "registry node owner");
            assertEq(
                dotnsRegistry.resolver(node),
                address(dotnsReverseResolver),
                "resolver reset to default"
            );
            assertFalse(dotnsRegistrar.available(entries[i].id), "no longer available");
        }
    }

    function test_holderCanReplayRecordsAfterMigration() public {
        DotnsMigrationController.Entry[] memory entries = new DotnsMigrationController.Entry[](1);
        entries[0] = _entry("browse", holderA);
        vm.prank(migrator);
        migration.migrate(entries);

        bytes32 node = bytes32(entries[0].id);
        bytes memory hash = hex"e30101701220996949";
        vm.startPrank(holderA);
        dotnsRegistry.setResolver(node, address(dotnsContentResolver));
        dotnsContentResolver.setContenthash(node, hash);
        dotnsContentResolver.setText(node, "manifest", "bafy");
        vm.stopPrank();

        assertEq(dotnsRegistry.resolver(node), address(dotnsContentResolver));
        assertEq(dotnsContentResolver.contenthash(node), hash);
        assertEq(dotnsContentResolver.text(node, "manifest"), "bafy");
    }

    function test_migrateIsAllOrNothingAndResumable() public {
        DotnsMigrationController.Entry[] memory first = new DotnsMigrationController.Entry[](1);
        first[0] = _entry("browse", holderA);
        vm.prank(migrator);
        migration.migrate(first);

        // Replaying an entry that already landed reverts the whole batch.
        DotnsMigrationController.Entry[] memory again = new DotnsMigrationController.Entry[](2);
        again[0] = _entry("browse", holderA);
        again[1] = _entry("survey", holderB);
        vm.prank(migrator);
        vm.expectRevert(
            abi.encodeWithSelector(IDotnsRegistrar.NameNotAvailable.selector, first[0].id)
        );
        migration.migrate(again);
        assertTrue(dotnsRegistrar.available(uint256(_node("survey"))), "survey untouched");

        // Dropping the landed entry resumes.
        DotnsMigrationController.Entry[] memory rest = new DotnsMigrationController.Entry[](1);
        rest[0] = _entry("survey", holderB);
        vm.prank(migrator);
        migration.migrate(rest);
        assertEq(dotnsRegistrar.ownerOf(rest[0].id), holderB);
    }

    function test_rejectsIdMismatchAndZeroHolder() public {
        DotnsMigrationController.Entry[] memory bad = new DotnsMigrationController.Entry[](1);
        bad[0] = _entry("browse", holderA);
        bad[0].id = bad[0].id + 1;
        vm.prank(migrator);
        vm.expectRevert(
            abi.encodeWithSelector(
                DotnsMigrationController.IdMismatch.selector, bad[0].id, "browse"
            )
        );
        migration.migrate(bad);

        DotnsMigrationController.Entry[] memory zero = new DotnsMigrationController.Entry[](1);
        zero[0] = _entry("browse", address(0));
        vm.prank(migrator);
        vm.expectRevert(
            abi.encodeWithSelector(DotnsMigrationController.ZeroHolder.selector, zero[0].id)
        );
        migration.migrate(zero);
    }

    function test_onlyMigrationOwnerAndOnlyWhileController() public {
        DotnsMigrationController.Entry[] memory entries = new DotnsMigrationController.Entry[](1);
        entries[0] = _entry("browse", holderA);

        vm.prank(holderA);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, holderA)
        );
        migration.migrate(entries);

        vm.prank(owner);
        dotnsRegistrar.removeController(IDotnsController(address(migration)));
        vm.prank(migrator);
        vm.expectRevert();
        migration.migrate(entries);
    }

    function test_supportsControllerInterface() public view {
        assertTrue(migration.supportsInterface(type(IDotnsController).interfaceId));
        assertTrue(dotnsRegistrar.controllers(IDotnsController(address(migration))));
    }
}
