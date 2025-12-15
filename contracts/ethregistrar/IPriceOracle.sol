// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title Price Oracle Interface
/// @notice Defines pricing structure for .dot domain registrations and renewals
/// @dev Implementations calculate base pricing and time-based premiums
interface IPriceOracle {
    /// @notice Price breakdown for domain operations
    /// @param base Standard registration cost based on length and duration
    /// @param premium Additional cost for recently expired domains
    struct Price {
        uint256 base;
        uint256 premium;
    }

    /// @notice Calculates registration or renewal price
    /// @param name Domain label to price
    /// @param expires Current expiration timestamp (zero for new registrations)
    /// @param duration Registration period in seconds
    /// @return pricing Price breakdown with base and premium components
    function price(
        string calldata name,
        uint256 expires,
        uint256 duration
    )
        external
        view
        returns (Price memory pricing);
}
