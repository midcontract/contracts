// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRegistry {
    // Custom errors
    error Registry__ZeroAddressProvided();

    error Registry__TokenAlreadyAdded();

    error Registry__PaymentTokenNotRegistered();

    // Events
    event PaymentTokenAdded(address token);

    event PaymentTokenRemoved(address token);

    // Functions
    function paymentTokens(address token) external view returns (bool);
}