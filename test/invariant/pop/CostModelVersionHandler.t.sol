// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {DotnsCostModelRegistry} from "../../../contracts/pop/DotnsCostModelRegistry.sol";
import {DotnsScarcityPricing} from "../../../contracts/pop/DotnsScarcityPricing.sol";
import {IDotnsPricing} from "../../../contracts/pop/IDotnsPricing.sol";
import {PopRules} from "../../../contracts/pop/PopRules.sol";
import {
    IDotnsRegistrarController,
    DotnsRegistrarController
} from "../../../contracts/registrars/DotnsRegistrarController.sol";

/// @title CostModelVersionHandler
/// @notice Bounded random-action handler that registers cost models, moves the current version
///         around, and drives commit-reveal registrations bound to a version.
/// @dev Ghost-tracks every version ever registered and the amount each returns at three base
///      lengths, so the invariant suite can assert a version's price never moves and that
///      commit-reveal always settles at the committed version.
contract CostModelVersionHandler is Test {
    DotnsCostModelRegistry public registry;
    PopRules public popRules;
    DotnsRegistrarController public controller;
    address public owner;
    address public actor;

    /// @notice Every version ever registered, in registration order.
    uint256[] public versions;

    /// @notice Expected amount each version returns at base length seven.
    mapping(uint256 version => uint256 price) public expectedAt7;

    /// @notice Expected amount each version returns at base length nine.
    mapping(uint256 version => uint256 price) public expectedAt9;

    /// @notice Expected amount each version returns at base length twelve.
    mapping(uint256 version => uint256 price) public expectedAt12;

    /// @notice Marks versions already tracked so a re-registration is skipped.
    mapping(uint256 version => bool tracked) public tracked;

    uint256 internal feeCounter;
    uint256 internal labelNonce;

    constructor(
        DotnsCostModelRegistry registry_,
        PopRules popRules_,
        DotnsRegistrarController controller_,
        address owner_,
        address actor_
    ) {
        registry = registry_;
        popRules = popRules_;
        controller = controller_;
        owner = owner_;
        actor = actor_;
        feeCounter = 1;
        // Track the model already registered as the current version at construction.
        _track(registry.currentVersion());
    }

    /// @notice Number of distinct versions tracked so far.
    function versionCount() external view returns (uint256 count) {
        return versions.length;
    }

    /// @notice Registers a fresh immutable model at a new base fee and makes it current.
    function registerModel(uint256 seed) external {
        uint256 baseFee = bound(seed, 1 ether, 400 ether) + feeCounter * 1 wei;
        feeCounter++;
        DotnsScarcityPricing model = new DotnsScarcityPricing(baseFee, 0.1 ether);
        uint256 version = model.version();
        if (address(registry.modelOf(version)) != address(0)) return;

        vm.prank(owner);
        registry.register(IDotnsPricing(address(model)));
        _track(version);
    }

    /// @notice Points the current version at any already-registered version, older or newer.
    function pointCurrent(uint256 idx) external {
        if (versions.length == 0) return;
        uint256 version = versions[idx % versions.length];
        vm.prank(owner);
        registry.setCurrentVersion(version);
    }

    /// @notice Commits a registration under the current version, moves the current pointer, then
    ///         reveals, asserting the charge settles at the committed version.
    function bindMoveReveal(uint256 seed) external {
        string memory label = _uniqueLabel();
        if (!controller.available(label)) return;

        uint256 committedVersion = registry.currentVersion();
        uint256 committedPrice = popRules.price(label);

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label,
                owner: actor,
                secret: keccak256(abi.encodePacked(label, seed)),
                reserved: false,
                maxPrice: committedPrice,
                pricingVersion: committedVersion
            });

        bytes32 commitment = controller.makeCommitment(registration);
        vm.prank(actor);
        controller.commit(commitment);
        vm.warp(block.timestamp + controller.minCommitmentAge() + 1);

        // Move the current pointer to any registered version before revealing.
        if (versions.length != 0) {
            vm.prank(owner);
            registry.setCurrentVersion(versions[seed % versions.length]);
        }

        vm.deal(actor, committedPrice);
        vm.prank(actor);
        controller.register{value: committedPrice}(registration);

        assertFalse(
            controller.available(label), "reveal must settle at the committed version and mint"
        );
    }

    function _track(uint256 version) internal {
        if (tracked[version]) return;
        tracked[version] = true;
        versions.push(version);
        expectedAt7[version] = registry.priceForBaseLengthAtVersion(version, 7);
        expectedAt9[version] = registry.priceForBaseLengthAtVersion(version, 9);
        expectedAt12[version] = registry.priceForBaseLengthAtVersion(version, 12);
    }

    /// @notice Produces a unique lowercase-letter label of base length eleven (NoStatus band).
    function _uniqueLabel() internal returns (string memory label) {
        uint256 n = labelNonce++;
        bytes memory suffix = new bytes(4);
        for (uint256 i = 0; i < 4; i++) {
            suffix[3 - i] = bytes1(uint8(97 + uint8(n % 26)));
            n /= 26;
        }
        return string.concat("invcost", string(suffix));
    }
}
