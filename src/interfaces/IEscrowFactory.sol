// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Enums } from "../common/Enums.sol";

/// @title Interface for the Escrow Factory
/// @dev Interface defining the functionality for an escrow factory, responsible for deploying new escrow contracts.
interface IEscrowFactory {
    /// @notice Thrown when an unauthorized account attempts an action.
    error Factory__UnauthorizedAccount();
    /// @notice Thrown when an operation involves a zero address where a valid address is required.
    error Factory__ZeroAddressProvided();
    /// @notice Thrown when an invalid escrow type is used in operations requiring a specific escrow type.
    error Factory__InvalidEscrowType();
    /// @notice Thrown when an ETH transfer failed.
    error Factory__ETHTransferFailed();

    /// @notice Emitted when a new escrow proxy is successfully deployed.
    /// @param sender The address of the sender who initiated the escrow deployment.
    /// @param deployedProxy The address of the newly deployed escrow proxy.
    /// @param escrowType The type of escrow to deploy, which determines the template used for cloning.
    event EscrowProxyDeployed(address sender, address deployedProxy, Enums.EscrowType escrowType);

    /// @notice Emitted when the admin manager address is updated in the registry.
    /// @param adminManager The new admin manager contract address.
    event AdminManagerUpdated(address adminManager);

    /// @notice Emitted when the registry address is updated in the factory.
    /// @param registry The new registry address.
    event RegistryUpdated(address registry);

    /// @notice Emitted when ETH is successfully withdrawn from the contract.
    /// @param receiver The address that received the withdrawn ETH.
    /// @param amount The amount of ETH withdrawn from the contract.
    event ETHWithdrawn(address receiver, uint256 amount);

    /// @notice Checks if the given address is an escrow contract deployed by this factory.
    /// @param escrow The address of the escrow contract to check.
    /// @return True if the address is an existing deployed escrow contract, false otherwise.
    function existingEscrow(address escrow) external returns (bool);

    /// @notice Deploys a new escrow contract with specified parameters.
    /// @param escrowType The type of escrow to deploy, which determines the template used for cloning.
    /// @return The address of the newly deployed escrow contract.
    function deployEscrow(Enums.EscrowType escrowType) external returns (address);
}
