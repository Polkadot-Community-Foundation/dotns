// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDotns} from "../../base/BaseDotNS.t.sol";
import {IPopOracle} from "../../../contracts/pop/IPopOracle.sol";

contract PopOracleTests is BaseDotns {
    function test_classify_governance_reserved() public view {
        (IPopOracle.PopStatus status, string memory message) = popOracle.classifyName("hello");
        assertEq(uint256(status), uint256(IPopOracle.PopStatus.Reserved));
        assertEq(message, "Reserved for Governance");
    }

    function test_classify_governance_reserved_even_with_suffix_digits() public view {
        // governance reservation is not bypassable by adding a suffix
        (IPopOracle.PopStatus status, string memory message) = popOracle.classifyName("hello01");
        assertEq(uint256(status), uint256(IPopOracle.PopStatus.Reserved));
        assertEq(message, "Reserved for Governance");
    }

    function test_classify_poplite_username_variant_requires_lite() public view {
        // lite-eligible username variant (two-digit suffix)
        (IPopOracle.PopStatus status, string memory message) = popOracle.classifyName("lights01");
        assertEq(uint256(status), uint256(IPopOracle.PopStatus.PopLite));
        assertEq(message, "Requires Light personhood verification");
    }

    function test_classify_popfull_username_requires_full() public view {
        // popfull required (no suffix)
        (IPopOracle.PopStatus status, string memory message) = popOracle.classifyName("alicebob");
        assertEq(uint256(status), uint256(IPopOracle.PopStatus.PopFull));
        assertEq(message, "Requires Full personhood verification");
    }

    function test_classify_popfull_single_digit_suffix_still_full() public view {
        // one digit is not a lite username variant, still popfull-required
        (IPopOracle.PopStatus status, string memory message) = popOracle.classifyName("alicebo1");
        assertEq(uint256(status), uint256(IPopOracle.PopStatus.PopFull));
        assertEq(message, "Requires Full personhood verification");
    }

    function test_classify_nostatus_long_username_variant_available_to_all() public view {
        // long username variant with two-digit suffix is NoStatus
        (IPopOracle.PopStatus status, string memory message) =
            popOracle.classifyName("longnamehere01");
        assertEq(uint256(status), uint256(IPopOracle.PopStatus.NoStatus));
        assertEq(message, "Available to all");
    }

    function test_price_with_check_reverts_for_governance_reserved() public {
        vm.expectRevert(
            abi.encodeWithSelector(IPopOracle.PopError.selector, "Reserved for Governance")
        );
        popOracle.priceWithCheck("hello", ed);
    }

    function test_price_with_check_reverts_when_full_required_and_user_not_full() public {
        // "alicebob" requires PopFull, ed has not set PopFull for this name
        vm.expectRevert(
            abi.encodeWithSelector(
                IPopOracle.PopError.selector, "Requires Full Personhood verification"
            )
        );
        popOracle.priceWithCheck("alicebob", ed);
    }

    function test_price_with_check_allows_full_user_for_lite_required_name() public {
        // PopFull is allowed to register PopLite-required names
        vm.prank(ed);
        popOracle.setNamePopStatus("lights01", IPopOracle.PopStatus.PopFull);

        IPopOracle.PriceWithMeta memory priced = popOracle.priceWithCheck("lights01", ed);

        assertEq(uint256(priced.status), uint256(IPopOracle.PopStatus.PopLite));
        assertEq(uint256(priced.userStatus), uint256(IPopOracle.PopStatus.PopFull));
    }

    function test_base_reservation_blocks_other_user_and_is_idempotent() public {
        // allow this test contract to act as the registry controller for reserveBaseName()
        vm.prank(owner);
        popOracle.updateEthRegistry(address(this));

        // first reservation created by original lite registrant
        popOracle.reserveBaseName("lights01", leonardo);

        (bool isReserved1, address reservationOwner1, uint64 expires1) =
            popOracle.isBaseNameReserved("lights");
        assertTrue(isReserved1);
        assertEq(reservationOwner1, leonardo);
        assertEq(expires1, uint64(block.timestamp + 12 weeks));

        // idempotent: second attempt must not overwrite an existing reservation
        popOracle.reserveBaseName("lights01", tiago);

        (bool isReserved2, address reservationOwner2, uint64 expires2) =
            popOracle.isBaseNameReserved("lights");
        assertTrue(isReserved2);
        assertEq(reservationOwner2, leonardo);
        assertEq(expires2, expires1);

        // reservation enforcement: other user is blocked from the base name while active
        vm.expectRevert(
            abi.encodeWithSelector(
                IPopOracle.PopError.selector, "Base name reserved for original Lite registrant"
            )
        );
        popOracle.priceWithCheck("lights", tiago);
    }
}
