// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Interface for the Registry
/// @dev Interface for the registry that manages configuration settings such as payment tokens and contract addresses for an escrow system.
interface IRegistry {
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

    /// @notice Checks if a token is enabled as a payment token in the registry.
    /// @param token The address of the token to check.
    /// @return True if the token is enabled, false otherwise.
    function paymentTokens(address token) external view returns (bool);

    /// @notice Retrieves the current escrow contract address stored in the registry.
    /// @return The address of the escrow contract.
    function escrow() external view returns (address);

    /// @notice Retrieves the current factory contract address stored in the registry.
    /// @return The address of the factory contract.
    function factory() external view returns (address);
}