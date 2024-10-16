// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { OwnedRoles } from "@solbase/auth/OwnedRoles.sol";

/// @title Escrow Admin Manager
/// @notice Manages administrative roles and permissions for the escrow system, using a role-based access control mechanism.
/// @dev This contract extends OwnedRoles to utilize its role management functionalities and establishes predefined roles such as Admin, Guardian, and Strategist.
/// It includes references to unused role constants defined in the OwnedRoles library, which are part of the library's design to accommodate potential future roles. 
/// These constants do not affect the contract's functionality or gas efficiency but are retained for compatibility and future flexibility.
contract EscrowAdminManager is OwnedRoles {
    // Define roles bitmask.
    uint256 private constant ADMIN_ROLE = 1 << 1;
    uint256 private constant GUARDIAN_ROLE = 1 << 2;
    uint256 private constant STRATEGIST_ROLE = 1 << 3;
    uint256 private constant DAO_ROLE = 1 << 4;

    /// @dev Initializes the contract by setting the initial owner and granting them the Admin role.
    /// @param _initialOwner Address of the initial owner of the contract.
    constructor(address _initialOwner) {
        _initializeOwner(_initialOwner);
        _grantRoles(_initialOwner, ADMIN_ROLE);
    }

    /// @notice Grants the Admin role to a specified address.
    /// @param _admin Address to which the Admin role will be granted.
    function addAdmin(address _admin) external onlyOwner {
        _grantRoles(_admin, ADMIN_ROLE);
    }

    /// @notice Revokes the Admin role from a specified address.
    /// @param _admin Address from which the Admin role will be revoked.
    function removeAdmin(address _admin) external onlyOwner {
        _removeRoles(_admin, ADMIN_ROLE);
    }

    /// @notice Grants the Guardian role to a specified address.
    /// @param _guardian Address to which the Guardian role will be granted.
    function addGuardian(address _guardian) external onlyOwner {
        _grantRoles(_guardian, GUARDIAN_ROLE);
    }

    /// @notice Revokes the Guardian role from a specified address.
    /// @param _guardian Address from which the Guardian role will be revoked.
    function removeGuardian(address _guardian) external onlyOwner {
        _removeRoles(_guardian, GUARDIAN_ROLE);
    }

    /// @notice Grants the Strategist role to a specified address.
    /// @param _strategist Address to which the Strategist role will be granted.
    function addStrategist(address _strategist) external onlyOwner {
        _grantRoles(_strategist, STRATEGIST_ROLE);
    }

    /// @notice Revokes the Strategist role from a specified address.
    /// @param _strategist Address from which the Strategist role will be revoked.
    function removeStrategist(address _strategist) external onlyOwner {
        _removeRoles(_strategist, STRATEGIST_ROLE);
    }

    /// @notice Grants the Dao role to a specified address.
    /// @param _daoAccount Address to which the Dao role will be granted.
    function addDaoAccount(address _daoAccount) external onlyOwner {
        _grantRoles(_daoAccount, DAO_ROLE);
    }

    /// @notice Revokes the Dao role from a specified address.
    /// @param _daoAccount Address from which the Dao role will be revoked.
    function removeDaoAccount(address _daoAccount) external onlyOwner {
        _removeRoles(_daoAccount, DAO_ROLE);
    }

    /// @notice Checks if a specified address has the Admin role.
    /// @param _account Address to check for the Admin role.
    /// @return True if the address has the Admin role, otherwise false.
    function isAdmin(address _account) public view returns (bool) {
        return hasAnyRole(_account, ADMIN_ROLE);
    }

    /// @notice Checks if a specified address has the Guardian role.
    /// @param _account Address to check for the Guardian role.
    /// @return True if the address has the Guardian role, otherwise false.
    function isGuardian(address _account) public view returns (bool) {
        return hasAnyRole(_account, GUARDIAN_ROLE);
    }

    /// @notice Checks if a specified address has the Strategist role.
    /// @param _account Address to check for the Strategist role.
    /// @return True if the address has the Strategist role, otherwise false.
    function isStrategist(address _account) public view returns (bool) {
        return hasAnyRole(_account, STRATEGIST_ROLE);
    }

    /// @notice Checks if a specified address has the Dao role.
    /// @param _account Address to check for the Dao role.
    /// @return True if the address has the Dao role, otherwise false.
    function isDao(address _account) public view returns (bool) {
        return hasAnyRole(_account, DAO_ROLE);
    }
}
