// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEscrow, Enums} from "./IEscrow.sol";

/// @title EscrowHourly Interface
/// @notice Interface for the Escrow Hourly contract that handles deposits, withdrawals, and disputes.
interface IEscrowHourly is IEscrow {
    /// @notice Thrown when no deposits are provided in a function call that expects at least one.
    error Escrow__NoDepositsProvided();

    /// @notice Thrown when an invalid contract ID is provided to a function expecting a valid existing contract ID.
    error Escrow__InvalidContractId();

    /// @notice Thrown when an invalid week ID is provided to a function expecting a valid week ID within range.
    error Escrow__InvalidWeekId();

    /// @notice Thrown when the available prepayment amount is insufficient to cover the requested operation.
    error Escrow__InsufficientPrepayment();

    /// @param paymentToken The address of the payment token.
    /// @param prepaymentAmount The prepayment amount for the week.
    /// @param status The status of the deposit.
    struct ContractDetails {
        address paymentToken;
        uint256 prepaymentAmount;
        Enums.Status status;
    }

    /// @notice Represents a deposit in the escrow.
    /// @param contractor The address of the contractor.
    /// @param amountToClaim The amount to be claimed.
    /// @param amountToWithdraw The amount to be withdrawn.
    /// @param feeConfig The fee configuration.
    struct Deposit {
        address contractor;
        uint256 amountToClaim;
        uint256 amountToWithdraw;
        Enums.FeeConfig feeConfig;
    }

    /// @notice Emitted when a deposit is made.
    /// @param sender The address of the sender.
    /// @param contractId The ID of the contract.
    /// @param weekId The ID of the week.
    /// @param paymentToken The address of the payment token.
    /// @param totalDepositAmount The total amount deposited: principal + platform fee.
    // /// @param feeConfig The fee configuration.
    event Deposited(
        address indexed sender,
        uint256 indexed contractId,
        uint256 weekId,
        address paymentToken,
        uint256 totalDepositAmount
    );

    /// @notice Emitted when an approval is made.
    /// @param contractId The ID of the contract.
    /// @param weekId The ID of the week.
    /// @param amountApprove The approved amount.
    /// @param receiver The address of the receiver.
    event Approved(uint256 indexed contractId, uint256 indexed weekId, uint256 amountApprove, address receiver);

    /// @notice Emitted when the prepayment for a contract is refilled.
    /// @param contractId The ID of the contract.
    /// @param amount The additional amount added.
    event RefilledPrepayment(uint256 indexed contractId, uint256 amount);

    /// @notice Emitted when a contract is refilled.
    /// @param contractId The ID of the contract.
    /// @param weekId The ID of the week.
    /// @param amount The additional amount added.
    event RefilledWeekPayment(uint256 indexed contractId, uint256 indexed weekId, uint256 amount);

    /// @notice Emitted when a claim is made.
    /// @param contractId The ID of the contract.
    /// @param weekId The ID of the week.
    /// @param amount The claimed amount.
    event Claimed(uint256 indexed contractId, uint256 indexed weekId, uint256 indexed amount);

    /// @notice Emitted when a withdrawal is made.
    /// @param contractId The ID of the contract.
    /// @param weekId The ID of the week.
    /// @param amount The amount withdrawn.
    event Withdrawn(uint256 indexed contractId, uint256 indexed weekId, uint256 amount);

    // TODO Return Request for the PrepaymenAmount not weekId

    /// @notice Emitted when a return is requested.
    /// @param contractId The ID of the contract.
    /// @param weekId The ID of the week.
    event ReturnRequested(uint256 contractId, uint256 weekId);

    /// @notice Emitted when a return is approved.
    /// @param contractId The ID of the contract.
    /// @param weekId The ID of the week.
    /// @param sender The address of the sender.
    event ReturnApproved(uint256 contractId, uint256 weekId, address sender);

    /// @notice Emitted when a return is canceled.
    /// @param contractId The ID of the contract.
    /// @param weekId The ID of the week.
    event ReturnCanceled(uint256 contractId, uint256 weekId);

    /// @notice Emitted when a dispute is created.
    /// @param contractId The ID of the contract.
    /// @param weekId The ID of the week.
    /// @param sender The address of the sender.
    event DisputeCreated(uint256 contractId, uint256 weekId, address sender);

    /// @notice Emitted when a dispute is resolved.
    /// @param contractId The ID of the contract.
    /// @param weekId The ID of the week.
    /// @param winner The winner of the dispute.
    /// @param clientAmount The amount awarded to the client.
    /// @param contractorAmount The amount awarded to the contractor.
    event DisputeResolved(
        uint256 contractId, uint256 weekId, Enums.Winner winner, uint256 clientAmount, uint256 contractorAmount
    );

    /// @notice Emitted when the ownership of a contractor account is transferred to a new owner.
    /// @param contractId The identifier of the contract for which contractor ownership is being transferred.
    /// @param previousOwner The previous owner of the contractor account.
    /// @param newOwner The new owner of the contractor account.
    event ContractorOwnershipTransferred(uint256 contractId, address indexed previousOwner, address indexed newOwner);

    /// @notice Interface declaration for transferring contractor ownership.
    /// @param contractId The identifier of the contract for which contractor ownership is being transferred.
    /// @param newOwner The address to which the contractor ownership will be transferred.
    function transferContractorOwnership(uint256 contractId, address newOwner) external;
}
