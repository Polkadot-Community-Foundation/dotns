// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {BaseDotns} from "../base/BaseDotNS.t.sol";
import {IStableOracle} from "../../contracts/ethregistrar/StableOracle.sol";
import {IETHRegistrarController} from "../../contracts/ethregistrar/IETHRegistrarController.sol";

contract BasicDotns is BaseDotns {
    function test_RevertWhen_NameReservedForGovernance() public {
        string memory label = "alice";

        IETHRegistrarController.Registration memory registration = IETHRegistrarController
            .Registration({
            label: label,
            owner: ed,
            duration: 365 days,
            secret: keccak256(abi.encodePacked(label, block.timestamp)),
            resolver: address(publicResolver),
            data: new bytes[](0),
            reverseRecord: 1,
            referrer: bytes32(0)
        });

        vm.startPrank(ed);
        vm.warp(block.timestamp + 1);

        bytes32 commitHash = ethRegistrarController.makeCommitment(registration);
        ethRegistrarController.commit(commitHash);

        vm.warp(block.timestamp + ethRegistrarController.minCommitmentAge() + 2);

        vm.expectRevert(
            abi.encodeWithSelector(IStableOracle.PopError.selector, "Reserved for Governance")
        );

        ethRegistrarController.rentPrice(label, 365 days);
        vm.stopPrank();
    }

    function test_RevertWhen_PopFullRequiredNotClaimed() public {
        string memory label = "alicebob";

        IETHRegistrarController.Registration memory registration = IETHRegistrarController
            .Registration({
            label: label,
            owner: ed,
            duration: 365 days,
            secret: keccak256(abi.encodePacked(label, block.timestamp)),
            resolver: address(publicResolver),
            data: new bytes[](0),
            reverseRecord: 1,
            referrer: bytes32(0)
        });

        vm.startPrank(ed);
        vm.warp(block.timestamp + 1);

        bytes32 commitHash = ethRegistrarController.makeCommitment(registration);
        ethRegistrarController.commit(commitHash);

        vm.warp(block.timestamp + ethRegistrarController.minCommitmentAge() + 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                IStableOracle.PopError.selector, "Requires Full Personhood verification"
            )
        );

        ethRegistrarController.rentPrice(label, 365 days);
        vm.stopPrank();
    }

    function test_RegisterPopFull_8CharsAlphaOnly() public {
        string memory label = "alicebob";

        vm.prank(ed);
        priceOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopFull);
        vm.stopPrank();

        IETHRegistrarController.Registration memory registration = IETHRegistrarController
            .Registration({
            label: label,
            owner: ed,
            duration: 365 days,
            secret: keccak256(abi.encodePacked(label, block.timestamp)),
            resolver: address(publicResolver),
            data: new bytes[](0),
            reverseRecord: 1,
            referrer: bytes32(0)
        });

        _commitAndRegister(registration);

        assertEq(baseRegistrar.ownerOf(uint256(keccak256(bytes(label)))), ed);
    }

    function test_RegisterPopLite_7CharsTwoSuffixDigits() public {
        string memory label = "alice01";

        vm.prank(ed);
        priceOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopLite);
        vm.stopPrank();

        IETHRegistrarController.Registration memory registration = IETHRegistrarController
            .Registration({
            label: label,
            owner: ed,
            duration: 365 days,
            secret: keccak256(abi.encodePacked(label, block.timestamp)),
            resolver: address(publicResolver),
            data: new bytes[](0),
            reverseRecord: 1,
            referrer: bytes32(0)
        });

        _commitAndRegister(registration);

        assertEq(baseRegistrar.ownerOf(uint256(keccak256(bytes(label)))), ed);
    }

    function test_RegisterPopLite_8CharsTwoSuffixDigits() public {
        string memory label = "bobbob99";

        vm.prank(leonardo);
        priceOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopLite);
        vm.stopPrank();

        IETHRegistrarController.Registration memory registration = IETHRegistrarController
            .Registration({
            label: label,
            owner: leonardo,
            duration: 365 days,
            secret: keccak256(abi.encodePacked(label, block.timestamp)),
            resolver: address(publicResolver),
            data: new bytes[](0),
            reverseRecord: 1,
            referrer: bytes32(0)
        });

        _commitAndRegister(registration);

        assertEq(baseRegistrar.ownerOf(uint256(keccak256(bytes(label)))), leonardo);
    }

    function test_RegisterPopFull_WhenSuffixIsSingleDigit() public {
        string memory label = "charlie7";

        vm.prank(tiago);
        priceOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopFull);
        vm.stopPrank();

        IETHRegistrarController.Registration memory registration = IETHRegistrarController
            .Registration({
            label: label,
            owner: tiago,
            duration: 365 days,
            secret: keccak256(abi.encodePacked(label, block.timestamp)),
            resolver: address(publicResolver),
            data: new bytes[](0),
            reverseRecord: 1,
            referrer: bytes32(0)
        });

        _commitAndRegister(registration);

        assertEq(baseRegistrar.ownerOf(uint256(keccak256(bytes(label)))), tiago);
    }

    function test_Register9Plus_PopFullRequired_NoDigits() public {
        string memory label = "longnamehere";

        vm.startPrank(ed);
        priceOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopFull);
        vm.stopPrank();

        IETHRegistrarController.Registration memory registration = IETHRegistrarController
            .Registration({
            label: label,
            owner: ed,
            duration: 365 days,
            secret: keccak256(abi.encodePacked(label, block.timestamp)),
            resolver: address(publicResolver),
            data: new bytes[](0),
            reverseRecord: 1,
            referrer: bytes32(0)
        });

        _commitAndRegister(registration);

        assertEq(baseRegistrar.ownerOf(uint256(keccak256(bytes(label)))), ed);
    }

    function test_Register9Plus_NoStatus_WhenTwoSuffixDigits() public {
        string memory label = "longnamehere01";

        IETHRegistrarController.Registration memory registration = IETHRegistrarController
            .Registration({
            label: label,
            owner: ed,
            duration: 365 days,
            secret: keccak256(abi.encodePacked(label, block.timestamp)),
            resolver: address(publicResolver),
            data: new bytes[](0),
            reverseRecord: 1,
            referrer: bytes32(0)
        });

        _commitAndRegister(registration);

        assertEq(baseRegistrar.ownerOf(uint256(keccak256(bytes(label)))), ed);
    }

    function test_RevertWhen_MoreThanTwoSuffixDigits() public {
        string memory label = "alice123";

        vm.prank(ed);
        priceOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopLite);

        IETHRegistrarController.Registration memory registration = IETHRegistrarController
            .Registration({
            label: label,
            owner: ed,
            duration: 365 days,
            secret: keccak256(abi.encodePacked(label, block.timestamp)),
            resolver: address(publicResolver),
            data: new bytes[](0),
            reverseRecord: 1,
            referrer: bytes32(0)
        });

        vm.startPrank(ed);
        vm.warp(block.timestamp + 1);

        bytes32 commitHash = ethRegistrarController.makeCommitment(registration);
        ethRegistrarController.commit(commitHash);

        vm.warp(block.timestamp + ethRegistrarController.minCommitmentAge() + 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                IStableOracle.PopError.selector, "Name can have maximum 2 digit suffix"
            )
        );

        ethRegistrarController.rentPrice(label, 365 days);
        vm.stopPrank();
    }

    function test_GetNamePopStatus_ReturnsSetStatus() public {
        string memory label = "testname";

        vm.prank(ed);
        priceOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopFull);
        vm.stopPrank();

        vm.prank(ed);
        IStableOracle.PopStatus status = priceOracle.getNamePopStatus(label);
        vm.stopPrank();

        assertEq(uint256(status), uint256(IStableOracle.PopStatus.PopFull));
    }

    function test_PriceNonZero_ForAllEligibleNames() public {
        string memory label = "alicebob";

        vm.prank(ed);
        priceOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopFull);
        vm.stopPrank();

        vm.prank(ed);
        IStableOracle.Price memory priceData = ethRegistrarController.rentPrice(label, 365 days);
        vm.stopPrank();

        assertGt(priceData.base, 0);
    }

    function test_ReservedBaseName_PreventsOtherUserFromRegisteringFullName() public {
        string memory suffixLabel = "bobbob99";
        string memory baseLabel = "bobbob";

        vm.startPrank(leonardo);
        priceOracle.setNamePopStatus(suffixLabel, IStableOracle.PopStatus.PopLite);
        vm.stopPrank();

        IETHRegistrarController.Registration memory regLite = IETHRegistrarController.Registration({
            label: suffixLabel,
            owner: leonardo,
            duration: 365 days,
            secret: keccak256(abi.encodePacked(suffixLabel, block.timestamp)),
            resolver: address(publicResolver),
            data: new bytes[](0),
            reverseRecord: 1,
            referrer: bytes32(0)
        });

        _commitAndRegister(regLite);

        vm.startPrank(tiago);

        vm.expectRevert(
            abi.encodeWithSelector(
                IStableOracle.PopError.selector, "Base name reserved for original Lite registrant"
            )
        );

        ethRegistrarController.rentPrice(baseLabel, 365 days);

        vm.stopPrank();
    }
}
