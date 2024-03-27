// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IEscrow {

    error Escrow__AlreadyInitialized();

    error Escrow__UnauthorizedAccount(address account);

    error Escrow__ZeroAddressProvided();

    error Escrow__FeeTooHigh();

    enum FeeConfig {
        FULL,
        ONLY_CLIENT,
        ONLY_CONTRACTOR,
        FREE
    }

    enum Status {
        PENDING,
        SUBMITTED,
        APPROVED
    }

}