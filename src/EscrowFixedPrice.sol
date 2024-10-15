// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { SafeTransferLib } from "@solbase/utils/SafeTransferLib.sol";
import { SignatureChecker } from "@openzeppelin/utils/cryptography/SignatureChecker.sol";

import { IEscrowAdminManager } from "./interfaces/IEscrowAdminManager.sol";
import { IEscrowFixedPrice } from "./interfaces/IEscrowFixedPrice.sol";
import { IEscrowFeeManager } from "./interfaces/IEscrowFeeManager.sol";
import { IEscrowRegistry } from "./interfaces/IEscrowRegistry.sol";
import { ECDSA, ERC1271 } from "./libs/ERC1271.sol";
import { Enums } from "./libs/Enums.sol";

/// @title Escrow for Fixed-Price Contracts
/// @notice Manages lifecycle of fixed-price contracts including deposits, approvals, submissions, claims,
/// withdrawals, and dispute resolutions.
contract EscrowFixedPrice is IEscrowFixedPrice, ERC1271 {
    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                       CONFIGURATION & STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Address of the adminManager contract.
    IEscrowAdminManager public adminManager;

    /// @dev Address of the registry contract.
    IEscrowRegistry public registry;

    /// @dev Address of the client initiating actions within the escrow.
    address public client;

    /// @dev Current contract ID, incremented for each new deposit.
    uint256 private currentContractId;

    /// @dev Indicates that the contract has been initialized.
    bool public initialized;

    /// @dev Stores the total amount deposited for each contract ID.
    mapping(uint256 contractId => Deposit depositInfo) public deposits;

    /// @dev Modifier to restrict functions to the client address.
    modifier onlyClient() {
        if (msg.sender != client) revert Escrow__UnauthorizedAccount(msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the escrow contract.
    /// @param _client Address of the client initiating actions within the escrow.
    /// @param _adminManager Address of the adminManager contract of the escrow platform.
    /// @param _registry Address of the registry contract.
    function initialize(address _client, address _adminManager, address _registry) external {
        if (initialized) revert Escrow__AlreadyInitialized();

        if (_client == address(0) || _adminManager == address(0) || _registry == address(0)) {
            revert Escrow__ZeroAddressProvided();
        }

        client = _client;
        adminManager = IEscrowAdminManager(_adminManager);
        registry = IEscrowRegistry(_registry);

        initialized = true;
    }

    /*//////////////////////////////////////////////////////////////
                        ESCROW UNDERLYING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new deposit for a fixed-price contract within the escrow system.
    /// @param _deposit Details of the deposit to be created.
    function deposit(Deposit calldata _deposit) external onlyClient {
        // Ensure the sender is not blacklisted and that the payment token is supported.
        if (registry.blacklist(msg.sender)) revert Escrow__BlacklistedAccount();
        if (!registry.paymentTokens(_deposit.paymentToken)) revert Escrow__NotSupportedPaymentToken();

        // Validate that the deposit amount is greater than zero.
        if (_deposit.amount == 0) revert Escrow__ZeroDepositAmount();

        // Compute the total amount to be transferred, including any applicable fees.
        (uint256 totalDepositAmount,) = _computeDepositAmountAndFee(msg.sender, _deposit.amount, _deposit.feeConfig);

        // Transfer the calculated total deposit amount from the sender to this contract.
        SafeTransferLib.safeTransferFrom(_deposit.paymentToken, msg.sender, address(this), totalDepositAmount);

        // Increment the contract ID counter safely.
        unchecked {
            currentContractId++;
        }

        // Store the deposit information in the storage mapping.
        Deposit storage D = deposits[currentContractId];
        D.contractor = _deposit.contractor;
        D.paymentToken = _deposit.paymentToken;
        D.amount = _deposit.amount;
        D.contractorData = _deposit.contractorData;
        D.feeConfig = _deposit.feeConfig;
        D.status = Enums.Status.ACTIVE;

        // Initialize unmentioned fields with default values: Enums can default to the first listed option
        // if not explicitly set, and all uninitialized uints and addresses will be set to zero.

        // Emit an event to log the deposit details.
        emit Deposited(msg.sender, currentContractId, _deposit.paymentToken, _deposit.amount, _deposit.feeConfig);
    }

    /// @notice Submits work for a contract by the contractor.
    /// @dev This function allows the contractor to submit their work details for a contract.
    /// @param _contractId ID of the deposit to be submitted.
    /// @param _data Contractor’s details or work summary.
    /// @param _salt Unique salt for cryptographic operations.
    function submit(uint256 _contractId, bytes calldata _data, bytes32 _salt) external {
        Deposit storage D = deposits[_contractId];
        // Only allow the designated contractor to submit, or allow initial submission if no contractor has been set.
        if (D.contractor != address(0) && msg.sender != D.contractor) {
            revert Escrow__UnauthorizedAccount(msg.sender);
        }

        // Check that the contract is currently active and ready to receive a submission.
        if (D.status != Enums.Status.ACTIVE) revert Escrow__InvalidStatusForSubmit();

        // Verify contractor's data using a hash function to ensure it matches expected details.
        bytes32 contractorDataHash = _getContractorDataHash(_data, _salt);
        if (D.contractorData != contractorDataHash) revert Escrow__InvalidContractorDataHash();

        // Update the contractor's address and change the contract status to SUBMITTED.
        D.contractor = msg.sender;
        D.status = Enums.Status.SUBMITTED;

        // Emit an event to signal that the work has been successfully submitted.
        emit Submitted(msg.sender, _contractId);
    }

    /// @notice Approves a submitted deposit by the client or an administrator.
    /// @dev Allows the client or an admin to officially approve a deposit that has been submitted by a contractor.
    /// @param _contractId ID of the deposit to be approved.
    /// @param _amountApprove Amount to approve for the deposit.
    /// @param _receiver Address of the contractor receiving the approved amount.
    function approve(uint256 _contractId, uint256 _amountApprove, address _receiver) external {
        // Ensure only the client or an admin can approve the deposit.
        if (msg.sender != client && !IEscrowAdminManager(adminManager).isAdmin(msg.sender)) {
            revert Escrow__UnauthorizedAccount(msg.sender);
        }

        // Check that the approval amount is greater than zero.
        if (_amountApprove == 0) revert Escrow__InvalidAmount();

        Deposit storage D = deposits[_contractId];

        // Verify the deposit is in a status that allows for approval.
        if (D.status != Enums.Status.SUBMITTED) revert Escrow__InvalidStatusForApprove();

        // Confirm the receiver is the contractor linked to this deposit.
        if (D.contractor != _receiver) revert Escrow__UnauthorizedReceiver();

        // Ensure the approval does not exceed the deposit's total amount.
        if (D.amountToClaim + _amountApprove > D.amount) revert Escrow__NotEnoughDeposit();

        // Update the amount to claim and set the deposit status to APPROVED.
        D.amountToClaim += _amountApprove;
        D.status = Enums.Status.APPROVED;

        // Emit an event indicating the deposit has been approved.
        emit Approved(msg.sender, _contractId, _amountApprove, _receiver);
    }

    /// @notice Adds additional funds to a specific deposit.
    /// @dev Enhances a deposit's total amount, which can be crucial for ongoing contracts needing extra funds.
    /// @param _contractId The identifier of the deposit to be refilled.
    /// @param _amountAdditional The extra amount to be added to the deposit.
    function refill(uint256 _contractId, uint256 _amountAdditional) external onlyClient {
        // Verify that the client is not blacklisted before proceeding.
        if (registry.blacklist(msg.sender)) revert Escrow__BlacklistedAccount();

        // Ensure a non-zero amount is specified for the refill operation.
        if (_amountAdditional == 0) revert Escrow__InvalidAmount();

        Deposit storage D = deposits[_contractId];

        // Calculate the total amount including any applicable fees.
        (uint256 totalAmountAdditional,) = _computeDepositAmountAndFee(msg.sender, _amountAdditional, D.feeConfig);

        // Transfer the funds from the client to the contract.
        SafeTransferLib.safeTransferFrom(D.paymentToken, msg.sender, address(this), totalAmountAdditional);

        // Increase the deposit's total amount by the additional funds provided.
        D.amount += _amountAdditional;

        // Emit an event to log the successful refill of the deposit.
        emit Refilled(msg.sender, _contractId, _amountAdditional);
    }

    /// @notice Claims the approved funds for a contract by the contractor.
    /// @dev Allows contractors to retrieve funds that have been approved for their work.
    /// @param _contractId Identifier of the deposit from which funds will be claimed.
    function claim(uint256 _contractId) external {
        // Ensure the caller is not blacklisted to prevent abuse.
        if (registry.blacklist(msg.sender)) revert Escrow__BlacklistedAccount();

        Deposit storage D = deposits[_contractId];
        // Verify that the deposit is in a state that allows claiming.
        if (D.status != Enums.Status.APPROVED && D.status != Enums.Status.RESOLVED && D.status != Enums.Status.CANCELED)
        {
            revert Escrow__InvalidStatusToClaim();
        }

        // Confirm that there are funds approved to be claimed.
        if (D.amountToClaim == 0) revert Escrow__NotApproved();

        // Ensure that the caller is the authorized contractor for the deposit.
        if (D.contractor != msg.sender) revert Escrow__UnauthorizedAccount(msg.sender);

        // Calculate the claimable amount and the associated fees.
        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
            _computeClaimableAmountAndFee(msg.sender, D.amountToClaim, D.feeConfig);

        // Update the deposit to reflect the claimed amount.
        D.amount -= D.amountToClaim;
        D.amountToClaim = 0;

        // Transfer the claimable amount to the contractor.
        SafeTransferLib.safeTransfer(D.paymentToken, msg.sender, claimAmount);

        // Handle fee deductions and possible reimbursements.
        if ((D.status == Enums.Status.RESOLVED || D.status == Enums.Status.CANCELED) && feeAmount > 0) {
            // Send platform fees if the contract was resolved or canceled.
            _sendPlatformFee(D.paymentToken, feeAmount);
        } else if (feeAmount > 0 || clientFee > 0) {
            // Send any additional fees incurred.
            _sendPlatformFee(D.paymentToken, feeAmount + clientFee);
        }

        // Mark the deposit as completed if all funds have been claimed.
        if (D.amount == 0) D.status = Enums.Status.COMPLETED;

        // Emit an event to record the claim transaction.
        emit Claimed(msg.sender, _contractId, D.paymentToken, claimAmount);
    }

    /// @notice Withdraws funds from a deposit under specific conditions after a refund approval or resolution.
    /// @dev Handles the withdrawal process including fee deductions and state updates.
    /// @param _contractId Identifier of the deposit from which funds will be withdrawn.
    function withdraw(uint256 _contractId) external onlyClient {
        // Check if the caller is blacklisted to prevent unauthorized access.
        if (registry.blacklist(msg.sender)) revert Escrow__BlacklistedAccount();

        Deposit storage D = deposits[_contractId];
        // Verify the deposit's status to ensure it's eligible for withdrawal.
        if (D.status != Enums.Status.REFUND_APPROVED && D.status != Enums.Status.RESOLVED) {
            revert Escrow__InvalidStatusToWithdraw();
        }

        // Ensure there are funds available for withdrawal.
        if (D.amountToWithdraw == 0) revert Escrow__NoFundsAvailableForWithdraw();

        // Calculate the fee to be deducted from the withdrawal amount.
        (, uint256 feeAmount) = _computeDepositAmountAndFee(msg.sender, D.amountToWithdraw, D.feeConfig);

        // Determine the initial fee based on the total deposit amount for accurate fee processing.
        (, uint256 initialFeeAmount) = _computeDepositAmountAndFee(msg.sender, D.amount, D.feeConfig);

        // Update the deposit amount after deducting the withdrawal.
        D.amount -= D.amountToWithdraw;
        uint256 withdrawAmount = D.amountToWithdraw + feeAmount; // Calculate total amount to withdraw including fees.
        D.amountToWithdraw = 0; // Reset the amount to prevent re-withdrawal.

        // Change the deposit status to CANCELED post-withdrawal to mark its completion.
        D.status = Enums.Status.CANCELED;

        // Execute the transfer of funds to the client.
        SafeTransferLib.safeTransfer(D.paymentToken, msg.sender, withdrawAmount);

        // Calculate any platform fee differential due to fee adjustments during the process.
        uint256 platformFee = initialFeeAmount > feeAmount ? initialFeeAmount - feeAmount : 0;

        // Transfer the platform fee to the designated fee collector if applicable.
        if (platformFee > 0) {
            _sendPlatformFee(D.paymentToken, platformFee);
        }

        // Emit an event to log the withdrawal action.
        emit Withdrawn(msg.sender, _contractId, D.paymentToken, withdrawAmount);
    }

    /*//////////////////////////////////////////////////////////////
                ESCROW RETURN REQUEST & DISPUTE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Requests the return of funds by the client for a specific contract.
    /// @dev The contract must be in an eligible state to request a return (not in disputed or already returned status).
    /// @param _contractId ID of the deposit for which the return is requested.
    function requestReturn(uint256 _contractId) external onlyClient {
        Deposit storage D = deposits[_contractId];
        if (
            D.status != Enums.Status.ACTIVE && D.status != Enums.Status.SUBMITTED && D.status != Enums.Status.APPROVED
                && D.status != Enums.Status.COMPLETED
        ) revert Escrow__ReturnNotAllowed();

        D.status = Enums.Status.RETURN_REQUESTED;
        emit ReturnRequested(msg.sender, _contractId);
    }

    /// @notice Approves the return of funds, which can be called by the contractor or platform admin.
    /// @dev This changes the status of the deposit to allow the client to withdraw their funds.
    /// @param _contractId ID of the deposit for which the return is approved.
    function approveReturn(uint256 _contractId) external {
        Deposit storage D = deposits[_contractId];
        if (D.status != Enums.Status.RETURN_REQUESTED) revert Escrow__NoReturnRequested();
        if (msg.sender != D.contractor && !IEscrowAdminManager(adminManager).isAdmin(msg.sender)) {
            revert Escrow__UnauthorizedToApproveReturn();
        }

        D.amountToWithdraw = D.amount; // Allows full withdrawal of the initial deposit.
        D.status = Enums.Status.REFUND_APPROVED;
        emit ReturnApproved(msg.sender, _contractId);
    }

    /// @notice Cancels a previously requested return and resets the deposit's status.
    /// @dev Allows reverting the deposit status from RETURN_REQUESTED to an active state.
    /// @param _contractId The unique identifier of the deposit for which the return is being cancelled.
    /// @param _status The new status to set for the deposit, must be ACTIVE, SUBMITTED, APPROVED, or COMPLETED.
    function cancelReturn(uint256 _contractId, Enums.Status _status) external onlyClient {
        Deposit storage D = deposits[_contractId];
        if (D.status != Enums.Status.RETURN_REQUESTED) revert Escrow__NoReturnRequested();
        if (
            _status != Enums.Status.ACTIVE && _status != Enums.Status.SUBMITTED && _status != Enums.Status.APPROVED
                && _status != Enums.Status.COMPLETED
        ) {
            revert Escrow__InvalidStatusProvided();
        }

        D.status = _status;
        emit ReturnCanceled(msg.sender, _contractId);
    }

    /// @notice Creates a dispute over a specific deposit.
    /// @dev Initiates a dispute status for a deposit that can be activated by the client or contractor
    /// when they disagree on the previously submitted work.
    /// @param _contractId ID of the deposit where the dispute is to be created.
    /// This function can only be called if the deposit status is either RETURN_REQUESTED or SUBMITTED.
    function createDispute(uint256 _contractId) external {
        Deposit storage D = deposits[_contractId];
        if (D.status != Enums.Status.RETURN_REQUESTED && D.status != Enums.Status.SUBMITTED) {
            revert Escrow__CreateDisputeNotAllowed();
        }
        if (msg.sender != client && msg.sender != D.contractor) revert Escrow__UnauthorizedToApproveDispute();

        D.status = Enums.Status.DISPUTED;
        emit DisputeCreated(msg.sender, _contractId);
    }

    /// @notice Resolves a dispute over a specific deposit.
    /// @dev Handles the resolution of disputes by assigning the funds according to the outcome of the dispute.
    /// Admin intervention is required to resolve disputes to ensure fairness.
    /// @param _contractId ID of the deposit where the dispute occurred.
    /// @param _winner Specifies who the winner is: Client, Contractor, or Split.
    /// @param _clientAmount Amount to be allocated to the client if Split or Client wins.
    /// @param _contractorAmount Amount to be allocated to the contractor if Split or Contractor wins.
    /// This function ensures that the total resolution amounts do not exceed the deposited amount and adjusts the
    /// status of the deposit based on the dispute outcome.
    function resolveDispute(uint256 _contractId, Enums.Winner _winner, uint256 _clientAmount, uint256 _contractorAmount)
        external
    {
        if (!IEscrowAdminManager(adminManager).isAdmin(msg.sender)) revert Escrow__UnauthorizedAccount(msg.sender);

        Deposit storage D = deposits[_contractId];
        if (D.status != Enums.Status.DISPUTED) revert Escrow__DisputeNotActiveForThisDeposit();

        // Validate the total resolution does not exceed the available deposit amount.
        uint256 totalResolutionAmount = _clientAmount + _contractorAmount;
        if (totalResolutionAmount > D.amount) revert Escrow__ResolutionExceedsDepositedAmount();

        // Apply resolution based on the winner.
        if (_winner == Enums.Winner.CLIENT) {
            D.status = Enums.Status.RESOLVED; // Client can now withdraw the full amount.
            D.amountToWithdraw = _clientAmount; // Full amount for the client to withdraw.
            D.amountToClaim = 0; // No claimable amount for the contractor.
        } else if (_winner == Enums.Winner.CONTRACTOR) {
            D.status = Enums.Status.APPROVED; // Status that allows the contractor to claim.
            D.amountToClaim = _contractorAmount; // Amount the contractor can claim.
            D.amountToWithdraw = 0; // No amount for the client to withdraw.
        } else if (_winner == Enums.Winner.SPLIT) {
            D.status = Enums.Status.RESOLVED; // Indicates a resolved dispute with split amounts.
            D.amountToClaim = _contractorAmount; // Set the claimable amount for the contractor.
            D.amountToWithdraw = _clientAmount; // Set the withdrawable amount for the client.
        }

        emit DisputeResolved(msg.sender, _contractId, _winner, _clientAmount, _contractorAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Computes the total deposit amount and the applied fee.
    /// @dev This internal function calculates the total deposit amount and the fee applied based on the client, deposit
    /// amount, and fee configuration.
    /// @param _client Address of the client making the deposit.
    /// @param _depositAmount Amount of the deposit.
    /// @param _feeConfig Fee configuration for the deposit.
    /// @return totalDepositAmount Total deposit amount after applying the fee.
    /// @return feeApplied Fee applied to the deposit.
    function _computeDepositAmountAndFee(address _client, uint256 _depositAmount, Enums.FeeConfig _feeConfig)
        internal
        view
        returns (uint256 totalDepositAmount, uint256 feeApplied)
    {
        address feeManagerAddress = registry.feeManager();
        if (feeManagerAddress == address(0)) revert Escrow__NotSetFeeManager();
        IEscrowFeeManager feeManager = IEscrowFeeManager(feeManagerAddress); // Cast to the interface.

        (totalDepositAmount, feeApplied) = feeManager.computeDepositAmountAndFee(_client, _depositAmount, _feeConfig);

        return (totalDepositAmount, feeApplied);
    }

    /// @notice Computes the claimable amount and the fee deducted from the claimed amount.
    /// @dev This internal function calculates the claimable amount for the contractor and the fees deducted from the
    /// claimed amount based on the contractor,
    ///     claimed amount, and fee configuration.
    /// @param _contractor Address of the contractor claiming the amount.
    /// @param _claimedAmount Amount claimed by the contractor.
    /// @param _feeConfig Fee configuration for the deposit.
    /// @return claimableAmount Amount claimable by the contractor.
    /// @return feeDeducted Fee deducted from the claimed amount.
    /// @return clientFee Fee to be paid by the client for covering the claim.
    function _computeClaimableAmountAndFee(address _contractor, uint256 _claimedAmount, Enums.FeeConfig _feeConfig)
        internal
        view
        returns (uint256 claimableAmount, uint256 feeDeducted, uint256 clientFee)
    {
        address feeManagerAddress = registry.feeManager();
        if (feeManagerAddress == address(0)) revert Escrow__NotSetFeeManager();
        IEscrowFeeManager feeManager = IEscrowFeeManager(feeManagerAddress);

        (claimableAmount, feeDeducted, clientFee) =
            feeManager.computeClaimableAmountAndFee(_contractor, _claimedAmount, _feeConfig);

        return (claimableAmount, feeDeducted, clientFee);
    }

    /// @notice Sends the platform fee to the treasury.
    /// @dev This internal function transfers the platform fee to the treasury address.
    /// @param _paymentToken Address of the payment token for the fee.
    /// @param _feeAmount Amount of the fee to be transferred.
    function _sendPlatformFee(address _paymentToken, uint256 _feeAmount) internal {
        address treasury = IEscrowRegistry(registry).treasury();
        if (treasury == address(0)) revert Escrow__ZeroAddressProvided();
        SafeTransferLib.safeTransfer(_paymentToken, treasury, _feeAmount);
    }

    /// @notice Internal function to validate the signature of the provided data.
    /// @dev Verifies if the signature is from the msg.sender, which can be an externally owned account (EOA) or a
    /// contract implementing ERC-1271.
    /// @param _hash The hash of the data that was signed.
    /// @param _signature The signature byte array associated with the hash.
    /// @return True if the signature is valid, false otherwise.
    function _isValidSignature(bytes32 _hash, bytes calldata _signature) internal view override returns (bool) {
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(_hash);
        // Check if msg.sender is a contract.
        if (msg.sender.code.length > 0) {
            // ERC-1271 signature verification.
            return SignatureChecker.isValidERC1271SignatureNow(msg.sender, ethSignedHash, _signature);
        } else {
            // EOA signature verification.
            address recoveredSigner = ECDSA.recover(ethSignedHash, _signature);
            return recoveredSigner == msg.sender;
        }
    }

    /// @notice Generates a hash for the contractor data.
    /// @dev This internal function computes the hash value for the contractor data using the provided data and salt.
    function _getContractorDataHash(bytes calldata _data, bytes32 _salt) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_data, _salt));
    }

    /*//////////////////////////////////////////////////////////////
                    EXTERNAL VIEW & MANAGER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Generates a hash for the contractor data.
    /// @dev This external function computes the hash value for the contractor data using the provided data and salt.
    /// @param _data Contractor data.
    /// @param _salt Salt value for generating the hash.
    /// @return Hash value of the contractor data.
    function getContractorDataHash(bytes calldata _data, bytes32 _salt) external pure returns (bytes32) {
        return _getContractorDataHash(_data, _salt);
    }

    /// @notice Retrieves the current contract ID.
    /// @return The current contract ID.
    function getCurrentContractId() external view returns (uint256) {
        return currentContractId;
    }

    /// @notice Transfers ownership of the client account to a new account.
    /// @dev Can only be called by the account recovery module registered in the system.
    /// @param _newAccount The address to which the client ownership will be transferred.
    function transferClientOwnership(address _newAccount) external {
        // Verify that the caller is the authorized account recovery module.
        if (msg.sender != registry.accountRecovery()) revert Escrow__UnauthorizedAccount(msg.sender);

        if (_newAccount == address(0)) revert Escrow__ZeroAddressProvided();

        // Emit the ownership transfer event before changing the state to reflect the previous state.
        emit ClientOwnershipTransferred(client, _newAccount);

        // Update the client address to the new owner's address.
        client = _newAccount;
    }

    /// @notice Transfers ownership of the contractor account to a new account for a specified contract.
    /// @dev Can only be called by the account recovery module registered in the system.
    /// @param _contractId The identifier of the contract for which contractor ownership is being transferred.
    /// @param _newAccount The address to which the contractor ownership will be transferred.
    function transferContractorOwnership(uint256 _contractId, address _newAccount) external {
        // Verify that the caller is the authorized account recovery module.
        if (msg.sender != registry.accountRecovery()) revert Escrow__UnauthorizedAccount(msg.sender);

        if (_newAccount == address(0)) revert Escrow__ZeroAddressProvided();

        Deposit storage D = deposits[_contractId];

        // Emit the ownership transfer event before changing the state to reflect the previous state.
        emit ContractorOwnershipTransferred(_contractId, D.contractor, _newAccount);

        // Update the contractor address to the new owner's address.
        D.contractor = _newAccount;
    }

    /// @notice Updates the registry address used for fetching escrow implementations.
    /// @param _registry New registry address.
    function updateRegistry(address _registry) external {
        if (!IEscrowAdminManager(adminManager).isAdmin(msg.sender)) revert Escrow__UnauthorizedAccount(msg.sender);
        if (_registry == address(0)) revert Escrow__ZeroAddressProvided();
        registry = IEscrowRegistry(_registry);
        emit RegistryUpdated(_registry);
    }

    /// @notice Updates the address of the admin manager contract.
    /// @dev Restricts the function to be callable only by the current owner of the admin manager.
    /// @param _adminManager The new address of the admin manager contract.
    function updateAdminManager(address _adminManager) external {
        if (msg.sender != IEscrowAdminManager(adminManager).owner()) revert Escrow__UnauthorizedAccount(msg.sender);
        if (_adminManager == address(0)) revert Escrow__ZeroAddressProvided();
        adminManager = IEscrowAdminManager(_adminManager);
        emit AdminManagerUpdated(_adminManager);
    }
}
