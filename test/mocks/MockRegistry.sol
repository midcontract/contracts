// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRegistry} from "src/interfaces/IRegistry.sol";
import {Ownable} from "src/libs/Ownable.sol";

/// @title Registry Contract
/// @dev This contract manages configuration settings for the escrow system including approved payment tokens.
contract MockRegistry is IRegistry, Ownable {
    /// @notice Constant for the native token of the chain.
    /// @dev Used to represent the native blockchain currency in payment tokens mapping.
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Address of the Escrow contract currently in use.
    /// @dev This can be updated by the owner as new versions of the Escrow contract are deployed.
    address public escrow;

    /// @notice Address of the Factory contract currently in use.
    /// @dev This can be updated by the owner as new versions of the Factory contract are deployed.
    address public factory;

    /// @notice Address of the FeeManager contract currently in use.
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

    /// @notice Updates the address of the Escrow contract.
    /// @param _escrow The new address of the Escrow contract to be used.
    function updateEscrow(address _escrow) external onlyOwner {
        // if (_escrow == address(0)) revert Registry__ZeroAddressProvided();
        escrow = _escrow;
        emit EscrowUpdated(_escrow);
    }

    /// @notice Updates the address of the Factory contract.
    /// @param _factory The new address of the Factory contract to be used.
    function updateFactory(address _factory) external onlyOwner {
        // if (_factory == address(0)) revert Registry__ZeroAddressProvided();
        factory = _factory;
        emit FactoryUpdated(_factory);
    }

    /// @notice Updates the address of the FeeManager contract.
    /// @param _feeManager The new address of the FeeManager contract to be used.
    function updateFeeManager(address _feeManager) external onlyOwner {
        // if (_feeManager == address(0)) revert Registry__ZeroAddressProvided();
        feeManager = _feeManager;
        emit FeeManagerUpdated(_feeManager);
    }

    /// @notice Sets the treasury address where collected fees and other payments will be sent.
    /// @param _treasury New treasury address.
    /// @dev Reverts if a zero address is provided.
    function setTreasury(address _treasury) external onlyOwner {
        // if (_treasury == address(0)) revert Registry__ZeroAddressProvided();
        treasury = _treasury;
        emit TreasurySet(_treasury);
    }
}