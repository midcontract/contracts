// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Enums} from "src/libs/Enums.sol";

/// @title Escrow Interface
/// @notice Interface for the Escrow contract that handles deposits, withdrawals, and disputes.
interface IEscrow {
    /// @notice Thrown when the escrow is already initialized.
    error Escrow__AlreadyInitialized();

    /// @notice Thrown when an unauthorized account attempts an action.
    /// @param account The address of the unauthorized account.
    error Escrow__UnauthorizedAccount(address account);

    /// @notice Thrown when a zero address is provided.
    error Escrow__ZeroAddressProvided();

    /// @notice Thrown when the fee is too high.
    error Escrow__FeeTooHigh();

    /// @notice Thrown when the status is invalid for withdrawal.
    error Escrow__InvalidStatusToWithdraw();

    /// @notice Thrown when the status is invalid for submission.
    error Escrow__InvalidStatusForSubmit();

    /// @notice Thrown when the contractor data hash is invalid.
    error Escrow__InvalidContractorDataHash();

    /// @notice Thrown when the status is invalid for approval.
    error Escrow__InvalidStatusForApprove();

    /// @notice Thrown when the status is invalid to claim.
    error Escrow__InvalidStatusToClaim();

    /// @notice Thrown when there is not enough deposit.
    error Escrow__NotEnoughDeposit();

    /// @notice Thrown when the receiver is unauthorized.
    error Escrow__UnauthorizedReceiver();

    /// @notice Thrown when the amount is invalid.
    error Escrow__InvalidAmount();

    /// @notice Thrown when the action is not approved.
    error Escrow__NotApproved();

    /// @notice Thrown when the payment token is not supported.
    error Escrow__NotSupportedPaymentToken();

    /// @notice Thrown when the deposit amount is zero.
    error Escrow__ZeroDepositAmount();

    /// @notice Thrown when the fee configuration is invalid.
    error Escrow__InvalidFeeConfig();

    /// @notice Thrown when the fee manager is not set.
    error Escrow__NotSetFeeManager();

    /// @notice Thrown when no funds are available for withdrawal.
    error Escrow__NoFundsAvailableForWithdraw();

    /// @notice Thrown when return is not allowed.
    error Escrow__ReturnNotAllowed();

    /// @notice Thrown when no return is requested.
    error Escrow__NoReturnRequested();

    /// @notice Thrown when unauthorized account tries to approve return.
    error Escrow__UnauthorizedToApproveReturn();

    /// @notice Thrown when unauthorized account tries to approve dispute.
    error Escrow__UnauthorizedToApproveDispute();

    /// @notice Thrown when creating dispute is not allowed.
    error Escrow__CreateDisputeNotAllowed();

    /// @notice Thrown when dispute is not active for the deposit.
    error Escrow__DisputeNotActiveForThisDeposit();

    /// @notice Thrown when the provided status is invalid.
    error Escrow__InvalidStatusProvided();

    /// @notice Thrown when the specified winner is invalid.
    error Escrow__InvalidWinnerSpecified();

    /// @notice Thrown when the resolution exceeds the deposited amount.
    error Escrow__ResolutionExceedsDepositedAmount();

    /// @notice Represents a deposit in the escrow.
    /// @param contractor The address of the contractor.
    /// @param paymentToken The address of the payment token.
    /// @param amount The amount deposited.
    /// @param amountToClaim The amount to be claimed.
    /// @param amountToWithdraw The amount to be withdrawn.
    /// @param timeLock The time lock for the deposit.
    /// @param contractorData The contractor's data hash.
    /// @param feeConfig The fee configuration.
    /// @param status The status of the deposit.
    struct Deposit {
        address contractor;
        address paymentToken;
        uint256 amount;
        uint256 amountToClaim;
        uint256 amountToWithdraw;
        uint256 timeLock;
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
    /// @param contractId The ID of the contract.
    /// @param amountApprove The approved amount.
    /// @param receiver The address of the receiver.
    event Approved(uint256 indexed contractId, uint256 indexed amountApprove, address indexed receiver);

    /// @notice Emitted when a contract is refilled.
    /// @param contractId The ID of the contract.
    /// @param amountAdditional The additional amount added.
    event Refilled(uint256 indexed contractId, uint256 indexed amountAdditional);

    /// @notice Emitted when a claim is made.
    /// @param contractId The ID of the contract.
    /// @param paymentToken The address of the payment token.
    /// @param amount The claimed amount.
    event Claimed(uint256 indexed contractId, address indexed paymentToken, uint256 amount);

    /// @notice Emitted when a withdrawal is made.
    /// @param contractId The ID of the contract.
    /// @param paymentToken The address of the payment token.
    /// @param amount The amount withdrawn.
    event Withdrawn(uint256 indexed contractId, address indexed paymentToken, uint256 amount);

    /// @notice Emitted when a return is requested.
    /// @param contractId The ID of the contract.
    event ReturnRequested(uint256 contractId);

    /// @notice Emitted when a return is approved.
    /// @param contractId The ID of the contract.
    /// @param sender The address of the sender.
    event ReturnApproved(uint256 contractId, address sender);

    /// @notice Emitted when a return is canceled.
    /// @param contractId The ID of the contract.
    event ReturnCanceled(uint256 contractId);

    /// @notice Emitted when a dispute is created.
    /// @param contractId The ID of the contract.
    /// @param sender The address of the sender.
    event DisputeCreated(uint256 contractId, address sender);

    /// @notice Emitted when a dispute is resolved.
    /// @param contractId The ID of the contract.
    /// @param winner The winner of the dispute.
    /// @param clientAmount The amount awarded to the client.
    /// @param contractorAmount The amount awarded to the contractor.
    event DisputeResolved(uint256 contractId, Enums.Winner winner, uint256 clientAmount, uint256 contractorAmount);

    /// @notice Emitted when the registry address is updated in the escrow.
    /// @param registry The new registry address.
    event RegistryUpdated(address registry);
}
