// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title Interface for Escrow Admin Manager
/// @notice Provides interface methods for checking roles in the Escrow Admin Management system.
interface IEscrowAdminManager {
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
}
