// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IEscrow, Enums } from "./IEscrow.sol";

/// @title Fixed-Price Escrow Interface
/// @notice Interface for managing fixed-price escrow agreements within the system, focusing on defining common events
/// and errors.
/// Defines only the essential components such as errors, events, struct and key function signatures related to
/// fixed-price escrow operations.
interface IEscrowFixedPrice is IEscrow {
    /// @notice Represents input deposit payload for authorization in the escrow.
    /// @dev This struct is used as a parameter when submitting a deposit request.
    /// It includes additional metadata like expiration and signature for validation purposes.
    /// @param contractor The address of the contractor who will receive the deposit.
    /// @param paymentToken The address of the ERC20 token used for payment.
    /// @param amount The total amount being deposited.
    /// @param amountToClaim The amount that can be claimed by the contractor.
    /// @param amountToWithdraw The amount available for withdrawal by the contractor.
    /// @param contractorData A hash representing additional data related to the contractor.
    /// @param feeConfig Configuration specifying how fees are applied to the deposit.
    /// @param status The status of the deposit request before processing.
    /// @param escrow The explicit address of the escrow contract handling the deposit.
    /// @param expiration The timestamp specifying when the deposit request becomes invalid.
    /// @param signature A digital signature from an admin validating the deposit request.
    struct DepositRequest {
        address contractor;
        address paymentToken;
        uint256 amount;
        uint256 amountToClaim;
        uint256 amountToWithdraw;
        bytes32 contractorData;
        Enums.FeeConfig feeConfig;
        Enums.Status status;
        address escrow;
        uint256 expiration;
        bytes signature;
    }

    /// @notice Represents a storage for deposit details in the escrow.
    /// @dev This struct stores essential details about the deposit after it is processed.
    /// @param contractor The address of the contractor who will receive the deposit.
    /// @param paymentToken The address of the ERC20 token used for payment.
    /// @param amount The total amount deposited.
    /// @param amountToClaim The amount that the contractor is eligible to claim.
    /// @param amountToWithdraw The amount available for withdrawal by the contractor.
    /// @param contractorData A hash representing additional data related to the contractor.
    /// @param feeConfig Configuration specifying how fees are applied to the deposit.
    /// @param status The current status of the deposit.
    struct DepositInfo {
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
    /// @param depositor The address of the depositor.
    /// @param contractId The ID of the contract.
    /// @param totalDepositAmount The total amount deposited: principal + platform fee.
    /// @param contractor The address of the contractor.
    event Deposited(
        address indexed depositor, uint256 indexed contractId, uint256 totalDepositAmount, address indexed contractor
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

    /// @notice Emitted when a claim is made by the contractor.
    /// @param contractor The address of the contractor making the claim.
    /// @param contractId The ID of the contract associated with the claim.
    /// @param amount The net amount claimed by the contractor, after deducting fees.
    /// @param feeAmount The fee amount paid by the contractor for the claim.
    event Claimed(address indexed contractor, uint256 indexed contractId, uint256 amount, uint256 feeAmount);

    /// @notice Emitted when a withdrawal is made by a withdrawer.
    /// @param withdrawer The address of the withdrawer executing the withdrawal.
    /// @param contractId The ID of the contract associated with the withdrawal.
    /// @param amount The net amount withdrawn by the withdrawer, after deducting fees.
    /// @param feeAmount The fee amount paid by the withdrawer for the withdrawal, if applicable.
    event Withdrawn(address indexed withdrawer, uint256 indexed contractId, uint256 amount, uint256 feeAmount);

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
