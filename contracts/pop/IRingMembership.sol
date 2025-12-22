// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IRingMembership
/// @author Popme / DotNS
/// @notice Read-only interface for querying ring membership
/// @dev
///  This interface exposes a single membership predicate.
///  It is intended for consumption by Solidity contracts that need to
///  verify whether an opaque identifier is admitted to an attested ring.
///
///  The identifier is treated as a 32-byte opaque value and MUST NOT
///  be interpreted as an EVM address or decoded further.
/// @dev deployed on paseo: 0x856BA92204F44325cB196016115c15e7CF89bd4B
interface IRingMembership {
    /// @notice Determines whether an identifier is admitted to the ring
    /// @dev
    ///  Implementations MUST return `true` if and only if the identifier
    ///  has been explicitly admitted by the ring attester.
    ///
    ///  No guarantees are made regarding:
    ///   - Admission order
    ///   - Revocation timing
    ///   - Ring size or composition
    ///
    /// @param identifier The 32-byte opaque identifier to query
    /// @return isMember True if the identifier is part of the ring
    function isRingMember(bytes32 identifier) external view returns (bool isMember);
}
