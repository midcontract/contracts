// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IEscrow } from "../interfaces/IEscrow.sol";
import { IEscrowAdminManager } from "../interfaces/IEscrowAdminManager.sol";
import { IEscrowFixedPrice } from "../interfaces/IEscrowFixedPrice.sol";
import { IEscrowHourly } from "../interfaces/IEscrowHourly.sol";
import { IEscrowMilestone } from "../interfaces/IEscrowMilestone.sol";
import { IEscrowRegistry } from "../interfaces/IEscrowRegistry.sol";
import { Enums } from "../common/Enums.sol";

/// @title Escrow Account Recovery
/// @notice Provides mechanisms for recovering access to the client or contractor accounts
/// in an escrow contract in case of lost credentials, using a guardian-based recovery process.
contract EscrowAccountRecovery {
    /// @dev Address of the adminManager contract.
    IEscrowAdminManager public adminManager;

    /// @dev Address of the registry contract.
    IEscrowRegistry public registry;

    /// @dev Recovery period after which recovery can be executed.
    uint256 public constant MIN_RECOVERY_PERIOD = 3 days;

    /// @dev Maximum allowed recovery period to prevent indefinite blocking of recovery actions.
    uint256 public constant MAX_RECOVERY_PERIOD = 30 days;

    /// @dev Configurable recovery period initialized to the minimum allowed.
    uint256 public recoveryPeriod;

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
        /// @dev Type of escrow involved.
        Enums.EscrowType escrowType;
        /// @dev Type of account to recovery.
        Enums.AccountTypeRecovery accountType;
    }

    /// @dev Mapping of recovery hashes to their corresponding data.
    mapping(bytes32 recoveryHash => RecoveryData) public recoveryData;

    /// @dev Thrown when zero address usage where prohibited.
    error ZeroAddressProvided();
    /// @dev Thrown when trying to execute an already executed recovery.
    error RecoveryAlreadyExecuted();
    /// @dev Thrown when trying to execute recovery before the period has elapsed.
    error RecoveryPeriodStillPending();
    /// @dev Thrown when trying to execute a recovery that has not been initiated.
    error RecoveryNotInitiated();
    /// @dev Thrown when an unauthorized account attempts a restricted action.
    error UnauthorizedAccount();
    /// @dev Thrown indicates an attempt to set the recovery period below the minimum required or to zero.
    error RecoveryPeriodNotValid();

    /// @dev Emitted when a recovery is initiated by the guardian.
    event RecoveryInitiated(address indexed sender, bytes32 indexed recoveryHash);
    /// @dev Emitted when a recovery is executed successfully.
    event RecoveryExecuted(address indexed sender, bytes32 indexed recoveryHash);
    /// @dev Emitted when a recovery is canceled.
    event RecoveryCanceled(address indexed sender, bytes32 indexed recoveryHash);
    /// @dev Emitted when the recovery period is updated to a new value.
    event RecoveryPeriodUpdated(uint256 recoveryPeriod);
    /// @dev Emitted when the admin manager address is updated in the contract.
    event AdminManagerUpdated(address adminManager);

    /// @dev Initializes the contract with the owner and guardian addresses.
    /// @param _adminManager Address of the adminManager contract of the escrow platform.
    /// @param _registry Address of the registry contract.
    constructor(address _adminManager, address _registry) {
        if (_adminManager == address(0) || _registry == address(0)) revert ZeroAddressProvided();
        adminManager = IEscrowAdminManager(_adminManager);
        registry = IEscrowRegistry(_registry);
        recoveryPeriod = MIN_RECOVERY_PERIOD;
    }

    /// @notice Initiates the recovery process for an account.
    /// @param _escrow Address of the escrow contract related to the recovery.
    /// @param _contractId Contract identifier within the escrow.
    /// @param _milestoneId Milestone identifier within the contract.
    /// @param _oldAccount Current account address that needs recovery.
    /// @param _newAccount New account address to replace the old one.
    /// @param _escrowType Type of the escrow contract involved.
    /// @param _accountType Type of the account for recovery.
    function initiateRecovery(
        address _escrow,
        uint256 _contractId,
        uint256 _milestoneId,
        address _oldAccount,
        address _newAccount,
        Enums.EscrowType _escrowType,
        Enums.AccountTypeRecovery _accountType
    ) external {
        if (!IEscrowAdminManager(adminManager).isGuardian(msg.sender)) revert UnauthorizedAccount();

        bytes32 recoveryHash = _encodeRecoveryHash(_escrow, _oldAccount, _newAccount, _accountType);
        RecoveryData storage data = recoveryData[recoveryHash];
        if (data.executed) revert RecoveryAlreadyExecuted();

        recoveryData[recoveryHash] = RecoveryData({
            escrow: _escrow,
            account: _oldAccount,
            contractId: _contractId,
            milestoneId: _milestoneId,
            executeAfter: uint64(block.timestamp + recoveryPeriod),
            executed: false,
            escrowType: _escrowType,
            accountType: _accountType
        });

        emit RecoveryInitiated(msg.sender, recoveryHash);
    }

    /// @notice Executes a previously confirmed recovery.
    /// @param _accountType Type of the account being recovered, either CLIENT or CONTRACTOR.
    /// @param _escrow Address of the escrow involved in the recovery.
    /// @param _oldAccount Old account address being replaced in the recovery.
    /// @dev This function checks that the recovery period has elapsed and that the recovery is confirmed before
    /// executing it.
    function executeRecovery(Enums.AccountTypeRecovery _accountType, address _escrow, address _oldAccount) external {
        bytes32 recoveryHash = _encodeRecoveryHash(_escrow, _oldAccount, msg.sender, _accountType);
        RecoveryData storage data = recoveryData[recoveryHash];

        if (uint64(block.timestamp) < data.executeAfter) revert RecoveryPeriodStillPending();
        if (data.executed) revert RecoveryAlreadyExecuted();
        if (data.executeAfter == 0) revert RecoveryNotInitiated();

        data.executed = true;
        data.executeAfter = 0;

        _transferContractOwnership(data.escrowType, data.escrow, data.contractId, data.milestoneId, _accountType);

        emit RecoveryExecuted(msg.sender, recoveryHash);
    }

    /// @notice Cancels an ongoing recovery process.
    /// @param _recoveryHash Hash of the recovery request to be canceled.
    function cancelRecovery(bytes32 _recoveryHash) external {
        if (registry.blacklist(msg.sender)) revert UnauthorizedAccount();

        RecoveryData storage data = recoveryData[_recoveryHash];
        if (msg.sender != data.account) revert UnauthorizedAccount();
        if (data.executeAfter == 0) revert RecoveryNotInitiated();

        data.executed = true;
        data.executeAfter = 0;

        emit RecoveryCanceled(msg.sender, _recoveryHash);
    }

    /// @dev Transfers the ownership of the escrow contract based on the specified account type and escrow type.
    /// @param escrowType The type of escrow contract involved in the transfer.
    /// @param escrow The address of the escrow contract.
    /// @param contractId The identifier of the contract within the escrow, relevant for contractor transfers.
    /// @param milestoneId The identifier of the milestone within the contract, relevant for milestone-specific
    /// contractor transfers.
    /// @param accountType The type of account to be transferred, can be either CLIENT or CONTRACTOR.
    function _transferContractOwnership(
        Enums.EscrowType escrowType,
        address escrow,
        uint256 contractId,
        uint256 milestoneId,
        Enums.AccountTypeRecovery accountType
    ) internal {
        if (accountType == Enums.AccountTypeRecovery.CLIENT) {
            IEscrow(escrow).transferClientOwnership(msg.sender);
        } else if (accountType == Enums.AccountTypeRecovery.CONTRACTOR) {
            if (escrowType == Enums.EscrowType.MILESTONE) {
                IEscrowMilestone(escrow).transferContractorOwnership(contractId, milestoneId, msg.sender);
            } else {
                IEscrowFixedPrice(escrow).transferContractorOwnership(contractId, msg.sender);
            }
        }
    }

    /// @dev Encodes recovery details into a hash (used internally).
    function _encodeRecoveryHash(
        address _escrow,
        address _oldAccount,
        address _newAccount,
        Enums.AccountTypeRecovery _accountType
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_escrow, _oldAccount, _newAccount, _accountType));
    }

    /// @dev Generates the recovery hash that should be signed by the guardian to initiate a recovery.
    /// @param _oldAccount Address of the user being replaced.
    /// @param _newAccount Address of the new user.
    /// @param _accountType Type of the account being recovered, either CLIENT or CONTRACTOR.
    /// @return Hash of the recovery details.
    function getRecoveryHash(
        address _escrow,
        address _oldAccount,
        address _newAccount,
        Enums.AccountTypeRecovery _accountType
    ) external pure returns (bytes32) {
        return _encodeRecoveryHash(_escrow, _oldAccount, _newAccount, _accountType);
    }

    /// @notice Updates the recovery period to a new value, ensuring it meets minimum requirements.
    /// @dev Can only be called by the owner of the contract.
    /// @param _recoveryPeriod The new recovery period in seconds.
    function updateRecoveryPeriod(uint256 _recoveryPeriod) external {
        if (!IEscrowAdminManager(adminManager).isAdmin(msg.sender)) revert UnauthorizedAccount();
        if (_recoveryPeriod == 0 || _recoveryPeriod < MIN_RECOVERY_PERIOD || _recoveryPeriod > MAX_RECOVERY_PERIOD) {
            revert RecoveryPeriodNotValid();
        }
        recoveryPeriod = _recoveryPeriod;
        emit RecoveryPeriodUpdated(_recoveryPeriod);
    }

    /// @notice Updates the address of the admin manager contract.
    /// @dev Restricts the function to be callable only by the current owner of the admin manager.
    /// @param _adminManager The new address of the admin manager contract.
    function updateAdminManager(address _adminManager) external {
        if (msg.sender != IEscrowAdminManager(adminManager).owner()) revert UnauthorizedAccount();
        if (_adminManager == address(0)) revert ZeroAddressProvided();
        adminManager = IEscrowAdminManager(_adminManager);
        emit AdminManagerUpdated(_adminManager);
    }
}
