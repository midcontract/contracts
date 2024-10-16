// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IEscrow, Enums } from "./IEscrow.sol";

/// @title Fixed-Price Escrow Interface
/// @notice Interface for managing fixed-price escrow agreements within the system, focusing on defining common events and errors.
/// Defines only the essential components such as errors, events, struct and key function signatures related to fixed-price escrow operations.
interface IEscrowFixedPrice is IEscrow {
    /// @notice Represents a deposit in the escrow.
    /// @param contractor The address of the contractor.
    /// @param paymentToken The address of the payment token.
    /// @param amount The amount deposited.
    /// @param amountToClaim The amount to be claimed.
    /// @param amountToWithdraw The amount to be withdrawn.
    /// @param contractorData The contractor's data hash.
    /// @param feeConfig The fee configuration.
    /// @param status The status of the deposit.
    struct Deposit {
        address contractor;
        address paymentToken;
        uint256 amount;
        uint256 amountToClaim;
        uint256 amountToWithdraw;
        bytes32 contractorData;
        Enums.FeeConfig feeConfig;
        Enums.Status status;
    }

    /// @notice Emitted when a deposit is made.
    /// @param sender The address of the sender.
    /// @param contractId The ID of the contract.
    /// @param paymentToken The address of the payment token.
    /// @param amount The amount deposited.
    /// @param feeConfig The fee configuration.
    event Deposited(
        address indexed sender,
        uint256 indexed contractId,
        address paymentToken,
        uint256 amount,
        Enums.FeeConfig feeConfig
    );

    /// @notice Emitted when a submission is made.
    /// @param sender The address of the sender.
    /// @param contractId The ID of the contract.
    event Submitted(address indexed sender, uint256 indexed contractId);

    /// @notice Emitted when an approval is made.
    /// @param approver The address of the approver.
    /// @param contractId The ID of the contract.
    /// @param amountApprove The approved amount.
    /// @param receiver The address of the receiver.
    event Approved(
        address indexed approver, uint256 indexed contractId, uint256 amountApprove, address indexed receiver
    );

    /// @notice Emitted when a contract is refilled.
    /// @param sender The address of the sender.
    /// @param contractId The ID of the contract.
    /// @param amountAdditional The additional amount added.
    event Refilled(address indexed sender, uint256 indexed contractId, uint256 amountAdditional);

    /// @notice Emitted when a claim is made.
    /// @param contractor The address of the contractor.
    /// @param contractId The ID of the contract.
    /// @param paymentToken The address of the payment token.
    /// @param amount The claimed amount.
    event Claimed(address indexed contractor, uint256 indexed contractId, address paymentToken, uint256 amount);

    /// @notice Emitted when a withdrawal is made.
    /// @param withdrawer The address of the withdrawer.
    /// @param contractId The ID of the contract.
    /// @param paymentToken The address of the payment token.
    /// @param amount The amount withdrawn.
    event Withdrawn(address indexed withdrawer, uint256 indexed contractId, address paymentToken, uint256 amount);

    /// @notice Emitted when a return is requested.
    /// @param sender The address of the sender.
    /// @param contractId The ID of the contract.
    event ReturnRequested(address indexed sender, uint256 contractId);

    /// @notice Emitted when a return is approved.
    /// @param approver The address of the approver.
    /// @param contractId The ID of the contract.
    event ReturnApproved(address indexed approver, uint256 contractId);

    /// @notice Emitted when a return is canceled.
    /// @param sender The address of the sender.
    /// @param contractId The ID of the contract.
    event ReturnCanceled(address indexed sender, uint256 contractId);

    /// @notice Emitted when a dispute is created.
    /// @param sender The address of the sender.
    /// @param contractId The ID of the contract.
    event DisputeCreated(address indexed sender, uint256 contractId);

    /// @notice Emitted when a dispute is resolved.
    /// @param approver The address of the approver.
    /// @param contractId The ID of the contract.
    /// @param winner The winner of the dispute.
    /// @param clientAmount The amount awarded to the client.
    /// @param contractorAmount The amount awarded to the contractor.
    event DisputeResolved(
        address indexed approver,
        uint256 contractId,
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
