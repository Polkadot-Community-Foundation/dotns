// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {StringUtils} from "../../../contracts/utils/StringUtils.sol";

/// @title StringUtilsHarness
/// @notice Exposes the library's internal validators as external functions so tests can call
///         them across both data locations.
/// @dev The `Memory` wrapper takes `calldata` and forwards it, which is what produces the
///      calldata-to-memory copy the controller paths rely on.
contract StringUtilsHarness {
    using StringUtils for *;

    function isSingleLabel(string calldata value) external pure returns (bool) {
        return value.isSingleLabel();
    }

    function isLitePersonLabel(string calldata value) external pure returns (bool) {
        return value.isLitePersonLabel();
    }

    function isLitePersonLabelMemory(string calldata value) external pure returns (bool) {
        return StringUtils.isLitePersonLabelMemory(value);
    }
}

/// @title StringUtilsTests
/// @notice Unit tests for the lite-label shape predicate and the digit-suffix helper.
/// @dev A lite label is the only shape in DotNS permitted to carry a separator or a digit
///      suffix, so these tests are the definition of that boundary.
contract StringUtilsTests is Test {
    StringUtilsHarness internal utils;

    function setUp() public {
        utils = new StringUtilsHarness();
    }

    /// @notice Builds a string of `count` repetitions of "a".
    function _stem(uint256 count) internal pure returns (string memory) {
        bytes memory out = new bytes(count);
        for (uint256 i = 0; i < count; ++i) {
            out[i] = "a";
        }
        return string(out);
    }

    /// @notice Asserts both data locations agree, then that they agree with `expected`.
    function _assertLite(string memory value, bool expected) internal view {
        bool fromCalldata = utils.isLitePersonLabel(value);
        bool fromMemory = utils.isLitePersonLabelMemory(value);
        assertEq(fromCalldata, fromMemory, "calldata and memory variants disagree");
        assertEq(fromCalldata, expected, value);
    }

    function test_isLitePersonLabel_accepts_the_dotted_shape() public view {
        _assertLite("a.42", true);
        _assertLite("alice.42", true);
        _assertLite("joseph.00", true);
        _assertLite("alice-bob.99", true);
        _assertLite(string.concat(_stem(63), ".42"), true);
    }

    function test_isLitePersonLabel_rejects_a_missing_or_repeated_separator() public view {
        _assertLite("alice42", false);
        _assertLite("a.b.42", false);
        _assertLite(".42", false);
        _assertLite("alice.", false);
    }

    function test_isLitePersonLabel_rejects_any_suffix_but_two_digits() public view {
        _assertLite("alice.4", false);
        _assertLite("alice.123", false);
        _assertLite("alice.4x", false);
        _assertLite("alice.x4", false);
    }

    function test_isLitePersonLabel_rejects_a_non_canonical_stem() public view {
        _assertLite("Alice.42", false);
        _assertLite("ali_ce.42", false);
        _assertLite("-alice.42", false);
        _assertLite("alice-.42", false);
        _assertLite(string.concat(_stem(64), ".42"), false);
    }

    function test_isLitePersonLabel_rejects_the_empty_string() public view {
        _assertLite("", false);
    }

    /// @dev The bound moved from the whole label to the stem, so a lite label runs three octets
    ///      past the single-label limit. Pinned because it is a deliberate widening.
    function test_isLitePersonLabel_bounds_the_stem_not_the_whole_label() public view {
        string memory longest = string.concat(_stem(63), ".42");
        assertEq(bytes(longest).length, 66, "longest lite label is 66 octets");
        _assertLite(longest, true);
        assertFalse(utils.isSingleLabel(longest), "a lite label is not a single DNS label");
    }
}
