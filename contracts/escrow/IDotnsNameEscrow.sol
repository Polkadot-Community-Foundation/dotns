// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title Dotns Name Escrow Interface
/// @notice Escrows refundable deposits for .dot registrations and manages the release lifecycle.
/// @custom:security-contact admin@parity.io
interface IDotnsNameEscrow {
    /// @notice Parameters for recording a deposit position.
    /// @dev `recipient` is locked at deposit time and snapshotted into the position so the original
    ///      payer remains the only address that can ever pull a refund, regardless of subsequent
    ///      NFT transfers on the registrar.
    /// @param asset Deposit asset. `address(0)` denotes native token.
    /// @param recipient Refund recipient locked at deposit time.
    struct DepositParams {
        uint256 tokenId;
        address asset;
        uint256 amount;
        address recipient;
    }

    /// @notice Parameters for recording a cross-tier registration fee into the insurance fund.
    /// @dev Funds the shared insurance pool used by `withdraw` to top up refunds whose per-asset
    ///      reserve is short; `payer` is preserved purely for event accounting since the deposit
    ///      itself is non-refundable.
    /// @param payer Original `msg.sender` of the controller's `register` call.
    /// @param recipient The NFT registrant the fee was paid on behalf of.
    struct InsuranceDepositParams {
        uint256 tokenId;
        address payer;
        address recipient;
    }

    /// @notice Inputs for charging a cross-tier transfer fee.
    /// @dev The fee charged is `max(priceForTo - runningMax, reachFloor)`: the delta captures
    ///      cross-tier upgrades against the per-token watermark, while `reachFloor` enforces a
    ///      length-scaled friction floor whenever the recipient is below the label's required tier.
    /// @param priceForTo Recipient-tier price quoted from PopRules.
    /// @param reachFloor Length-scaled friction floor when the recipient is below the required tier.
    /// @param payer The original `msg.sender` of the registrar transfer entrypoint.
    /// @param to NFT recipient.
    struct ChargeTransferFeeParams {
        uint256 tokenId;
        uint256 priceForTo;
        uint256 reachFloor;
        address payer;
        address to;
    }

    /// @notice Canonical escrow state for a token.
    /// @dev Tracks the phased lifecycle as two flags: `released` flips on `release` (NFT in escrow,
    ///      cooldown started); `claimed` flips on `withdraw` (refund credited to the pull-payment
    ///      ledger). The position is deleted on `reclaim`, freeing the slot for re-registration.
    /// @param asset Deposit asset. `address(0)` denotes native token.
    /// @param withdrawAvailableAt Earliest timestamp at which withdrawal is permitted.
    struct ReleasePosition {
        address recipient;
        address asset;
        uint256 amount;
        uint64 withdrawAvailableAt;
        bool released;
        bool claimed;
    }

    /// @notice Emitted when a native-token deposit is recorded.
    event NativeDepositRecorded(uint256 indexed tokenId, uint256 amount);

    /// @notice Emitted when a token is released into escrow.
    /// @param recipient Refund recipient snapshotted at release time.
    /// @param asset Deposit asset. `address(0)` denotes native token.
    /// @param withdrawAvailableAt Earliest withdrawal timestamp.
    event NameReleased(
        uint256 indexed tokenId,
        address indexed recipient,
        address indexed asset,
        uint256 amount,
        uint256 withdrawAvailableAt
    );

    /// @notice Emitted when a refund is credited to the recipient's pending balance.
    /// @param asset Refund asset. `address(0)` denotes native token.
    event RefundWithdrawn(
        uint256 indexed tokenId, address indexed recipient, address indexed asset, uint256 amount
    );

    /// @notice Emitted when a recipient pulls their accumulated pending refund balance.
    event WithdrawalClaimed(address indexed recipient, uint256 amount);

    /// @notice Emitted when a released token is reclaimed by a new owner via registration.
    /// @param previousRecipient Address that received the refund for the prior registration.
    event NameReclaimed(
        uint256 indexed tokenId, address indexed previousRecipient, address indexed newOwner
    );

    /// @notice Emitted when the cooldown duration for future releases is updated.
    event CooldownUpdated(uint256 indexed currentCooldown, uint256 indexed newCooldown);

    /// @notice Emitted when a cross-tier fee is paid into the insurance fund.
    /// @param payer Original `msg.sender` whose value funded the fee.
    /// @param isRegistration True when emitted from `depositInsurance`; false from `chargeTransferFee`.
    event CrossTierFeePaid(
        uint256 indexed tokenId,
        address indexed payer,
        address indexed recipient,
        uint256 amount,
        bool isRegistration
    );

    /// @notice Emitted when a withdrawal draws from the insurance fund to cover a shortfall in `tokenReserved`.
    event InsuranceDraw(uint256 indexed tokenId, uint256 amount);

    /// @notice Emitted when overpayment is refunded to the payer.
    event OverpaymentRefunded(address indexed payer, uint256 amount);

    /// @notice Thrown when the caller is not the configured registrar controller.
    error NotController(address caller);

    /// @notice Thrown when the caller is not the configured registrar.
    error NotRegistrar(address caller);

    /// @notice Thrown when the supplied refund recipient is invalid (e.g. zero address).
    error InvalidRecipient();

    /// @notice Thrown when the attached call value is insufficient to cover the computed charge.
    error InsufficientValue();

    /// @notice Thrown when neither `tokenReserved` nor the insurance fund can cover the refund.
    /// @param available Combined balance available across reserves and insurance.
    error InsufficientFunds(uint256 tokenId, uint256 owed, uint256 available);

    /// @notice Thrown when assets being deposited are not supported by the escrow.
    error AssetNotSupported(address asset);

    /// @notice Thrown when the configured page size is invalid.
    error InvalidPageSize(uint256 limit);

    /// @notice Thrown when the configured cooldown is invalid.
    error InvalidCooldown();

    /// @notice Thrown when the supplied amount is invalid.
    error InvalidAmount();

    /// @notice Thrown when the supplied ERC20 asset is invalid.
    error InvalidAsset();

    /// @notice Thrown when a deposit position is already funded.
    error PositionAlreadyFunded(uint256 tokenId);

    /// @notice Thrown when no deposit is configured for the token.
    error DepositNotConfigured(uint256 tokenId);

    /// @notice Thrown when the token has already been released.
    error AlreadyReleased(uint256 tokenId);

    /// @notice Thrown when the token has not been released.
    error NotReleased(uint256 tokenId);

    /// @notice Thrown when the refund has already been claimed.
    error AlreadyClaimed(uint256 tokenId);

    /// @notice Thrown when a token is not in a reclaimable state (released + claimed).
    error NotReclaimable(uint256 tokenId);

    /// @notice Thrown when the caller is neither the token owner nor an approved operator.
    error NotTokenOwnerOrApproved(address caller, uint256 tokenId);

    /// @notice Thrown when escrow is not approved to transfer the token.
    error EscrowNotApproved(uint256 tokenId);

    /// @notice Thrown when the caller is not the refund recipient.
    error NotRefundRecipient(address caller, uint256 tokenId);

    /// @notice Thrown when withdrawal is attempted before cooldown has elapsed.
    /// @param availableAt Earliest withdrawal timestamp.
    /// @param currentTime Current block timestamp.
    error WithdrawalTooEarly(uint256 tokenId, uint256 availableAt, uint256 currentTime);

    /// @notice Thrown when a refund transfer fails.
    error RefundFailed(uint256 tokenId);

    /// @notice Thrown when `claimWithdrawal()` is called but the caller has no pending balance.
    error NoPendingWithdrawal();

    /// @notice Thrown when escrow receives an ERC721 transfer from a non-registrar source.
    error NotAcceptedTransfer(address caller);

    /// @notice Returns total amount of assets liabilities reserved for withdrawals.
    /// @param asset Asset address. `address(0)` denotes native token.
    function reserves(address asset) external view returns (uint256 amount);

    /// @notice Returns the escrow state for a token.
    function getReleasePosition(uint256 tokenId)
        external
        view
        returns (ReleasePosition memory position);

    /// @notice Returns the number of tokens currently held by escrow pending reclaim or withdrawal.
    /// @return count Number of released tokens not yet reclaimed.
    function releasedTokenCount() external view returns (uint256 count);

    /// @notice Returns a bounded paginated slice of released token identifiers.
    /// @param start Start index into the released-token set.
    /// @param limit Maximum number of token identifiers to return.
    /// @custom:reverts InvalidPageSize
    function releasedTokens(
        uint256 start,
        uint256 limit
    )
        external
        view
        returns (uint256[] memory tokenIds);

    /// @notice Records an asset deposit position for a token.
    /// @custom:emits NativeDepositRecorded
    /// @custom:reverts NotController
    /// @custom:reverts InvalidAmount
    /// @custom:reverts AssetNotSupported
    /// @custom:reverts InvalidRecipient
    /// @custom:reverts PositionAlreadyFunded
    /// @custom:reverts AlreadyReleased
    function deposit(DepositParams calldata params) external payable;

    /// @notice Records a cross-tier registration fee into the insurance fund.
    /// @custom:emits CrossTierFeePaid
    /// @custom:reverts NotController
    /// @custom:reverts InvalidAmount
    function depositInsurance(InsuranceDepositParams calldata params) external payable;

    /// @notice Charges the cross-tier transfer-fee delta against the running max for a token.
    /// @return charged Amount actually credited to insurance.
    /// @custom:emits CrossTierFeePaid
    /// @custom:emits OverpaymentRefunded
    /// @custom:reverts NotRegistrar
    /// @custom:reverts InsufficientValue
    /// @custom:reverts RefundFailed
    function chargeTransferFee(ChargeTransferFeeParams calldata params)
        external
        payable
        returns (uint256 charged);

    /// @notice Returns the cumulative cross-tier fee balance held against future shortfalls.
    /// @return balance Current insurance fund balance, in wei.
    function insuranceFund() external view returns (uint256 balance);

    /// @notice Returns the highest price ever charged for a token across registration and transfers.
    /// @dev Monotonically non-decreasing per token while a position is live; only `reclaim` resets it
    ///      so that a fresh registration starts from a clean baseline rather than inheriting the
    ///      previous owner's high-water mark.
    /// @return max The current running maximum, in wei.
    function runningMax(uint256 tokenId) external view returns (uint256 max);

    /// @notice Releases a token into escrow and starts the withdrawal cooldown.
    /// @dev First step of the phased lifecycle. Only the locked refund recipient can trigger this,
    ///      and the current NFT holder must have approved escrow, enforcing two-party cooperation
    ///      so a secondary-market buyer cannot release someone else's deposit.
    /// @custom:emits NameReleased
    /// @custom:reverts NotTokenOwnerOrApproved
    /// @custom:reverts DepositNotConfigured
    /// @custom:reverts AlreadyReleased
    /// @custom:reverts NotRefundRecipient
    /// @custom:reverts EscrowNotApproved
    function release(uint256 tokenId) external;

    /// @notice Credits the refundable deposit for a released token to the recipient's pending balance.
    /// @dev Second step of the phased lifecycle. Must be called after `withdrawAvailableAt` has
    ///      elapsed; draws from the per-asset `tokenReserved` pool first and falls back to the
    ///      shared insurance fund on shortfall. Funds are not transferred here, only credited to
    ///      the pull-payment ledger.
    /// @custom:emits RefundWithdrawn
    /// @custom:emits InsuranceDraw
    /// @custom:reverts NotReleased
    /// @custom:reverts AlreadyClaimed
    /// @custom:reverts NotRefundRecipient
    /// @custom:reverts WithdrawalTooEarly
    /// @custom:reverts InsufficientFunds
    function withdraw(uint256 tokenId) external;

    /// @notice Pulls the caller's accumulated pending refund balance.
    /// @dev Final step of the phased lifecycle. Pull-payment isolation: each recipient owns an
    ///      independent ledger entry, so a failing or reentrant receiver cannot block other users'
    ///      withdrawals.
    /// @return amount Native amount transferred to the caller.
    /// @custom:emits WithdrawalClaimed
    /// @custom:reverts NoPendingWithdrawal
    /// @custom:reverts RefundFailed
    function claimWithdrawal() external returns (uint256 amount);

    /// @notice Returns the pending refund balance owed to `recipient`.
    /// @return amount Native amount currently credited to `recipient` and pullable via `claimWithdrawal`.
    function pendingWithdrawal(address recipient) external view returns (uint256 amount);

    /// @notice Transfers a released-and-claimed token from escrow custody to a new owner.
    /// @dev Hands the NFT back to the controller for re-registration and clears `runningMax` so the
    ///      next registrant starts from a fresh price baseline rather than inheriting the previous
    ///      owner's transfer-fee high-water mark.
    /// @param newOwner Address of the new registrant taking over the name.
    /// @custom:emits NameReclaimed
    /// @custom:reverts NotController
    /// @custom:reverts NotReclaimable
    function reclaim(uint256 tokenId, address newOwner) external;

    /// @notice Updates the cooldown duration for future releases.
    /// @dev Affects only releases recorded after this call; positions already released keep the
    ///      `withdrawAvailableAt` snapshot taken at their release time.
    /// @custom:emits CooldownUpdated
    /// @custom:reverts InvalidCooldown
    function updateCooldown(uint256 newCooldown) external;
}
