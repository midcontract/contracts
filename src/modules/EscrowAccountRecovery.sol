// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Escrow Account Recovery
/// @notice Provides mechanisms for recovering access to the client or contractor accounts 
/// in an escrow contract in case of lost credentials, using a guardian-based recovery process.
contract EscrowAccountRecovery {
    /// @dev Recovery period after which recovery can be executed.
    uint64 public constant RECOVERY_PERIOD = 5 days;

    /// @dev Time after which the next recovery can be executed.
    uint64 public executeAfter;

    /// @dev Nonce to ensure unique recovery requests.
    uint256 public recoveryNonce;

    /// @notice Indicates the guardian's address who can initiate recoveries.
    address public guardian;

    /// @notice Enum to specify the account type for recovery.
    enum AccountTypeRecovery {
        CLIENT,
        CONTRACTOR
    }

    /// @dev Mapping from recovery hash to whether it has been executed.
    mapping(bytes32 recoveryHash => bool executed) public isExecuted;

    /// @dev Mapping from recovery hash to whether it has been confirmed.
    mapping(bytes32 recoveryHash => bool confirmed) public isConfirmed;

    /// @dev Custom errors
    error InvalidGuardian();
    error ZeroAddressProvided();
    error RecoveryAlreadyExecuted();
    error RecoveryPeriodStillPending();
    error RecoveryNotConfirmed();
    error UnauthorizedAccount();

    /// @dev Emitted when recovery is initiated by guardian
    event RecoveryInitiated(address sender, bytes32 recoveryHash);
    /// @dev Emitted when recovery is executed by new user account
    event RecoveryExecuted(address sender, bytes32 recoveryHash);
    /// @dev Emmited when recovey is canceled by old user account
    event RecoveryCanceled(address sender, bytes32 recoveryHash);
    /// @dev Emitted when guardian is updated
    event GuardianUpdated(address guardian);

    /// @dev Modifier to restrict functions to the guardian address.
    modifier onlyGuardian() {
        if (msg.sender != guardian) revert InvalidGuardian();
        _;
    }

    /// @notice Initiates a recovery process for an account.
    /// @param _recoveryHash The hash representing the recovery details.
    function initiateRecovery(bytes32 _recoveryHash) external onlyGuardian {
        if (isExecuted[_recoveryHash]) revert RecoveryAlreadyExecuted();
        isConfirmed[_recoveryHash] = true;
        executeAfter = uint64(block.timestamp + RECOVERY_PERIOD);
        emit RecoveryInitiated(msg.sender, _recoveryHash);
    }

    /// @notice Executes a previously confirmed recovery.
    /// @param _accountType The type of account being recovered, either CLIENT or CONTRACTOR.
    /// @param _oldUser The current address that will be replaced.
    function executeRecovery(AccountTypeRecovery _accountType, address _oldUser) external {
        if (uint64(block.timestamp) < executeAfter) revert RecoveryPeriodStillPending();
        bytes32 recoveryHash = _encodeRecoveryHash(_oldUser, msg.sender);

        if (isExecuted[recoveryHash]) revert RecoveryAlreadyExecuted();
        if (!isConfirmed[recoveryHash]) revert RecoveryNotConfirmed();

        isExecuted[recoveryHash] = true;
        executeAfter = 0;

        if (_accountType == AccountTypeRecovery.CLIENT) {
            // _transferClientOwnership(msg.sender);
        } else if (_accountType == AccountTypeRecovery.CONTRACTOR) {
            // _transferContractorOwnership(msg.sender);
        }

        unchecked {
            recoveryNonce++;
        }

        emit RecoveryExecuted(msg.sender, recoveryHash);
    }

    /// @notice Cancels a recovery process.
    /// @param _recoveryHash The hash of the recovery request.
    function cancelRecovery(bytes32 _recoveryHash) external {
        // if (msg.sender != client && msg.sender != contractor) revert UnauthorizedAccount();
        if (executeAfter == 0) revert RecoveryNotConfirmed();

        isExecuted[_recoveryHash] = true;
        executeAfter = 0;
        emit RecoveryCanceled(msg.sender, _recoveryHash);
    }

    /// @dev Internal function to generate a recovery hash.
    /// @param _oldUser Address of the user being replaced.
    /// @param _newUser Address of the new user.
    /// @return Hash of the recovery details.
    function _encodeRecoveryHash(address _oldUser, address _newUser) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(_oldUser, _newUser, recoveryNonce));
    }

    /// @dev Internal function to update the guardian address.
    /// @param _guardian New guardian address.
    function _updateGuardian(address _guardian) internal {
        if (_guardian == address(0)) revert ZeroAddressProvided();
        guardian = _guardian;
        emit GuardianUpdated(_guardian);
    }

    /// @dev Generates the recovery hash that should be signed by the guardian to initiate a recovery.
    /// @param _oldUser Address of the user being replaced.
    /// @param _newUser Address of the new user.
    /// @return Hash of the recovery details.
    function getRecoveryHash(address _oldUser, address _newUser) external view returns (bytes32) {
        return _encodeRecoveryHash(_oldUser, _newUser);
    }

    /// @notice Allows the guardian to update to a new guardian address.
    /// @param _guardian The new guardian's address.
    function updateGuardian(address _guardian) external onlyGuardian {
        _updateGuardian(_guardian);
    }
}
