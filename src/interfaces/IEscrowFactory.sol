// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEscrow} from "./IEscrow.sol";

interface IEscrowFactory {
    error Factory__ZeroAddressProvided();

    event EscrowProxyDeployed(address sender, address deployedProxy);

    function existingEscrow(address escrow) external returns (bool);

    function deployEscrow(
        address client,
        address treasury,
        address admin,
        address registry,
        uint256 feeClient,
        uint256 feeContractor,
        IEscrow.Deposit calldata deposit
    ) external returns (address);
}