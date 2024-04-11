// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRegistry} from "./interfaces/IRegistry.sol";
import {Owned} from "./libs/Owned.sol";

contract Registry is IRegistry, Owned {
    /// @dev The address interpreted as native token of the chain.
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public escrow;

    /// @notice Mapping of the enabled ERC20 token addresses as a payment token.
    /// @dev The NATIVE_TOKEN constant should be enabled for facilitating payments using the native token of the chain.
    mapping(address token => bool enabled) public paymentTokens;

    constructor() Owned(msg.sender) {}

    /// @notice Method for adding payment token.
    function addPaymentToken(address _token) external onlyOwner {
        if (_token == address(0)) revert Registry__ZeroAddressProvided();
        if (paymentTokens[_token]) revert Registry__TokenAlreadyAdded();
        paymentTokens[_token] = true;
        emit PaymentTokenAdded(_token);
    }

    /// @notice Method for removing payment token.
    function removePaymentToken(address _token) external onlyOwner {
        if (!paymentTokens[_token]) revert Registry__PaymentTokenNotRegistered();
        delete paymentTokens[_token];
        emit PaymentTokenRemoved(_token);
    }

    function setEscrowAddress(address _escrow) external onlyOwner {
        if (_escrow == address(0)) revert Registry__ZeroAddressProvided();
        escrow = _escrow;
        emit EscrowSet(_escrow);
    }
}