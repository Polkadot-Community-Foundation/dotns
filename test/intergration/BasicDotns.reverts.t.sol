// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../base/BaseDotNS.t.sol";
import {IPopOracle} from "../../contracts/pop/IPopOracle.sol";
import {IDotnsRegistrarController} from "../../contracts/registrars/IDotnsRegistrarController.sol";

contract BasicDotnsReverts is BaseDotns {
    function test_revert_register_5_or_less_chars_governance_reserved() public {
        string memory label = "alice";

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label, owner: ed, secret: keccak256(abi.encodePacked(label, block.timestamp))
            });

        _commitRegistrationAndWaitMinimumAge(registration);

        vm.prank(ed);
        vm.expectRevert(
            abi.encodeWithSelector(IPopOracle.PopError.selector, "Reserved for Governance")
        );
        dotnsRegistrarController.register{value: 0}(registration);
    }

    function test_revert_6_to_8_chars_no_digits_without_pop_full() public {
        string memory label = "testit"; // baseLen=6, no digits => PopFull required

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label, owner: ed, secret: keccak256(abi.encodePacked(label, block.timestamp))
            });

        _commitRegistrationAndWaitMinimumAge(registration);

        vm.prank(ed);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPopOracle.PopError.selector, "Requires Full Personhood verification"
            )
        );
        dotnsRegistrarController.register{value: 0}(registration);
    }

    function test_revert_6_to_8_chars_with_digits_without_pop_lite() public {
        // base "testit" is 6 chars, + "01" => lite-eligible username
        string memory label = "testit01";

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label, owner: ed, secret: keccak256(abi.encodePacked(label, block.timestamp))
            });

        _commitRegistrationAndWaitMinimumAge(registration);

        vm.prank(ed);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPopOracle.PopError.selector, "Requires Personhood Lite verification"
            )
        );
        dotnsRegistrarController.register{value: 0}(registration);
    }

    function test_revert_9_plus_chars_no_digits_without_pop_full() public {
        // This assumes oracle policy: 9+ base with no digits => PopFull required.
        // We assert revert on the controller register path (after commit+wait).
        string memory label = "kitesurfing_guru";

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label, owner: ed, secret: keccak256(abi.encodePacked(label, block.timestamp))
            });

        _commitRegistrationAndWaitMinimumAge(registration);

        vm.prank(ed);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPopOracle.PopError.selector, "Requires Full Personhood verification"
            )
        );
        dotnsRegistrarController.register{value: 0}(registration);
    }

    function test_revert_more_than_two_suffix_digits() public {
        string memory label = "test123";

        vm.prank(ed);
        popOracle.setNamePopStatus(label, IPopOracle.PopStatus.PopLite);

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label, owner: ed, secret: keccak256(abi.encodePacked(label, block.timestamp))
            });

        _commitRegistrationAndWaitMinimumAge(registration);

        vm.prank(ed);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPopOracle.PopError.selector, "Name can have maximum 2 digit suffix"
            )
        );
        dotnsRegistrarController.register{value: 0}(registration);
    }

    function test_revert_other_user_claiming_reserved_base_name() public {
        string memory suffixLabel = "reserved99";
        string memory baseLabel = "reserved";

        vm.prank(leonardo);
        popOracle.setNamePopStatus(suffixLabel, IPopOracle.PopStatus.PopLite);

        IDotnsRegistrarController.Registration memory suffixRegistration =
            IDotnsRegistrarController.Registration({
                label: suffixLabel,
                owner: leonardo,
                secret: keccak256(abi.encodePacked(suffixLabel, block.timestamp))
            });

        _commitRegistrationAndRegister(suffixRegistration);

        vm.prank(tiago);
        popOracle.setNamePopStatus(baseLabel, IPopOracle.PopStatus.PopFull);

        IDotnsRegistrarController.Registration memory baseRegistration =
            IDotnsRegistrarController.Registration({
                label: baseLabel,
                owner: tiago,
                secret: keccak256(abi.encodePacked(baseLabel, block.timestamp))
            });

        _commitRegistrationAndWaitMinimumAge(baseRegistration);

        vm.prank(tiago);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPopOracle.PopError.selector, "Base name reserved for original Lite registrant"
            )
        );
        dotnsRegistrarController.register{value: 0}(baseRegistration);
    }

    function test_revert_registering_same_base_different_suffix() public {
        // base "multix" is 6 chars (not governance reserved), + two digits => lite-eligible
        string memory firstLabel = "multix01";
        string memory secondLabel = "multix02";

        vm.prank(ed);
        popOracle.setNamePopStatus(firstLabel, IPopOracle.PopStatus.PopLite);

        IDotnsRegistrarController.Registration memory firstRegistration =
            IDotnsRegistrarController.Registration({
                label: firstLabel,
                owner: ed,
                secret: keccak256(abi.encodePacked(firstLabel, block.timestamp))
            });

        _commitRegistrationAndRegister(firstRegistration);

        vm.prank(leonardo);
        popOracle.setNamePopStatus(secondLabel, IPopOracle.PopStatus.PopLite);

        IDotnsRegistrarController.Registration memory secondRegistration =
            IDotnsRegistrarController.Registration({
                label: secondLabel,
                owner: leonardo,
                secret: keccak256(abi.encodePacked(secondLabel, block.timestamp))
            });

        _commitRegistrationAndWaitMinimumAge(secondRegistration);

        vm.prank(leonardo);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPopOracle.PopError.selector, "Base name reserved for original Lite registrant"
            )
        );
        dotnsRegistrarController.register{value: 0}(secondRegistration);
    }
}
