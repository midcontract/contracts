// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SignatureChecker} from "@openzeppelin/utils/cryptography/SignatureChecker.sol";

import {IEscrowHourly} from "./interfaces/IEscrowHourly.sol";
import {IEscrowFeeManager} from "./interfaces/IEscrowFeeManager.sol";
import {IEscrowRegistry} from "./interfaces/IEscrowRegistry.sol";
import {ECDSA, ERC1271} from "src/libs/ERC1271.sol";
import {Enums} from "src/libs/Enums.sol";
import {Ownable} from "src/libs/Ownable.sol";
import {SafeTransferLib} from "src/libs/SafeTransferLib.sol";

import {console2} from "lib/forge-std/src/console2.sol";

/// @title Deposit management for Escrow Hourly
/// @notice Manages the creation and addition of multiple weekly beels to escrow contracts.
/// @dev Handles both the creation of a new escrow contract and the addition of weekly beels to existing contracts.
contract EscrowHourly is IEscrowHourly, ERC1271, Ownable {
    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                       CONFIGURATION & STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Address of the registry contract.
    IEscrowRegistry public registry;

    /// @dev Address of the client initiating actions within the escrow.
    address public client;

    /// @dev Current contract ID, incremented for each new deposit.
    uint256 private currentContractId;

    /// @dev Indicates that the contract has been initialized.
    bool public initialized;

    // Maps from contract ID to its details
    mapping(uint256 contractId => ContractDetails) public contractDetails;

    /// @dev Maps a contract ID to an array of `Deposit` structures representing weeks.
    mapping(uint256 contractId => Deposit[] weekIds) public contractWeeks;

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
    /// @param _owner Address of the owner of the midcontract escrow platform.
    /// @param _registry Address of the registry contract.
    function initialize(address _client, address _owner, address _registry) external {
        if (initialized) revert Escrow__AlreadyInitialized();

        if (_client == address(0) || _owner == address(0) || _registry == address(0)) {
            revert Escrow__ZeroAddressProvided();
        }

        client = _client;
        registry = IEscrowRegistry(_registry);
        _initializeOwner(_owner);

        initialized = true;
    }

    /*//////////////////////////////////////////////////////////////
                    ESCROW HOURLY UNDERLYING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates or updates a week's deposit for a new or existing contract.
    /// @dev This function handles the initialization or update of a week's deposit in a single transaction.
    ///      If a new contract ID is provided, a new contract is initialized; otherwise, it adds to an existing contract.
    /// @param _contractId ID of the contract for which the deposit is made; if zero, a new contract is initialized.
    /// @param _deposit Details of the week's deposit.
    function deposit(uint256 _contractId, address _paymentToken, uint256 _prepaymentAmount, Deposit calldata _deposit)
        external
        onlyClient
    {
        // Validate deposit inputs
        if (_prepaymentAmount == 0 && _deposit.amountToClaim == 0) {
            revert Escrow__InvalidAmount();
        }

        if (_deposit.contractor == address(0)) revert Escrow__ZeroAddressProvided();

        // Determine contract ID
        uint256 contractId = _contractId == 0 ? ++currentContractId : _contractId;
        if (_contractId > 0 && (contractWeeks[_contractId].length == 0 && _contractId > currentContractId)) {
            revert Escrow__InvalidContractId();
        }

        if (!registry.paymentTokens(_paymentToken)) revert Escrow__NotSupportedPaymentToken();

        uint256 totalDepositAmount = 0;
        uint256 depositAmount = _prepaymentAmount > 0 ? _prepaymentAmount : _deposit.amountToClaim;
        (totalDepositAmount,) = _computeDepositAmountAndFee(msg.sender, depositAmount, _deposit.feeConfig);

        SafeTransferLib.safeTransferFrom(_paymentToken, msg.sender, address(this), totalDepositAmount);

        ContractDetails storage C = contractDetails[contractId];
        C.paymentToken = _paymentToken;
        C.prepaymentAmount = _prepaymentAmount;

        // Determine the correct status based on deposit amounts
        Enums.Status contractStatus = _prepaymentAmount > 0
            ? Enums.Status.ACTIVE
            : (_deposit.amountToClaim > 0 ? Enums.Status.APPROVED : Enums.Status.ACTIVE);

        C.status = contractStatus;

        // Add the new deposit as a new week
        contractWeeks[contractId].push(
            Deposit({
                contractor: _deposit.contractor, // Initialize with contractor assigned, could be zero address on initial stage
                amount: _deposit.amount, // TODO TBC Amount for the week can be zero, for calculation
                amountToClaim: _deposit.amountToClaim, // amountToClaim > 0 if prepaymentAmount == 0 && Status.APPROVED; || D.amountToClaim == 0 if prepaymentAmount > 0 && Status.ACTIVE;
                feeConfig: _deposit.feeConfig
            })
        );

        // Emit an event for the deposit of each week
        emit Deposited(msg.sender, contractId, contractWeeks[contractId].length - 1, _paymentToken, totalDepositAmount);
    }

    // - If the client initially sets up the contract with only a prepayment, they must subsequently call the `approve` function and transfer the amount approved for the specific service or task.
    // - If the client does not make a prepayment, they should directly use the `deposit` function, providing all necessary details in the payload and transferring the amount approved for the work, but without including a prepayment.
    /// @notice Approves a deposit by the client.
    /// @dev This function allows the client or owner to approve a submitted deposit, specifying the amount to approve and any additional amount.
    /// @param _contractId ID of the deposit to be approved.
    /// @param _weekId ID of the week within the contract to be approved.
    /// @param _amountApprove Amount to approve for the deposit.
    /// @param _receiver Address of the contractor receiving the approved amount.
    function approve(uint256 _contractId, uint256 _weekId, uint256 _amountApprove, address _receiver) external {
        if (msg.sender != client && msg.sender != owner()) revert Escrow__UnauthorizedAccount(msg.sender);
        if (_weekId >= contractWeeks[_contractId].length) revert Escrow__InvalidWeekId();
        if (_amountApprove == 0) revert Escrow__InvalidAmount();

        ContractDetails storage C = contractDetails[_contractId];

        if (uint256(C.status) != uint256(Enums.Status.ACTIVE)) revert Escrow__InvalidStatusForApprove();

        Deposit storage D = contractWeeks[_contractId][_weekId];

        if (D.contractor != _receiver) revert Escrow__UnauthorizedReceiver();

        if (msg.sender == owner()) {
            if (C.prepaymentAmount < _amountApprove) revert Escrow__InsufficientPrepayment();
            C.prepaymentAmount -= _amountApprove;
            D.amountToClaim += _amountApprove;
        } else {
            (uint256 totalAmountApprove, uint256 feeApplied) =
                _computeDepositAmountAndFee(msg.sender, _amountApprove, D.feeConfig);
            SafeTransferLib.safeTransferFrom(C.paymentToken, msg.sender, address(this), totalAmountApprove);
            D.amountToClaim += _amountApprove;
        }

        C.status = Enums.Status.APPROVED;

        emit Approved(_contractId, _weekId, _amountApprove, _receiver);
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
        if (_amount == 0) revert Escrow__InvalidAmount();

        ContractDetails storage C = contractDetails[_contractId];

        if (!registry.paymentTokens(C.paymentToken)) revert Escrow__NotSupportedPaymentToken();

        Deposit storage D = contractWeeks[_contractId][_weekId];

        if (_type == Enums.RefillType.PREPAYMENT) {
            // Add funds to prepayment
            (uint256 totalAmountAdditional, uint256 feeApplied) =
                _computeDepositAmountAndFee(msg.sender, _amount, D.feeConfig);
            SafeTransferLib.safeTransferFrom(C.paymentToken, msg.sender, address(this), totalAmountAdditional);
            C.prepaymentAmount += _amount;
            emit RefilledPrepayment(_contractId, _amount);
        } else if (_type == Enums.RefillType.WEEK_PAYMENT) {
            // Ensure weekId is within range
            if (_weekId >= contractWeeks[_contractId].length) revert Escrow__InvalidWeekId();

            (uint256 totalAmountAdditional, uint256 feeApplied) =
                _computeDepositAmountAndFee(msg.sender, _amount, D.feeConfig);
            SafeTransferLib.safeTransferFrom(C.paymentToken, msg.sender, address(this), totalAmountAdditional);
            D.amountToClaim += _amount;
            emit RefilledWeekPayment(_contractId, _weekId, _amount);
        }
    }

    /// @notice Claims the approved amount by the contractor.
    /// @dev This function allows the contractor to claim the approved amount from the deposit.
    /// @param _contractId ID of the deposit from which to claim funds.
    /// @param _weekId ID of the week within the contract to be claimed.
    function claim(uint256 _contractId, uint256 _weekId) external {
        ContractDetails storage C = contractDetails[_contractId];
        if (C.status != Enums.Status.APPROVED && C.status != Enums.Status.CANCELED) {
            revert Escrow__InvalidStatusToClaim();
        }

        Deposit storage D = contractWeeks[_contractId][_weekId];
        if (D.contractor != msg.sender) revert Escrow__UnauthorizedAccount(msg.sender);
        if (D.amountToClaim == 0) revert Escrow__NotApproved();

        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
            _computeClaimableAmountAndFee(msg.sender, D.amountToClaim, D.feeConfig);

        D.amountToClaim = 0;

        SafeTransferLib.safeTransfer(C.paymentToken, msg.sender, claimAmount);

        if (C.status == Enums.Status.CANCELED && feeAmount > 0) {
            _sendPlatformFee(C.paymentToken, feeAmount);
        } else if (feeAmount > 0 || clientFee > 0) {
            _sendPlatformFee(C.paymentToken, feeAmount + clientFee);
        }

        if (D.amount == 0) C.status = Enums.Status.COMPLETED;

        emit Claimed(_contractId, _weekId, claimAmount);
    }

    /// @notice Withdraws funds from a deposit under specific conditions.
    /// @param _contractId ID of the deposit from which funds are to be withdrawn.
    /// @param _weekId ID of the week within the contract to be withdrawn.
    function withdraw(uint256 _contractId, uint256 _weekId) external onlyClient {
        Deposit storage D = contractWeeks[_contractId][_weekId];
        ContractDetails storage C = contractDetails[_contractId];
        if (C.status != Enums.Status.REFUND_APPROVED) {
            revert Escrow__InvalidStatusToWithdraw();
        }
        // if (D.amountToWithdraw == 0) revert Escrow__NoFundsAvailableForWithdraw();

        (, uint256 feeAmount) = _computeDepositAmountAndFee(msg.sender, C.prepaymentAmount, D.feeConfig);

        // (, uint256 initialFeeAmount) = _computeDepositAmountAndFee(msg.sender, D.amount, D.feeConfig);

        // D.amount -= D.amountToWithdraw;
        uint256 withdrawAmount = C.prepaymentAmount + feeAmount;
        // D.amountToWithdraw = 0; // Prevent re-withdrawal
        C.status = Enums.Status.CANCELED; // Mark the deposit as canceled after funds are withdrawn

        SafeTransferLib.safeTransfer(C.paymentToken, msg.sender, withdrawAmount);

        // uint256 platformFee = initialFeeAmount - feeAmount;
        // if (platformFee > 0) {
        //     _sendPlatformFee(C.paymentToken, platformFee);
        // }

        emit Withdrawn(_contractId, _weekId, withdrawAmount);
    }

    /*//////////////////////////////////////////////////////////////
                ESCROW RETURN REQUEST & DISPUTE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Requests the return of funds by the client.
    /// @param _contractId ID of the deposit for which the return is requested.
    /// @param _weekId ID of the week for which the return is requested.
    function requestReturn(uint256 _contractId, uint256 _weekId) external onlyClient {
        ContractDetails storage C = contractDetails[_contractId];
        if (C.status != Enums.Status.ACTIVE && C.status != Enums.Status.SUBMITTED) revert Escrow__ReturnNotAllowed();

        C.status = Enums.Status.RETURN_REQUESTED;
        emit ReturnRequested(_contractId, _weekId);
    }

    /// @notice Approves the return of funds, callable by contractor or platform owner/admin.
    /// @param _contractId ID of the deposit for which the return is approved.
    /// @param _weekId ID of the deposit for which the return is approved.
    function approveReturn(uint256 _contractId, uint256 _weekId) external {
        ContractDetails storage C = contractDetails[_contractId];
        if (C.status != Enums.Status.RETURN_REQUESTED) revert Escrow__NoReturnRequested();

        Deposit storage D = contractWeeks[_contractId][_weekId];
        if (msg.sender != D.contractor && msg.sender != owner()) revert Escrow__UnauthorizedToApproveReturn();

        // ContractDetails storage C = contractDetails[_contractId];
        // D.amountToWithdraw = D.amount;

        C.status = Enums.Status.REFUND_APPROVED;
        emit ReturnApproved(_contractId, _weekId, msg.sender);
    }

    /// @notice Cancels a previously requested return and resets the deposit's status.
    /// @dev This function allows a client to cancel a return request, setting the deposit status back to either ACTIVE or SUBMITTED.
    /// @param _contractId The unique identifier of the deposit for which the return is cancelled.
    /// @param _weekId ID of the deposit for which the return is cancelled.
    /// @param _status The new status to set for the deposit, must be either ACTIVE or SUBMITTED.
    /// @custom:modifier onlyClient Ensures that only the client associated with the deposit can execute this function.
    function cancelReturn(uint256 _contractId, uint256 _weekId, Enums.Status _status) external onlyClient {
        ContractDetails storage C = contractDetails[_contractId];
        if (C.status != Enums.Status.RETURN_REQUESTED) revert Escrow__NoReturnRequested();
        if (_status != Enums.Status.ACTIVE && _status != Enums.Status.SUBMITTED) {
            revert Escrow__InvalidStatusProvided();
        }

        C.status = _status;
        emit ReturnCanceled(_contractId, _weekId);
    }
    /*
    /// @notice Creates a dispute over a specific deposit.
    /// @param _contractId ID of the deposit where the dispute occurred.
    /// @param _weekId ID of the deposit where the dispute occurred.
    function createDispute(uint256 _contractId, uint256 _weekId) external {
        Deposit storage D = contractWeeks[_contractId][_weekId];
        if (D.status != Enums.Status.RETURN_REQUESTED && D.status != Enums.Status.SUBMITTED) {
            revert Escrow__CreateDisputeNotAllowed();
        }
        if (msg.sender != client && msg.sender != D.contractor) revert Escrow__UnauthorizedToApproveDispute();

        D.status = Enums.Status.DISPUTED;
        emit DisputeCreated(_contractId, _weekId, msg.sender);
    }

    /// @notice Resolves a dispute over a specific deposit.
    /// @param _contractId ID of the deposit where the dispute occurred.
    /// @param _weekId ID of the deposit where the dispute occurred.
    /// @param _winner Specifies who the winner is: Client, Contractor, or Split.
    /// @param _clientAmount Amount to be allocated to the client if Split or Client wins.
    /// @param _contractorAmount Amount to be allocated to the contractor if Split or Contractor wins.
    function resolveDispute(
        uint256 _contractId,
        uint256 _weekId,
        Enums.Winner _winner,
        uint256 _clientAmount,
        uint256 _contractorAmount
    ) external onlyOwner {
        Deposit storage D = contractWeeks[_contractId][_weekId];
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

        emit DisputeResolved(_contractId, _weekId, _winner, _clientAmount, _contractorAmount);
    }
    */
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
        if (treasury == address(0)) revert Escrow__ZeroAddressProvided(); // TODO test
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

    // /// @notice Generates a hash for the contractor data.
    // /// @dev This internal function computes the hash value for the contractor data using the provided data and salt.
    // function _getContractorDataHash(bytes calldata _data, bytes32 _salt) internal pure returns (bytes32) {
    //     return keccak256(abi.encodePacked(_data, _salt));
    // }

    /*//////////////////////////////////////////////////////////////
                    EXTERNAL VIEW & MANAGER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // /// @notice Generates a hash for the contractor data.
    // /// @dev This external function computes the hash value for the contractor data using the provided data and salt.
    // /// @param _data Contractor data.
    // /// @param _salt Salt value for generating the hash.
    // /// @return Hash value of the contractor data.
    // function getContractorDataHash(bytes calldata _data, bytes32 _salt) external pure returns (bytes32) {
    //     return _getContractorDataHash(_data, _salt);
    // }

    /// @notice Retrieves the current contract ID.
    /// @return The current contract ID.
    function getCurrentContractId() external view returns (uint256) {
        return currentContractId;
    }

    /// @notice Retrieves the number of weeks for a given contract ID.
    /// @param _contractId The contract ID for which to retrieve the week count.
    /// @return The number of weeks associated with the given contract ID.
    function getWeeksCount(uint256 _contractId) external view returns (uint256) {
        return contractWeeks[_contractId].length;
    }

    /// @notice Updates the registry address used for fetching escrow implementations.
    /// @param _registry New registry address.
    function updateRegistry(address _registry) external onlyOwner {
        if (_registry == address(0)) revert Escrow__ZeroAddressProvided();
        registry = IEscrowRegistry(_registry);
        emit RegistryUpdated(_registry);
    }
}
