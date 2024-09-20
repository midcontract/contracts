// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Enums } from "../libs/Enums.sol";

/// @title Escrow Interface
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

    /// @notice Thrown when an operation is attempted by an account that is currently blacklisted.
    error Escrow__BlacklistedAccount();

    /// @notice Thrown when a specified range is invalid, such as an ending index being less than the starting index.
    error Escrow__InvalidRange();

    /// @notice Thrown when the specified ID is out of the valid range for the contract.
    error Escrow__OutOfRange();

    /// @notice Emitted when the registry address is updated in the escrow.
    /// @param registry The new registry address.
    event RegistryUpdated(address registry);

    /// @dev Emitted when the admin manager address is updated in the contract.
    /// @param adminManager The new address of the admin manager.
    event AdminManagerUpdated(address adminManager);

    /// @notice Event emitted when the ownership of the client account is transferred.
    /// @param previousOwner The previous owner of the client account.
    /// @param newOwner The new owner of the client account.
    event ClientOwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Initializes the escrow contract.
    /// @param client Address of the client initiating actions within the escrow.
    /// @param adminManager Address of the adminManager contract of the escrow platform.
    /// @param registry Address of the registry contract.
    function initialize(address client, address adminManager, address registry) external;

    /// @notice Transfers ownership of the client account to a new account.
    /// @dev Can only be called by the account recovery module registered in the system.
    /// @param newOwner The address to which the client ownership will be transferred.
    function transferClientOwnership(address newOwner) external;
}
