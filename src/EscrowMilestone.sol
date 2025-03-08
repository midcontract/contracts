// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { SafeTransferLib } from "@solbase/utils/SafeTransferLib.sol";
import { SignatureChecker } from "@openzeppelin/utils/cryptography/SignatureChecker.sol";

import { IEscrowAdminManager } from "./interfaces/IEscrowAdminManager.sol";
import { IEscrowMilestone, IEscrow } from "./interfaces/IEscrowMilestone.sol";
import { IEscrowFeeManager } from "./interfaces/IEscrowFeeManager.sol";
import { IEscrowRegistry } from "./interfaces/IEscrowRegistry.sol";
import { ECDSA, ERC1271 } from "./common/ERC1271.sol";
import { Enums } from "./common/Enums.sol";

/// @title Milestone Management for Escrow Agreements
/// @notice Facilitates the management of milestones within escrow contracts, including the creation, modification, and
/// completion of milestones.
contract EscrowMilestone is IEscrowMilestone, ERC1271 {
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

    /// @notice The maximum number of milestones that can be processed in a single transaction.
    uint256 public maxMilestones;

    /// @dev Indicates that the contract has been initialized.
    bool public initialized;

    /// @dev Maps each contract ID to an array of `Milestone` structs, representing the milestones of the contract.
    mapping(uint256 contractId => Milestone[]) public contractMilestones;

    /// @dev Maps each contract and milestone ID pair to its corresponding MilestoneDetails.
    mapping(uint256 contractId => mapping(uint256 milestoneId => MilestoneDetails)) public milestoneDetails;

    /// @dev Maps each contract ID and milestone ID pair to its previous status before the return request.
    mapping(uint256 contractId => mapping(uint256 milestoneId => Enums.Status)) public previousStatuses;

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
        maxMilestones = 10; // Default value.
        initialized = true;
    }

    /*//////////////////////////////////////////////////////////////
                    ESCROW MILESTONE UNDERLYING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates multiple milestones for a new or existing contract.
    /// @dev This function allows the initialization of multiple milestones in a single transaction,
    ///     either by creating a new contract or adding to an existing one. Uses the adjustable limit `maxMilestones`
    ///     to prevent gas limit issues.
    ///     Uses authorization validation to prevent tampering or unauthorized deposits.
    /// @param _deposit DepositRequest struct containing all deposit details.
    function deposit(DepositRequest calldata _deposit, Milestone[] calldata _milestones) external onlyClient {
        // Check for blacklisted accounts and unsupported payment tokens.
        if (registry.blacklist(msg.sender)) revert Escrow__BlacklistedAccount();
        if (!registry.paymentTokens(_deposit.paymentToken)) revert Escrow__NotSupportedPaymentToken();

        // Ensure there are milestones provided and do not exceed the limit.
        uint256 milestonesLength = _milestones.length;
        if (milestonesLength == 0) revert Escrow__NoDepositsProvided();
        if (milestonesLength > maxMilestones) revert Escrow__TooManyMilestones();

        // Verify hash integrity.
        bytes32 computedHash = _hashMilestones(_milestones);
        if (computedHash != _deposit.milestonesHash) revert Escrow__InvalidMilestonesHash();

        // Validate authorization using a single signature for the entire request.
        _validateDepositAuthorization(_deposit);

        // Ensure the provided `contractId` is valid.
        uint256 contractId = _deposit.contractId;
        if (contractId == 0) revert Escrow__InvalidContractId();

        // Handle new or existing contracts.
        if (contractMilestones[contractId].length == 0) {
            // New contract initialization.
            if (milestoneDetails[contractId][0].paymentToken != address(0)) revert Escrow__ContractIdAlreadyExists();

            // Initialize contract milestone metadata.
            milestoneDetails[contractId][0].paymentToken = _deposit.paymentToken;
        } else {
            // Validate consistency for existing contracts.
            if (milestoneDetails[contractId][0].paymentToken != _deposit.paymentToken) {
                revert Escrow__PaymentTokenMismatch();
            }
        }

        // Calculate the required deposit amounts for each milestone to ensure sufficient funds are transferred.
        uint256 totalAmountNeeded = 0;
        // uint256 milestonesLength = _milestones.length;
        for (uint256 i; i < milestonesLength;) {
            if (_milestones[i].amount == 0) revert Escrow__ZeroDepositAmount();
            (uint256 totalDepositAmount,) =
                _computeDepositAmountAndFee(contractId, msg.sender, _milestones[i].amount, _milestones[i].feeConfig);
            totalAmountNeeded += totalDepositAmount;
            unchecked {
                ++i;
            }
        }

        // Perform the token transfer once to cover all milestone deposits.
        SafeTransferLib.safeTransferFrom(_deposit.paymentToken, msg.sender, address(this), totalAmountNeeded);

        // Start adding milestones to the contract.
        uint256 milestoneId = contractMilestones[contractId].length;
        for (uint256 i; i < milestonesLength;) {
            Milestone calldata M = _milestones[i];

            // Add the new deposit as a new milestone.
            contractMilestones[contractId].push(
                Milestone({
                    contractor: M.contractor, // Initialize with contractor assigned, can be zero address initially.
                    amount: M.amount,
                    amountToClaim: 0, // Initialize claimable amount to zero.
                    amountToWithdraw: 0, // Initialize withdrawable amount to zero.
                    contractorData: M.contractorData,
                    feeConfig: M.feeConfig,
                    status: Enums.Status.ACTIVE // Set the initial status of the milestone.
                 })
            );

            // Update milestone details and initialize it in the mapping.
            MilestoneDetails storage D = milestoneDetails[contractId][milestoneId];
            D.paymentToken = _deposit.paymentToken;
            D.depositAmount = M.amount;
            D.winner = Enums.Winner.NONE; // Initially set to NONE.

            // Emit an event to indicate a successful deposit of a milestone.
            emit Deposited(msg.sender, contractId, milestoneId, M.amount, M.contractor);

            unchecked {
                ++i;
                ++milestoneId;
            }
        }
    }

    /// @notice Submits work for a milestone by the contractor.
    /// @dev Uses an admin-signed authorization to verify submission legitimacy,
    ///      ensuring multiple submissions are uniquely signed and replay-proof.
    /// @param _request Struct containing all required parameters for submission.
    function submit(SubmitRequest calldata _request) external {
        // Ensure that the specified milestone exists within the bounds of the contract's milestones.
        if (_request.milestoneId >= contractMilestones[_request.contractId].length) revert Escrow__InvalidMilestoneId();

        Milestone storage M = contractMilestones[_request.contractId][_request.milestoneId];

        // Only allow the designated contractor to submit, or allow initial submission if no contractor has been set.
        if (M.contractor != address(0) && msg.sender != M.contractor) {
            revert Escrow__UnauthorizedAccount(msg.sender);
        }

        // Ensure that the milestone is in a state that allows submission.
        if (M.status != Enums.Status.ACTIVE) revert Escrow__InvalidStatusForSubmit();

        // Compute hash with contractor binding.
        bytes32 contractorDataHash = _getContractorDataHash(msg.sender, _request.data, _request.salt);

        // Verify that the computed hash matches stored contractor data.
        if (M.contractorData != contractorDataHash) revert Escrow__InvalidContractorDataHash();

        // Validate the submission using admin-signed approval.
        _validateSubmitAuthorization(msg.sender, _request);

        // Update the contractor information and status to SUBMITTED.
        M.contractor = msg.sender; // Assign the contractor if not previously set.
        M.status = Enums.Status.SUBMITTED;

        // Emit an event indicating successful submission of the milestone.
        emit Submitted(msg.sender, _request.contractId, _request.milestoneId, client);
    }

    /// @notice Approves a milestone's submitted work, specifying the amount to release to the contractor.
    /// @dev This function allows the client or an authorized admin to approve work submitted for a milestone,
    /// specifying the amount to be released.
    /// @param _contractId ID of the contract containing the milestone.
    /// @param _milestoneId ID of the milestone within the contract to be approved.
    /// @param _amountApprove Amount to be released for the milestone.
    /// @param _receiver Address of the contractor receiving the approved amount.
    function approve(uint256 _contractId, uint256 _milestoneId, uint256 _amountApprove, address _receiver) external {
        // Ensure the caller is either the client or an authorized admin.
        if (msg.sender != client && !IEscrowAdminManager(adminManager).isAdmin(msg.sender)) {
            revert Escrow__UnauthorizedAccount(msg.sender);
        }

        // Ensure a non-zero amount is being approved.
        if (_amountApprove == 0) revert Escrow__InvalidAmount();

        Milestone storage M = contractMilestones[_contractId][_milestoneId];

        // Ensure the milestone is in a status that can be approved.
        if (M.status != Enums.Status.SUBMITTED) revert Escrow__InvalidStatusForApprove();

        // Ensure the receiver is authorized to receive the funds.
        if (M.contractor != _receiver) revert Escrow__UnauthorizedReceiver();

        // Ensure there are sufficient funds in the deposit to cover the approval amount.
        if (M.amountToClaim + _amountApprove > M.amount) revert Escrow__NotEnoughDeposit();

        // Update the milestone's claimable amount and status.
        M.amountToClaim += _amountApprove;
        M.status = Enums.Status.APPROVED;

        // Emit an event indicating the approval.
        emit Approved(msg.sender, _contractId, _milestoneId, _amountApprove, _receiver);
    }

    /// @notice Adds additional funds to a milestone's budget within a contract.
    /// @dev Allows a client to add funds to a specific milestone, updating the total deposit amount for that milestone.
    /// @param _contractId ID of the contract containing the milestone.
    /// @param _milestoneId ID of the milestone within the contract to be refilled.
    /// @param _amountAdditional The additional amount to be added to the milestone's budget.
    function refill(uint256 _contractId, uint256 _milestoneId, uint256 _amountAdditional) external onlyClient {
        if (registry.blacklist(msg.sender)) revert Escrow__BlacklistedAccount();
        if (_amountAdditional == 0) revert Escrow__InvalidAmount();

        Milestone storage M = contractMilestones[_contractId][_milestoneId];

        // Compute the total amount including any applicable fees.
        (uint256 totalAmountAdditional, uint256 feeApplied) =
            _computeDepositAmountAndFee(_contractId, msg.sender, _amountAdditional, M.feeConfig);
        (feeApplied);

        MilestoneDetails storage D = milestoneDetails[_contractId][_milestoneId];

        // Transfer funds from the client to the contract, adjusted for fees.
        SafeTransferLib.safeTransferFrom(D.paymentToken, msg.sender, address(this), totalAmountAdditional);

        // Update the deposit amount by adding the additional amount.
        M.amount += _amountAdditional;

        // Emit an event to log the refill action.
        emit Refilled(msg.sender, _contractId, _milestoneId, _amountAdditional);
    }

    /// @notice Allows the contractor to claim the approved amount for a milestone within a contract.
    /// @dev Handles the transfer of approved amounts to the contractor while adjusting for any applicable fees.
    /// @param _contractId ID of the contract containing the milestone.
    /// @param _milestoneId ID of the milestone from which funds are to be claimed.
    function claim(uint256 _contractId, uint256 _milestoneId) external {
        Milestone storage M = contractMilestones[_contractId][_milestoneId];
        if (msg.sender != M.contractor) revert Escrow__UnauthorizedAccount(msg.sender);
        if (M.status != Enums.Status.APPROVED && M.status != Enums.Status.RESOLVED && M.status != Enums.Status.CANCELED)
        {
            revert Escrow__InvalidStatusToClaim(); // Ensure only milestones in appropriate statuses can be claimed.
        }
        if (M.amountToClaim == 0) revert Escrow__NotApproved(); // Ensure there is an amount to claim.

        // Calculate the claimable amount and fees.
        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
            _computeClaimableAmountAndFee(_contractId, msg.sender, M.amountToClaim, M.feeConfig);

        // Update the milestone's details post-claim.
        M.amount -= M.amountToClaim;
        M.amountToClaim = 0;

        MilestoneDetails storage D = milestoneDetails[_contractId][_milestoneId];

        // Transfer the claimable amount to the contractor.
        SafeTransferLib.safeTransfer(D.paymentToken, msg.sender, claimAmount);

        // Handle platform fees if applicable.
        if ((M.status == Enums.Status.RESOLVED || M.status == Enums.Status.CANCELED) && feeAmount > 0) {
            _sendPlatformFee(D.paymentToken, feeAmount);
        } else if (feeAmount > 0 || clientFee > 0) {
            _sendPlatformFee(D.paymentToken, feeAmount + clientFee);
        }

        // Update the milestone status to COMPLETED if all funds have been claimed.
        if (M.amount == 0) M.status = Enums.Status.COMPLETED;

        // Emit an event to log the claim.
        emit Claimed(msg.sender, _contractId, _milestoneId, claimAmount, feeAmount, client);
    }

    /// @notice Claims all approved amounts by the contractor for a given contract.
    /// @dev Allows the contractor to claim for multiple milestones in a specified range.
    /// @param _contractId ID of the contract from which to claim funds.
    /// @param _startMilestoneId Starting milestone ID from which to begin claims.
    /// @param _endMilestoneId Ending milestone ID until which claims are made.
    /// This function mitigates gas exhaustion issues by allowing batch processing within a specified limit.
    function claimAll(uint256 _contractId, uint256 _startMilestoneId, uint256 _endMilestoneId) external {
        if (_startMilestoneId > _endMilestoneId) revert Escrow__InvalidRange();
        if (_endMilestoneId >= contractMilestones[_contractId].length) revert Escrow__OutOfRange();

        uint256 totalClaimedAmount = 0;
        uint256 totalFeeAmount = 0;
        uint256 totalClientFee = 0;

        Milestone[] storage milestones = contractMilestones[_contractId];
        MilestoneDetails storage D = milestoneDetails[_contractId][0]; // Assume same payment token for all milestones.

        for (uint256 i = _startMilestoneId; i <= _endMilestoneId; ++i) {
            Milestone storage M = milestones[i];

            if (M.contractor != msg.sender) continue; // Only process milestones for the calling contractor.

            if (
                M.amountToClaim == 0
                    || (
                        M.status != Enums.Status.APPROVED && M.status != Enums.Status.RESOLVED
                            && M.status != Enums.Status.CANCELED
                    )
            ) {
                continue; // Skip processing if nothing to claim or not in a claimable state.
            }
            (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
                _computeClaimableAmountAndFee(_contractId, msg.sender, M.amountToClaim, M.feeConfig);

            M.amount -= M.amountToClaim;
            totalClaimedAmount += claimAmount;
            totalFeeAmount += feeAmount;
            if (M.status != Enums.Status.RESOLVED && M.status != Enums.Status.CANCELED) {
                totalClientFee += clientFee;
            }

            M.amountToClaim = 0; // Reset the claimable amount after claiming.
            if (M.amount == 0) M.status = Enums.Status.COMPLETED; // Update the status if all funds have been claimed.
        }

        // Token transfers are batched at the end to minimize gas costs.
        if (totalClaimedAmount > 0) {
            SafeTransferLib.safeTransfer(D.paymentToken, msg.sender, totalClaimedAmount);
        }

        // Consolidate and send platform fees in one transaction if applicable.
        if (totalFeeAmount > 0 || totalClientFee > 0) {
            _sendPlatformFee(D.paymentToken, totalFeeAmount + totalClientFee);
        }

        emit BulkClaimed(
            msg.sender,
            _contractId,
            _startMilestoneId,
            _endMilestoneId,
            totalClaimedAmount,
            totalFeeAmount,
            totalClientFee,
            client
        );
    }

    /// @notice Withdraws funds from a milestone under specific conditions.
    /// @dev Withdrawal depends on the milestone being approved for refund or resolved.
    /// @param _contractId The identifier of the contract from which to withdraw funds.
    /// @param _milestoneId The identifier of the milestone within the contract from which to withdraw funds.
    function withdraw(uint256 _contractId, uint256 _milestoneId) external onlyClient {
        Milestone storage M = contractMilestones[_contractId][_milestoneId];
        if (M.status != Enums.Status.REFUND_APPROVED && M.status != Enums.Status.RESOLVED) {
            revert Escrow__InvalidStatusToWithdraw();
        }

        if (M.amountToWithdraw == 0) revert Escrow__NoFundsAvailableForWithdraw();

        // Calculate the fee based on the amount to be withdrawn.
        (, uint256 feeAmount) = _computeDepositAmountAndFee(_contractId, msg.sender, M.amountToWithdraw, M.feeConfig);

        MilestoneDetails storage D = milestoneDetails[_contractId][_milestoneId];
        uint256 initialFeeAmount;
        // Distinguish between fee calculations based on milestone status or dispute resolution.
        if (M.status == Enums.Status.REFUND_APPROVED) {
            // Regular fee calculation from the current amount.
            (, initialFeeAmount) = _computeDepositAmountAndFee(_contractId, msg.sender, M.amount, M.feeConfig);
        } else if (M.status == Enums.Status.RESOLVED && D.winner == Enums.Winner.SPLIT) {
            // Special case for split resolutions.
            (, initialFeeAmount) = _computeDepositAmountAndFee(_contractId, msg.sender, D.depositAmount, M.feeConfig);
        } else {
            // Default case for resolved or canceled without split, using current amount.
            (, initialFeeAmount) = _computeDepositAmountAndFee(_contractId, msg.sender, M.amount, M.feeConfig);
        }

        uint256 platformFee = (initialFeeAmount > feeAmount) ? (initialFeeAmount - feeAmount) : 0;

        M.amount -= M.amountToWithdraw;
        uint256 withdrawAmount = M.amountToWithdraw + feeAmount;
        M.amountToWithdraw = 0; // Prevent re-withdrawal.

        SafeTransferLib.safeTransfer(D.paymentToken, msg.sender, withdrawAmount);

        if (platformFee > 0) {
            _sendPlatformFee(D.paymentToken, platformFee);
        }

        M.status = Enums.Status.CANCELED; // Mark the deposit as canceled after funds are withdrawn.

        // Emit an event to log the withdraw.
        emit Withdrawn(msg.sender, _contractId, _milestoneId, withdrawAmount, platformFee);
    }

    /*//////////////////////////////////////////////////////////////
                ESCROW RETURN REQUEST & DISPUTE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Requests the return of funds by the client for a specific milestone.
    /// @dev The milestone must be in an eligible state to request a return (not in disputed or already returned
    /// status).
    /// @param _contractId ID of the deposit for which the return is requested.
    /// @param _milestoneId ID of the milestone for which the return is requested.
    function requestReturn(uint256 _contractId, uint256 _milestoneId) external onlyClient {
        Milestone storage M = contractMilestones[_contractId][_milestoneId];
        if (
            M.status != Enums.Status.ACTIVE && M.status != Enums.Status.SUBMITTED && M.status != Enums.Status.APPROVED
                && M.status != Enums.Status.COMPLETED
        ) revert Escrow__ReturnNotAllowed();

        // Store the current status before changing it to RETURN_REQUESTED.
        previousStatuses[_contractId][_milestoneId] = M.status;

        M.status = Enums.Status.RETURN_REQUESTED;
        emit ReturnRequested(msg.sender, _contractId, _milestoneId);
    }

    /// @notice Approves the return of funds, which can be called by the contractor or platform admin.
    /// @dev This changes the status of the milestone to allow the client to withdraw their funds.
    /// @param _contractId ID of the milestone for which the return is approved.
    /// @param _milestoneId ID of the milestone for which the return is approved.
    function approveReturn(uint256 _contractId, uint256 _milestoneId) external {
        Milestone storage M = contractMilestones[_contractId][_milestoneId];
        if (M.status != Enums.Status.RETURN_REQUESTED) revert Escrow__NoReturnRequested();
        if (msg.sender != M.contractor && !IEscrowAdminManager(adminManager).isAdmin(msg.sender)) {
            revert Escrow__UnauthorizedToApproveReturn();
        }
        M.amountToWithdraw = M.amount;
        M.status = Enums.Status.REFUND_APPROVED;
        emit ReturnApproved(msg.sender, _contractId, _milestoneId, client);
    }

    /// @notice Cancels a previously requested return and resets the milestone's status.
    /// @dev Reverts the status from RETURN_REQUESTED to the previous status stored in `previousStatuses`.
    /// @param _contractId The unique identifier of the milestone for which the return is being cancelled.
    /// @param _milestoneId ID of the milestone for which the return is being cancelled.
    function cancelReturn(uint256 _contractId, uint256 _milestoneId) external onlyClient {
        Milestone storage M = contractMilestones[_contractId][_milestoneId];
        if (M.status != Enums.Status.RETURN_REQUESTED) revert Escrow__NoReturnRequested();

        M.status = previousStatuses[_contractId][_milestoneId];
        delete previousStatuses[_contractId][_milestoneId];

        emit ReturnCanceled(msg.sender, _contractId, _milestoneId);
    }

    /// @notice Creates a dispute over a specific milestone.
    /// @dev Initiates a dispute status for a milestone that can be activated by the client or contractor
    /// when they disagree on the previously submitted work.
    /// @param _contractId ID of the milestone where the dispute occurred.
    /// @param _milestoneId ID of the milestone where the dispute occurred.
    /// This function can only be called if the milestone status is either RETURN_REQUESTED or SUBMITTED.
    function createDispute(uint256 _contractId, uint256 _milestoneId) external {
        Milestone storage M = contractMilestones[_contractId][_milestoneId];
        if (M.status != Enums.Status.RETURN_REQUESTED && M.status != Enums.Status.SUBMITTED) {
            revert Escrow__CreateDisputeNotAllowed();
        }
        if (msg.sender != client && msg.sender != M.contractor) revert Escrow__UnauthorizedToApproveDispute();

        M.status = Enums.Status.DISPUTED;
        emit DisputeCreated(msg.sender, _contractId, _milestoneId, client);
    }

    /// @notice Resolves a dispute over a specific milestone.
    /// @dev Handles the resolution of disputes by assigning the funds according to the outcome of the dispute.
    /// Admin intervention is required to resolve disputes to ensure fairness.
    /// @param _contractId ID of the milestone where the dispute occurred.
    /// @param _milestoneId ID of the milestone where the dispute occurred.
    /// @param _winner Specifies who the winner is: Client, Contractor, or Split.
    /// @param _clientAmount Amount to be allocated to the client if Split or Client wins.
    /// @param _contractorAmount Amount to be allocated to the contractor if Split or Contractor wins.
    /// This function ensures that the total resolution amounts do not exceed the deposited amount and adjusts the
    /// status of the milestone based on the dispute outcome.
    function resolveDispute(
        uint256 _contractId,
        uint256 _milestoneId,
        Enums.Winner _winner,
        uint256 _clientAmount,
        uint256 _contractorAmount
    ) external {
        if (!IEscrowAdminManager(adminManager).isAdmin(msg.sender)) revert Escrow__UnauthorizedAccount(msg.sender);
        Milestone storage M = contractMilestones[_contractId][_milestoneId];
        if (M.status != Enums.Status.DISPUTED) revert Escrow__DisputeNotActiveForThisDeposit();

        // Validate the total resolution does not exceed the available deposit amount.
        uint256 totalResolutionAmount = _clientAmount + _contractorAmount;
        if (totalResolutionAmount > M.amount) revert Escrow__ResolutionExceedsDepositedAmount();

        // Apply resolution based on the winner.
        M.amountToClaim = (_winner == Enums.Winner.CONTRACTOR || _winner == Enums.Winner.SPLIT) ? _contractorAmount : 0;
        if (_winner == Enums.Winner.CONTRACTOR) {
            M.status = Enums.Status.APPROVED; // Status that allows the contractor to claim.
            M.amountToWithdraw = 0; // No amount for the client to withdraw.
        } else {
            M.status = Enums.Status.RESOLVED; // Sets the status to resolved for both Client and Split outcomes.
            M.amountToWithdraw = (_winner == Enums.Winner.CLIENT || _winner == Enums.Winner.SPLIT) ? _clientAmount : 0;
        }

        milestoneDetails[_contractId][_milestoneId].winner = _winner;

        emit DisputeResolved(msg.sender, _contractId, _milestoneId, _winner, _clientAmount, _contractorAmount, client);
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
    /// @param _milestoneId The identifier of the milestone for which contractor ownership is being transferred.
    /// @param _newAccount The address to which the contractor ownership will be transferred.
    function transferContractorOwnership(uint256 _contractId, uint256 _milestoneId, address _newAccount) external {
        if (msg.sender != registry.accountRecovery()) revert Escrow__UnauthorizedAccount(msg.sender);
        if (_newAccount == address(0)) revert Escrow__ZeroAddressProvided();

        Milestone storage M = contractMilestones[_contractId][_milestoneId];

        // Emit the ownership transfer event before changing the state to reflect the previous state.
        emit ContractorOwnershipTransferred(_contractId, _milestoneId, M.contractor, _newAccount);

        // Update the contractor address to the new owner's address.
        M.contractor = _newAccount;
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

    /// @notice Sets the maximum number of milestones that can be added in a single transaction.
    /// @dev This limit helps prevent gas limit issues during bulk operations and can be adjusted by the contract admin.
    /// @param _maxMilestones The new maximum number of milestones.
    function setMaxMilestones(uint256 _maxMilestones) external {
        if (!IEscrowAdminManager(adminManager).isAdmin(msg.sender)) revert Escrow__UnauthorizedAccount(msg.sender);
        if (_maxMilestones == 0 || _maxMilestones > 20) revert Escrow__InvalidMilestoneLimit();
        maxMilestones = _maxMilestones;
        emit MaxMilestonesSet(_maxMilestones);
    }

    /// @notice Checks if a given contract ID exists.
    /// @param _contractId The contract ID to check.
    /// @return bool True if the contract exists, false otherwise.
    function contractExists(uint256 _contractId) external view returns (bool) {
        return contractMilestones[_contractId].length > 0;
    }

    /// @notice Retrieves the number of milestones for a given contract ID.
    /// @param _contractId The contract ID for which to retrieve the milestone count.
    /// @return The number of milestones associated with the given contract ID.
    function getMilestoneCount(uint256 _contractId) external view returns (uint256) {
        return contractMilestones[_contractId].length;
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

    /// @notice Generates the hash required for deposit signing in EscrowMilestone.
    /// @param _client The address of the client submitting the deposit.
    /// @param _contractId The unique contract ID associated with the deposit.
    /// @param _paymentToken The ERC20 token used for the deposit.
    /// @param _milestonesHash The hash representing the milestones structure.
    /// @param _expiration The timestamp when the deposit authorization expires.
    /// @return ethSignedHash The Ethereum signed message hash that needs to be signed.
    function getDepositHash(
        address _client,
        uint256 _contractId,
        address _paymentToken,
        bytes32 _milestonesHash,
        uint256 _expiration
    ) external view returns (bytes32) {
        // Generate the raw hash using the same structure as `_validateDepositAuthorization`.
        bytes32 hash = keccak256(
            abi.encodePacked(_client, _contractId, _paymentToken, _milestonesHash, _expiration, address(this))
        );

        // Apply Ethereum’s signed message prefix (same as ECDSA.toEthSignedMessageHash).
        return ECDSA.toEthSignedMessageHash(hash);
    }

    /// @notice Computes a hash for the given array of milestones.
    /// @param _milestones The array of milestones to hash.
    /// @return bytes32 The combined hash of all the milestones.
    function hashMilestones(Milestone[] calldata _milestones) public pure returns (bytes32) {
        return _hashMilestones(_milestones);
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
        IEscrowFeeManager feeManager = IEscrowFeeManager(feeManagerAddress);

        (totalDepositAmount, feeApplied) =
            feeManager.computeDepositAmountAndFee(address(this), _contractId, _client, _depositAmount, _feeConfig);

        return (totalDepositAmount, feeApplied);
    }

    /// @notice Computes the claimable amount and the fee deducted from the claimed amount.
    /// @dev This internal function calculates the claimable amount for the contractor and the fees deducted from the
    /// claimed amount based on the contractor, claimed amount, and fee configuration.
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
        address treasury = IEscrowRegistry(registry).milestoneTreasury();
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
        // Check if msg.sender is a contract.
        if (msg.sender.code.length > 0) {
            // ERC-1271 signature verification.
            return SignatureChecker.isValidERC1271SignatureNow(msg.sender, _hash, _signature);
        } else {
            // EOA signature verification.
            bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(_hash);
            address recoveredSigner = ECDSA.recover(ethSignedHash, _signature);
            return recoveredSigner == msg.sender;
        }
    }

    /// @notice Validates the deposit request using a single signature.
    /// @dev Ensures the signature is signed off-chain and matches the provided parameters.
    /// @param _deposit The deposit details including signature, expiration, and milestones hash.
    function _validateDepositAuthorization(DepositRequest calldata _deposit) internal view {
        if (_deposit.expiration < block.timestamp) revert Escrow__AuthorizationExpired();

        bytes32 hash = keccak256(
            abi.encodePacked(
                msg.sender,
                _deposit.contractId,
                _deposit.paymentToken,
                _deposit.milestonesHash,
                _deposit.expiration,
                address(this)
            )
        );
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(hash);
        address signer = adminManager.owner();
        if (!SignatureChecker.isValidSignatureNow(signer, ethSignedHash, _deposit.signature)) {
            revert Escrow__InvalidSignature();
        }
    }

    /// @notice Hashes all milestones into a single bytes32 hash.
    /// @dev Used internally to compute a unique identifier for an array of milestones.
    /// @param _milestones Array of milestones to hash.
    /// @return bytes32 Combined hash of all milestones.
    function _hashMilestones(Milestone[] calldata _milestones) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](_milestones.length);

        for (uint256 i = 0; i < _milestones.length; i++) {
            hashes[i] = keccak256(
                abi.encode(
                    _milestones[i].contractor,
                    _milestones[i].amount,
                    _milestones[i].contractorData,
                    _milestones[i].feeConfig
                )
            );
        }

        return keccak256(abi.encodePacked(hashes));
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
                _request.milestoneId,
                _contractor,
                _request.data,
                _request.salt,
                _request.expiration,
                address(this)
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
