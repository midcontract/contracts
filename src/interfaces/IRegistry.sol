// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRegistry {
    error Registry__ZeroAddressProvided();
    error Registry__TokenAlreadyAdded();
    error Registry__PaymentTokenNotRegistered();

    event PaymentTokenAdded(address token);
    event PaymentTokenRemoved(address token);
}