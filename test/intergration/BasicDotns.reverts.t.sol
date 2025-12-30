// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../base/BaseDotns.t.sol";
import {IPopOracle} from "../../contracts/pop/IPopOracle.sol";
import {IDotnsRegistrarController} from "../../contracts/registrars/IDotnsRegistrarController.sol";

contract BasicDotnsReverts is BaseDotns {
    function reserved_name_reverts_for_governance() public {
        string memory label = "alice";

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                reserved: true,
                label: label,
                owner: ed,
                secret: keccak256(abi.encodePacked(label, block.timestamp))
            });

        _commitRegistrationAndWaitMinimumAge(registration);

        vm.prank(ed);
        vm.expectRevert(
            abi.encodeWithSelector(IPopOracle.PopError.selector, "Reserved for Governance")
        );
        dotnsRegistrarController.register{value: 0}(registration);
    }

    function no_digits_6_to_8_chars_requires_full() public {
        string memory label = "testit";

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                reserved: true,
                label: label,
                owner: ed,
                secret: keccak256(abi.encodePacked(label, block.timestamp))
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

    function two_digit_suffix_requires_lite() public {
        string memory label = "testit01";

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label,
                owner: ed,
                secret: keccak256(abi.encodePacked(label, block.timestamp)),
                reserved: true
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

    function long_name_without_digits_requires_full() public {
        string memory label = "kitesurfing_guru";

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label,
                owner: ed,
                secret: keccak256(abi.encodePacked(label, block.timestamp)),
                reserved: true
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

    function more_than_two_suffix_digits_reverts() public {
        string memory label = "test123";

        vm.prank(ed);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopLite);

        IDotnsRegistrarController.Registration memory registration =
            IDotnsRegistrarController.Registration({
                label: label,
                owner: ed,
                secret: keccak256(abi.encodePacked(label, block.timestamp)),
                reserved: true
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

    function other_user_cannot_claim_reserved_base() public {
        string memory suffixLabel = "reserved99";
        string memory baseLabel = "reserved";

        vm.prank(leonardo);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopLite);

        IDotnsRegistrarController.Registration memory suffixRegistration =
            IDotnsRegistrarController.Registration({
                label: suffixLabel,
                owner: leonardo,
                secret: keccak256(abi.encodePacked(suffixLabel, block.timestamp)),
                reserved: true
            });

        _commitRegistrationAndRegister(suffixRegistration);

        vm.prank(tiago);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopFull);

        IDotnsRegistrarController.Registration memory baseRegistration =
            IDotnsRegistrarController.Registration({
                label: baseLabel,
                owner: tiago,
                secret: keccak256(abi.encodePacked(baseLabel, block.timestamp)),
                reserved: true
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

    function registering_same_base_different_suffix_reverts() public {
        string memory firstLabel = "multix01";
        string memory secondLabel = "multix02";

        vm.prank(ed);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopLite);

        IDotnsRegistrarController.Registration memory firstRegistration =
            IDotnsRegistrarController.Registration({
                label: firstLabel,
                owner: ed,
                secret: keccak256(abi.encodePacked(firstLabel, block.timestamp)),
                reserved: true
            });

        _commitRegistrationAndRegister(firstRegistration);

        vm.prank(leonardo);
        popOracle.setUserPopStatus(IPopOracle.PopStatus.PopLite);

        IDotnsRegistrarController.Registration memory secondRegistration =
            IDotnsRegistrarController.Registration({
                label: secondLabel,
                owner: leonardo,
                secret: keccak256(abi.encodePacked(secondLabel, block.timestamp)),
                reserved: true
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
