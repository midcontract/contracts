// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEscrowRegistry} from "src/interfaces/IEscrowRegistry.sol";
import {Ownable} from "src/libs/Ownable.sol";

/// @title EscrowRegistry Contract
/// @dev This contract manages configuration settings for the escrow system including approved payment tokens.
contract MockRegistry is IEscrowRegistry, Ownable {
    /// @notice Constant for the native token of the chain.
    /// @dev Used to represent the native blockchain currency in payment tokens mapping.
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Address of the escrow fixed price contract currently in use.
    address public escrowFixedPrice;

    /// @notice Address of the escrow milestone contract currently in use.
    address public escrowMilestone;

    /// @notice Address of the escrow hourly contract currently in use.
    address public escrowHourly;

    /// @notice Address of the factory contract currently in use.
    /// @dev This can be updated by the owner as new versions of the Factory contract are deployed.
    address public factory;

    /// @notice Address of the fee manager contract currently in use.
    /// @dev This can be updated by the owner as new versions of the FeeManager contract are deployed.
    address public feeManager;

    /// @notice Address of the treasury where fees and other payments are collected.
    address public treasury;

    /// @notice Mapping of ERC20 token addresses that are enabled as payment options.
    /// @dev Includes the ability to enable the native chain token for payments.
    mapping(address token => bool enabled) public paymentTokens;

    /// @dev Initializes the contract setting the owner to the message sender.
    constructor(address _owner) {
        _initializeOwner(_owner);
    }

    /// @notice Adds a new ERC20 token to the list of accepted payment tokens.
    /// @param _token The address of the ERC20 token to enable.
    function addPaymentToken(address _token) external onlyOwner {
        // if (_token == address(0)) revert Registry__ZeroAddressProvided();
        // if (paymentTokens[_token]) revert Registry__TokenAlreadyAdded();
        paymentTokens[_token] = true;
        emit PaymentTokenAdded(_token);
    }

    /// @notice Removes an ERC20 token from the list of accepted payment tokens.
    /// @param _token The address of the ERC20 token to disable.
    function removePaymentToken(address _token) external onlyOwner {
        // if (!paymentTokens[_token]) revert Registry__PaymentTokenNotRegistered();
        delete paymentTokens[_token];
        emit PaymentTokenRemoved(_token);
    }

    /// @notice Updates the address of the escrow fixed price contract.
    /// @param _escrowFixedPrice The new address of the EscrowFixedPrice contract to be used.
    function updateEscrowFixedPrice(address _escrowFixedPrice) external onlyOwner {
        // if (_escrowFixedPrice == address(0)) revert Registry__ZeroAddressProvided();
        escrowFixedPrice = _escrowFixedPrice;
        emit EscrowUpdated(_escrowFixedPrice);
    }

    /// @notice Updates the address of the escrow milestone contract.
    /// @param _escrowMilestone The new address of the EscrowMilestone contract to be used.
    function updateEscrowMilestone(address _escrowMilestone) external onlyOwner {
        // if (_escrowMilestone == address(0)) revert Registry__ZeroAddressProvided();
        escrowMilestone = _escrowMilestone;
        emit EscrowUpdated(_escrowMilestone);
    }

    /// @notice Updates the address of the escrow hourly contract.
    /// @param _escrowHourly The new address of the EscrowHourly contract to be used.
    function updateEscrowHourly(address _escrowHourly) external onlyOwner {
        // if (_escrowHourly == address(0)) revert Registry__ZeroAddressProvided();
        escrowHourly = _escrowHourly;
        emit EscrowUpdated(_escrowHourly);
    }

    /// @notice Updates the address of the factory contract.
    /// @param _factory The new address of the Factory contract to be used.
    function updateFactory(address _factory) external onlyOwner {
        // if (_factory == address(0)) revert Registry__ZeroAddressProvided();
        factory = _factory;
        emit FactoryUpdated(_factory);
    }

    /// @notice Updates the address of the fee manager contract.
    /// @param _feeManager The new address of the FeeManager contract to be used.
    function updateFeeManager(address _feeManager) external onlyOwner {
        // if (_feeManager == address(0)) revert Registry__ZeroAddressProvided();
        feeManager = _feeManager;
        emit FeeManagerUpdated(_feeManager);
    }

    /// @notice Sets the treasury address where collected fees and other payments will be sent.
    /// @param _treasury New treasury address.
    function setTreasury(address _treasury) external onlyOwner {
        // if (_treasury == address(0)) revert Registry__ZeroAddressProvided();
        treasury = _treasury;
        emit TreasurySet(_treasury);
    }
}
