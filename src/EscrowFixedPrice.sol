// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { SafeTransferLib } from "@solbase/utils/SafeTransferLib.sol";
import { SignatureChecker } from "@openzeppelin/utils/cryptography/SignatureChecker.sol";

import { IEscrowAdminManager } from "./interfaces/IEscrowAdminManager.sol";
import { IEscrowFixedPrice } from "./interfaces/IEscrowFixedPrice.sol";
import { IEscrowFeeManager } from "./interfaces/IEscrowFeeManager.sol";
import { IEscrowRegistry } from "./interfaces/IEscrowRegistry.sol";
import { ECDSA, ERC1271 } from "./common/ERC1271.sol";
import { Enums } from "./common/Enums.sol";

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

    /// @dev Address of the client who initiates the escrow contract.
    address public client;

    /// @dev Indicates that the contract has been initialized.
    bool public initialized;

    /// @dev Maps each contract ID to its corresponding deposit details.
    mapping(uint256 contractId => DepositInfo) public deposits;

    /// @dev Maps each contract ID to its previous status before the return request.
    mapping(uint256 contractId => Enums.Status) public previousStatuses;

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
    function deposit(DepositRequest calldata _deposit) external onlyClient {
        // Ensure the sender is not blacklisted and that the payment token is supported.
        if (registry.blacklist(msg.sender)) revert Escrow__BlacklistedAccount();
        if (!registry.paymentTokens(_deposit.paymentToken)) revert Escrow__NotSupportedPaymentToken();

        // Validate that the deposit amount is greater than zero.
        if (_deposit.amount == 0) revert Escrow__ZeroDepositAmount();

        // Ensure the provided `contractId` is valid, unique, and non-zero.
        if (
            _deposit.contractId == 0 || deposits[_deposit.contractId].status != Enums.Status.NONE
                || deposits[_deposit.contractId].paymentToken != address(0)
        ) {
            revert Escrow__ContractIdAlreadyExists();
        }

        // Validate the deposit fields against admin signature.
        _validateDepositAuthorization(_deposit);

        // Store the deposit information in the storage mapping.
        DepositInfo storage D = deposits[_deposit.contractId];
        D.contractor = _deposit.contractor;
        D.paymentToken = _deposit.paymentToken;
        D.amount = _deposit.amount;
        D.contractorData = _deposit.contractorData;
        D.feeConfig = _deposit.feeConfig;
        D.status = Enums.Status.ACTIVE;
        // Initialize unmentioned fields with default values: Enums can default to the first listed option
        // if not explicitly set, and all uninitialized uints and addresses will be set to zero.

        // Compute the total amount to be transferred, including any applicable fees.
        (uint256 totalDepositAmount,) =
            _computeDepositAmountAndFee(_deposit.contractId, msg.sender, _deposit.amount, _deposit.feeConfig);

        // Transfer the calculated total deposit amount from the sender to this contract.
        SafeTransferLib.safeTransferFrom(_deposit.paymentToken, msg.sender, address(this), totalDepositAmount);

        // Emit an event to log the deposit details.
        emit Deposited(msg.sender, _deposit.contractId, totalDepositAmount, _deposit.contractor);
    }

    /// @notice Submits work for a contract by the contractor.
    /// @dev Uses an admin-signed authorization to verify submission legitimacy,
    ///      ensuring multiple submissions are uniquely signed and replay-proof.
    /// @param _request Struct containing all required parameters for submission.
    function submit(SubmitRequest calldata _request) external {
        DepositInfo storage D = deposits[_request.contractId];
        // Only allow the designated contractor to submit, or allow initial submission if no contractor has been set.
        if (D.contractor != address(0) && msg.sender != D.contractor) {
            revert Escrow__UnauthorizedAccount(msg.sender);
        }

        // Check that the contract is currently active and ready to receive a submission.
        if (D.status != Enums.Status.ACTIVE) revert Escrow__InvalidStatusForSubmit();

        // Compute hash with contractor binding.
        bytes32 contractorDataHash = _getContractorDataHash(msg.sender, _request.data, _request.salt);

        // Verify that the computed hash matches stored contractor data.
        if (D.contractorData != contractorDataHash) revert Escrow__InvalidContractorDataHash();

        // Validate the submission using admin-signed approval.
        _validateSubmitAuthorization(msg.sender, _request);

        // Update the contractor's address and change the contract status to SUBMITTED.
        D.contractor = msg.sender;
        D.status = Enums.Status.SUBMITTED;

        // Emit an event to signal that the work has been successfully submitted.
        emit Submitted(msg.sender, _request.contractId, client);
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

        DepositInfo storage D = deposits[_contractId];

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
        if (registry.blacklist(msg.sender)) revert Escrow__BlacklistedAccount();

        // Ensure a non-zero amount is specified for the refill operation.
        if (_amountAdditional == 0) revert Escrow__InvalidAmount();

        DepositInfo storage D = deposits[_contractId];

        // Calculate the total amount including any applicable fees.
        (uint256 totalAmountAdditional,) =
            _computeDepositAmountAndFee(_contractId, msg.sender, _amountAdditional, D.feeConfig);

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
        DepositInfo storage D = deposits[_contractId];
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
            _computeClaimableAmountAndFee(_contractId, msg.sender, D.amountToClaim, D.feeConfig);

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
        emit Claimed(msg.sender, _contractId, claimAmount, feeAmount, client);
    }

    /// @notice Withdraws funds from a deposit under specific conditions after a refund approval or resolution.
    /// @dev Handles the withdrawal process including fee deductions and state updates.
    /// @param _contractId Identifier of the deposit from which funds will be withdrawn.
    function withdraw(uint256 _contractId) external onlyClient {
        DepositInfo storage D = deposits[_contractId];
        // Verify the deposit's status to ensure it's eligible for withdrawal.
        if (D.status != Enums.Status.REFUND_APPROVED && D.status != Enums.Status.RESOLVED) {
            revert Escrow__InvalidStatusToWithdraw();
        }

        // Ensure there are funds available for withdrawal.
        if (D.amountToWithdraw == 0) revert Escrow__NoFundsAvailableForWithdraw();

        // Calculate the fee to be deducted from the withdrawal amount.
        (, uint256 feeAmount) = _computeDepositAmountAndFee(_contractId, msg.sender, D.amountToWithdraw, D.feeConfig);

        // Determine the initial fee based on the total deposit amount for accurate fee processing.
        (, uint256 initialFeeAmount) = _computeDepositAmountAndFee(_contractId, msg.sender, D.amount, D.feeConfig);

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
        emit Withdrawn(msg.sender, _contractId, withdrawAmount, platformFee);
    }

    /*//////////////////////////////////////////////////////////////
                ESCROW RETURN REQUEST & DISPUTE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Requests the return of funds by the client for a specific contract.
    /// @dev The contract must be in an eligible state to request a return (not in disputed or already returned status).
    /// @param _contractId ID of the deposit for which the return is requested.
    function requestReturn(uint256 _contractId) external onlyClient {
        DepositInfo storage D = deposits[_contractId];
        if (
            D.status != Enums.Status.ACTIVE && D.status != Enums.Status.SUBMITTED && D.status != Enums.Status.APPROVED
                && D.status != Enums.Status.COMPLETED
        ) revert Escrow__ReturnNotAllowed();

        // Store the current status before changing it to RETURN_REQUESTED.
        previousStatuses[_contractId] = D.status;

        D.status = Enums.Status.RETURN_REQUESTED;
        emit ReturnRequested(msg.sender, _contractId);
    }

    /// @notice Approves the return of funds, which can be called by the contractor or platform admin.
    /// @dev This changes the status of the deposit to allow the client to withdraw their funds.
    /// @param _contractId ID of the deposit for which the return is approved.
    function approveReturn(uint256 _contractId) external {
        DepositInfo storage D = deposits[_contractId];
        if (D.status != Enums.Status.RETURN_REQUESTED) revert Escrow__NoReturnRequested();
        if (msg.sender != D.contractor && !IEscrowAdminManager(adminManager).isAdmin(msg.sender)) {
            revert Escrow__UnauthorizedToApproveReturn();
        }
        D.amountToWithdraw = D.amount; // Allows full withdrawal of the initial deposit.
        D.status = Enums.Status.REFUND_APPROVED;
        emit ReturnApproved(msg.sender, _contractId, client);
    }

    /// @notice Cancels a previously requested return and resets the deposit's status to the previous one.
    /// @dev Reverts the status from RETURN_REQUESTED to the previous status stored in `previousStatuses`.
    /// @param _contractId The unique identifier of the deposit for which the return is being cancelled.
    function cancelReturn(uint256 _contractId) external onlyClient {
        DepositInfo storage D = deposits[_contractId];
        if (D.status != Enums.Status.RETURN_REQUESTED) revert Escrow__NoReturnRequested();

        // Reset the status to the previous state.
        D.status = previousStatuses[_contractId];

        // Remove the previous status mapping entry.
        delete previousStatuses[_contractId];

        emit ReturnCanceled(msg.sender, _contractId);
    }

    /// @notice Creates a dispute over a specific deposit.
    /// @dev Initiates a dispute status for a deposit that can be activated by the client or contractor
    /// when they disagree on the previously submitted work.
    /// @param _contractId ID of the deposit where the dispute is to be created.
    /// This function can only be called if the deposit status is either RETURN_REQUESTED or SUBMITTED.
    function createDispute(uint256 _contractId) external {
        DepositInfo storage D = deposits[_contractId];
        if (D.status != Enums.Status.RETURN_REQUESTED && D.status != Enums.Status.SUBMITTED) {
            revert Escrow__CreateDisputeNotAllowed();
        }
        if (msg.sender != client && msg.sender != D.contractor) revert Escrow__UnauthorizedToApproveDispute();

        D.status = Enums.Status.DISPUTED;
        emit DisputeCreated(msg.sender, _contractId, client);
    }

    /// @notice Resolves a dispute over a specific deposit.
    /// @dev Handles the resolution of disputes by assigning the funds according to the outcome of the dispute.
    ///     Admin intervention is required to resolve disputes to ensure fairness.
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

        DepositInfo storage D = deposits[_contractId];
        if (D.status != Enums.Status.DISPUTED) revert Escrow__DisputeNotActiveForThisDeposit();

        // Validate the total resolution does not exceed the available deposit amount.
        uint256 totalResolutionAmount = _clientAmount + _contractorAmount;
        if (totalResolutionAmount > D.amount) revert Escrow__ResolutionExceedsDepositedAmount();

        // Apply resolution based on the winner.
        D.amountToClaim = (_winner == Enums.Winner.CONTRACTOR || _winner == Enums.Winner.SPLIT) ? _contractorAmount : 0;
        if (_winner == Enums.Winner.CONTRACTOR) {
            D.status = Enums.Status.APPROVED; // Status that allows the contractor to claim.
            D.amountToWithdraw = 0; // No amount for the client to withdraw.
        } else {
            D.status = Enums.Status.RESOLVED; // Sets the status to resolved for both Client and Split outcomes.
            D.amountToWithdraw = (_winner == Enums.Winner.CLIENT || _winner == Enums.Winner.SPLIT) ? _clientAmount : 0;
        }

        emit DisputeResolved(msg.sender, _contractId, _winner, _clientAmount, _contractorAmount, client);
    }

    /*//////////////////////////////////////////////////////////////
                    MANAGER & EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfers ownership of the client account to a new account.
    /// @dev Can only be called by the account recovery module registered in the system.
    /// @param _newAccount The address to which the client ownership will be transferred.
    function transferClientOwnership(address _newAccount) external {
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
        if (msg.sender != registry.accountRecovery()) revert Escrow__UnauthorizedAccount(msg.sender);
        if (_newAccount == address(0)) revert Escrow__ZeroAddressProvided();

        DepositInfo storage D = deposits[_contractId];

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

    /// @notice Checks if a given contract ID exists.
    /// @param _contractId The contract ID to check.
    /// @return bool True if the contract exists, false otherwise.
    function contractExists(uint256 _contractId) external view returns (bool) {
        return deposits[_contractId].status != Enums.Status.NONE;
    }

    /// @notice Generates a hash for the contractor data with address binding.
    /// @dev External function to compute a hash value tied to the contractor's identity.
    /// @param _contractor Address of the contractor.
    /// @param _data Contractor-specific data.
    /// @param _salt A unique salt value.
    /// @return Hash value bound to the contractor's address, data, and salt.
    function getContractorDataHash(address _contractor, bytes calldata _data, bytes32 _salt)
        external
        pure
        returns (bytes32)
    {
        return _getContractorDataHash(_contractor, _data, _salt);
    }

    /// @notice Generates the hash required for deposit signing.
    /// @param _client The address of the client submitting the deposit.
    /// @param _contractId The ID of the contract associated with the deposit.
    /// @param _contractor The contractor's address.
    /// @param _paymentToken The payment token used.
    /// @param _amount The deposit amount.
    /// @param _feeConfig The fee configuration.
    /// @param _contractorData Hash of the contractor's additional data.
    /// @param _expiration The timestamp when the deposit authorization expires.
    /// @return ethSignedHash The Ethereum signed message hash that needs to be signed.
    function getDepositHash(
        address _client,
        uint256 _contractId,
        address _contractor,
        address _paymentToken,
        uint256 _amount,
        Enums.FeeConfig _feeConfig,
        bytes32 _contractorData,
        uint256 _expiration
    ) external view returns (bytes32) {
        // Generate the raw hash.
        bytes32 hash = keccak256(
            abi.encodePacked(
                _client,
                _contractId,
                _contractor,
                _paymentToken,
                _amount,
                _feeConfig,
                _contractorData,
                _expiration,
                address(this) // Contract address to prevent replay attacks.
            )
        );

        // Apply Ethereum’s signed message prefix (same as ECDSA.toEthSignedMessageHash).
        return ECDSA.toEthSignedMessageHash(hash);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Generates a unique hash for verifying contractor data.
    /// @dev Computes a hash that combines the contractor's address, data, and a salt value to securely bind the data
    ///      to the contractor. This approach prevents impersonation and front-running attacks.
    /// @return A keccak256 hash combining the contractor's address, data, and salt for verification.
    function _getContractorDataHash(address _contractor, bytes calldata _data, bytes32 _salt)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_contractor, _data, _salt));
    }

    /// @notice Computes the total deposit amount and the applied fee.
    /// @dev This internal function calculates the total deposit amount and the fee applied based on the client, deposit
    ///     amount, and fee configuration.
    /// @param _contractId The specific contract ID within the proxy instance.
    /// @param _client Address of the client making the deposit.
    /// @param _depositAmount Amount of the deposit.
    /// @param _feeConfig Fee configuration for the deposit.
    /// @return totalDepositAmount Total deposit amount after applying the fee.
    /// @return feeApplied Fee applied to the deposit.
    function _computeDepositAmountAndFee(
        uint256 _contractId,
        address _client,
        uint256 _depositAmount,
        Enums.FeeConfig _feeConfig
    ) internal view returns (uint256 totalDepositAmount, uint256 feeApplied) {
        address feeManagerAddress = registry.feeManager();
        if (feeManagerAddress == address(0)) revert Escrow__NotSetFeeManager();
        IEscrowFeeManager feeManager = IEscrowFeeManager(feeManagerAddress); // Cast to the interface.

        (totalDepositAmount, feeApplied) =
            feeManager.computeDepositAmountAndFee(address(this), _contractId, _client, _depositAmount, _feeConfig);

        return (totalDepositAmount, feeApplied);
    }

    /// @notice Computes the claimable amount and the fee deducted from the claimed amount.
    /// @dev This internal function calculates the claimable amount for the contractor and the fees deducted from the
    ///     claimed amount based on the contractor, claimed amount, and fee configuration.
    /// @param _contractId The specific contract ID within the proxy instance.
    /// @param _contractor Address of the contractor claiming the amount.
    /// @param _claimedAmount Amount claimed by the contractor.
    /// @param _feeConfig Fee configuration for the deposit.
    /// @return claimableAmount Amount claimable by the contractor.
    /// @return feeDeducted Fee deducted from the claimed amount.
    /// @return clientFee Fee to be paid by the client for covering the claim.
    function _computeClaimableAmountAndFee(
        uint256 _contractId,
        address _contractor,
        uint256 _claimedAmount,
        Enums.FeeConfig _feeConfig
    ) internal view returns (uint256 claimableAmount, uint256 feeDeducted, uint256 clientFee) {
        address feeManagerAddress = registry.feeManager();
        if (feeManagerAddress == address(0)) revert Escrow__NotSetFeeManager();
        IEscrowFeeManager feeManager = IEscrowFeeManager(feeManagerAddress);

        (claimableAmount, feeDeducted, clientFee) =
            feeManager.computeClaimableAmountAndFee(address(this), _contractId, _contractor, _claimedAmount, _feeConfig);

        return (claimableAmount, feeDeducted, clientFee);
    }

    /// @notice Sends the platform fee to the treasury.
    /// @dev This internal function transfers the platform fee to the treasury address.
    /// @param _paymentToken Address of the payment token for the fee.
    /// @param _feeAmount Amount of the fee to be transferred.
    function _sendPlatformFee(address _paymentToken, uint256 _feeAmount) internal {
        address treasury = IEscrowRegistry(registry).fixedTreasury();
        if (treasury == address(0)) revert Escrow__ZeroAddressProvided();
        SafeTransferLib.safeTransfer(_paymentToken, treasury, _feeAmount);
    }

    /// @notice Internal function to validate the signature of the provided data.
    /// @dev Verifies if the signature is from the msg.sender, which can be an externally owned account (EOA) or a
    ///     contract implementing ERC-1271.
    /// @param _hash The hash of the data that was signed.
    /// @param _signature The signature byte array associated with the hash.
    /// @return True if the signature is valid, false otherwise.
    function _isValidSignature(bytes32 _hash, bytes calldata _signature) internal view override returns (bool) {
        // Check if msg.sender is a contract (Embedded Account).
        if (msg.sender.code.length > 0) {
            // ERC-1271 signature verification.
            return SignatureChecker.isValidERC1271SignatureNow(msg.sender, _hash, _signature);
        } else {
            // EOA signature verification (Apply Ethereum Signed Message Prefix).
            bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(_hash);
            address recoveredSigner = ECDSA.recover(ethSignedHash, _signature);
            return recoveredSigner == msg.sender;
        }
    }

    /// @notice Validates deposit fields against admin-signed approval.
    /// @param _deposit The deposit details including signature and expiration.
    function _validateDepositAuthorization(DepositRequest calldata _deposit) internal view {
        // Ensure the authorization has not expired.
        if (_deposit.expiration < block.timestamp) revert Escrow__AuthorizationExpired();

        // Generate hash for signed data.
        bytes32 hash = keccak256(
            abi.encodePacked(
                msg.sender,
                _deposit.contractId,
                _deposit.contractor,
                _deposit.paymentToken,
                _deposit.amount,
                _deposit.feeConfig,
                _deposit.contractorData,
                _deposit.expiration,
                address(this)
            )
        );
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(hash);

        // Verify signature using the admin's address.
        address signer = adminManager.owner();
        if (!SignatureChecker.isValidSignatureNow(signer, ethSignedHash, _deposit.signature)) {
            revert Escrow__InvalidSignature();
        }
    }

    /// @notice Validates submit authorization using an admin-signed approval.
    /// @dev Prevents replay attacks and ensures multiple submissions are uniquely signed.
    /// @param _contractor Address of the contractor submitting the work.
    /// @param _request Struct containing all necessary parameters for submission.
    function _validateSubmitAuthorization(address _contractor, SubmitRequest calldata _request) internal view {
        // Ensure the authorization has not expired.
        if (_request.expiration < block.timestamp) revert Escrow__AuthorizationExpired();

        // Generate the hash for signature verification.
        bytes32 hash = keccak256(
            abi.encodePacked(
                _request.contractId,
                _contractor,
                _request.data,
                _request.salt,
                _request.expiration,
                address(this) // Prevents cross-contract replay attacks.
            )
        );
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(hash);

        // Retrieve the admin signer from the EscrowAdminManager.
        address adminSigner = adminManager.owner();

        // Verify ECDSA signature (admin must sign the submission).
        if (!SignatureChecker.isValidSignatureNow(adminSigner, ethSignedHash, _request.signature)) {
            revert Escrow__InvalidSignature();
        }
    }
}
