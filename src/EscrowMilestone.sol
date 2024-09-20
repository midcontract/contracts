// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { SafeTransferLib } from "@solbase/utils/SafeTransferLib.sol";
import { SignatureChecker } from "@openzeppelin/utils/cryptography/SignatureChecker.sol";

import { IEscrowAdminManager } from "./interfaces/IEscrowAdminManager.sol";
import { IEscrowMilestone , IEscrow} from "./interfaces/IEscrowMilestone.sol";
import { IEscrowFeeManager } from "./interfaces/IEscrowFeeManager.sol";
import { IEscrowRegistry } from "./interfaces/IEscrowRegistry.sol";
import { ECDSA, ERC1271 } from "./libs/ERC1271.sol";
import { Enums } from "./libs/Enums.sol";

/// @title Deposit management for Escrow Milestones
/// @notice Manages the creation and addition of multiple milestones to escrow contracts.
/// @dev Handles both the creation of a new escrow contract and the addition of milestones to existing contracts.
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

    /// @dev Indicates that the contract has been initialized.
    bool public initialized;

    /// @notice Maps each contract ID to its respective array of milestone deposits.
    /// @dev This mapping stores an array of `Deposit` structs for each contract, where each struct represents a milestone within the contract.
    mapping(uint256 contractId => Deposit[]) public contractMilestones;

    /// @notice Mapping of Contract and Milestone IDs to their Details.
    /// @dev Accessible via contractId and milestoneId to retrieve `MilestoneDetails`.
    mapping(uint256 contractId => mapping(uint256 milestoneId => MilestoneDetails)) public milestoneData;

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
                    ESCROW MILESTONE UNDERLYING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates multiple milestones for a new or existing contract.
    /// @dev This function allows the initialization of multiple milestones in a single transaction,
    ///     either by creating a new contract or adding to an existing one. Limits the number of milestones to 10 to prevent gas limit issues.
    /// @param _contractId ID of the contract for which the deposits are made; if zero, a new contract is initialized.
    /// @param _paymentToken  The address of the payment token for the contractId.
    /// @param _deposits Array of details for each new milestone.
    function deposit(uint256 _contractId, address _paymentToken, Deposit[] calldata _deposits) external onlyClient {
        if (registry.blacklist(msg.sender)) revert Escrow__BlacklistedAccount();
        if (_deposits.length == 0) revert Escrow__NoDepositsProvided();
        if (_deposits.length > 10) revert Escrow__TooManyDeposits(); // Limit the number of deposits that can be processed at once

        uint256 contractId;
        if (_contractId == 0) {
            // Create a new contract ID since `_contractId` is zero, indicating a new contract
            contractId = ++currentContractId;
        } else {
            // Check if the provided `_contractId` is valid for adding new milestones
            if (contractMilestones[_contractId].length == 0 && _contractId > currentContractId) {
                revert Escrow__InvalidContractId();
            }
            contractId = _contractId;
        }

        uint256 milestoneId = 0;
        if (contractMilestones[_contractId].length > 0) {
            milestoneId = contractMilestones[_contractId].length;
        }
        uint256 depositsLength = _deposits.length;
        for (uint256 i; i < depositsLength;) {
            Deposit calldata D = _deposits[i];

            if (!registry.paymentTokens(_paymentToken)) revert Escrow__NotSupportedPaymentToken();
            if (D.amount == 0) revert Escrow__ZeroDepositAmount();

            // Calculate the total deposit amount including any fees
            (uint256 totalDepositAmount,) = _computeDepositAmountAndFee(msg.sender, D.amount, D.feeConfig);
            SafeTransferLib.safeTransferFrom(_paymentToken, msg.sender, address(this), totalDepositAmount);

            // Add the new deposit as a new milestone
            contractMilestones[contractId].push(
                Deposit({
                    contractor: D.contractor, // Initialize with contractor assigned, could be zero address on initial stage
                    amount: D.amount,
                    amountToClaim: 0, // Initialize claimable amount to zero
                    amountToWithdraw: 0, // Initialize withdrawable amount to zero
                    contractorData: D.contractorData,
                    feeConfig: D.feeConfig,
                    status: Enums.Status.ACTIVE // Set the initial status of the milestone
                })
            );

            MilestoneDetails storage M = milestoneData[contractId][milestoneId];
            M.paymentToken = _paymentToken;
            M.depositAmount = D.amount;
            M.winner = Enums.Winner.NONE; // Initially set to NONE

            // Emit an event for the deposit of each milestone
            emit Deposited(msg.sender, contractId, milestoneId, _paymentToken, D.amount, D.feeConfig);

            unchecked {
                i++;
                milestoneId++;
            }
        }
    }

    /// @notice Submits a deposit by the contractor.
    /// @dev This function allows the contractor to submit a deposit with their data and salt.
    /// @param _contractId ID of the deposit to be submitted.
    /// @param _milestoneId ID of the milestone within the contract to be submitted.
    /// @param _data Contractor data for the deposit.
    /// @param _salt Salt value for generating the contractor data hash.
    function submit(uint256 _contractId, uint256 _milestoneId, bytes calldata _data, bytes32 _salt) external {
        Deposit storage D = contractMilestones[_contractId][_milestoneId];

        if (D.contractor != address(0)) {
            if (msg.sender != D.contractor) revert Escrow__UnauthorizedAccount(msg.sender);
        }

        if (uint256(D.status) != uint256(Enums.Status.ACTIVE)) revert Escrow__InvalidStatusForSubmit();

        bytes32 contractorDataHash = _getContractorDataHash(_data, _salt);

        if (D.contractorData != contractorDataHash) revert Escrow__InvalidContractorDataHash();

        D.contractor = msg.sender;
        D.status = Enums.Status.SUBMITTED;

        emit Submitted(msg.sender, _contractId, _milestoneId);
    }

    /// @notice Approves a deposit by the client.
    /// @dev This function allows the client to approve a submitted deposit, specifying the amount to approve and any additional amount.
    /// @param _contractId ID of the deposit to be approved.
    /// @param _milestoneId ID of the milestone within the contract to be approved.
    /// @param _amountApprove Amount to approve for the deposit.
    /// @param _receiver Address of the contractor receiving the approved amount.
    function approve(uint256 _contractId, uint256 _milestoneId, uint256 _amountApprove, address _receiver) external {
        if (msg.sender != client && !IEscrowAdminManager(adminManager).isAdmin(msg.sender)) {
            revert Escrow__UnauthorizedAccount(msg.sender);
        }

        if (_amountApprove == 0) revert Escrow__InvalidAmount();

        Deposit storage D = contractMilestones[_contractId][_milestoneId];

        if (uint256(D.status) != uint256(Enums.Status.SUBMITTED)) revert Escrow__InvalidStatusForApprove();

        if (D.contractor != _receiver) revert Escrow__UnauthorizedReceiver();

        if (D.amountToClaim + _amountApprove > D.amount) revert Escrow__NotEnoughDeposit();

        D.amountToClaim += _amountApprove;
        D.status = Enums.Status.APPROVED;

        emit Approved(msg.sender, _contractId, _milestoneId, _amountApprove, _receiver);
    }

    /// @notice Refills the deposit with an additional amount.
    /// @dev This function allows adding additional funds to the deposit, updating the deposit amount accordingly.
    /// @param _contractId ID of the deposit to be refilled.
    /// @param _milestoneId ID of the milestone within the contract to be refilled.
    /// @param _amountAdditional Additional amount to be added to the deposit.
    function refill(uint256 _contractId, uint256 _milestoneId, uint256 _amountAdditional) external onlyClient {
        if (registry.blacklist(msg.sender)) revert Escrow__BlacklistedAccount();
        if (_amountAdditional == 0) revert Escrow__InvalidAmount();

        Deposit storage D = contractMilestones[_contractId][_milestoneId];

        (uint256 totalAmountAdditional, uint256 feeApplied) =
            _computeDepositAmountAndFee(msg.sender, _amountAdditional, D.feeConfig);
        (feeApplied);

        MilestoneDetails storage M = milestoneData[_contractId][_milestoneId];

        SafeTransferLib.safeTransferFrom(M.paymentToken, msg.sender, address(this), totalAmountAdditional);
        D.amount += _amountAdditional;
        emit Refilled(msg.sender, _contractId, _milestoneId, _amountAdditional);
    }

    /// @notice Claims the approved amount by the contractor for a given contract and milestone.
    /// @dev This function allows the contractor to claim the approved amount from the deposit.
    /// @param _contractId ID of the deposit from which to claim funds.
    /// @param _milestoneId ID of the milestone within the contract to be claimed.
    function claim(uint256 _contractId, uint256 _milestoneId) external {
        if (registry.blacklist(msg.sender)) revert Escrow__BlacklistedAccount();

        Deposit storage D = contractMilestones[_contractId][_milestoneId];
        if (D.status != Enums.Status.APPROVED && D.status != Enums.Status.RESOLVED && D.status != Enums.Status.CANCELED)
        {
            revert Escrow__InvalidStatusToClaim();
        }

        if (D.amountToClaim == 0) revert Escrow__NotApproved();
        if (D.contractor != msg.sender) revert Escrow__UnauthorizedAccount(msg.sender);

        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
            _computeClaimableAmountAndFee(msg.sender, D.amountToClaim, D.feeConfig);

        D.amount -= D.amountToClaim;
        D.amountToClaim = 0;

        MilestoneDetails storage M = milestoneData[_contractId][_milestoneId];

        SafeTransferLib.safeTransfer(M.paymentToken, msg.sender, claimAmount);

        if ((D.status == Enums.Status.RESOLVED || D.status == Enums.Status.CANCELED) && feeAmount > 0) {
            _sendPlatformFee(M.paymentToken, feeAmount);
        } else if (feeAmount > 0 || clientFee > 0) {
            _sendPlatformFee(M.paymentToken, feeAmount + clientFee);
        }

        if (D.amount == 0) D.status = Enums.Status.COMPLETED;

        emit Claimed(msg.sender, _contractId, _milestoneId, claimAmount);
    }

    /// @notice Claims all approved amounts by the contractor for a given contract.
    /// @dev Allows the contractor to claim for multiple milestones in a specified range to manage gas costs effectively.
    /// @param _contractId ID of the contract from which to claim funds.
    /// @param _startMilestoneId Starting milestone ID from which to begin claims.
    /// @param _endMilestoneId Ending milestone ID until which claims are made.
    /// This function mitigates gas exhaustion issues by allowing batch processing within a specified limit.
    /// It's designed to optimize transaction efficiency when dealing with numerous milestones.
    function claimAll(uint256 _contractId, uint256 _startMilestoneId, uint256 _endMilestoneId) external {
        if (registry.blacklist(msg.sender)) revert Escrow__BlacklistedAccount();
        if (_startMilestoneId > _endMilestoneId) revert Escrow__InvalidRange();
        if (_endMilestoneId >= contractMilestones[_contractId].length) revert Escrow__OutOfRange();

        uint256 totalClaimedAmount = 0;
        uint256 totalFeeAmount = 0;
        uint256 totalClientFee = 0;

        Deposit[] storage milestones = contractMilestones[_contractId];

        for (uint256 i = _startMilestoneId; i <= _endMilestoneId; ++i) {
            Deposit storage D = milestones[i];

            // Check if the milestone is in a state that allows claiming.
            if (
                D.status == Enums.Status.APPROVED || D.status == Enums.Status.RESOLVED
                    || D.status == Enums.Status.CANCELED
            ) {
                if (D.amountToClaim > 0 && D.contractor == msg.sender) {
                    (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
                        _computeClaimableAmountAndFee(msg.sender, D.amountToClaim, D.feeConfig);

                    D.amount -= D.amountToClaim;
                    totalClaimedAmount += claimAmount;
                    totalFeeAmount += feeAmount;
                    if (D.status != Enums.Status.RESOLVED && D.status != Enums.Status.CANCELED) {
                        totalClientFee += clientFee;
                    }

                    D.amountToClaim = 0; // Reset the claimable amount after claiming.

                    if (D.amount == 0) D.status = Enums.Status.COMPLETED; // Update the status if all funds have been claimed.
                }
            }
        }

        MilestoneDetails storage M = milestoneData[_contractId][0];

        // Perform the token transfer at the end to reduce gas cost by consolidating all transfers into a single operation.
        if (totalClaimedAmount > 0) {
            SafeTransferLib.safeTransfer(M.paymentToken, msg.sender, totalClaimedAmount);
        }

        // Consolidate and send platform fees in one transaction if applicable.
        if (totalFeeAmount > 0 || totalClientFee > 0) {
            _sendPlatformFee(M.paymentToken, totalFeeAmount + totalClientFee);
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

    /// @notice Withdraws funds from a deposit under specific conditions.
    /// @param _contractId ID of the deposit from which funds are to be withdrawn.
    /// @param _milestoneId ID of the milestone within the contract to be withdrawn.
    function withdraw(uint256 _contractId, uint256 _milestoneId) external onlyClient {
        if (registry.blacklist(msg.sender)) revert Escrow__BlacklistedAccount();

        Deposit storage D = contractMilestones[_contractId][_milestoneId];
        if (D.status != Enums.Status.REFUND_APPROVED && D.status != Enums.Status.RESOLVED) {
            revert Escrow__InvalidStatusToWithdraw();
        }

        if (D.amountToWithdraw == 0) revert Escrow__NoFundsAvailableForWithdraw();

        (, uint256 feeAmount) = _computeDepositAmountAndFee(msg.sender, D.amountToWithdraw, D.feeConfig);
        (, uint256 initialFeeAmount) = _computeDepositAmountAndFee(msg.sender, D.amount, D.feeConfig);

        MilestoneDetails storage M = milestoneData[_contractId][_milestoneId];

        uint256 platformFee;
        if (D.status == Enums.Status.REFUND_APPROVED) {
            platformFee = initialFeeAmount - feeAmount;
        } else {
            if (M.winner == Enums.Winner.SPLIT) {
                (, initialFeeAmount) = _computeDepositAmountAndFee(msg.sender, M.depositAmount, D.feeConfig);

                platformFee = initialFeeAmount - feeAmount;
            } else {
                // When withdrawn before claim
                platformFee = initialFeeAmount - feeAmount;
            }
        }

        D.amount -= D.amountToWithdraw;
        uint256 withdrawAmount = D.amountToWithdraw + feeAmount;
        D.amountToWithdraw = 0; // Prevent re-withdrawal

        SafeTransferLib.safeTransfer(M.paymentToken, msg.sender, withdrawAmount);

        if (platformFee > 0) {
            _sendPlatformFee(M.paymentToken, platformFee);
        }

        D.status = Enums.Status.CANCELED; // Mark the deposit as canceled after funds are withdrawn

        emit Withdrawn(msg.sender, _contractId, _milestoneId, withdrawAmount);
    }

    /*//////////////////////////////////////////////////////////////
                ESCROW RETURN REQUEST & DISPUTE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Requests the return of funds by the client.
    /// @param _contractId ID of the deposit for which the return is requested.
    /// @param _milestoneId ID of the milestone for which the return is requested.
    function requestReturn(uint256 _contractId, uint256 _milestoneId) external onlyClient {
        Deposit storage D = contractMilestones[_contractId][_milestoneId];
        if (
            D.status != Enums.Status.ACTIVE && D.status != Enums.Status.SUBMITTED && D.status != Enums.Status.APPROVED
                && D.status != Enums.Status.COMPLETED
        ) revert Escrow__ReturnNotAllowed();

        D.status = Enums.Status.RETURN_REQUESTED;
        emit ReturnRequested(msg.sender, _contractId, _milestoneId);
    }

    /// @notice Approves the return of funds, callable by contractor or platform owner/admin.
    /// @param _contractId ID of the deposit for which the return is approved.
    /// @param _milestoneId ID of the milestone for which the return is approved.
    function approveReturn(uint256 _contractId, uint256 _milestoneId) external {
        Deposit storage D = contractMilestones[_contractId][_milestoneId];
        if (D.status != Enums.Status.RETURN_REQUESTED) revert Escrow__NoReturnRequested();
        if (msg.sender != D.contractor && !IEscrowAdminManager(adminManager).isAdmin(msg.sender)) {
            revert Escrow__UnauthorizedToApproveReturn();
        }

        D.amountToWithdraw = D.amount;

        D.status = Enums.Status.REFUND_APPROVED;
        emit ReturnApproved(msg.sender, _contractId, _milestoneId);
    }

    /// @notice Cancels a previously requested return and resets the deposit's status.
    /// @dev This function allows a client to cancel a return request, setting the deposit status back to either ACTIVE or SUBMITTED or APPROVED or COMPLETED.
    /// @param _contractId The unique identifier of the deposit for which the return is being cancelled.
    /// @param _milestoneId ID of the milestone for which the return is being cancelled.
    /// @param _status The new status to set for the deposit, must be either ACTIVE or SUBMITTED or APPROVED or COMPLETED.
    function cancelReturn(uint256 _contractId, uint256 _milestoneId, Enums.Status _status) external onlyClient {
        Deposit storage D = contractMilestones[_contractId][_milestoneId];
        if (D.status != Enums.Status.RETURN_REQUESTED) revert Escrow__NoReturnRequested();
        if (
            _status != Enums.Status.ACTIVE && _status != Enums.Status.SUBMITTED && _status != Enums.Status.APPROVED
                && _status != Enums.Status.COMPLETED
        ) {
            revert Escrow__InvalidStatusProvided();
        }

        D.status = _status;
        emit ReturnCanceled(msg.sender, _contractId, _milestoneId);
    }

    /// @notice Creates a dispute over a specific deposit.
    /// @param _contractId ID of the deposit where the dispute occurred.
    /// @param _milestoneId ID of the deposit where the dispute occurred.
    function createDispute(uint256 _contractId, uint256 _milestoneId) external {
        Deposit storage D = contractMilestones[_contractId][_milestoneId];
        if (D.status != Enums.Status.RETURN_REQUESTED && D.status != Enums.Status.SUBMITTED) {
            revert Escrow__CreateDisputeNotAllowed();
        }
        if (msg.sender != client && msg.sender != D.contractor) revert Escrow__UnauthorizedToApproveDispute();

        D.status = Enums.Status.DISPUTED;
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

        Deposit storage D = contractMilestones[_contractId][_milestoneId];
        if (D.status != Enums.Status.DISPUTED) revert Escrow__DisputeNotActiveForThisDeposit();

        // Validate the total resolution does not exceed the available deposit amount.
        uint256 totalResolutionAmount = _clientAmount + _contractorAmount;
        if (totalResolutionAmount > D.amount) revert Escrow__ResolutionExceedsDepositedAmount();

        // Apply resolution based on the winner
        if (_winner == Enums.Winner.CLIENT) {
            D.status = Enums.Status.RESOLVED; // Client can now withdraw the full amount
            D.amountToWithdraw = _clientAmount; // Full amount for the client to withdraw
            D.amountToClaim = 0; // No claimable amount for the contractor
        } else if (_winner == Enums.Winner.CONTRACTOR) {
            D.status = Enums.Status.APPROVED; // Status that allows the contractor to claim
            D.amountToClaim = _contractorAmount; // Amount the contractor can claim
            D.amountToWithdraw = 0; // No amount for the client to withdraw
        } else if (_winner == Enums.Winner.SPLIT) {
            D.status = Enums.Status.RESOLVED; // Indicates a resolved dispute with split amounts
            D.amountToClaim = _contractorAmount; // Set the claimable amount for the contractor
            D.amountToWithdraw = _clientAmount; // Set the withdrawable amount for the client
        }

        MilestoneDetails storage M = milestoneData[_contractId][_milestoneId];
        M.winner = _winner;

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

        Deposit storage D = contractMilestones[_contractId][_milestoneId];

        // Emit the ownership transfer event before changing the state to reflect the previous state.
        emit ContractorOwnershipTransferred(_contractId, _milestoneId, D.contractor, _newAccount);

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
