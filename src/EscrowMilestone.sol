// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { SafeTransferLib } from "@solbase/utils/SafeTransferLib.sol";
import { SignatureChecker } from "@openzeppelin/utils/cryptography/SignatureChecker.sol";

import { IEscrowAdminManager } from "./interfaces/IEscrowAdminManager.sol";
import { IEscrowMilestone , IEscrow } from "./interfaces/IEscrowMilestone.sol";
import { IEscrowFeeManager} from "./interfaces/IEscrowFeeManager.sol";
import { IEscrowRegistry} from "./interfaces/IEscrowRegistry.sol";
import { ECDSA, ERC1271 } from "./libs/ERC1271.sol";
import { Enums } from "./libs/Enums.sol";

/// @title Milestone Management for Escrow Agreements
/// @notice Facilitates the management of milestones within escrow contracts, including the creation, modification, and completion of milestones.
/// @dev Extends functionality for escrow systems by enabling detailed milestone management.
contract EscrowMilestone is IEscrowMilestone, ERC1271 {
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

    /// @notice The maximum number of milestones that can be processed in a single transaction.
    /// @dev This limit helps prevent gas limit issues during bulk operations and can be adjusted by the contract admin.
    uint256 public maxMilestonesPerTransaction;

    /// @dev Indicates that the contract has been initialized.
    bool public initialized;

    /// @notice Maps each contract ID to an array of `Milestone` structs, representing the milestones of the contract.
    /// @dev Stores milestones for each contract, indexed by contract ID.
    mapping(uint256 contractId => Milestone[]) public contractMilestones;

    /// @notice Maps each contract and milestone ID pair to its corresponding MilestoneDetails for easy retrieval.
    /// @dev This mapping serves as a repository for detailed attributes of each milestone, allowing for efficient data lookup and management.
    mapping(uint256 contractId => mapping(uint256 milestoneId => MilestoneDetails)) public milestoneDetails;

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
        maxMilestonesPerTransaction = 10; // Default value.

        initialized = true;
    }

    /*//////////////////////////////////////////////////////////////
                    ESCROW MILESTONE UNDERLYING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates multiple milestones for a new or existing contract.
    /// @dev This function allows the initialization of multiple milestones in a single transaction,
    ///     either by creating a new contract or adding to an existing one. Uses the adjustable limit `maxMilestonesPerTransaction`
    ///     to prevent gas limit issues.
    /// @param _contractId ID of the contract for which the deposits are made; if zero, a new contract is initialized.
    /// @param _paymentToken  The address of the payment token for the contractId.
    /// @param _milestones Array of details for each new milestone.
    function deposit(uint256 _contractId, address _paymentToken, Milestone[] calldata _milestones)
        external
        onlyClient
    {
        // Check for blacklisted accounts and unsupported payment tokens.
        if (registry.blacklist(msg.sender)) revert Escrow__BlacklistedAccount();
        if (!registry.paymentTokens(_paymentToken)) revert Escrow__NotSupportedPaymentToken();

        // Ensure there are milestones provided and do not exceed the limit.
        if (_milestones.length == 0) revert Escrow__NoDepositsProvided();
        if (_milestones.length > maxMilestonesPerTransaction) revert Escrow__TooManyMilestones();

        // Initialize or validate the contract ID.
        uint256 contractId = _contractId == 0 ? ++currentContractId : _contractId;
        if (_contractId > 0 && (contractMilestones[_contractId].length == 0 && _contractId > currentContractId)) {
            revert Escrow__InvalidContractId();
        }

        // Calculate the required deposit amounts for each milestone to ensure sufficient funds are transferred.
        uint256 totalAmountNeeded = 0;
        uint256 milestonesLength = _milestones.length;
        for (uint256 i; i < milestonesLength;) {
            if (_milestones[i].amount == 0) revert Escrow__ZeroDepositAmount();
            (uint256 totalDepositAmount,) =
                _computeDepositAmountAndFee(msg.sender, _milestones[i].amount, _milestones[i].feeConfig);
            totalAmountNeeded += totalDepositAmount;
            unchecked {
                i++;
            }
        }

        // Perform the token transfer once to cover all milestone deposits.
        SafeTransferLib.safeTransferFrom(_paymentToken, msg.sender, address(this), totalAmountNeeded);

        // Start adding milestones to the contract.
        uint256 milestoneId = contractMilestones[contractId].length;
        for (uint256 i; i < milestonesLength;) {
            Milestone calldata M = _milestones[i];

            // Add the new deposit as a new milestone.
            contractMilestones[contractId].push(
                Milestone({
                    contractor: M.contractor, // Initialize with contractor assigned, could be zero address on initial stage.
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
            D.paymentToken = _paymentToken;
            D.depositAmount = M.amount;
            D.winner = Enums.Winner.NONE; // Initially set to NONE.

            // Emit an event to indicate a successful deposit of a milestone.
            emit Deposited(msg.sender, contractId, milestoneId, _paymentToken, M.amount, M.feeConfig);

            unchecked {
                i++;
                milestoneId++;
            }
        }
    }

    /// @notice Submits work for a milestone by the contractor.
    /// @dev This function allows the contractor to submit their work details for a milestone.
    /// @param _contractId ID of the contract containing the milestone.
    /// @param _milestoneId ID of the milestone to submit work for.
    /// @param _data Contractor’s details or work summary.
    /// @param _salt Unique salt for cryptographic operations.
    function submit(uint256 _contractId, uint256 _milestoneId, bytes calldata _data, bytes32 _salt) external {
        // Ensure that the specified milestone exists within the bounds of the contract's milestones.
        if (_milestoneId >= contractMilestones[_contractId].length) revert Escrow__InvalidMilestoneId();

        Milestone storage M = contractMilestones[_contractId][_milestoneId];

        // Only allow the designated contractor to submit, or allow initial submission if no contractor has been set.
        if (M.contractor != address(0) && msg.sender != M.contractor) {
            revert Escrow__UnauthorizedAccount(msg.sender);
        }

        // Ensure that the milestone is in a state that allows submission.
        if (M.status != Enums.Status.ACTIVE) revert Escrow__InvalidStatusForSubmit();

        // Verify contractor's data using a hash function to ensure it matches expected details.
        bytes32 contractorDataHash = _getContractorDataHash(_data, _salt);
        if (M.contractorData != contractorDataHash) revert Escrow__InvalidContractorDataHash();

        // Update the contractor information and status to SUBMITTED.
        M.contractor = msg.sender; // Assign the contractor if not previously set.
        M.status = Enums.Status.SUBMITTED;

        // Emit an event indicating successful submission of the milestone.
        emit Submitted(msg.sender, _contractId, _milestoneId);
    }

    /// @notice Approves a milestone's submitted work, specifying the amount to release to the contractor.
    /// @dev This function allows the client or an authorized admin to approve work submitted for a milestone, specifying the amount to be released.
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
    /// @dev This function allows a client to add funds to a specific milestone, updating the total deposit amount for that milestone.
    /// @param _contractId ID of the contract containing the milestone.
    /// @param _milestoneId ID of the milestone within the contract to be refilled.
    /// @param _amountAdditional The additional amount to be added to the milestone's budget.
    function refill(uint256 _contractId, uint256 _milestoneId, uint256 _amountAdditional) external onlyClient {
        if (registry.blacklist(msg.sender)) revert Escrow__BlacklistedAccount(); // Check if the client is blacklisted.
        if (_amountAdditional == 0) revert Escrow__InvalidAmount(); // Ensure a valid amount is being added.

        Milestone storage M = contractMilestones[_contractId][_milestoneId];

        // Compute the total amount including any applicable fees.
        (uint256 totalAmountAdditional, uint256 feeApplied) =
            _computeDepositAmountAndFee(msg.sender, _amountAdditional, M.feeConfig);
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
        if (registry.blacklist(msg.sender)) revert Escrow__BlacklistedAccount(); // Prevent blacklisted accounts from claiming.

        Milestone storage M = contractMilestones[_contractId][_milestoneId];
        if (msg.sender != M.contractor) revert Escrow__UnauthorizedAccount(msg.sender);
        if (M.status != Enums.Status.APPROVED && M.status != Enums.Status.RESOLVED && M.status != Enums.Status.CANCELED)
        {
            revert Escrow__InvalidStatusToClaim(); // Ensure only milestones in appropriate statuses can be claimed.
        }
        if (M.amountToClaim == 0) revert Escrow__NotApproved(); // Ensure there is an amount to claim.

        // Calculate the claimable amount and fees.
        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
            _computeClaimableAmountAndFee(msg.sender, M.amountToClaim, M.feeConfig);

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
        emit Claimed(msg.sender, _contractId, _milestoneId, claimAmount);
    }

    /// @notice Claims all approved amounts by the contractor for a given contract.
    /// @dev Allows the contractor to claim for multiple milestones in a specified range to manage gas costs effectively.
    /// @param _contractId ID of the contract from which to claim funds.
    /// @param _startMilestoneId Starting milestone ID from which to begin claims.
    /// @param _endMilestoneId Ending milestone ID until which claims are made.
    /// This function mitigates gas exhaustion issues by allowing batch processing within a specified limit.
    function claimAll(uint256 _contractId, uint256 _startMilestoneId, uint256 _endMilestoneId) external {
        if (registry.blacklist(msg.sender)) revert Escrow__BlacklistedAccount();
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
                _computeClaimableAmountAndFee(msg.sender, M.amountToClaim, M.feeConfig);

            M.amount -= M.amountToClaim;
            totalClaimedAmount += claimAmount;
            totalFeeAmount += feeAmount;
            if (M.status != Enums.Status.RESOLVED && M.status != Enums.Status.CANCELED) {
                totalClientFee += clientFee;
            }

            M.amountToClaim = 0; // Reset the claimable amount after claiming.
            if (M.amount == 0) M.status = Enums.Status.COMPLETED; // Update the status if all funds have been claimed.
        }

        // Perform the token transfer at the end to reduce gas cost by consolidating all transfers into a single operation.
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
            totalClientFee
        );
    }

    /// @notice Withdraws funds from a milestone under specific conditions.
    /// @dev Withdrawal is contingent upon the milestone being in a suitable state, either fully approved for refund or resolved.
    /// @param _contractId The identifier of the contract from which to withdraw funds.
    /// @param _milestoneId The identifier of the milestone within the contract from which to withdraw funds.
    function withdraw(uint256 _contractId, uint256 _milestoneId) external onlyClient {
        if (registry.blacklist(msg.sender)) revert Escrow__BlacklistedAccount();

        Milestone storage M = contractMilestones[_contractId][_milestoneId];
        if (M.status != Enums.Status.REFUND_APPROVED && M.status != Enums.Status.RESOLVED) {
            revert Escrow__InvalidStatusToWithdraw();
        }

        if (M.amountToWithdraw == 0) revert Escrow__NoFundsAvailableForWithdraw();

        // Calculate the fee based on the amount to be withdrawn.
        (, uint256 feeAmount) = _computeDepositAmountAndFee(msg.sender, M.amountToWithdraw, M.feeConfig);

        MilestoneDetails storage D = milestoneDetails[_contractId][_milestoneId];
        uint256 initialFeeAmount;
        // Distinguish between fee calculations based on milestone status or dispute resolution.
        if (M.status == Enums.Status.REFUND_APPROVED) {
            // Regular fee calculation from the current amount.
            (, initialFeeAmount) = _computeDepositAmountAndFee(msg.sender, M.amount, M.feeConfig);
        } else if (M.status == Enums.Status.RESOLVED && D.winner == Enums.Winner.SPLIT) {
            // Special case for split resolutions.
            (, initialFeeAmount) = _computeDepositAmountAndFee(msg.sender, D.depositAmount, M.feeConfig);
        } else {
            // Default case for resolved or canceled without split, using current amount.
            (, initialFeeAmount) = _computeDepositAmountAndFee(msg.sender, M.amount, M.feeConfig);
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
        emit Withdrawn(msg.sender, _contractId, _milestoneId, withdrawAmount);
    }

    /*//////////////////////////////////////////////////////////////
                ESCROW RETURN REQUEST & DISPUTE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Requests the return of funds by the client.
    /// @param _contractId ID of the deposit for which the return is requested.
    /// @param _milestoneId ID of the milestone for which the return is requested.
    function requestReturn(uint256 _contractId, uint256 _milestoneId) external onlyClient {
        Milestone storage M = contractMilestones[_contractId][_milestoneId];
        if (
            M.status != Enums.Status.ACTIVE && M.status != Enums.Status.SUBMITTED && M.status != Enums.Status.APPROVED
                && M.status != Enums.Status.COMPLETED
        ) revert Escrow__ReturnNotAllowed();

        M.status = Enums.Status.RETURN_REQUESTED;
        emit ReturnRequested(msg.sender, _contractId, _milestoneId);
    }

    /// @notice Approves the return of funds, callable by contractor or platform owner/admin.
    /// @param _contractId ID of the deposit for which the return is approved.
    /// @param _milestoneId ID of the milestone for which the return is approved.
    function approveReturn(uint256 _contractId, uint256 _milestoneId) external {
        Milestone storage M = contractMilestones[_contractId][_milestoneId];
        if (M.status != Enums.Status.RETURN_REQUESTED) revert Escrow__NoReturnRequested();
        if (msg.sender != M.contractor && !IEscrowAdminManager(adminManager).isAdmin(msg.sender)) {
            revert Escrow__UnauthorizedToApproveReturn();
        }

        M.amountToWithdraw = M.amount;
        M.status = Enums.Status.REFUND_APPROVED;
        emit ReturnApproved(msg.sender, _contractId, _milestoneId);
    }

    /// @notice Cancels a previously requested return and resets the deposit's status.
    /// @dev This function allows a client to cancel a return request, setting the deposit status back to either ACTIVE or SUBMITTED or APPROVED or COMPLETED.
    /// @param _contractId The unique identifier of the deposit for which the return is being cancelled.
    /// @param _milestoneId ID of the milestone for which the return is being cancelled.
    /// @param _status The new status to set for the deposit, must be either ACTIVE or SUBMITTED or APPROVED or COMPLETED.
    function cancelReturn(uint256 _contractId, uint256 _milestoneId, Enums.Status _status) external onlyClient {
        Milestone storage M = contractMilestones[_contractId][_milestoneId];
        if (M.status != Enums.Status.RETURN_REQUESTED) revert Escrow__NoReturnRequested();
        if (
            _status != Enums.Status.ACTIVE && _status != Enums.Status.SUBMITTED && _status != Enums.Status.APPROVED
                && _status != Enums.Status.COMPLETED
        ) {
            revert Escrow__InvalidStatusProvided();
        }

        M.status = _status;
        emit ReturnCanceled(msg.sender, _contractId, _milestoneId);
    }

    /// @notice Creates a dispute over a specific deposit.
    /// @param _contractId ID of the deposit where the dispute occurred.
    /// @param _milestoneId ID of the deposit where the dispute occurred.
    function createDispute(uint256 _contractId, uint256 _milestoneId) external {
        Milestone storage M = contractMilestones[_contractId][_milestoneId];
        if (M.status != Enums.Status.RETURN_REQUESTED && M.status != Enums.Status.SUBMITTED) {
            revert Escrow__CreateDisputeNotAllowed();
        }
        if (msg.sender != client && msg.sender != M.contractor) revert Escrow__UnauthorizedToApproveDispute();

        M.status = Enums.Status.DISPUTED;
        emit DisputeCreated(msg.sender, _contractId, _milestoneId);
    }

    /// @notice Resolves a dispute over a specific deposit.
    /// @param _contractId ID of the deposit where the dispute occurred.
    /// @param _milestoneId ID of the deposit where the dispute occurred.
    /// @param _winner Specifies who the winner is: Client, Contractor, or Split.
    /// @param _clientAmount Amount to be allocated to the client if Split or Client wins.
    /// @param _contractorAmount Amount to be allocated to the contractor if Split or Contractor wins.
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

        // Apply resolution based on the winner
        if (_winner == Enums.Winner.CLIENT) {
            M.status = Enums.Status.RESOLVED; // Client can now withdraw the full amount
            M.amountToWithdraw = _clientAmount; // Full amount for the client to withdraw
            M.amountToClaim = 0; // No claimable amount for the contractor
        } else if (_winner == Enums.Winner.CONTRACTOR) {
            M.status = Enums.Status.APPROVED; // Status that allows the contractor to claim
            M.amountToClaim = _contractorAmount; // Amount the contractor can claim
            M.amountToWithdraw = 0; // No amount for the client to withdraw
        } else if (_winner == Enums.Winner.SPLIT) {
            M.status = Enums.Status.RESOLVED; // Indicates a resolved dispute with split amounts
            M.amountToClaim = _contractorAmount; // Set the claimable amount for the contractor
            M.amountToWithdraw = _clientAmount; // Set the withdrawable amount for the client
        }

        milestoneDetails[_contractId][_milestoneId].winner = _winner;

        emit DisputeResolved(msg.sender, _contractId, _milestoneId, _winner, _clientAmount, _contractorAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Computes the total deposit amount and the applied fee.
    /// @dev This internal function calculates the total deposit amount and the fee applied based on the client, deposit amount, and fee configuration.
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
        IEscrowFeeManager feeManager = IEscrowFeeManager(feeManagerAddress); // Cast to the interface

        (totalDepositAmount, feeApplied) = feeManager.computeDepositAmountAndFee(_client, _depositAmount, _feeConfig);

        return (totalDepositAmount, feeApplied);
    }

    /// @notice Computes the claimable amount and the fee deducted from the claimed amount.
    /// @dev This internal function calculates the claimable amount for the contractor and the fees deducted from the claimed amount based on the contractor, claimed amount, and fee configuration.
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
    /// @dev Verifies if the signature is from the msg.sender, which can be an externally owned account (EOA) or a contract implementing ERC-1271.
    /// @param _hash The hash of the data that was signed.
    /// @param _signature The signature byte array associated with the hash.
    /// @return True if the signature is valid, false otherwise.
    function _isValidSignature(bytes32 _hash, bytes calldata _signature) internal view override returns (bool) {
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(_hash);
        // Check if msg.sender is a contract
        if (msg.sender.code.length > 0) {
            // ERC-1271 signature verification
            return SignatureChecker.isValidERC1271SignatureNow(msg.sender, ethSignedHash, _signature);
        } else {
            // EOA signature verification
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

    /// @notice Retrieves the number of milestones for a given contract ID.
    /// @param _contractId The contract ID for which to retrieve the milestone count.
    /// @return The number of milestones associated with the given contract ID.
    function getMilestoneCount(uint256 _contractId) external view returns (uint256) {
        return contractMilestones[_contractId].length;
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
    /// @param _milestoneId The identifier of the milestone for which contractor ownership is being transferred.
    /// @param _newAccount The address to which the contractor ownership will be transferred.
    function transferContractorOwnership(uint256 _contractId, uint256 _milestoneId, address _newAccount) external {
        // Verify that the caller is the authorized account recovery module.
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
    /// @param _maxMilestones The new maximum number of milestones.
    function setMaxMilestonesPerTransaction(uint256 _maxMilestones) external {
        if (!IEscrowAdminManager(adminManager).isAdmin(msg.sender)) revert Escrow__UnauthorizedAccount(msg.sender);
        if (_maxMilestones == 0 || _maxMilestones > 20) revert Escrow__InvalidMilestoneLimit();
        maxMilestonesPerTransaction = _maxMilestones;
        emit MaxMilestonesSet(_maxMilestones);
    }
}
