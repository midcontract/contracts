// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Enums} from "src/libs/Enums.sol";

/// @title Escrow Account Recovery
/// @notice Provides mechanisms for recovering access to the client or contractor accounts
/// in an escrow contract in case of lost credentials, using a guardian-based recovery process.
contract EscrowAccountRecovery {
    /// @dev Recovery period after which recovery can be executed.
    uint64 public constant MIN_RECOVERY_PERIOD = 3 days;

    /// @dev Time after which the next recovery can be executed.
    uint64 public executeAfter;

    // /// @dev Nonce to ensure unique recovery requests.
    // uint256 public recoveryNonce;

    /// @notice Indicates the guardian's address who can initiate recoveries.
    address public guardian;

    /// @notice Enum to specify the account type for recovery.
    enum AccountTypeRecovery {
        CLIENT,
        CONTRACTOR
    }

    /// TODO blacklisting globaly in Registry

    struct RecoveryData {
        address escrow; // address of escrow contract where account should be recovered
        uint256 contractId;
        uint256 milestoneId; //milestoneId or weekId
        address account; // oldAccount to be recovered
        uint64 executeAfter;
        bool executed;
        bool confirmed;
        Enums.EscrowType escrowType;
    }

    /// @dev Mapping of recovery hashes to their corresponding data.
    mapping(bytes32 recoveryHash => RecoveryData) public recoveryData;

    /// @dev Custom errors
    error InvalidGuardian();
    error ZeroAddressProvided();
    error RecoveryAlreadyExecuted();
    error RecoveryPeriodStillPending();
    error RecoveryNotConfirmed();
    error UnauthorizedAccount();

    /// @dev Emitted when recovery is initiated by guardian
    event RecoveryInitiated(address indexed sender, bytes32 indexed recoveryHash);
    /// @dev Emitted when recovery is executed by new user account
    event RecoveryExecuted(address indexed sender, bytes32 indexed recoveryHash);
    /// @dev Emmited when recovey is canceled by old user account
    event RecoveryCanceled(address indexed sender, bytes32 indexed recoveryHash);
    /// @dev Emitted when guardian is updated
    event GuardianUpdated(address guardian);

    /// @dev Modifier to restrict functions to the guardian address.
    modifier onlyGuardian() {
        if (msg.sender != guardian) revert InvalidGuardian();
        _;
    }

    /// @notice Initiates a recovery process for an account.
    // /// @param _recoveryHash The hash representing the recovery details.
    function initiateRecovery(
        address _escrow,
        uint256 _contractId,
        uint256 _milestoneId,
        address _oldAccount,
        address _newAccount,
        Enums.EscrowType _escrowType
    ) external onlyGuardian {
        //, bytes32 _recoveryHash
        bytes32 recoveryHash = _encodeRecoveryHash(_escrow, _oldAccount, _newAccount);
        RecoveryData storage data = recoveryData[recoveryHash];
        if (data.executed) revert RecoveryAlreadyExecuted();

        recoveryData[recoveryHash] = RecoveryData({
            escrow: _escrow,
            account: _oldAccount,
            contractId: _contractId,
            milestoneId: _milestoneId,
            executeAfter: uint64(block.timestamp + MIN_RECOVERY_PERIOD),
            executed: false,
            confirmed: true,
            escrowType: _escrowType
        });

        emit RecoveryInitiated(msg.sender, recoveryHash);
    }

    /// @notice Executes a previously confirmed recovery.
    /// @param _accountType The type of account being recovered, either CLIENT or CONTRACTOR.
    /// @param _oldAccount The current address that will be replaced.
    function executeRecovery(AccountTypeRecovery _accountType, address _escrow, address _oldAccount) external {
        bytes32 recoveryHash = _encodeRecoveryHash(_escrow, _oldAccount, msg.sender);
        RecoveryData storage data = recoveryData[recoveryHash];

        if (uint64(block.timestamp) < data.executeAfter) revert RecoveryPeriodStillPending();

        if (data.executed) revert RecoveryAlreadyExecuted();
        if (!data.confirmed) revert RecoveryNotConfirmed();

        data.executed = true;
        data.executeAfter = 0;

        if (_accountType == AccountTypeRecovery.CLIENT) {
            // transferClientOwnership(msg.sender); contractAddress
            // IEscrow(data.escrow).transferClientOwnership(contractId, msg.sender) external onlyRecovery() {
            // client = msg.sender}
        } else if (_accountType == AccountTypeRecovery.CONTRACTOR) {
            // enum param of the type of contract - EscrowType
            // FIXED_PRICE
            // IEscrow(data.escrow).transferContractorOwnership(contractId, msg.sender) external onlyRecovery() {
            // Deposit storage D = deposits[contractId];
            // D.contractor = msg.sender}
            // MILESTONE
            // IEscrow(data.escrow).transferContractorOwnership(contractId, milestoneId, msg.sender) external onlyRecovery() {
            // Deposit storage D = deposits[contractId][milestoneId];
            // D.contractor = msg.sender}
            // HOURLY
            // IEscrow(data.escrow).transferContractorOwnership(contractId, weekId, msg.sender) external onlyRecovery() {
            // Deposit storage D = deposits[contractId][weekId];
            // D.contractor = msg.sender}
        }

        // unchecked {
        //     recoveryNonce++;
        // }

        emit RecoveryExecuted(msg.sender, recoveryHash);
    }

    // _oldAccount address could be extracted from recoveryHash to check with msg.sender
    /// @notice Cancels a recovery process.
    /// @param _recoveryHash The hash of the recovery request.
    function cancelRecovery(bytes32 _recoveryHash) external {
        RecoveryData storage data = recoveryData[_recoveryHash];
        if (msg.sender != data.account) revert UnauthorizedAccount();
        if (data.executeAfter == 0) revert RecoveryNotConfirmed(); // there could be several recovery processess, so executeAfter should be for particular recoveryHash

        data.executed = true;
        data.executeAfter = 0;

        emit RecoveryCanceled(msg.sender, _recoveryHash);
    }

    /// @dev Internal function to generate a recovery hash.
    /// @param _oldAccount Address of the user being replaced.
    /// @param _newAccount Address of the new user.
    /// @return Hash of the recovery details.
    function _encodeRecoveryHash(address _escrow, address _oldAccount, address _newAccount)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_escrow, _oldAccount, _newAccount)); //, recoveryNonce
    }

    /// @dev Internal function to update the guardian address.
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

    // updateRecoveryPeriod
}
