// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEscrow} from "./IEscrow.sol";

/// @title Interface for the Escrow Factory
/// @dev Interface defining the functionality for an escrow factory, responsible for deploying new escrow contracts.
interface IEscrowFactory {
    /// @notice Thrown when an operation involves a zero address where a valid address is required.
    error Factory__ZeroAddressProvided();

    /// @notice Emitted when a new escrow proxy is successfully deployed.
    /// @param sender The address of the sender who initiated the escrow deployment.
    /// @param deployedProxy The address of the newly deployed escrow proxy.
    event EscrowProxyDeployed(address sender, address deployedProxy);

    /// @notice Emitted when the registry address is updated in the factory.
    /// @param registry The new registry address.
    event RegistryUpdated(address registry);

    /// @notice Checks if the given address is an escrow contract deployed by this factory.
    /// @param escrow The address of the escrow contract to check.
    /// @return True if the address is an existing deployed escrow contract, false otherwise.
    function existingEscrow(address escrow) external returns (bool);

    /// @notice Deploys a new escrow contract with specified parameters.
    /// @param client The address of the client for whom the escrow is being created.
    /// @param admin The address with administrative privileges over the new escrow.
    /// @param registry The address of the registry containing escrow configurations.
    /// @param feeClient The fee percentage to be paid by the client.
    /// @param feeContractor The fee percentage to be paid by the contractor.
    /// @return The address of the newly deployed escrow contract.
    function deployEscrow(
        address client,
        address admin,
        address registry,
        uint256 feeClient,
        uint256 feeContractor
    ) external returns (address);
}