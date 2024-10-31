// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IEscrow, Enums } from "./IEscrow.sol";

/// @title Hourly Escrow Interface
/// @notice Interface for managing hourly-based escrow agreements.
/// Focuses on the declaration of structs, events, errors, and essential function signatures to support hourly-based
/// operations within the escrow system.
interface IEscrowHourly is IEscrow {
    /// @notice Thrown when no deposits are provided in a function call that expects at least one.
    error Escrow__NoDepositsProvided();

    /// @notice Thrown when an invalid contract ID is provided to a function expecting a valid existing contract ID.
    error Escrow__InvalidContractId();

    /// @notice Thrown when an invalid week ID is provided to a function expecting a valid week ID within range.
    error Escrow__InvalidWeekId();

    /// @notice Thrown when the available prepayment amount is insufficient to cover the requested operation.
    error Escrow__InsufficientPrepayment();

    /// @notice Represents the payload for initializing or adding to a deposit within a contract.
    /// @param contractor The address of the contractor responsible for the work.
    /// @param paymentToken The address of the payment token used for the deposit.
    /// @param prepaymentAmount The amount paid upfront for the contract.
    /// @param amountToClaim The amount that can be claimed by the contractor upon completion.
    /// @param feeConfig Configuration setting that determines how fees are handled within the deposit.
    struct Deposit {
        address contractor;
        address paymentToken;
        uint256 prepaymentAmount;
        uint256 amountToClaim;
        Enums.FeeConfig feeConfig;
    }

    /// @notice Holds detailed information about a contract's settings and status.
    /// @param contractor The address of the contractor assigned to the contract.
    /// @param paymentToken The token used for financial transactions within the contract.
    /// @param prepaymentAmount The total amount prepaid by the client, setting the financial basis for the contract.
    /// @param amountToWithdraw The total amount available for withdrawal post-completion or approval.
    /// @param feeConfig The fee configuration, dictating how fees are calculated and allocated.
    /// @param status The current status of the contract, indicating its phase within the lifecycle.
    struct ContractDetails {
        address contractor;
        address paymentToken;
        uint256 prepaymentAmount;
        uint256 amountToWithdraw;
        Enums.FeeConfig feeConfig;
        Enums.Status status;
    }

    /// @notice Represents the claim details and status for a weekly billing cycle in an escrow contract.
    /// @param amountToClaim Amount set for the contractor to claim upon completion of weekly tasks.
    /// @param weekStatus Operational status of the week, indicating claim readiness or dispute status.
    struct WeeklyEntry {
        uint256 amountToClaim;
        Enums.Status weekStatus;
    }

    /// @notice Emitted when a deposit is made.
    /// @param sender The address of the sender.
    /// @param contractId The ID of the contract.
    /// @param weekId The ID of the week.
    /// @param paymentToken The address of the payment token.
    /// @param totalDepositAmount The total amount deposited: principal + platform fee.
    event Deposited(
        address indexed sender,
        uint256 indexed contractId,
        uint256 weekId,
        address paymentToken,
        uint256 totalDepositAmount
    );

    /// @notice Emitted when an approval is made.
    /// @param approver The address of the approver.
    /// @param contractId The ID of the contract.
    /// @param weekId The ID of the week.
    /// @param amountApprove The approved amount.
    /// @param receiver The address of the receiver.
    event Approved(
        address indexed approver, uint256 indexed contractId, uint256 weekId, uint256 amountApprove, address receiver
    );

    /// @notice Emitted when the prepayment for a contract is refilled.
    /// @param sender The address of the sender.
    /// @param contractId The ID of the contract.
    /// @param amount The additional amount added.
    event RefilledPrepayment(address indexed sender, uint256 indexed contractId, uint256 amount);

    /// @notice Emitted when a contract is refilled.
    /// @param sender The address of the sender.
    /// @param contractId The ID of the contract.
    /// @param weekId The ID of the week.
    /// @param amount The additional amount added.
    event RefilledWeekPayment(address indexed sender, uint256 indexed contractId, uint256 weekId, uint256 amount);

    /// @notice Emitted when a claim is made.
    /// @param contractor The address of the contractor.
    /// @param contractId The ID of the contract.
    /// @param weekId The ID of the week.
    /// @param amount The claimed amount.
    event Claimed(address indexed contractor, uint256 indexed contractId, uint256 weekId, uint256 amount);

    /// @notice Emitted when a contractor claims amounts from multiple weeks in one transaction.
    /// @param contractor The address of the contractor who performed the bulk claim.
    /// @param contractId The identifier of the contract within which the bulk claim was made.
    /// @param startWeekId The starting week ID of the range within which the claims were made.
    /// @param endWeekId The ending week ID of the range within which the claims were made.
    /// @param totalClaimedAmount The total amount claimed across all weeks in the specified range.
    /// @param totalFeeAmount The total fee amount deducted from the claims.
    /// @param totalClientFee The total additional fee paid by the client related to the claims.
    event BulkClaimed(
        address indexed contractor,
        uint256 indexed contractId,
        uint256 startWeekId,
        uint256 endWeekId,
        uint256 totalClaimedAmount,
        uint256 totalFeeAmount,
        uint256 totalClientFee
    );

    /// @notice Emitted when a withdrawal is made.
    /// @param withdrawer The address of the withdrawer.
    /// @param contractId The ID of the contract.
    /// @param amount The amount withdrawn.
    event Withdrawn(address indexed withdrawer, uint256 indexed contractId, uint256 amount);

    /// @notice Emitted when a return is requested.
    /// @dev Currently focuses on the return of prepayment amounts but includes a `weekId` for potential future use
    /// where returns might be processed on a week-by-week basis.
    /// @param sender The address of the sender.
    /// @param contractId The ID of the contract.
    event ReturnRequested(address indexed sender, uint256 indexed contractId);

    /// @notice Emitted when a return is approved.
    /// @param approver The address of the approver.
    /// @param contractId The ID of the contract.
    event ReturnApproved(address indexed approver, uint256 indexed contractId);

    /// @notice Emitted when a return is canceled.
    /// @param sender The address of the sender.
    /// @param contractId The ID of the contract.
    event ReturnCanceled(address indexed sender, uint256 indexed contractId);

    /// @notice Emitted when a dispute is created.
    /// @param sender The address of the sender.
    /// @param contractId The ID of the contract.
    /// @param weekId The ID of the week.
    /// @param sender The address of the sender.
    event DisputeCreated(address indexed sender, uint256 indexed contractId, uint256 weekId);

    /// @notice Emitted when a dispute is resolved.
    /// @param approver The address of the approver.
    /// @param contractId The ID of the contract.
    /// @param weekId The ID of the week.
    /// @param winner The winner of the dispute.
    /// @param clientAmount The amount awarded to the client.
    /// @param contractorAmount The amount awarded to the contractor.
    event DisputeResolved(
        address indexed approver,
        uint256 indexed contractId,
        uint256 weekId,
        Enums.Winner winner,
        uint256 clientAmount,
        uint256 contractorAmount
    );

    /// @notice Emitted when the ownership of a contractor account is transferred to a new owner.
    /// @param contractId The identifier of the contract for which contractor ownership is being transferred.
    /// @param previousOwner The previous owner of the contractor account.
    /// @param newOwner The new owner of the contractor account.
    event ContractorOwnershipTransferred(
        uint256 indexed contractId, address indexed previousOwner, address indexed newOwner
    );

    /// @notice Interface declaration for transferring contractor ownership.
    /// @param contractId The identifier of the contract for which contractor ownership is being transferred.
    /// @param newOwner The address to which the contractor ownership will be transferred.
    function transferContractorOwnership(uint256 contractId, address newOwner) external;
}
