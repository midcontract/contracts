// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Owned} from "./libs/Owned.sol";
import {LibClone} from "./libs/LibClone.sol";
import {IEscrowFactory} from "./interfaces/IEscrowFactory.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";
import {Escrow} from "./Escrow.sol";
import {IEscrow} from "./interfaces/IEscrow.sol";

contract EscrowFactory is IEscrowFactory, Owned {
    IRegistry public registry;

    uint256 private factoryNonce;

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
        uint256 _feeContractor,
        IEscrow.Deposit calldata _deposit
    ) external returns (address deployedProxy) {
        bytes32 salt = keccak256(abi.encode(msg.sender, _deposit, factoryNonce));
        
        address escrowImplement = IRegistry(registry).escrow();

        address clone = LibClone.cloneDeterministic(escrowImplement, salt);

        Escrow(clone).initialize(_client, _treasury, _admin, _registry, _feeClient, _feeContractor);

        Escrow(clone).deposit(_deposit);

        deployedProxy = address(clone);

        existingEscrow[deployedProxy] = true;

        unchecked { factoryNonce++; }

        emit EscrowProxyDeployed(msg.sender, deployedProxy);
    }
}
