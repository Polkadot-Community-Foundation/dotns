// SPDX-License-Identifier: MIT
pragma solidity ~0.8.17;

import {IPriceOracle} from "./IPriceOracle.sol";

/// @title IStableOracle
/// @notice Oracle interface defining DotNS price calculation, PoP-tier requirements, and base-name reservation rules
/// @dev Provides the classification logic for DotNS labels, enforces suffix constraints, and exposes reservation metadata.
///      Names are evaluated according to the following rules:
///      • Length ≤ 5: Reserved
///      • Length 6–8 without trailing digits: PopFull required
///      • Length 6–8 with 1–2 trailing digits: PopLite required
///      • Length ≥ 9 without trailing digits: PopFull required
///      • Length ≥ 9 with 2 trailing digits: NoStatus (open)
///      Trailing digits beyond 2 are invalid. Internal digits do not affect classification.
///      Reservation rules apply to a label stripped of trailing digits.
interface IStableOracle is IPriceOracle {
    /// @notice Proof-of-Personhood eligibility tier
    /// @dev Defines verification requirements for a given name classification
    enum PopStatus {
        NoStatus,
        PopLite,
        PopFull,
        Reserved
    }

    /// @notice Emitted when a name is assigned a Proof-of-Personhood tier
    /// @param name The name label updated
    /// @param status The tier assigned to the name
    /// @param owner The owner of the name
    event NamePopStatusSet(string indexed name, PopStatus indexed status, address indexed owner);

    /// @notice Emitted when a base name receives a reservation
    /// @param baseName The digit-stripped label receiving reservation
    /// @param owner Address obtaining the reservation right
    /// @param expires Timestamp when the reservation expires
    event BaseNameReserved(string indexed baseName, address indexed owner, uint64 expires);

    /// @notice Emitted when the registry is updated
    /// @param oldReg Currently set registry address
    /// @param newReg New address to set
    event RegistryUpdated(address indexed oldReg, address indexed newReg);

    /// @notice Thrown when a name violates PoP-tier or reservation requirements
    /// @param reason Human-readable explanation of the failure condition
    error PopError(string reason);

    /// @notice Used to throw generic errors
    /// @param reason Human-readable explanation of the failure condition
    error GenericError(string reason);

    /// @notice Used when functions only allow the registry to make calls
    error NotRegistry();

    /// @notice Bundle returned from metadata-aware pricing queries
    /// @param price Base and premium values in wei
    /// @param status Required PoP tier for this name
    /// @param message Human-readable classification description
    struct PriceWithMeta {
        IPriceOracle.Price price;
        PopStatus status;
        string message;
    }

    /// @notice Reservation metadata for a base name (digits removed)
    /// @param owner Address holding exclusive claim rights during the reservation window
    /// @param expires UNIX timestamp when the reservation expires
    struct Reservation {
        address owner;
        uint64 expires;
    }

    /// @notice Assigns a PoP verification tier to a name
    /// @param name The name label
    /// @param status The tier being assigned
    /// @dev This is tied to the caller of this function such that when they register
    ///      The name we check if the names status was setup by them
    function setNamePopStatus(string calldata name, PopStatus status) external;

    /// @notice Returns the PoP verification tier assigned to a name
    /// @param name The name label
    /// @return The assigned PopStatus tier
    function getNamePopStatus(string calldata name) external view returns (PopStatus);

    /// @notice Classifies a name into a required PoP tier according to DotNS naming rules
    /// @param name The name label being evaluated
    /// @return requirement Required tier for registration
    /// @return message Explanation of classification result
    function classifyName(string calldata name)
        external
        pure
        returns (PopStatus requirement, string memory message);

    /// @notice Creates a reservation entry for the digit-stripped version of a name
    /// @param baseName The base label with trailing digits removed
    /// @param user The address receiving reservation rights
    /// @dev Can only be called by the registry
    function reserveBaseName(string calldata baseName, address user) external;

    /// @notice Retrieves reservation information for a base name
    /// @param baseName The base label without trailing digits
    /// @return owner The address assigned to the reservation
    /// @return expires UNIX timestamp when the reservation expires
    function getBaseNameReservation(string calldata baseName)
        external
        view
        returns (address owner, uint64 expires);

    /// @notice Indicates whether a base name is currently reserved
    /// @param baseName The base label without trailing digits
    /// @return reservedStatus True if a reservation is active
    /// @return owner The reservation holder
    /// @return expires The reservation expiry timestamp
    function isBaseNameReserved(string calldata baseName)
        external
        view
        returns (bool reservedStatus, address owner, uint64 expires);

    /// @notice Computes pricing and classification metadata while enforcing base-name reservation rules
    /// @param name The full name label (with or without suffix)
    /// @param expires Current expiry timestamp for the name
    /// @param duration Duration of requested registration
    /// @param user Address attempting to register
    /// @return meta A bundle containing pricing and classification metadata
    function priceWithCheck(
        string calldata name,
        uint256 expires,
        uint256 duration,
        address user
    )
        external
        view
        returns (PriceWithMeta memory meta);

    /// @notice allows the Owner to update the dot/eth registry
    /// @param ethReg the address of the new registry
    function updateEthRegistry(address ethReg) external;
}
