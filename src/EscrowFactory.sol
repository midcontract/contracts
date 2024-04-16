// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Owned} from "./libs/Owned.sol";
import {Pausable} from "./libs/Pausable.sol";
import {LibClone} from "./libs/LibClone.sol";
import {IEscrowFactory} from "./interfaces/IEscrowFactory.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";
import {Escrow} from "./Escrow.sol";

contract EscrowFactory is IEscrowFactory, Owned, Pausable {
    IRegistry public registry;

    mapping(address deployer => uint256 nonce) public factoryNonce;

    mapping(address escrow => bool deployed) public existingEscrow;

    constructor(address _registry) Owned(msg.sender) {
        if (_registry == address(0)) {
            revert Factory__ZeroAddressProvided();
        }
        registry = IRegistry(_registry);
    }

    function deployEscrow(
        address _client, //msg.sender
        address _treasury,
        address _admin,
        address _registry,
        uint256 _feeClient,
        uint256 _feeContractor
    ) external whenNotPaused returns (address deployedProxy) {
        bytes32 salt = keccak256(abi.encode(msg.sender, factoryNonce[msg.sender]));
        
        address escrowImplement = IRegistry(registry).escrow();

        address clone = LibClone.cloneDeterministic(escrowImplement, salt);

        Escrow(clone).initialize(_client, _treasury, _admin, _registry, _feeClient, _feeContractor);

        deployedProxy = address(clone);

        existingEscrow[deployedProxy] = true;

        unchecked { factoryNonce[msg.sender]++; }

        emit EscrowProxyDeployed(msg.sender, deployedProxy);
    }

    function updateRegistry(address _registry) external onlyOwner {
        if (_registry == address(0)) revert Factory__ZeroAddressProvided();
        registry = IRegistry(_registry);
        emit RegistryUpdated(_registry);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
