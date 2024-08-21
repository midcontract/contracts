// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {OwnedThreeStep} from "@solbase/auth/OwnedThreeStep.sol";

import {EscrowFixedPrice} from "./EscrowFixedPrice.sol";
import {IEscrowFactory} from "./interfaces/IEscrowFactory.sol";
import {IEscrowRegistry} from "./interfaces/IEscrowRegistry.sol";
import {Enums} from "./libs/Enums.sol";
import {LibClone} from "./libs/LibClone.sol";
import {Pausable} from "./libs/Pausable.sol";

/// @title EscrowFixedPrice Factory Contract
/// @dev This contract is used for creating new escrow contract instances using the clone factory pattern.
contract EscrowFactory is IEscrowFactory, OwnedThreeStep, Pausable {
    /// @notice EscrowRegistry contract address storing escrow templates and configurations.
    IEscrowRegistry public registry;

    /// @notice Tracks the number of escrows deployed per deployer to generate unique salts for clones.
    mapping(address deployer => uint256 nonce) public factoryNonce;

    /// @notice Tracks the addresses of deployed escrow contracts.
    mapping(address escrow => bool deployed) public existingEscrow;

    /// @dev Sets the initial registry used for cloning escrow contracts.
    /// @param _registry Address of the registry contract.
    /// @param _owner Address of the initial owner of the factory contract.
    constructor(address _registry, address _owner) OwnedThreeStep(_owner) {
        if (_registry == address(0)) {
            revert Factory__ZeroAddressProvided();
        }
        registry = IEscrowRegistry(_registry);
    }

    /// @notice Deploys a new escrow contract clone with unique settings for each project.
    /// @param _escrowType The type of escrow to deploy, which determines the template used for cloning.
    /// @param _client The client's address who initiates the escrow, msg.sender.
    /// @param _owner The owner's address who has administrative privileges over the escrow.
    /// @param _registry Address of the registry contract to fetch escrow implementation.
    /// @return deployedProxy The address of the newly deployed escrow proxy.
    /// @dev This function clones the specified escrow template and initializes it with specific parameters for the project.
    /// It uses the clone factory pattern for deployment to minimize gas costs and manage multiple escrow contract versions.
    function deployEscrow(Enums.EscrowType _escrowType, address _client, address _owner, address _registry)
        external
        whenNotPaused
        returns (address deployedProxy)
    {
        address escrowImplement = _getEscrowImplementation(_escrowType);

        bytes32 salt = keccak256(abi.encode(msg.sender, factoryNonce[msg.sender]));
        address clone = LibClone.cloneDeterministic(escrowImplement, salt);
        EscrowFixedPrice(clone).initialize(_client, _owner, _registry); // TODO or IEscrowCommon.initialize

        deployedProxy = address(clone);
        existingEscrow[deployedProxy] = true;

        unchecked {
            factoryNonce[msg.sender]++;
        }

        emit EscrowProxyDeployed(msg.sender, deployedProxy, _escrowType);
    }

    /// @notice Fetches the appropriate escrow contract implementation address from the registry based on the escrow type.
    /// @param _escrowType The type of escrow contract (FixedPrice, Milestone, or Hourly).
    /// @return escrowImpl The address of the escrow implementation.
    /// @dev This internal helper function queries the registry to obtain the correct implementation address for cloning.
    function _getEscrowImplementation(Enums.EscrowType _escrowType) internal view returns (address escrowImpl) {
        if (_escrowType == Enums.EscrowType.FIXED_PRICE) {
            return IEscrowRegistry(registry).escrowFixedPrice();
        } else if (_escrowType == Enums.EscrowType.MILESTONE) {
            return IEscrowRegistry(registry).escrowMilestone();
        } else if (_escrowType == Enums.EscrowType.HOURLY) {
            return IEscrowRegistry(registry).escrowHourly();
        }
    }

    /// @notice Updates the registry address used for fetching escrow implementations.
    /// @param _registry New registry address.
    function updateRegistry(address _registry) external onlyOwner {
        if (_registry == address(0)) revert Factory__ZeroAddressProvided();
        registry = IEscrowRegistry(_registry);
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
