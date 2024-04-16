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

    event EscrowUpdated(address escrow);

    event FactoryUpdated(address factory);

    // Functions
    function paymentTokens(address token) external view returns (bool);

    function escrow() external view returns (address);

    function factory() external view returns (address);
}