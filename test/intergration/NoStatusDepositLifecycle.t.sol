// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {BaseDotns} from "../base/BaseDotns.t.sol";
import {IDotnsNameEscrow} from "../../contracts/escrow/IDotnsNameEscrow.sol";

/// @title NoStatusDepositLifecycle
/// @notice Integration coverage for the NoStatus refundable-deposit hurdle as it
///         binds to the original depositor across registration, NFT transfer,
///         cooldown elapse, and refund claim.
/// @dev Asserts the post-redesign rule: a NoStatus depositor's stake clears in
///      full the moment the NFT leaves their address and is routed through the
///      time-locked refund ledger, claimable by the depositor only after the
///      cooldown elapses. The recipient never inherits the deposit.
contract NoStatusDepositLifecycle is BaseDotns {
    /// @notice NoStatus label fixture (baselength >= 9 classifies as NoStatus).
    string internal constant DEPOSIT_LABEL = "depositname01";

    function test_NoStatus_register_then_transfer_then_claim_refund() public {
        address depositor = ed;
        address recipient = leonardo;

        uint256 ownerPrice = popRules.priceWithCheck(DEPOSIT_LABEL, depositor).price;
        assertEq(ownerPrice, RENT_PRICE, "NoStatus price baseline must match RENT_PRICE");

        // Register pays D = RENT_PRICE into the depositor's position.
        _commitAndRegister(DEPOSIT_LABEL, depositor, false);
        uint256 tokenId = _tokenIdForLabel(DEPOSIT_LABEL);

        IDotnsNameEscrow.ReleasePosition memory atMint = dotnsNameEscrow.getReleasePosition(tokenId);
        assertEq(atMint.amount, RENT_PRICE, "position must hold full RENT_PRICE deposit");
        assertEq(atMint.recipient, depositor, "position recipient must be the depositor");
        assertEq(
            dotnsNameEscrow.reserves(address(0)),
            RENT_PRICE,
            "tokenReserved must reflect the seeded deposit"
        );
        assertEq(
            dotnsNameEscrow.pendingRefundCount(depositor),
            0,
            "no refund must exist before the depositor-leaving transfer"
        );

        // Transfer the NFT away from the depositor with zero fee. NoStatus-to-NoStatus
        // transferFloor is zero, so msg.value == 0 must still route through escrow
        // because the deposit needs clearing.
        uint256 transferFee = dotnsRegistrar.quoteTransferFee(tokenId, recipient);
        assertEq(transferFee, 0, "NoStatus to NoStatus transfer floor is zero");

        vm.prank(depositor);
        dotnsRegistrar.transferFrom{value: 0}(depositor, recipient, tokenId);

        IDotnsNameEscrow.ReleasePosition memory afterTransfer =
            dotnsNameEscrow.getReleasePosition(tokenId);
        assertEq(afterTransfer.amount, 0, "deposit must clear when NFT leaves the depositor");
        assertEq(
            afterTransfer.recipient,
            address(0),
            "position must be deleted; recipient must not inherit"
        );
        assertEq(
            dotnsNameEscrow.reserves(address(0)),
            0,
            "tokenReserved must drop by the cleared deposit"
        );

        // The refund is credited to the original depositor, never the new owner.
        assertEq(
            dotnsNameEscrow.pendingRefundCount(depositor),
            1,
            "depositor must receive a single refund entry on the leaving leg"
        );
        assertEq(
            dotnsNameEscrow.pendingRefundCount(recipient),
            0,
            "recipient must never inherit the deposit"
        );
        assertEq(
            dotnsNameEscrow.pendingWithdrawal(depositor),
            0,
            "deposit refund routes through the time-locked refund ledger, not pendingWithdrawals"
        );

        // The entry is locked by the escrow cooldown; an early claim must revert.
        uint256[] memory entries = dotnsNameEscrow.pendingRefundIds(
            depositor, 0, dotnsNameEscrow.pendingRefundCount(depositor)
        );
        assertEq(entries.length, 1, "exactly one entry must be claimable");
        uint256 entryId = entries[0];

        IDotnsNameEscrow.RefundEntry memory entry = dotnsNameEscrow.refundEntry(entryId);
        assertEq(entry.recipient, depositor, "entry recipient must be the depositor");
        assertEq(entry.amount, RENT_PRICE, "entry amount must equal the full deposit");
        assertEq(entry.tokenId, tokenId, "entry must trace back to the transferred token");

        vm.prank(depositor);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDotnsNameEscrow.RefundLocked.selector, entryId, entry.availableAt
            )
        );
        dotnsNameEscrow.claimRefund(entryId);

        // Warp past the cooldown and pull the refund. The depositor's balance
        // must grow by exactly D.
        vm.warp(uint256(entry.availableAt) + 1);

        uint256 balanceBefore = depositor.balance;

        vm.prank(depositor);
        uint256 claimed = dotnsNameEscrow.claimRefund(entryId);

        assertEq(claimed, RENT_PRICE, "claim must return the full deposit");
        assertEq(
            depositor.balance - balanceBefore,
            RENT_PRICE,
            "depositor balance must increase by the full deposit"
        );
        assertEq(
            dotnsNameEscrow.pendingRefundCount(depositor),
            0,
            "claimed entry must be removed from the depositor's pending list"
        );
    }
}
