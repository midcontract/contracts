// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IEscrow, Enums } from "./IEscrow.sol";

/// @title Milestone Escrow Interface
/// @notice Defines the contract interface necessary for managing milestone-based escrow agreements.
/// Focuses on the declaration of structs, events, errors, and essential function signatures to support milestone
/// operations within the escrow system.
interface IEscrowMilestone is IEscrow {
    /// @notice Thrown when no deposits are provided in a function call that expects at least one.
    error Escrow__NoDepositsProvided();

    /// @notice Thrown when too many deposit entries are provided, exceeding the allowed limit for a single
    /// transaction.
    error Escrow__TooManyMilestones();

    /// @notice Thrown when an invalid contract ID is provided to a function expecting a valid existing contract ID.
    error Escrow__InvalidContractId();

    /// @notice Thrown when an invalid milestone ID is provided to a function expecting a valid existing milestone
    /// ID.
    error Escrow__InvalidMilestoneId();

    /// @notice Thrown when the provided milestone limit is zero or exceeds the maximum allowed.
    error Escrow__InvalidMilestoneLimit();

    /// @notice Thrown when the provided milestonesHash does not match the computed hash of milestones.
    error Escrow__InvalidMilestonesHash();

    /// @notice Struct to encapsulate all parameters required for a milestone deposit.
    /// @param contractId ID of the contract, or zero to create a new contract.
    /// @param paymentToken Address of the payment token for deposits.
    /// @param milestonesHash Precomputed hash of milestones.
    /// @param escrow The explicit address of the escrow contract handling the deposit.
    /// @param expiration Timestamp indicating expiration of authorization.
    /// @param signature Signature authorizing the deposit request.
    struct DepositRequest {
        uint256 contractId;
        address paymentToken;
        bytes32 milestonesHash;
        address escrow;
        uint256 expiration;
        bytes signature;
    }

    /// @notice This struct stores details about individual milestones within an escrow contract.
    /// @param paymentToken The address of the token to be used for payments.
    /// @param depositAmount The initial deposit amount set aside for this milestone.
    /// @param winner The winner of any dispute related to this milestone, if applicable.
    struct MilestoneDetails {
        address paymentToken;
        uint256 depositAmount;
        Enums.Winner winner;
    }

    /// @notice Represents a milestone within an escrow contract.
    /// @param contractor The address of the contractor responsible for completing the milestone.
    /// @param amount The total amount allocated to the milestone.
    /// @param amountToClaim The amount available to the contractor upon completion of the milestone.
    /// @param amountToWithdraw The amount available for withdrawal if certain conditions are met.
    /// @param contractorData Data hash containing specific information about the contractor's obligations.
    /// @param feeConfig Configuration for any applicable fees associated with the milestone.
    /// @param status Current status of the milestone, tracking its lifecycle from creation to completion.
    struct Milestone {
        address contractor;
        uint256 amount;
        uint256 amountToClaim;
        uint256 amountToWithdraw;
        bytes32 contractorData;
        Enums.FeeConfig feeConfig;
        Enums.Status status;
    }

    /// @notice Represents input submission payload for authorization in the escrow.
    /// @dev This struct encapsulate submission parameters and prevent stack too deep errors.
    /// @param contractId ID of the deposit being submitted.
    /// @param milestoneId ID of the milestone to submit work for.
    /// @param data Contractor-specific data related to the submission.
    /// @param salt Unique salt value to prevent replay attacks.
    /// @param expiration Timestamp when the authorization expires.
    /// @param signature Signature from an admin (EOA) verifying the submission.
    struct SubmitRequest {
        uint256 contractId;
        uint256 milestoneId;
        bytes data;
        bytes32 salt;
        uint256 expiration;
        bytes signature;
    }

    /// @notice Emitted when a deposit is made.
    /// @param depositor The address of the depositor.
    /// @param contractId The ID of the contract.
    /// @param milestoneId The ID of the milestone.
    /// @param amount The amount deposited.
    /// @param contractor The address of the contractor.
    event Deposited(
        address indexed depositor,
        uint256 indexed contractId,
        uint256 milestoneId,
        uint256 amount,
        address indexed contractor
    );

    /// @notice Emitted when a submission is made.
    /// @param sender The address of the sender.
    /// @param contractId The ID of the contract.
    /// @param milestoneId The ID of the milestone.
    /// @param client The address of the client associated with the contract.
    event Submitted(address indexed sender, uint256 indexed contractId, uint256 milestoneId, address indexed client);

    /// @notice Emitted when an approval is made.
    /// @param approver The address of the approver.
    /// @param contractId The ID of the contract.
    /// @param milestoneId The ID of the milestone.
    /// @param amountApprove The approved amount.
    /// @param receiver The address of the receiver.
    event Approved(
        address indexed approver,
        uint256 indexed contractId,
        uint256 indexed milestoneId,
        uint256 amountApprove,
        address receiver
    );

    /// @notice Emitted when a contract is refilled.
    /// @param sender The address of the sender.
    /// @param contractId The ID of the contract.
    /// @param milestoneId The ID of the milestone.
    /// @param amountAdditional The additional amount added.
    event Refilled(
        address indexed sender, uint256 indexed contractId, uint256 indexed milestoneId, uint256 amountAdditional
    );

    /// @notice Emitted when a claim is made.
    /// @param contractor The address of the contractor.
    /// @param contractId The ID of the contract.
    /// @param milestoneId The ID of the milestone.
    /// @param amount The net amount claimed by the contractor, after deducting fees.
    /// @param feeAmount The fee amount paid by the contractor for the claim.
    /// @param client The address of the client associated with the contract.
    event Claimed(
        address indexed contractor,
        uint256 indexed contractId,
        uint256 milestoneId,
        uint256 amount,
        uint256 feeAmount,
        address indexed client
    );

    /// @notice Emitted when a contractor claims amounts from multiple milestones in one transaction.
    /// @param contractor The address of the contractor who performed the bulk claim.
    /// @param contractId The identifier of the contract within which the bulk claim was made.
    /// @param startMilestoneId The starting milestone ID of the range within which the claims were made.
    /// @param endMilestoneId The ending milestone ID of the range within which the claims were made.
    /// @param totalClaimedAmount The total amount claimed across all milestones in the specified range.
    /// @param totalFeeAmount The total fee amount deducted during the bulk claim process.
    /// @param totalClientFee The total client fee amount deducted, if applicable, during the bulk claim process.
    /// @param client The address of the client associated with the contract.
    event BulkClaimed(
        address indexed contractor,
        uint256 indexed contractId,
        uint256 startMilestoneId,
        uint256 endMilestoneId,
        uint256 totalClaimedAmount,
        uint256 totalFeeAmount,
        uint256 totalClientFee,
        address indexed client
    );

    /// @notice Emitted when a withdrawal is made.
    /// @param withdrawer The address of the withdrawer.
    /// @param contractId The ID of the contract.
    /// @param milestoneId The ID of the milestone.
    /// @param amount The net amount withdrawn, after deducting fees.
    /// @param feeAmount The fee amount paid by the withdrawer for the withdrawal, if applicable.
    event Withdrawn(
        address indexed withdrawer,
        uint256 indexed contractId,
        uint256 indexed milestoneId,
        uint256 amount,
        uint256 feeAmount
    );

    /// @notice Emitted when a return is requested.
    /// @param sender The address of the sender.
    /// @param contractId The ID of the contract.
    /// @param milestoneId The ID of the milestone.
    event ReturnRequested(address indexed sender, uint256 indexed contractId, uint256 indexed milestoneId);

    /// @notice Emitted when a return is approved.
    /// @param approver The address of the approver.
    /// @param contractId The ID of the contract.
    /// @param milestoneId The ID of the milestone.
    /// @param client The address of the client associated with the contract.
    event ReturnApproved(
        address indexed approver, uint256 indexed contractId, uint256 milestoneId, address indexed client
    );

    /// @notice Emitted when a return is canceled.
    /// @param sender The address of the sender.
    /// @param contractId The ID of the contract.
    /// @param milestoneId The ID of the milestone.
    event ReturnCanceled(address indexed sender, uint256 indexed contractId, uint256 indexed milestoneId);

    /// @notice Emitted when a dispute is created.
    /// @param sender The address of the sender.
    /// @param contractId The ID of the contract.
    /// @param milestoneId The ID of the milestone.
    /// @param client The address of the client associated with the contract.
    event DisputeCreated(
        address indexed sender, uint256 indexed contractId, uint256 milestoneId, address indexed client
    );

    /// @notice Emitted when a dispute is resolved.
    /// @param approver The address of the approver.
    /// @param contractId The ID of the contract.
    /// @param milestoneId The ID of the milestone.
    /// @param winner The winner of the dispute.
    /// @param clientAmount The amount awarded to the client.
    /// @param contractorAmount The amount awarded to the contractor.
    /// @param client The address of the client associated with the contract.
    event DisputeResolved(
        address indexed approver,
        uint256 indexed contractId,
        uint256 milestoneId,
        Enums.Winner winner,
        uint256 clientAmount,
        uint256 contractorAmount,
        address indexed client
    );

    /// @notice Emitted when the ownership of a contractor account is transferred to a new owner.
    /// @param contractId The identifier of the contract for which contractor ownership is being transferred.
    /// @param milestoneId The identifier of the milestone for which contractor ownership is being transferred.
    /// @param previousOwner The previous owner of the contractor account.
    /// @param newOwner The new owner of the contractor account.
    event ContractorOwnershipTransferred(
        uint256 indexed contractId, uint256 indexed milestoneId, address previousOwner, address indexed newOwner
    );

    /// @notice Emitted when the maximum number of milestones per transaction is updated.
    /// @param maxMilestones The new maximum number of milestones that can be processed in a single transaction.
    event MaxMilestonesSet(uint256 maxMilestones);

    /// @notice Retrieves the total number of milestones associated with a specific contract ID.
    /// @dev Provides the length of the milestones array for the specified contract.
    /// @param contractId The ID of the contract for which milestone count is requested.
    /// @return milestoneCount The number of milestones linked to the specified contract ID.
    function getMilestoneCount(uint256 contractId) external view returns (uint256);

    /// @notice Interface declaration for transferring contractor ownership.
    /// @param contractId The identifier of the contract for which contractor ownership is being transferred.
    /// @param milestoneId The identifier of the milestone for which contractor ownership is being transferred.
    /// @param newOwner The address to which the contractor ownership will be transferred.
    function transferContractorOwnership(uint256 contractId, uint256 milestoneId, address newOwner) external;
}
