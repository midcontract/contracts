// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title Interface for the EscrowRegistry
/// @dev Interface for the registry that manages configuration settings such as payment tokens and contract addresses
/// for an escrow system.
interface IEscrowRegistry {
    /// @notice Thrown when a zero address is provided where a valid address is required.
    error Registry__ZeroAddressProvided();

    /// @notice Thrown when attempting to add a token that has already been added to the registry.
    error Registry__TokenAlreadyAdded();

    /// @notice Thrown when attempting to remove or access a token that is not registered.
    error Registry__PaymentTokenNotRegistered();

    /// @notice Emitted when a new payment token is added to the registry.
    /// @param token The address of the token that was added.
    event PaymentTokenAdded(address token);

    /// @notice Emitted when a payment token is removed from the registry.
    /// @param token The address of the token that was removed.
    event PaymentTokenRemoved(address token);

    /// @notice Emitted when the escrow contract address is updated in the registry.
    /// @param escrow The new escrow contract address.
    event EscrowUpdated(address escrow);

    /// @notice Emitted when the factory contract address is updated in the registry.
    /// @param factory The new factory contract address.
    event FactoryUpdated(address factory);

    /// @notice Emitted when the feeManager contract address is updated in the registry.
    /// @param feeManager The new feeManager contract address.
    event FeeManagerUpdated(address feeManager);

    /// @notice Emitted when the treasury account address is set in the registry.
    /// @param treasury The new treasury contract address.
    event TreasurySet(address treasury);

    /// @notice Emitted when the account recovery address is updated in the registry.
    /// @param accountRecovery The new account recovery contract address.
    event AccountRecoverySet(address accountRecovery);

    /// @notice Emitted when the admin manager address is updated in the registry.
    /// @param adminManager The new admin manager contract address.
    event AdminManagerSet(address adminManager);

    /// @notice Emitted when an address is added to the blacklist.
    /// @param user The address that has been blacklisted.
    event Blacklisted(address indexed user);

    /// @notice Emitted when an address is removed from the blacklist.
    /// @param user The address that has been removed from the blacklist.
    event Whitelisted(address indexed user);

    /// @notice Checks if a token is enabled as a payment token in the registry.
    /// @param token The address of the token to check.
    /// @return True if the token is enabled, false otherwise.
    function paymentTokens(address token) external view returns (bool);

    /// @notice Retrieves the current fixed price escrow contract address stored in the registry.
    /// @return The address of the fixed price escrow contract.
    function escrowFixedPrice() external view returns (address);

    /// @notice Retrieves the current milestone escrow contract address stored in the registry.
    /// @return The address of the milestone escrow contract.
    function escrowMilestone() external view returns (address);

    /// @notice Retrieves the current hourly escrow contract address stored in the registry.
    /// @return The address of the hourly escrow contract.
    function escrowHourly() external view returns (address);

    /// @notice Retrieves the current factory contract address stored in the registry.
    /// @return The address of the factory contract.
    function factory() external view returns (address);

    /// @notice Retrieves the current feeManager contract address stored in the registry.
    /// @return The address of the feeManager contract.
    function feeManager() external view returns (address);

    /// @notice Retrieves the treasury address used for fixed-price escrow contracts.
    /// @dev Used to isolate funds collected from fixed-price contracts.
    /// @return The address of the fixed-price escrow treasury.
    function fixedTreasury() external view returns (address);

    /// @notice Retrieves the treasury address used for hourly escrow contracts.
    /// @dev Used to isolate funds collected from hourly-based contracts.
    /// @return The address of the hourly escrow treasury.
    function hourlyTreasury() external view returns (address);

    /// @notice Retrieves the treasury address used for milestone escrow contracts.
    /// @dev Used to isolate funds collected from milestone-based contracts.
    /// @return The address of the milestone escrow treasury.
    function milestoneTreasury() external view returns (address);

    /// @notice Retrieves the current account recovery address stored in the registry.
    /// @return The address of the account recovery contract.
    function accountRecovery() external view returns (address);

    /// @notice Retrieves the current admin manager address stored in the registry.
    /// @return The address of the admin manager contract.
    function adminManager() external view returns (address);

    /// @notice Checks if an address is blacklisted.
    /// @param user The address to check against the blacklist.
    /// @return bool True if the address is blacklisted, false otherwise.
    function blacklist(address user) external view returns (bool);

    /// @notice Updates the address of the fixed price escrow contract used in the system.
    /// @param newEscrowFixedPrice The new address of the fixed price escrow contract to be used across the platform.
    function updateEscrowFixedPrice(address newEscrowFixedPrice) external;

    /// @notice Updates the address of the milestone escrow contract used in the system.
    /// @param newEscrowMilestone The new address of the milestone escrow contract to be used.
    function updateEscrowMilestone(address newEscrowMilestone) external;

    /// @notice Updates the address of the hourly escrow contract used in the system.
    /// @param newEscrowHourly The new address of the hourly escrow contract to be used.
    function updateEscrowHourly(address newEscrowHourly) external;

    /// @notice Updates the address of the Factory contract used in the system.
    /// @dev This function allows the system administrator to set a new factory contract address.
    /// @param newFactory The new address of the Factory contract to be used across the platform.
    function updateFactory(address newFactory) external;
}
