// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEscrow, Enums} from "./IEscrow.sol";

/// @title EscrowHourly Interface
/// @notice Interface for the Escrow Hourly contract that handles deposits, withdrawals, and disputes.
interface IEscrowHourly is IEscrow {
    /// @notice Error for when no deposits are provided in a function call that expects at least one.
    error Escrow__NoDepositsProvided();

    /// @notice Error for when an invalid contract ID is provided to a function expecting a valid existing contract ID.
    error Escrow__InvalidContractId();

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
    /// @param amount The amount to be TBC.
    /// @param amountToClaim The amount to be claimed.
    /// @param amountToWithdraw The amount to be withdrawn.
    /// @param feeConfig The fee configuration.
    struct Deposit {
        address contractor;
        uint256 amount;
        uint256 amountToClaim;
        Enums.FeeConfig feeConfig;
    }

    /// @notice Emitted when a deposit is made.
    /// @param sender The address of the sender.
    /// @param contractId The ID of the contract.
    /// @param weekId The ID of the week.
    /// @param paymentToken The address of the payment token.
    /// @param prepaymentAmount The amount deposited.
    // /// @param feeConfig The fee configuration.
    event Deposited(
        address indexed sender,
        uint256 indexed contractId,
        uint256 weekId,
        address paymentToken,
        uint256 prepaymentAmount
    );

    // /// @notice Emitted when a submission is made.
    // /// @param sender The address of the sender.
    // /// @param contractId The ID of the contract.
    // /// @param weekId The ID of the week.
    // event Submitted(address indexed sender, uint256 indexed weekId, uint256 indexed contractId);

    /// @notice Emitted when an approval is made.
    /// @param contractId The ID of the contract.
    /// @param weekId The ID of the week.
    /// @param amountApprove The approved amount.
    /// @param receiver The address of the receiver.
    event Approved(uint256 indexed contractId, uint256 indexed weekId, uint256 amountApprove, address receiver);

    /// @notice Emitted when a contract is refilled.
    /// @param contractId The ID of the contract.
    /// @param weekId The ID of the week.
    /// @param amountAdditional The additional amount added.
    event Refilled(uint256 indexed contractId, uint256 indexed weekId, uint256 indexed amountAdditional);

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

    // /// @notice Emitted when a dispute is created.
    // /// @param contractId The ID of the contract.
    // /// @param weekId The ID of the week.
    // /// @param sender The address of the sender.
    // event DisputeCreated(uint256 contractId, uint256 weekId, address sender);

    // /// @notice Emitted when a dispute is resolved.
    // /// @param contractId The ID of the contract.
    // /// @param weekId The ID of the week.
    // /// @param winner The winner of the dispute.
    // /// @param clientAmount The amount awarded to the client.
    // /// @param contractorAmount The amount awarded to the contractor.
    // event DisputeResolved(
    //     uint256 contractId, uint256 weekId, Enums.Winner winner, uint256 clientAmount, uint256 contractorAmount
    // );
}
