// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import {BaseDotns} from "../base/BaseDotNS.t.sol";
import {IStableOracle} from "../../contracts/ethregistrar/StableOracle.sol";
import {StableOracleV2} from "../utils/StableOracleV2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract StableOracleTests is BaseDotns {
    function test_ClassifyName_ReturnsReservedFor5Chars() public view {
        (IStableOracle.PopStatus status, string memory message) = stableOracle.classifyName("hello");

        assertEq(uint256(status), uint256(IStableOracle.PopStatus.Reserved));
        assertEq(message, "Reserved for Governance");
    }

    function test_ClassifyName_ReturnsPopFullFor8CharsAlphaOnly() public view {
        (IStableOracle.PopStatus status, string memory message) =
            stableOracle.classifyName("alicebob");

        assertEq(uint256(status), uint256(IStableOracle.PopStatus.PopFull));
        assertEq(message, "Requires Full personhood verification");
    }

    function test_ClassifyName_ReturnsPopLiteFor8CharsWithTwoDigitSuffix() public view {
        (IStableOracle.PopStatus status, string memory message) =
            stableOracle.classifyName("alice01");

        assertEq(uint256(status), uint256(IStableOracle.PopStatus.PopLite));
        assertEq(message, "Requires Light personhood verification");
    }

    function test_ClassifyName_ReturnsPopFullFor9PlusCharsWithoutSuffix() public view {
        (IStableOracle.PopStatus status, string memory message) =
            stableOracle.classifyName("longnamehere");

        assertEq(uint256(status), uint256(IStableOracle.PopStatus.PopFull));
        assertEq(message, "Requires Full personhood verification");
    }

    function test_ClassifyName_ReturnsNoStatusFor9PlusCharsWithTwoDigitSuffix() public view {
        (IStableOracle.PopStatus status, string memory message) =
            stableOracle.classifyName("longnamehere01");

        assertEq(uint256(status), uint256(IStableOracle.PopStatus.NoStatus));
        assertEq(message, "Available to all");
    }

    function test_RevertWhen_NameHasMoreThanTwoTrailingDigits() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IStableOracle.PopError.selector, "Name can have maximum 2 digit suffix"
            )
        );

        stableOracle.classifyName("alice123");
    }

    function test_Upgrade_Oracle() public {
        vm.startPrank(owner);
        bytes memory code = vm.getCode("./out/StableOracleV2.sol/StableOracleV2.json");
        assert(code.length > 0);
        Upgrades.upgradeProxy(
            address(stableOracle),
            "./out/StableOracleV2.sol/StableOracleV2.json",
            abi.encodeCall(StableOracleV2.initializeV2, ())
        );
    }
}
