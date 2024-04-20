// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Owned} from "./libs/Owned.sol";
import {Pausable} from "./libs/Pausable.sol";
import {LibClone} from "./libs/LibClone.sol";
import {IEscrowFactory} from "./interfaces/IEscrowFactory.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";
import {Escrow} from "./Escrow.sol";

/// @title Escrow Factory Contract
/// @dev This contract is used for creating new escrow contract instances using the clone factory pattern.
contract EscrowFactory is IEscrowFactory, Owned, Pausable {
    /// @notice Registry contract address storing escrow templates and configurations.
    IRegistry public registry;

    /// @notice Tracks the number of escrows deployed per deployer to generate unique salts for clones.
    mapping(address deployer => uint256 nonce) public factoryNonce;

    /// @notice Tracks the addresses of deployed escrow contracts.
    mapping(address escrow => bool deployed) public existingEscrow;

    /// @dev Sets the initial registry used for cloning escrow contracts.
    /// @param _registry Address of the registry contract.
    constructor(address _registry) Owned(msg.sender) {
        if (_registry == address(0)) {
            revert Factory__ZeroAddressProvided();
        }
        registry = IRegistry(_registry);
    }

    /// @notice Deploys a new escrow contract clone with unique settings for each project.
    /// @param _client The client's address who initiates the escrow, msg.sender.
    /// @param _admin The admin's address who has administrative privileges over the escrow.
    /// @param _registry Address of the registry contract to fetch escrow implementation.
    /// @param _feeClient Fee percentage to be paid by the client.
    /// @param _feeContractor Fee percentage to be paid by the contractor.
    /// @return deployedProxy The address of the newly deployed escrow proxy.
    /// @dev Clones the escrow template and initializes it with specific parameters for the project.
    function deployEscrow(
        address _client,
        address _admin,
        address _registry,
        uint256 _feeClient,
        uint256 _feeContractor
    ) external whenNotPaused returns (address deployedProxy) {
        bytes32 salt = keccak256(abi.encode(msg.sender, factoryNonce[msg.sender]));
        
        address escrowImplement = IRegistry(registry).escrow();

        address clone = LibClone.cloneDeterministic(escrowImplement, salt);

        Escrow(clone).initialize(_client, _admin, _registry, _feeClient, _feeContractor);

        deployedProxy = address(clone);

        existingEscrow[deployedProxy] = true;

        unchecked { factoryNonce[msg.sender]++; }

        emit EscrowProxyDeployed(msg.sender, deployedProxy);
    }

    /// @notice Updates the registry address used for fetching escrow implementations.
    /// @param _registry New registry address.
    function updateRegistry(address _registry) external onlyOwner {
        if (_registry == address(0)) revert Factory__ZeroAddressProvided();
        registry = IRegistry(_registry);
        emit RegistryUpdated(_registry);
    }

    /// @notice Pauses the contract, preventing new escrows from being deployed.
    function pause() public onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract, allowing new escrows to be deployed.
    function unpause() public onlyOwner {
        _unpause();
    }
}
