// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEscrow} from "src/interfaces/IEscrow.sol";
import {IEscrowFixedPrice} from "src/interfaces/IEscrowFixedPrice.sol";
import {IEscrowMilestone} from "src/interfaces/IEscrowMilestone.sol";
import {IEscrowHourly} from "src/interfaces/IEscrowHourly.sol";
import {Enums} from "src/libs/Enums.sol";
import {Ownable} from "../libs/Ownable.sol";

/// @title Escrow Account Recovery
/// @notice Provides mechanisms for recovering access to the client or contractor accounts
/// in an escrow contract in case of lost credentials, using a guardian-based recovery process.
contract EscrowAccountRecovery is Ownable {
    /// @dev Recovery period after which recovery can be executed.
    uint256 public constant MIN_RECOVERY_PERIOD = 3 days;

    /// @dev Configurable recovery period initialized to the minimum allowed.
    uint256 public recoveryPeriod;

    /// @notice Guardian's address authorized to initiate recovery processes.
    address public guardian;

    /// @notice Data structure to store recovery-related information.
    struct RecoveryData {
        /// @dev Address of the escrow contract where account should be recovered.
        address escrow; 
        /// @dev Address of the old account to be recovered.
        address account; 
        /// @dev Identifier of the contract within the escrow.
        uint256 contractId; 
        /// @dev Identifier of the milestone within the contract.
        uint256 milestoneId; 
        /// @dev Timestamp after which the recovery can be executed.
        uint64 executeAfter; 
        /// @dev Flag indicating if the recovery has been executed.
        bool executed;
        /// @dev Flag indicating if the recovery has been confirmed.
        bool confirmed;
        /// @dev Type of escrow involved.
        Enums.EscrowType escrowType;
    }

    /// @dev Mapping of recovery hashes to their corresponding data.
    mapping(bytes32 recoveryHash => RecoveryData) public recoveryData;

    /// @dev Custom error for invalid guardian operation attempts.
    error InvalidGuardian();
    /// @dev Custom error for zero address usage where prohibited.
    error ZeroAddressProvided();
    /// @dev Custom error when trying to execute an already executed recovery.
    error RecoveryAlreadyExecuted();
    /// @dev Custom error when trying to execute recovery before the period has elapsed.
    error RecoveryPeriodStillPending();
    /// @dev Custom error when trying to execute a recovery that has not been confirmed.
    error RecoveryNotConfirmed();
    /// @dev Custom error when an unauthorized account attempts a restricted action.
    error UnauthorizedAccount();

    /// @dev Emitted when a recovery is initiated by the guardian.
    event RecoveryInitiated(address indexed sender, bytes32 indexed recoveryHash);
    /// @dev Emitted when a recovery is executed successfully.
    event RecoveryExecuted(address indexed sender, bytes32 indexed recoveryHash);
    /// @dev Emitted when a recovery is canceled.
    event RecoveryCanceled(address indexed sender, bytes32 indexed recoveryHash);
    /// @dev Emitted when the guardian address is updated.
    event GuardianUpdated(address guardian);

    /// @dev Modifier to restrict functions to the guardian address.
    modifier onlyGuardian() {
        if (msg.sender != guardian) revert InvalidGuardian();
        _;
    }

    /// @dev Initializes the contract with the owner and guardian addresses.
    /// @param _owner Address of the initial owner of the account recovery contract.
    /// @param _guardian Initial guardian authorized to manage recoveries.
    constructor(address _owner, address _guardian) {
        _initializeOwner(_owner);
        _updateGuardian(_guardian);
        recoveryPeriod = MIN_RECOVERY_PERIOD;
    }

    /// @notice Initiates the recovery process for an account.
    /// @param _escrow Address of the escrow contract related to the recovery.
    /// @param _contractId Contract identifier within the escrow.
    /// @param _milestoneId Milestone identifier within the contract.
    /// @param _oldAccount Current account address that needs recovery.
    /// @param _newAccount New account address to replace the old one.
    /// @param _escrowType Type of the escrow contract involved.
    function initiateRecovery(
        address _escrow,
        uint256 _contractId,
        uint256 _milestoneId,
        address _oldAccount,
        address _newAccount,
        Enums.EscrowType _escrowType
    ) external onlyGuardian {
        bytes32 recoveryHash = _encodeRecoveryHash(_escrow, _oldAccount, _newAccount);
        RecoveryData storage data = recoveryData[recoveryHash];
        if (data.executed) revert RecoveryAlreadyExecuted();

        recoveryData[recoveryHash] = RecoveryData({
            escrow: _escrow,
            account: _oldAccount,
            contractId: _contractId,
            milestoneId: _milestoneId,
            executeAfter: uint64(block.timestamp + recoveryPeriod),
            executed: false,
            confirmed: true,
            escrowType: _escrowType
        });

        emit RecoveryInitiated(msg.sender, recoveryHash);
    }

    /// @notice Executes a previously confirmed recovery.
    /// @param _accountType Type of the account being recovered, either CLIENT or CONTRACTOR.
    /// @param _escrow Address of the escrow involved in the recovery.
    /// @param _oldAccount Old account address being replaced in the recovery.
    function executeRecovery(Enums.AccountTypeRecovery _accountType, address _escrow, address _oldAccount) external {
        bytes32 recoveryHash = _encodeRecoveryHash(_escrow, _oldAccount, msg.sender);
        RecoveryData storage data = recoveryData[recoveryHash];

        if (uint64(block.timestamp) < data.executeAfter) revert RecoveryPeriodStillPending();

        if (data.executed) revert RecoveryAlreadyExecuted();
        if (!data.confirmed) revert RecoveryNotConfirmed();

        data.executed = true;
        data.executeAfter = 0;

        if (_accountType == Enums.AccountTypeRecovery.CLIENT) {
            IEscrow(data.escrow).transferClientOwnership(msg.sender);
        } else if (_accountType == Enums.AccountTypeRecovery.CONTRACTOR) {
            if (data.escrowType == Enums.EscrowType.FIXED_PRICE) {
                IEscrowFixedPrice(data.escrow).transferContractorOwnership(data.contractId, msg.sender);
            } else if (data.escrowType == Enums.EscrowType.MILESTONE) {
                IEscrowMilestone(data.escrow).transferContractorOwnership(data.contractId, data.milestoneId, msg.sender);
            } else if (data.escrowType == Enums.EscrowType.HOURLY) {
                IEscrowHourly(data.escrow).transferContractorOwnership(data.contractId, msg.sender);
            }
        }

        emit RecoveryExecuted(msg.sender, recoveryHash);
    }

    /// @notice Cancels an ongoing recovery process.
    /// @param _recoveryHash Hash of the recovery request to be canceled.
    function cancelRecovery(bytes32 _recoveryHash) external {
        RecoveryData storage data = recoveryData[_recoveryHash];
        if (msg.sender != data.account) revert UnauthorizedAccount();
        if (data.executeAfter == 0) revert RecoveryNotConfirmed(); // there could be several recovery processess, so executeAfter should be for particular recoveryHash

        data.executed = true;
        data.executeAfter = 0;

        emit RecoveryCanceled(msg.sender, _recoveryHash);
    }

    /// @dev Generates the recovery hash based on the escrow, old account, and new account addresses.
    /// @param _escrow Address of the escrow contract involved in the recovery.
    /// @param _oldAccount Address of the old account being replaced.
    /// @param _newAccount Address of the new account replacing the old.
    /// @return Hash of the recovery details.
    function _encodeRecoveryHash(address _escrow, address _oldAccount, address _newAccount)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_escrow, _oldAccount, _newAccount));
    }

    /// @notice Updates the guardian address responsible for initiating recoveries.
    /// @param _guardian New guardian address.
    function _updateGuardian(address _guardian) internal {
        if (_guardian == address(0)) revert ZeroAddressProvided();
        guardian = _guardian;
        emit GuardianUpdated(_guardian);
    }

    /// @dev Generates the recovery hash that should be signed by the guardian to initiate a recovery.
    /// @param _oldAccount Address of the user being replaced.
    /// @param _newAccount Address of the new user.
    /// @return Hash of the recovery details.
    function getRecoveryHash(address _escrow, address _oldAccount, address _newAccount)
        external
        pure
        returns (bytes32)
    {
        return _encodeRecoveryHash(_escrow, _oldAccount, _newAccount);
    }

    /// @notice Allows the guardian to update to a new guardian address.
    /// @param _guardian The new guardian's address.
    function updateGuardian(address _guardian) external onlyGuardian {
        _updateGuardian(_guardian);
    }

}
