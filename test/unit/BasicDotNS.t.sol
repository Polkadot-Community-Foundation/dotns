// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../base/BaseDotNS.t.sol";
import {IStableOracle} from "../../contracts/ethregistrar/StableOracle.sol";
import {IDotRegistrarController} from "../../contracts/ethregistrar/IDotRegistrarController.sol";

contract BasicDotns is BaseDotns {
    function test_RevertWhen_NameReservedForGovernance() public {
        string memory label = "alice";

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
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

        bytes32 commitHash = dotRegistrarController.makeCommitment(registration);
        dotRegistrarController.commit(commitHash);

        vm.warp(block.timestamp + dotRegistrarController.minCommitmentAge() + 2);

        vm.expectRevert(
            abi.encodeWithSelector(IStableOracle.PopError.selector, "Reserved for Governance")
        );

        dotRegistrarController.rentPrice(label, 365 days);
        vm.stopPrank();
    }

    function test_RevertWhen_PopFullRequiredNotClaimed() public {
        string memory label = "alicebob";

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
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

        bytes32 commitHash = dotRegistrarController.makeCommitment(registration);
        dotRegistrarController.commit(commitHash);

        vm.warp(block.timestamp + dotRegistrarController.minCommitmentAge() + 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                IStableOracle.PopError.selector, "Requires Full Personhood verification"
            )
        );

        dotRegistrarController.rentPrice(label, 365 days);
        vm.stopPrank();
    }

    function test_RegisterPopFull_8CharsAlphaOnly() public {
        string memory label = "alicebob";

        vm.prank(ed);
        stableOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopFull);
        vm.stopPrank();

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
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
        stableOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopLite);
        vm.stopPrank();

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
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
        stableOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopLite);
        vm.stopPrank();

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
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
        stableOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopFull);
        vm.stopPrank();

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
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
        stableOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopFull);
        vm.stopPrank();

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
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

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
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
        stableOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopLite);

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
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

        bytes32 commitHash = dotRegistrarController.makeCommitment(registration);
        dotRegistrarController.commit(commitHash);

        vm.warp(block.timestamp + dotRegistrarController.minCommitmentAge() + 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                IStableOracle.PopError.selector, "Name can have maximum 2 digit suffix"
            )
        );

        dotRegistrarController.rentPrice(label, 365 days);
        vm.stopPrank();
    }

    function test_GetNamePopStatus_ReturnsSetStatus() public {
        string memory label = "testname";

        vm.prank(ed);
        stableOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopFull);
        vm.stopPrank();

        vm.prank(ed);
        IStableOracle.PopStatus status = stableOracle.getNamePopStatus(label);
        vm.stopPrank();

        assertEq(uint256(status), uint256(IStableOracle.PopStatus.PopFull));
    }

    function test_PriceNonZero_ForAllEligibleNames() public {
        string memory label = "alicebob";

        vm.prank(ed);
        stableOracle.setNamePopStatus(label, IStableOracle.PopStatus.PopFull);
        vm.stopPrank();

        vm.prank(ed);
        IStableOracle.Price memory priceData = dotRegistrarController.rentPrice(label, 365 days);
        vm.stopPrank();

        assertGt(priceData.base, 0);
    }

    function test_ReservedBaseName_PreventsOtherUserFromRegisteringFullName() public {
        string memory suffixLabel = "bobbob99";
        string memory baseLabel = "bobbob";

        vm.startPrank(leonardo);
        stableOracle.setNamePopStatus(suffixLabel, IStableOracle.PopStatus.PopLite);
        vm.stopPrank();

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
                label: suffixLabel,
                owner: leonardo,
                duration: 365 days,
                secret: keccak256(abi.encodePacked(suffixLabel, block.timestamp)),
                resolver: address(publicResolver),
                data: new bytes[](0),
                reverseRecord: 1,
                referrer: bytes32(0)
            });

        _commitAndRegister(registration);

        vm.startPrank(tiago);

        vm.expectRevert(
            abi.encodeWithSelector(
                IStableOracle.PopError.selector, "Base name reserved for original Lite registrant"
            )
        );

        dotRegistrarController.rentPrice(baseLabel, 365 days);

        vm.stopPrank();
    }
}
