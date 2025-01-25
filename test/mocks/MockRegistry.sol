// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { OwnedThreeStep } from "@solbase/auth/OwnedThreeStep.sol";
import { IEscrowRegistry } from "src/interfaces/IEscrowRegistry.sol";

/// @title EscrowRegistry Contract
/// @dev This contract manages configuration settings for the escrow system including approved payment tokens.
contract MockRegistry is IEscrowRegistry, OwnedThreeStep {
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

    /// @notice Addresses of the treasury where fees and other payments are collected.
    address public fixedTreasury;
    address public hourlyTreasury;
    address public milestoneTreasury;

    /// @notice Address of the account recovery module contract.
    address public accountRecovery;

    /// @notice Address of the admin manager contract.
    address public adminManager;

    /// @notice Mapping of ERC20 token addresses that are enabled as payment options.
    /// @dev Includes the ability to enable the native chain token for payments.
    mapping(address token => bool enabled) public paymentTokens;

    /// @notice Checks if an address is blacklisted.
    /// @dev Stores addresses that are blacklisted from participating in transactions.
    mapping(address user => bool blacklisted) public blacklist;

    /// @dev Initializes the contract setting the owner to the message sender.
    /// @param _owner Address of the initial owner of the registry contract.
    constructor(address _owner) OwnedThreeStep(_owner) { }

    /// @notice Adds a new ERC20 token to the list of accepted payment tokens.
    /// @param _token The address of the ERC20 token to enable.
    function addPaymentToken(address _token) external onlyOwner {
        // if (_token == address(0)) revert ZeroAddressProvided();
        // if (paymentTokens[_token]) revert TokenAlreadyAdded();
        paymentTokens[_token] = true;
        emit PaymentTokenAdded(_token);
    }

    /// @notice Removes an ERC20 token from the list of accepted payment tokens.
    /// @param _token The address of the ERC20 token to disable.
    function removePaymentToken(address _token) external onlyOwner {
        // if (!paymentTokens[_token]) revert PaymentTokenNotRegistered();
        delete paymentTokens[_token];
        emit PaymentTokenRemoved(_token);
    }

    /// @notice Updates the address of the escrow fixed price contract.
    /// @param _escrowFixedPrice The new address of the EscrowFixedPrice contract to be used.
    function updateEscrowFixedPrice(address _escrowFixedPrice) external onlyOwner {
        // if (_escrowFixedPrice == address(0)) revert ZeroAddressProvided();
        escrowFixedPrice = _escrowFixedPrice;
        emit EscrowUpdated(_escrowFixedPrice);
    }

    /// @notice Updates the address of the escrow milestone contract.
    /// @param _escrowMilestone The new address of the EscrowMilestone contract to be used.
    function updateEscrowMilestone(address _escrowMilestone) external onlyOwner {
        // if (_escrowMilestone == address(0)) revert ZeroAddressProvided();
        escrowMilestone = _escrowMilestone;
        emit EscrowUpdated(_escrowMilestone);
    }

    /// @notice Updates the address of the escrow hourly contract.
    /// @param _escrowHourly The new address of the EscrowHourly contract to be used.
    function updateEscrowHourly(address _escrowHourly) external onlyOwner {
        // if (_escrowHourly == address(0)) revert ZeroAddressProvided();
        escrowHourly = _escrowHourly;
        emit EscrowUpdated(_escrowHourly);
    }

    /// @notice Updates the address of the factory contract.
    /// @param _factory The new address of the Factory contract to be used.
    function updateFactory(address _factory) external onlyOwner {
        // if (_factory == address(0)) revert ZeroAddressProvided();
        factory = _factory;
        emit FactoryUpdated(_factory);
    }

    /// @notice Updates the address of the fee manager contract.
    /// @param _feeManager The new address of the FeeManager contract to be used.
    function updateFeeManager(address _feeManager) external onlyOwner {
        // if (_feeManager == address(0)) revert ZeroAddressProvided();
        feeManager = _feeManager;
        emit FeeManagerUpdated(_feeManager);
    }

    /// @notice Sets the treasury address designated for fixed-price escrow contracts.
    /// @param _fixedTreasury The new address of the fixed-price escrow treasury.
    function setFixedTreasury(address _fixedTreasury) external onlyOwner {
        // if (_fixedTreasury == address(0)) revert ZeroAddressProvided();
        fixedTreasury = _fixedTreasury;
        emit TreasurySet(_fixedTreasury);
    }

    /// @notice Sets the treasury address designated for hourly escrow contracts.
    /// @param _hourlyTreasury The new address of the hourly escrow treasury.
    function setHourlyTreasury(address _hourlyTreasury) external onlyOwner {
        // if (_hourlyTreasury == address(0)) revert ZeroAddressProvided();
        hourlyTreasury = _hourlyTreasury;
        emit TreasurySet(_hourlyTreasury);
    }

    /// @notice Sets the treasury address designated for milestone escrow contracts.
    /// @param _milestoneTreasury The new address of the milestone escrow treasury.
    function setMilestoneTreasury(address _milestoneTreasury) external onlyOwner {
        // if (_milestoneTreasury == address(0)) revert ZeroAddressProvided();
        milestoneTreasury = _milestoneTreasury;
        emit TreasurySet(_milestoneTreasury);
    }

    /// @notice Updates the address of the account recovery module contract.
    /// @param _accountRecovery The new address of the AccountRecovery module contract to be used.
    function setAccountRecovery(address _accountRecovery) external onlyOwner {
        // if (_accountRecovery == address(0)) revert ZeroAddressProvided();
        accountRecovery = _accountRecovery;
        emit AccountRecoverySet(_accountRecovery);
    }

    /// @notice Updates the address of the admin manager contract.
    /// @param _adminManager The new address of the AdminManager contract to be used.
    function setAdminManager(address _adminManager) external onlyOwner {
        // if (_adminManager == address(0)) revert ZeroAddressProvided();
        adminManager = _adminManager;
        emit AdminManagerSet(_adminManager);
    }

    /// @notice Adds an address to the blacklist.
    /// @param _user The address to add to the blacklist.
    function addToBlacklist(address _user) external onlyOwner {
        // if (_user == address(0)) revert ZeroAddressProvided();
        blacklist[_user] = true;
        emit Blacklisted(_user);
    }

    /// @notice Removes an address from the blacklist.
    /// @param _user The address to remove from the blacklist.
    function removeFromBlacklist(address _user) external onlyOwner {
        // if (_user == address(0)) revert ZeroAddressProvided();
        blacklist[_user] = false;
        emit Whitelisted(_user);
    }
}
