// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IEscrow, Enums } from "./IEscrow.sol";

/// @title EscrowMilestone Interface
/// @notice Interface for the Escrow Milestone contract that handles deposits, withdrawals, and disputes.
interface IEscrowMilestone is IEscrow {
    /// @notice Error for when no deposits are provided in a function call that expects at least one.
    error Escrow__NoDepositsProvided();

    /// @notice Error for when too many deposit entries are provided, exceeding the allowed limit for a single transaction.
    error Escrow__TooManyDeposits();

    /// @notice Error for when an invalid contract ID is provided to a function expecting a valid existing contract ID.
    error Escrow__InvalidContractId();

    /// @notice This struct stores details about individual milestones within an escrow contract.
    /// @param paymentToken The address of the token to be used for payments.
    /// @param depositAmount The initial deposit amount set aside for this milestone.
    /// @param winner The winner of any dispute related to this milestone, if applicable.
    struct MilestoneDetails {
        address paymentToken;
        uint256 depositAmount;
        Enums.Winner winner;
    }

    /// @notice Represents a deposit in the escrow.
    /// @param contractor The address of the contractor.
    /// @param amount The amount deposited.
    /// @param amountToClaim The amount to be claimed.
    /// @param amountToWithdraw The amount to be withdrawn.
    /// @param contractorData The contractor's data hash.
    /// @param feeConfig The fee configuration.
    /// @param status The status of the deposit.
    struct Deposit {
        address contractor;
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
    /// @param milestoneId The ID of the milestone.
    /// @param paymentToken The address of the payment token.
    /// @param amount The amount deposited.
    /// @param feeConfig The fee configuration.
    event Deposited(
        address indexed sender,
        uint256 indexed contractId,
        uint256 indexed milestoneId,
        address paymentToken,
        uint256 amount,
        Enums.FeeConfig feeConfig
    );

    /// @notice Emitted when a submission is made.
    /// @param sender The address of the sender.
    /// @param contractId The ID of the contract.
    /// @param milestoneId The ID of the milestone.
    event Submitted(address indexed sender, uint256 indexed milestoneId, uint256 indexed contractId);

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
    /// @param amount The claimed amount.
    event Claimed(address indexed contractor, uint256 indexed contractId, uint256 indexed milestoneId, uint256 amount);

    /// @notice Emitted when a contractor claims amounts from multiple milestones in one transaction.
    /// @param contractor The address of the contractor who performed the bulk claim.
    /// @param contractId The identifier of the contract within which the bulk claim was made.
    /// @param startMilestoneId The starting milestone ID of the range within which the claims were made.
    /// @param endMilestoneId The ending milestone ID of the range within which the claims were made.
    /// @param totalClaimedAmount The total amount claimed across all milestones in the specified range.
    /// @param totalFeeAmount The total fee amount deducted during the bulk claim process.
    /// @param totalClientFee The total client fee amount deducted, if applicable, during the bulk claim process.
    event BulkClaimed(
        address indexed contractor,
        uint256 indexed contractId,
        uint256 startMilestoneId,
        uint256 endMilestoneId,
        uint256 totalClaimedAmount,
        uint256 totalFeeAmount,
        uint256 totalClientFee
    );

    /// @notice Emitted when a withdrawal is made.
    /// @param withdrawer The address of the withdrawer.
    /// @param contractId The ID of the contract.
    /// @param milestoneId The ID of the milestone.
    /// @param amount The amount withdrawn.
    event Withdrawn(
        address indexed withdrawer, uint256 indexed contractId, uint256 indexed milestoneId, uint256 amount
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
    event ReturnApproved(address indexed approver, uint256 indexed contractId, uint256 indexed milestoneId);

    /// @notice Emitted when a return is canceled.
    /// @param sender The address of the sender.
    /// @param contractId The ID of the contract.
    /// @param milestoneId The ID of the milestone.
    event ReturnCanceled(address indexed sender, uint256 indexed contractId, uint256 indexed milestoneId);

    /// @notice Emitted when a dispute is created.
    /// @param sender The address of the sender.
    /// @param contractId The ID of the contract.
    /// @param milestoneId The ID of the milestone.
    event DisputeCreated(address indexed sender, uint256 indexed contractId, uint256 indexed milestoneId);

    /// @notice Emitted when a dispute is resolved.
    /// @param approver The address of the approver.
    /// @param contractId The ID of the contract.
    /// @param milestoneId The ID of the milestone.
    /// @param winner The winner of the dispute.
    /// @param clientAmount The amount awarded to the client.
    /// @param contractorAmount The amount awarded to the contractor.
    event DisputeResolved(
        address indexed approver,
        uint256 indexed contractId,
        uint256 indexed milestoneId,
        Enums.Winner winner,
        uint256 clientAmount,
        uint256 contractorAmount
    );

    /// @notice Emitted when the ownership of a contractor account is transferred to a new owner.
    /// @param contractId The identifier of the contract for which contractor ownership is being transferred.
    /// @param milestoneId The identifier of the milestone for which contractor ownership is being transferred.
    /// @param previousOwner The previous owner of the contractor account.
    /// @param newOwner The new owner of the contractor account.
    event ContractorOwnershipTransferred(
        uint256 indexed contractId, uint256 indexed milestoneId, address previousOwner, address indexed newOwner
    );

    /// @notice Interface declaration for transferring contractor ownership.
    /// @param contractId The identifier of the contract for which contractor ownership is being transferred.
    /// @param milestoneId The identifier of the milestone for which contractor ownership is being transferred.
    /// @param newOwner The address to which the contractor ownership will be transferred.
    function transferContractorOwnership(uint256 contractId, uint256 milestoneId, address newOwner) external;
}
