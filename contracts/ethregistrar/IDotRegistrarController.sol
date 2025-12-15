// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IStableOracle} from "./IStableOracle.sol";

/// @title DotNS Registrar Controller Interface
/// @custom:todo Rename for to align with naming convention in project
/// @notice Interface for commit-reveal registration with pricing and reverse records
/// @dev Implements two-step registration to prevent frontrunning
interface IDotRegistrarController {
    /// @notice Registration parameters for commit-reveal pattern
    /// @param label Domain label (e.g., "alice" for alice.dot)
    /// @param owner Address to receive the registration
    /// @param duration Registration period in seconds
    /// @param resolver Resolver contract address (zero for none)
    /// @param secret Commitment secret for commit-reveal
    /// @param data Multicall data for resolver initialization
    /// @param reverseRecord Bitmask for reverse record configuration
    /// @param referrer Referral tracking identifier
    struct Registration {
        string label;
        address owner;
        uint256 duration;
        address resolver;
        bytes32 secret;
        bytes[] data;
        uint8 reverseRecord;
        bytes32 referrer;
    }
    /// @notice Emitted when a name is registered.
    ///
    /// @param label The label of the name.
    /// @param labelhash The keccak256 hash of the label.
    /// @param owner The owner of the name.
    /// @param baseCost The base cost of the name.
    /// @param premium The premium cost of the name.
    /// @param expires The expiry time of the name.
    /// @param referrer The referrer of the registration.

    event NameRegistered(
        string label,
        bytes32 indexed labelhash,
        address indexed owner,
        uint256 baseCost,
        uint256 premium,
        uint256 expires,
        bytes32 referrer
    );

    /// @notice Emitted when a name is renewed.
    ///
    /// @param label The label of the name.
    /// @param labelhash The keccak256 hash of the label.
    /// @param cost The cost of the name.
    /// @param expires The expiry time of the name.
    /// @param referrer The referrer of the registration.
    event NameRenewed(
        string label, bytes32 indexed labelhash, uint256 cost, uint256 expires, bytes32 referrer
    );

    /// @notice Thrown when a refund fails
    error RefundFailed();

    /// @notice Thrown when a withdrawal fails
    /// @dev Usually by admin
    error WithdrawalFailed();

    /// @notice Thrown when commitment is not found
    error CommitmentNotFound(bytes32 commitment);

    /// @notice Thrown when commitment is too new
    error CommitmentTooNew(
        bytes32 commitment, uint256 minimumCommitmentTimestamp, uint256 currentTimestamp
    );

    /// @notice Thrown when commitment is too old
    error CommitmentTooOld(
        bytes32 commitment, uint256 maximumCommitmentTimestamp, uint256 currentTimestamp
    );

    /// @notice Thrown when name is unavailable
    error NameNotAvailable(string label);

    /// @notice Thrown when duration is too short
    error DurationTooShort(uint256 duration);

    /// @notice Thrown when resolver is required but not provided
    error ResolverRequiredWhenDataSupplied();

    /// @notice Thrown when resolver is required for reverse record
    error ResolverRequiredForReverseRecord();

    /// @notice Thrown when unexpired commitment exists
    error UnexpiredCommitmentExists(bytes32 commitment);

    /// @notice Thrown when payment is insufficient
    error InsufficientValue();

    /// @notice Thrown when max commitment age is invalid
    error MaxCommitmentAgeTooLow();

    /// @notice Thrown when max commitment age is invalid
    error MaxCommitmentAgeTooHigh();

    /// @notice Calculates registration price for a label
    /// @param label Domain label to price
    /// @param duration Registration period in seconds
    /// @return price Pricing breakdown (base + premium)
    function rentPrice(
        string calldata label,
        uint256 duration
    )
        external
        view
        returns (IStableOracle.Price memory price);

    /// @notice Checks if a label is available for registration
    /// @param label Domain label to check
    /// @return isAvailable True if label can be registered
    function available(string calldata label) external view returns (bool isAvailable);

    /// @notice Creates commitment for a registration
    /// @param registration Registration parameters
    /// @return commitment Keccak256 hash of registration data
    function makeCommitment(Registration calldata registration)
        external
        pure
        returns (bytes32 commitment);

    /// @notice Submits commitment for a registration
    /// @param commitment Commitment hash from makeCommitment
    function commit(bytes32 commitment) external;

    /// @notice Executes registration after commitment period
    /// @param registration Registration parameters (must match commitment)
    function register(Registration calldata registration) external payable;

    /// @notice Extends registration period for an existing name
    /// @param label Domain label to renew
    /// @param duration Additional time in seconds
    /// @param referrer Referral tracking identifier
    function renew(string calldata label, uint256 duration, bytes32 referrer) external payable;

    /// @notice Checks whether a given domain label is valid according to the controller's rules.
    /// @dev This function only checks syntactic validity (e.g., length or character constraints)
    ///      and does not check availability or registration status.
    ///      The function is `pure` because it does not read or modify contract state.
    /// @param label The domain label to validate (e.g., `"alice"` for `alice.dot`).
    /// @return isValid Returns `true` if the label meets the controller's validity rules, `false` otherwise.
    function valid(string calldata label) external pure returns (bool isValid);

    ///@notice Allows owner to withdraw any funds in the contract
    function withdraw() external;
}
