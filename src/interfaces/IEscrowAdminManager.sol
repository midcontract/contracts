// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title Interface for Escrow Admin Manager
/// @notice Provides interface methods for checking roles in the Escrow Admin Management system.
interface IEscrowAdminManager {
    /// @dev Thrown when zero address usage where prohibited.
    error ZeroAddressProvided();
    /// @notice Thrown when an ETH transfer failed.
    error ETHTransferFailed();

    /// @notice Emitted when ETH is successfully withdrawn from the contract.
    /// @param receiver The address that received the withdrawn ETH.
    /// @param amount The amount of ETH withdrawn from the contract.
    event ETHWithdrawn(address receiver, uint256 amount);

    /// @notice Retrieves the current owner of the contract.
    /// @return The address of the current owner.
    function owner() external view returns (address);

    /// @notice Determines if a given account has admin privileges.
    /// @param account The address to query for admin status.
    /// @return True if the specified account is an admin, false otherwise.
    function isAdmin(address account) external view returns (bool);

    /// @notice Determines if a given account is assigned the guardian role.
    /// @param account The address to query for guardian status.
    /// @return True if the specified account is a guardian, false otherwise.
    function isGuardian(address account) external view returns (bool);

    /// @notice Determines if a given account is assigned the strategist role.
    /// @param account The address to query for strategist status.
    /// @return True if the specified account is a strategist, false otherwise.
    function isStrategist(address account) external view returns (bool);

    /// @notice Determines if a given account is assigned the dao role.
    /// @param account The address to query for dao status.
    /// @return True if the specified account is a dao, false otherwise.
    function isDao(address account) external view returns (bool);
}
