// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {BaseDotns} from "../../base/BaseDotns.t.sol";
import {
    IDotnsRegistrarController
} from "../../../contracts/registrars/IDotnsRegistrarController.sol";
import {IDotnsRegistry} from "../../../contracts/registry/IDotnsRegistry.sol";
import {IDotnsReverseResolver} from "../../../contracts/resolvers/IDotnsReverseResolver.sol";
import {IPopRules} from "../../../contracts/pop/IPopRules.sol";
import {IStoreFactory} from "../../../contracts/store/IStoreFactory.sol";
import {Store} from "../../../contracts/store/Store.sol";
import {DotnsRegistrar} from "../../../contracts/registrars/DotnsRegistrar.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {RegistrarControllerHandler} from "./RegistrarControllerHandler.t.sol";

/// @title DotNS Registrar Controller Invariant Tests
/// @notice Invariant test suite validating correctness of the DotnsRegistrarController.
/// @dev Tests user flows for PopFull, PopLite, and NoStatus users.
///      Ensures protocol invariants hold across randomized action sequences.
contract DotnsRegistrarControllerInvariantTest is BaseDotns {
    /// @notice Handler contract that performs controlled actions on the controller.
    RegistrarControllerHandler public handler;

    /// @notice Sets up the invariant test environment.
    /// @dev Deploys the handler and configures it as the sole target for invariant testing.
    function setUp() public override {
        super.setUp();

        handler = new RegistrarControllerHandler(
            dotnsRegistrarController,
            dotnsRegistry,
            dotnsRegistrar,
            dotnsReverseResolver,
            popRules,
            storeFactory
        );

        // Fund handler for paid registrations
        vm.deal(address(handler), 1000 ether);

        // Configure test actors with different PoP statuses
        handler.addActor(ed, IPopRules.PopStatus.PopFull);
        handler.addActor(leonardo, IPopRules.PopStatus.PopLite);
        handler.addActor(tiago, IPopRules.PopStatus.NoStatus);

        // Target only the handler for invariant calls
        targetContract(address(handler));

        // Exclude system contracts from fuzzing
        excludeContract(address(dotnsRegistrarController));
        excludeContract(address(dotnsRegistry));
        excludeContract(address(dotnsRegistrar));
        excludeContract(address(popRules));
        excludeContract(address(storeFactory));
    }

    /// @notice Invariant: Every registered name has a corresponding ERC721 token.
    /// @dev For each successful registration, the labelhash-derived tokenId must exist
    ///      and be owned by the registered owner at the time of minting.
    function invariant_registered_names_have_tokens() public view {
        string[] memory registeredLabels = handler.getRegisteredLabels();

        for (uint256 i; i < registeredLabels.length; ++i) {
            bytes32 labelhash = keccak256(bytes(registeredLabels[i]));
            uint256 tokenId = uint256(labelhash);

            address tokenOwner = dotnsRegistrar.ownerOf(tokenId);
            assertTrue(tokenOwner != address(0), "Token must exist for registered name");
        }
    }

    /// @notice Invariant: Every registered name has a valid registry record.
    /// @dev The registry must have an existing record with a non-zero owner for each registration.
    function invariant_registered_names_have_registry_records() public view {
        string[] memory registeredLabels = handler.getRegisteredLabels();

        for (uint256 i; i < registeredLabels.length; ++i) {
            bytes32 labelhash = keccak256(bytes(registeredLabels[i]));
            bytes32 node = _computeNode(labelhash);

            assertTrue(dotnsRegistry.recordExists(node), "Registry record must exist");
            assertTrue(dotnsRegistry.owner(node) != address(0), "Registry owner must be set");
        }
    }

    /// @notice Invariant: Registered names are no longer available.
    /// @dev Once a name is registered, `available()` must return false.
    function invariant_registered_names_unavailable() public view {
        string[] memory registeredLabels = handler.getRegisteredLabels();

        for (uint256 i; i < registeredLabels.length; ++i) {
            assertFalse(
                dotnsRegistrarController.available(registeredLabels[i]),
                "Registered name must be unavailable"
            );
        }
    }

    /// @notice Invariant: Consumed commitments are deleted.
    /// @dev After a successful registration, the commitment timestamp must be zero.
    function invariant_consumed_commitments_deleted() public view {
        bytes32[] memory consumedCommitments = handler.getConsumedCommitments();

        for (uint256 i; i < consumedCommitments.length; ++i) {
            assertEq(
                dotnsRegistrarController.commitments(consumedCommitments[i]),
                0,
                "Consumed commitment must be deleted"
            );
        }
    }

    /// @notice Invariant: Active commitments have valid timestamps.
    /// @dev Pending commitments must have non-zero timestamps within the valid window.
    function invariant_active_commitments_have_valid_timestamps() public view {
        bytes32[] memory activeCommitments = handler.getActiveCommitments();

        for (uint256 i; i < activeCommitments.length; ++i) {
            uint256 timestamp = dotnsRegistrarController.commitments(activeCommitments[i]);

            if (timestamp != 0) {
                assertTrue(
                    timestamp <= block.timestamp, "Commitment timestamp must not be in future"
                );
            }
        }
    }

    /// @notice Invariant: Store entries are created and locked for all registrations.
    /// @dev Each registered name must have a locked store entry for its owner.
    function invariant_store_entries_locked() public view {
        string[] memory registeredLabels = handler.getRegisteredLabels();
        address[] memory registeredOwners = handler.getRegisteredOwners();

        for (uint256 i; i < registeredLabels.length; ++i) {
            address registrationOwner = registeredOwners[i];
            Store store = Store(address(storeFactory.getDeployedStore(registrationOwner)));

            if (address(store) != address(0)) {
                bytes32 labelhash = keccak256(bytes(registeredLabels[i]));
                bytes32 storeKey = _computeStoreKey(labelhash);

                assertTrue(
                    store.isLocked(registrationOwner, storeKey), "Store entry must be locked"
                );
            }
        }
    }

    /// @notice Invariant: Controller never holds excess ETH.
    /// @dev All overpayments must be refunded; controller balance should be zero or minimal.
    function invariant_no_stuck_funds() public view {
        assertEq(address(dotnsRegistrarController).balance, 0, "Controller must not hold funds");
    }

    /// @notice Invariant: Registration count matches minted token count.
    /// @dev The number of successful registrations must equal the number of tokens minted.
    ///      Verified by checking each registered label has a valid token owner.
    function invariant_registration_count_consistent() public view {
        uint256 registrationCount = handler.getRegistrationCount();
        string[] memory registeredLabels = handler.getRegisteredLabels();

        assertEq(
            registrationCount,
            registeredLabels.length,
            "Registration count must match labels array length"
        );

        uint256 validTokenCount;
        for (uint256 i; i < registeredLabels.length; ++i) {
            bytes32 labelhash = keccak256(bytes(registeredLabels[i]));
            uint256 tokenId = uint256(labelhash);

            try dotnsRegistrar.ownerOf(tokenId) returns (address tokenOwner) {
                if (tokenOwner != address(0)) {
                    ++validTokenCount;
                }
            } catch {
                // Token doesn't exist, which would be a failure
            }
        }

        assertEq(
            validTokenCount, registrationCount, "Valid token count must match registration count"
        );
    }

    /// @notice Invariant: Reserved names set reverse resolution.
    /// @dev Names registered with `reserved=true` must have reverse resolution configured.
    function invariant_reserved_names_have_reverse_resolution() public view {
        string[] memory reservedLabels = handler.getReservedLabels();
        address[] memory reservedOwners = handler.getReservedOwners();

        for (uint256 i; i < reservedLabels.length; ++i) {
            string memory expectedName = string.concat(reservedLabels[i], ".dot");
            string memory actualName = dotnsReverseResolver.nameOf(reservedOwners[i]);

            assertEq(actualName, expectedName, "Reverse resolution must be set for reserved name");
        }
    }

    /// @notice Invariant: Token ownership matches registry ownership at registration.
    /// @dev At the time of registration, ERC721 owner and registry owner must be the same.
    function invariant_ownership_consistency_at_registration() public view {
        string[] memory registeredLabels = handler.getRegisteredLabels();
        address[] memory registeredOwners = handler.getRegisteredOwners();

        for (uint256 i; i < registeredLabels.length; ++i) {
            bytes32 labelhash = keccak256(bytes(registeredLabels[i]));
            bytes32 node = _computeNode(labelhash);

            address registryOwner = dotnsRegistry.owner(node);

            assertEq(
                registryOwner, registeredOwners[i], "Registry owner must match registered owner"
            );
        }
    }

    /// @notice Computes the node hash for a given labelhash.
    /// @param labelhash The keccak256 hash of the label.
    /// @return node The namehash of the .dot node.
    function _computeNode(bytes32 labelhash) internal pure returns (bytes32 node) {
        bytes32 dotNodeHash = 0x3fce7d1364a893e213bc4212792b517ffc88f5b13b86c8ef9c8d390c3a1370ce;
        node = keccak256(abi.encodePacked(dotNodeHash, labelhash));
    }

    /// @notice Computes the store key for a given labelhash.
    /// @param labelhash The keccak256 hash of the label.
    /// @return key The store key for the registration entry.
    function _computeStoreKey(bytes32 labelhash) internal pure returns (bytes32 key) {
        key = keccak256(abi.encodePacked(bytes32("dotns.registered"), labelhash));
    }
}
