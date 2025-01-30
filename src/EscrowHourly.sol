// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { SignatureChecker } from "@openzeppelin/utils/cryptography/SignatureChecker.sol";
import { SafeTransferLib } from "@solbase/utils/SafeTransferLib.sol";

import { IEscrowAdminManager } from "./interfaces/IEscrowAdminManager.sol";
import { IEscrowHourly } from "./interfaces/IEscrowHourly.sol";
import { IEscrowFeeManager } from "./interfaces/IEscrowFeeManager.sol";
import { IEscrowRegistry } from "./interfaces/IEscrowRegistry.sol";
import { ECDSA, ERC1271 } from "./common/ERC1271.sol";
import { Enums } from "./common/Enums.sol";

/// @title Weekly Billing and Payment Management for Escrow Hourly
/// @notice Manages the creation and addition of multiple weekly bills to escrow contracts.
contract EscrowHourly is IEscrowHourly, ERC1271 {
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

    /// @dev Maps from contract ID to its detailed configuration.
    mapping(uint256 contractId => ContractDetails) public contractDetails;

    /// @dev Maps a contract ID to an array of `WeeklyEntry` structures representing billing cycles.
    mapping(uint256 contractId => WeeklyEntry[] weekIds) public weeklyEntries;

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
                    ESCROW HOURLY UNDERLYING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates or updates a week's deposit for a new or existing contract.
    /// @dev This function handles the initialization or update of a week's deposit in a single transaction.
    ///      If a new contract ID is provided, a new contract is initialized; otherwise, it adds to an existing
    /// contract.
    /// @param _deposit Details for deposit and initial week settings.
    function deposit(DepositRequest calldata _deposit) external onlyClient {
        if (registry.blacklist(msg.sender)) revert Escrow__BlacklistedAccount();
        if (!registry.paymentTokens(_deposit.paymentToken)) revert Escrow__NotSupportedPaymentToken();
        if (_deposit.prepaymentAmount == 0 && _deposit.amountToClaim == 0) revert Escrow__InvalidAmount();
        if (_deposit.contractor == address(0)) revert Escrow__ZeroAddressProvided();

        // Validate the deposit fields against admin signature.
        _validateDepositAuthorization(_deposit);

        // Ensure the provided `contractId` is valid.
        ContractDetails storage C = contractDetails[_deposit.contractId];
        if (_deposit.contractId == 0) revert Escrow__InvalidContractId();

        if (C.status == Enums.Status.NONE) {
            // New contract: Ensure it does not exist already.
            if (C.paymentToken != address(0)) revert Escrow__ContractIdAlreadyExists();

            // Initialize new contract.
            C.contractor = _deposit.contractor;
            C.paymentToken = _deposit.paymentToken;
            C.feeConfig = _deposit.feeConfig;
            C.prepaymentAmount = _deposit.prepaymentAmount;
        } else {
            // Existing contract: Validate consistency.
            if (C.contractor != _deposit.contractor) revert Escrow__ContractorMismatch();
            if (C.paymentToken != _deposit.paymentToken) revert Escrow__PaymentTokenMismatch();

            // Update prepayment amount if provided.
            if (_deposit.prepaymentAmount > 0) {
                C.prepaymentAmount += _deposit.prepaymentAmount;
            }
        }

        // Only update the contract status if it's not in a active or approved state.
        // The contract can be reactivated with new conditions or further funding by the client following any previous
        // settlement or cancellation.
        if (C.status != Enums.Status.ACTIVE || C.status != Enums.Status.APPROVED) {
            // Determine the correct status based on deposit amounts.
            Enums.Status newStatus = _deposit.prepaymentAmount > 0
                ? Enums.Status.ACTIVE
                : (_deposit.amountToClaim > 0 ? Enums.Status.APPROVED : Enums.Status.ACTIVE);

            C.status = newStatus;
        }

        // Append the new week entry.
        Enums.Status weekStatus = _deposit.amountToClaim > 0 ? Enums.Status.APPROVED : Enums.Status.ACTIVE;
        weeklyEntries[_deposit.contractId].push(
            WeeklyEntry({ amountToClaim: _deposit.amountToClaim, weekStatus: weekStatus })
        );

        uint256 depositAmount = _deposit.prepaymentAmount > 0 ? _deposit.prepaymentAmount : _deposit.amountToClaim;
        (uint256 totalDepositAmount,) =
            _computeDepositAmountAndFee(_deposit.contractId, msg.sender, depositAmount, C.feeConfig);

        SafeTransferLib.safeTransferFrom(C.paymentToken, msg.sender, address(this), totalDepositAmount);

        // Emit an event for the deposit of each week.
        emit Deposited(
            msg.sender,
            _deposit.contractId,
            weeklyEntries[_deposit.contractId].length - 1,
            totalDepositAmount,
            C.contractor
        );
    }

    /// @notice Approves a deposit by the client.
    /// @dev This function allows the client to approve a deposit, specifying the amount to approve.
    /// @param _contractId ID of the deposit to be approved.
    /// @param _weekId ID of the week within the contract to be approved.
    /// @param _amountApprove Amount to approve for the deposit.
    /// @param _receiver Address of the contractor receiving the approved amount.
    function approve(uint256 _contractId, uint256 _weekId, uint256 _amountApprove, address _receiver)
        external
        onlyClient
    {
        if (registry.blacklist(msg.sender)) revert Escrow__BlacklistedAccount(); // Check if the client is blacklisted.
        if (_amountApprove == 0) revert Escrow__InvalidAmount(); // Ensure a valid amount is being added.
        if (_weekId >= weeklyEntries[_contractId].length) revert Escrow__InvalidWeekId();

        WeeklyEntry storage W = weeklyEntries[_contractId][_weekId];
        if (W.weekStatus != Enums.Status.ACTIVE && W.weekStatus != Enums.Status.COMPLETED) {
            revert Escrow__InvalidStatusForApprove();
        }

        ContractDetails storage C = contractDetails[_contractId];
        if (C.contractor != _receiver) revert Escrow__UnauthorizedReceiver();

        if (C.status == Enums.Status.COMPLETED || C.status == Enums.Status.CANCELED) C.status = Enums.Status.APPROVED;

        // Calculate fee and approve the total amount once, then perform the transfer.
        (uint256 totalAmountApprove,) =
            _computeDepositAmountAndFee(_contractId, msg.sender, _amountApprove, C.feeConfig);
        SafeTransferLib.safeTransferFrom(C.paymentToken, msg.sender, address(this), totalAmountApprove);

        W.amountToClaim += _amountApprove;

        W.weekStatus = Enums.Status.APPROVED;
        emit Approved(msg.sender, _contractId, _weekId, _amountApprove, _receiver);
    }

    /// @notice Approves an existing deposit or creates a new week for approval by the admin.
    /// @dev This function handles both regular approval within existing weeks and admin-triggered approvals that may
    ///     need to create a new week.
    /// @param _contractId ID of the contract for which the approval is happening.
    /// @param _weekId ID of the week within the contract to be approved, or creates a new one if it does not exist.
    /// @param _amountApprove Amount to approve or initialize the week with.
    /// @param _receiver Address of the contractor receiving the approved amount.
    /// @param _initializeNewWeek If true, will initialize a new week if the specified weekId doesn't exist.
    function adminApprove(
        uint256 _contractId,
        uint256 _weekId,
        uint256 _amountApprove,
        address _receiver,
        bool _initializeNewWeek
    ) external {
        if (!IEscrowAdminManager(adminManager).isAdmin(msg.sender)) revert Escrow__UnauthorizedAccount(msg.sender);
        if (_amountApprove == 0) revert Escrow__InvalidAmount();

        ContractDetails storage C = contractDetails[_contractId];
        if (
            C.status != Enums.Status.ACTIVE && C.status != Enums.Status.APPROVED && C.status != Enums.Status.COMPLETED
                && C.status != Enums.Status.CANCELED
        ) {
            revert Escrow__InvalidStatusForApprove();
        }
        if (C.contractor != _receiver) revert Escrow__UnauthorizedReceiver();

        // Adjust for array bounds and check the necessity to initialize a new week.
        if (_weekId >= weeklyEntries[_contractId].length) {
            if (_initializeNewWeek) {
                // Initialize a new week if it does not exist and the flag is true.
                WeeklyEntry memory newDeposit = WeeklyEntry({ amountToClaim: 0, weekStatus: Enums.Status.NONE });
                weeklyEntries[_contractId].push(newDeposit);
            } else {
                revert Escrow__InvalidWeekId();
            }
        }

        WeeklyEntry storage W = weeklyEntries[_contractId][_weekId];
        if (C.prepaymentAmount < _amountApprove) {
            // If the prepayment is less than the amount to approve, use the entire prepayment for the amount to claim.
            W.amountToClaim += C.prepaymentAmount;
            C.prepaymentAmount = 0; // All prepayment is used up.
        } else {
            // If sufficient prepayment exists, use only the needed amount and reduce the prepayment balance.
            C.prepaymentAmount -= _amountApprove;
            W.amountToClaim += _amountApprove;
        }

        W.weekStatus = Enums.Status.APPROVED;
        emit Approved(msg.sender, _contractId, _weekId, _amountApprove, _receiver);
    }

    /// @notice Refills the prepayment or a specific week's deposit with an additional amount.
    /// @dev Allows adding additional funds either to the contract's prepayment or to a specific week's payment amount.
    /// @param _contractId ID of the contract for which the refill is done.
    /// @param _weekId ID of the week within the contract to be refilled, only used if _type is WeekPayment.
    /// @param _amount The additional amount to be added.
    /// @param _type The type of refill, either prepayment or week payment.
    function refill(uint256 _contractId, uint256 _weekId, uint256 _amount, Enums.RefillType _type)
        external
        onlyClient
    {
        if (registry.blacklist(msg.sender)) revert Escrow__BlacklistedAccount();
        if (_amount == 0) revert Escrow__InvalidAmount();

        // Validate weekId for WEEK_PAYMENT type to ensure it's within valid range.
        if (_type == Enums.RefillType.WEEK_PAYMENT && _weekId >= weeklyEntries[_contractId].length) {
            revert Escrow__InvalidWeekId();
        }

        ContractDetails storage C = contractDetails[_contractId];
        if (!registry.paymentTokens(C.paymentToken)) revert Escrow__NotSupportedPaymentToken();

        if (C.status == Enums.Status.COMPLETED || C.status == Enums.Status.CANCELED) C.status = Enums.Status.APPROVED;

        (uint256 totalAmountAdditional,) = _computeDepositAmountAndFee(_contractId, msg.sender, _amount, C.feeConfig);
        SafeTransferLib.safeTransferFrom(C.paymentToken, msg.sender, address(this), totalAmountAdditional);

        if (_type == Enums.RefillType.PREPAYMENT) {
            // Add funds to the overall prepayment pool for the contract.
            C.prepaymentAmount += _amount;
            emit RefilledPrepayment(msg.sender, _contractId, _amount);
        } else if (_type == Enums.RefillType.WEEK_PAYMENT) {
            WeeklyEntry storage W = weeklyEntries[_contractId][_weekId];
            // Add funds specifically to the week's deposit.
            W.amountToClaim += _amount;
            W.weekStatus = Enums.Status.APPROVED;
            emit RefilledWeekPayment(msg.sender, _contractId, _weekId, _amount);
        }
    }

    /// @notice Claims the approved amount by the contractor.
    /// @dev This function allows the contractor to claim the approved amount from the deposit.
    /// @param _contractId ID of the deposit from which to claim funds.
    /// @param _weekId ID of the week within the contract to be claimed.
    function claim(uint256 _contractId, uint256 _weekId) external {
        ContractDetails storage C = contractDetails[_contractId];
        if (C.contractor != msg.sender) revert Escrow__UnauthorizedAccount(msg.sender);

        WeeklyEntry storage W = weeklyEntries[_contractId][_weekId];
        if (W.weekStatus != Enums.Status.APPROVED && W.weekStatus != Enums.Status.RESOLVED) {
            revert Escrow__InvalidStatusToClaim();
        }
        if (W.amountToClaim == 0) revert Escrow__NotApproved();

        // Compute the amounts related to the claim.
        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
            _computeClaimableAmountAndFee(_contractId, msg.sender, W.amountToClaim, C.feeConfig);

        // Handle prepayment deduction for resolved or canceled states.
        if (C.prepaymentAmount > 0 && (C.status == Enums.Status.RESOLVED || C.status == Enums.Status.CANCELED)) {
            C.prepaymentAmount -= W.amountToClaim;
        }

        W.amountToClaim = 0; // Reset the claimable amount to prevent re-claiming.
        W.weekStatus = Enums.Status.COMPLETED; // Mark the week as completed.

        // Transfer the claimable amount to the contractor.
        SafeTransferLib.safeTransfer(C.paymentToken, msg.sender, claimAmount);

        // Handle platform fees if applicable.
        if (feeAmount > 0 || clientFee > 0) {
            uint256 totalFee = (C.status == Enums.Status.CANCELED) ? feeAmount : (feeAmount + clientFee);
            _sendPlatformFee(C.paymentToken, totalFee);
        }

        // Check if all weeks are completed and update the contract status if true.
        if (_verifyIfAllWeeksCompleted(_contractId)) C.status = Enums.Status.COMPLETED;

        emit Claimed(msg.sender, _contractId, _weekId, claimAmount, feeAmount, client);
    }

    /// @notice Allows the contractor to claim for multiple weeks in a specified range if those weeks are approved.
    /// @dev This function is designed to prevent running out of gas when claiming multiple weeks by limiting the range.
    /// @param _contractId ID of the contract for which the claim is made.
    /// @param _startWeekId Starting week ID from which to begin claims.
    /// @param _endWeekId Ending week ID until which claims are made.
    function claimAll(uint256 _contractId, uint256 _startWeekId, uint256 _endWeekId) external {
        if (_startWeekId > _endWeekId) revert Escrow__InvalidRange();
        if (_endWeekId >= weeklyEntries[_contractId].length) revert Escrow__OutOfRange();

        ContractDetails storage C = contractDetails[_contractId];
        if (C.contractor != msg.sender) revert Escrow__UnauthorizedAccount(msg.sender);

        uint256 totalClaimedAmount = 0;
        uint256 totalFeeAmount = 0;
        uint256 totalClientFee = 0;

        for (uint256 i = _startWeekId; i <= _endWeekId; ++i) {
            WeeklyEntry storage W = weeklyEntries[_contractId][i];

            // Skip if not approved or nothing to claim.
            if (W.amountToClaim == 0 && W.weekStatus != Enums.Status.APPROVED && W.weekStatus != Enums.Status.RESOLVED)
            {
                continue;
            }
            if (C.prepaymentAmount > 0 && (C.status == Enums.Status.RESOLVED || C.status == Enums.Status.CANCELED)) {
                C.prepaymentAmount -= W.amountToClaim; // Use prepaymentAmount in case not approved by client.
            }

            (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
                _computeClaimableAmountAndFee(_contractId, msg.sender, W.amountToClaim, C.feeConfig);

            W.amountToClaim = 0;
            W.weekStatus = Enums.Status.COMPLETED;
            totalClaimedAmount += claimAmount;
            totalFeeAmount += feeAmount;
            totalClientFee += clientFee;
        }

        // Perform transfers and fee handling after loop to optimize gas usage.
        SafeTransferLib.safeTransfer(C.paymentToken, msg.sender, totalClaimedAmount);
        if (totalFeeAmount > 0 || totalClientFee > 0) {
            uint256 totalFee = (C.status == Enums.Status.CANCELED) ? totalFeeAmount : (totalFeeAmount + totalClientFee);
            _sendPlatformFee(C.paymentToken, totalFee);
        }

        // Update contract status if all weeks are completed.
        if (_verifyIfAllWeeksCompleted(_contractId)) C.status = Enums.Status.COMPLETED;

        emit BulkClaimed(
            msg.sender,
            _contractId,
            _startWeekId,
            _endWeekId,
            totalClaimedAmount,
            totalFeeAmount,
            totalClientFee,
            client
        );
    }

    /// @notice Withdraws funds from a contract under specific conditions.
    /// @dev Withdraws from the contract's prepayment amount when certain conditions about the contract's
    ///     overall status are met.
    /// @param _contractId ID of the deposit from which funds are to be withdrawn.
    function withdraw(uint256 _contractId) external onlyClient {
        ContractDetails storage C = contractDetails[_contractId];
        if (C.status == Enums.Status.CANCELED) revert Escrow__InvalidStatusToWithdraw();
        if (
            C.status != Enums.Status.REFUND_APPROVED && C.status != Enums.Status.RESOLVED
                && C.status != Enums.Status.COMPLETED
        ) {
            revert Escrow__InvalidStatusToWithdraw();
        }
        if (C.amountToWithdraw == 0) revert Escrow__NoFundsAvailableForWithdraw();

        (, uint256 feeAmount) = _computeDepositAmountAndFee(_contractId, msg.sender, C.amountToWithdraw, C.feeConfig);
        (, uint256 initialFeeAmount) =
            _computeDepositAmountAndFee(_contractId, msg.sender, C.prepaymentAmount, C.feeConfig);

        C.prepaymentAmount -= C.amountToWithdraw;
        uint256 withdrawAmount = C.amountToWithdraw + feeAmount;
        C.amountToWithdraw = 0; // Prevent re-withdrawal.
        C.status = Enums.Status.CANCELED; // Mark the deposit as canceled after funds are withdrawn.

        SafeTransferLib.safeTransfer(C.paymentToken, msg.sender, withdrawAmount);

        // Calculate any platform fee differential due to fee adjustments during the process.
        uint256 platformFee = initialFeeAmount > feeAmount ? initialFeeAmount - feeAmount : 0;

        // Transfer the platform fee if applicable.
        if (platformFee > 0) {
            _sendPlatformFee(C.paymentToken, platformFee);
        }

        emit Withdrawn(msg.sender, _contractId, withdrawAmount, platformFee);
    }

    /*//////////////////////////////////////////////////////////////
                ESCROW RETURN REQUEST & DISPUTE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Requests the return of funds by the client for a specific contract.
    /// @dev The contract must be in an eligible state to request a return (not in disputed or already returned status).
    /// @param _contractId ID of the deposit for which the return is requested.
    function requestReturn(uint256 _contractId) external onlyClient {
        ContractDetails storage C = contractDetails[_contractId];
        if (C.status != Enums.Status.ACTIVE && C.status != Enums.Status.APPROVED && C.status != Enums.Status.COMPLETED)
        {
            revert Escrow__ReturnNotAllowed();
        }
        previousStatuses[_contractId] = C.status;
        C.status = Enums.Status.RETURN_REQUESTED;
        emit ReturnRequested(msg.sender, _contractId);
    }

    /// @notice Approves the return of funds, which can be called by the contractor or platform admin.
    /// @dev This changes the status of the deposit to allow the client to withdraw their funds.
    /// @param _contractId ID of the deposit for which the return is approved.
    function approveReturn(uint256 _contractId) external {
        ContractDetails storage C = contractDetails[_contractId];
        if (C.status != Enums.Status.RETURN_REQUESTED) revert Escrow__NoReturnRequested();
        if (msg.sender != C.contractor && !IEscrowAdminManager(adminManager).isAdmin(msg.sender)) {
            revert Escrow__UnauthorizedToApproveReturn();
        }
        C.amountToWithdraw = C.prepaymentAmount;
        C.status = Enums.Status.REFUND_APPROVED;
        emit ReturnApproved(msg.sender, _contractId, client);
    }

    /// @notice Cancels a previously requested return and resets the deposit's status to the previous one.
    /// @dev Reverts the status from RETURN_REQUESTED to the previous status stored in `previousStatuses`.
    /// @param _contractId The unique identifier of the deposit for which the return is being cancelled.
    function cancelReturn(uint256 _contractId) external onlyClient {
        ContractDetails storage C = contractDetails[_contractId];
        if (C.status != Enums.Status.RETURN_REQUESTED) revert Escrow__NoReturnRequested();

        C.status = previousStatuses[_contractId];
        delete previousStatuses[_contractId];

        emit ReturnCanceled(msg.sender, _contractId);
    }

    /// @notice Creates a dispute over a specific contract.
    /// @dev Initiates a dispute status for a contract that can be activated by the client or contractor
    ///     when they disagree on the previously submitted work.
    /// @param _contractId ID of the contract where the dispute occurred.
    /// @param _weekId ID of the contract where the dispute occurred.
    /// This function can only be called if the contract status is either RETURN_REQUESTED or SUBMITTED.
    function createDispute(uint256 _contractId, uint256 _weekId) external {
        ContractDetails storage C = contractDetails[_contractId];
        if (C.status != Enums.Status.RETURN_REQUESTED && C.status != Enums.Status.APPROVED) {
            revert Escrow__CreateDisputeNotAllowed();
        }
        if (msg.sender != client && msg.sender != C.contractor) revert Escrow__UnauthorizedToApproveDispute();

        C.status = Enums.Status.DISPUTED;
        weeklyEntries[_contractId][_weekId].weekStatus = Enums.Status.DISPUTED;
        emit DisputeCreated(msg.sender, _contractId, _weekId, client);
    }

    /// @notice Resolves a dispute over a specific contract.
    /// @dev Handles the resolution of disputes by assigning the funds according to the outcome of the dispute.
    ///     Admin intervention is required to resolve disputes to ensure fairness.
    /// @param _contractId ID of the contract where the dispute occurred.
    /// @param _weekId ID of the contract where the dispute occurred.
    /// @param _winner Specifies who the winner is: Client, Contractor, or Split.
    /// @param _clientAmount Amount to be allocated to the client if Split or Client wins.
    /// @param _contractorAmount Amount to be allocated to the contractor if Split or Contractor wins.
    /// This function ensures that the total resolution amounts do not exceed the deposited amount and adjusts the
    /// status of the contract based on the dispute outcome.
    function resolveDispute(
        uint256 _contractId,
        uint256 _weekId,
        Enums.Winner _winner,
        uint256 _clientAmount,
        uint256 _contractorAmount
    ) external {
        if (!IEscrowAdminManager(adminManager).isAdmin(msg.sender)) revert Escrow__UnauthorizedAccount(msg.sender);

        ContractDetails storage C = contractDetails[_contractId];
        WeeklyEntry storage W = weeklyEntries[_contractId][_weekId];
        if (C.status != Enums.Status.DISPUTED && W.weekStatus != Enums.Status.DISPUTED) {
            revert Escrow__DisputeNotActiveForThisDeposit();
        }

        // Validate the total resolution does not exceed the available deposit amount.
        uint256 totalResolutionAmount = _clientAmount + _contractorAmount;
        if (totalResolutionAmount > C.prepaymentAmount) revert Escrow__ResolutionExceedsDepositedAmount();

        // Set the amounts based on the dispute outcome.
        W.amountToClaim = (_winner == Enums.Winner.CONTRACTOR || _winner == Enums.Winner.SPLIT) ? _contractorAmount : 0;
        if (_winner == Enums.Winner.CONTRACTOR) {
            // In the case of contractor winning, they can claim using the prepayment amount.
            C.amountToWithdraw = 0;
        } else {
            C.amountToWithdraw = (_winner == Enums.Winner.CLIENT || _winner == Enums.Winner.SPLIT) ? _clientAmount : 0;
        }

        C.status = Enums.Status.RESOLVED; // Resolve the contract status for all cases.
        W.weekStatus = Enums.Status.RESOLVED;
        emit DisputeResolved(msg.sender, _contractId, _weekId, _winner, _clientAmount, _contractorAmount, client);
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

        ContractDetails storage C = contractDetails[_contractId];

        // Emit the ownership transfer event before changing the state to reflect the previous state.
        emit ContractorOwnershipTransferred(_contractId, C.contractor, _newAccount);

        // Update the contractor address to the new owner's address.
        C.contractor = _newAccount;
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
        return contractDetails[_contractId].status != Enums.Status.NONE;
    }

    /// @notice Retrieves the number of weeks for a given contract ID.
    /// @param _contractId The contract ID for which to retrieve the week count.
    /// @return The number of weeks associated with the given contract ID.
    function getWeeksCount(uint256 _contractId) external view returns (uint256) {
        return weeklyEntries[_contractId].length;
    }

    /// @notice Generates the hash required for deposit signing in EscrowHourly.
    /// @param _client The address of the client submitting the deposit.
    /// @param _contractId The ID of the contract associated with the deposit.
    /// @param _contractor The contractor's address.
    /// @param _paymentToken The payment token used.
    /// @param _prepaymentAmount The initial prepayment amount.
    /// @param _amountToClaim The amount designated for the contractor's claim.
    /// @param _feeConfig The fee configuration for this deposit.
    /// @param _expiration The timestamp when the deposit authorization expires.
    /// @return ethSignedHash The Ethereum signed message hash that needs to be signed.
    function getDepositHash(
        address _client,
        uint256 _contractId,
        address _contractor,
        address _paymentToken,
        uint256 _prepaymentAmount,
        uint256 _amountToClaim,
        Enums.FeeConfig _feeConfig,
        uint256 _expiration
    ) external view returns (bytes32) {
        // Generate the raw hash using the same structure as `_validateDepositAuthorization`
        bytes32 hash = keccak256(
            abi.encodePacked(
                _client,
                _contractId,
                _contractor,
                _paymentToken,
                _prepaymentAmount,
                _amountToClaim,
                _feeConfig,
                _expiration,
                address(this)
            )
        );

        // Apply Ethereum’s signed message prefix (same as ECDSA.toEthSignedMessageHash).
        return ECDSA.toEthSignedMessageHash(hash);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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
        address treasury = IEscrowRegistry(registry).hourlyTreasury();
        if (treasury == address(0)) revert Escrow__ZeroAddressProvided();
        SafeTransferLib.safeTransfer(_paymentToken, treasury, _feeAmount);
    }

    /// @dev Internal function to check if all weeks within a contract are completed.
    /// @param _contractId The ID of the contract to check.
    /// @return True if all weeks are completed, false otherwise.
    function _verifyIfAllWeeksCompleted(uint256 _contractId) internal view returns (bool) {
        uint256 length = weeklyEntries[_contractId].length;
        for (uint256 i; i < length;) {
            if (weeklyEntries[_contractId][i].weekStatus != Enums.Status.COMPLETED) {
                return false;
            }
            unchecked {
                ++i;
            }
        }
        return true;
    }

    /// @notice Internal function to validate the signature of the provided data.
    /// @dev Verifies if the signature is from the msg.sender, which can be an externally owned account (EOA) or a
    ///     contract implementing ERC-1271.
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

    /// @notice Validates deposit fields against admin-signed approval.
    /// @param _deposit The deposit details including signature and expiration.
    function _validateDepositAuthorization(DepositRequest calldata _deposit) internal view {
        // Ensure the authorization has not expired.
        if (_deposit.expiration < block.timestamp) revert Escrow__AuthorizationExpired();

        // Generate hash for signed data.
        bytes32 hash = keccak256(
            abi.encodePacked(
                msg.sender, // Client submitting the deposit.
                _deposit.contractId, // Contract ID.
                _deposit.contractor, // Contractor's address.
                _deposit.paymentToken, // Payment token address.
                _deposit.prepaymentAmount, // Deposit prepaymentAmount.
                _deposit.amountToClaim, // Deposit prepaymentAmount.
                _deposit.feeConfig, // Fee configuration.
                _deposit.expiration, // Expiration timestamp.
                address(this) // Contract address.
            )
        );
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(hash);

        // Verify signature using the admin's address.
        address signer = adminManager.owner();
        if (!SignatureChecker.isValidSignatureNow(signer, ethSignedHash, _deposit.signature)) {
            revert Escrow__InvalidSignature();
        }
    }
}
