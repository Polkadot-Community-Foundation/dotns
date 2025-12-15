// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../base/BaseDotNS.t.sol";
import {IStableOracle} from "../../contracts/ethregistrar/IStableOracle.sol";
import {IDotRegistrarController} from "../../contracts/ethregistrar/IDotRegistrarController.sol";

contract BasicDotnsReverts is BaseDotns {
    function test_revert_register_5_or_less_chars_governance_reserved() public {
        string memory label = "alice";

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
                label: label,
                owner: ed,
                duration: 365 days,
                secret: keccak256(abi.encodePacked(label, block.timestamp)),
                resolver: address(publicResolver),
                data: new bytes[](0),
                reverseRecord: 0,
                referrer: bytes32(0)
            });

        _commit(registration);
        vm.startPrank(ed);
        uint256 price =
            dotRegistrarController.rentPrice(registration.label, registration.duration).base;

        vm.expectRevert(
            abi.encodeWithSelector(IStableOracle.PopError.selector, "Reserved for Governance")
        );
        dotRegistrarController.register{value: price}(registration);
    }

    function test_revert_6_to_8_chars_no_digits_without_pop_full() public {
        string memory label = "testit";

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
                label: label,
                owner: ed,
                duration: 365 days,
                secret: keccak256(abi.encodePacked(label, block.timestamp)),
                resolver: address(publicResolver),
                data: new bytes[](0),
                reverseRecord: 0,
                referrer: bytes32(0)
            });

        _commit(registration);
        vm.startPrank(ed);
        uint256 price =
            dotRegistrarController.rentPrice(registration.label, registration.duration).base;

        vm.expectRevert(
            abi.encodeWithSelector(
                IStableOracle.PopError.selector, "Requires Full Personhood verification"
            )
        );
        dotRegistrarController.register{value: price}(registration);
    }

    function test_revert_6_to_8_chars_with_digits_without_pop_lite() public {
        string memory label = "test01";

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
                label: label,
                owner: ed,
                duration: 365 days,
                secret: keccak256(abi.encodePacked(label, block.timestamp)),
                resolver: address(publicResolver),
                data: new bytes[](0),
                reverseRecord: 0,
                referrer: bytes32(0)
            });

        _commit(registration);
        vm.startPrank(ed);
        uint256 price =
            dotRegistrarController.rentPrice(registration.label, registration.duration).base;

        vm.expectRevert(
            abi.encodeWithSelector(
                IStableOracle.PopError.selector, "Requires Personhood Lite verification"
            )
        );
        dotRegistrarController.register{value: price}(registration);
    }

    function test_revert_9_plus_chars_no_digits_without_pop_full() public {
        string memory label = "kitesurfing_guru";

        IDotRegistrarController.Registration memory registration =
            IDotRegistrarController.Registration({
                label: label,
                owner: ed,
                duration: 365 days,
                secret: keccak256(abi.encodePacked(label, block.timestamp)),
                resolver: address(publicResolver),
                data: new bytes[](0),
                reverseRecord: 0,
                referrer: bytes32(0)
            });

        _commit(registration);
        vm.startPrank(ed);
        uint256 price =
            dotRegistrarController.rentPrice(registration.label, registration.duration).base;

        vm.expectRevert(
            abi.encodeWithSelector(
                IStableOracle.PopError.selector, "Requires Full Personhood verification"
            )
        );
        dotRegistrarController.register{value: price}(registration);
    }

    function test_revert_more_than_two_suffix_digits() public {
        string memory label = "test123";

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
                reverseRecord: 0,
                referrer: bytes32(0)
            });

        _commit(registration);
        vm.startPrank(ed);
        uint256 price =
            dotRegistrarController.rentPrice(registration.label, registration.duration).base;

        vm.expectRevert(
            abi.encodeWithSelector(
                IStableOracle.PopError.selector, "Name can have maximum 2 digit suffix"
            )
        );
        dotRegistrarController.register{value: price}(registration);
    }

    function test_revert_pop_lite_user_registering_pop_full_name() public {
        string memory label = "kitesurfing_guru";

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
                reverseRecord: 0,
                referrer: bytes32(0)
            });

        _commit(registration);
        vm.startPrank(ed);
        uint256 price =
            dotRegistrarController.rentPrice(registration.label, registration.duration).base;

        vm.expectRevert(
            abi.encodeWithSelector(
                IStableOracle.PopError.selector, "Requires Full Personhood verification"
            )
        );
        dotRegistrarController.register{value: price}(registration);
    }

    function test_revert_other_user_claiming_reserved_base_name() public {
        string memory suffixLabel = "reserved99";
        string memory baseLabel = "reserved";

        vm.prank(leonardo);
        stableOracle.setNamePopStatus(suffixLabel, IStableOracle.PopStatus.PopLite);

        _commitAndRegister(
            IDotRegistrarController.Registration({
                label: suffixLabel,
                owner: leonardo,
                duration: 365 days,
                secret: keccak256(abi.encodePacked(suffixLabel, block.timestamp)),
                resolver: address(publicResolver),
                data: new bytes[](0),
                reverseRecord: 0,
                referrer: bytes32(0)
            })
        );

        vm.prank(tiago);
        stableOracle.setNamePopStatus(baseLabel, IStableOracle.PopStatus.PopFull);

        IDotRegistrarController.Registration memory baseRegistration =
            IDotRegistrarController.Registration({
                label: baseLabel,
                owner: tiago,
                duration: 365 days,
                secret: keccak256(abi.encodePacked(baseLabel, block.timestamp)),
                resolver: address(publicResolver),
                data: new bytes[](0),
                reverseRecord: 0,
                referrer: bytes32(0)
            });

        _commit(baseRegistration);
        uint256 price =
            dotRegistrarController.rentPrice(baseRegistration.label, baseRegistration.duration).base;

        vm.expectRevert(
            abi.encodeWithSelector(
                IStableOracle.PopError.selector, "Base name reserved for original Lite registrant"
            )
        );
        dotRegistrarController.register{value: price}(baseRegistration);
    }

    function test_revert_registering_same_base_different_suffix() public {
        string memory label1 = "multi01";
        string memory label2 = "multi02";

        vm.prank(ed);
        stableOracle.setNamePopStatus(label1, IStableOracle.PopStatus.PopLite);

        _commitAndRegister(
            IDotRegistrarController.Registration({
                label: label1,
                owner: ed,
                duration: 365 days,
                secret: keccak256(abi.encodePacked(label1, block.timestamp)),
                resolver: address(publicResolver),
                data: new bytes[](0),
                reverseRecord: 0,
                referrer: bytes32(0)
            })
        );

        vm.prank(leonardo);
        stableOracle.setNamePopStatus(label2, IStableOracle.PopStatus.PopLite);

        IDotRegistrarController.Registration memory registration2 =
            IDotRegistrarController.Registration({
                label: label2,
                owner: leonardo,
                duration: 365 days,
                secret: keccak256(abi.encodePacked(label2, block.timestamp)),
                resolver: address(publicResolver),
                data: new bytes[](0),
                reverseRecord: 0,
                referrer: bytes32(0)
            });

        _commit(registration2);
        uint256 price =
            dotRegistrarController.rentPrice(registration2.label, registration2.duration).base;

        vm.startPrank(leonardo);
        vm.expectRevert(
            abi.encodeWithSelector(
                IStableOracle.PopError.selector, "Base name reserved for original Lite registrant"
            )
        );
        dotRegistrarController.register{value: price}(registration2);
    }
}
