// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEscrow} from "./interfaces/IEscrow.sol";
import {SafeTransferLib} from "src/libs/SafeTransferLib.sol";

contract Escrow is IEscrow {
    /// @notice The basis points used for calculating fees and percentages.
    uint256 public constant MAX_BPS = 100_00; // 100%

    address public client;
    address public treasury;
    address public admin;

    uint256 public feeClient;
    uint256 public feeContractor;
    uint256 private currentContractId;

    /// @dev Indicates that the contract has been initialized.
    bool public initialized;

    mapping(uint256 contractId => Deposit depositInfo) public deposits;

    struct Deposit {
        address contractor;
        address paymentToken; // TokenRegistery
        uint256 amount;
        uint256 amountToClaim;
        uint256 timeLock; // TODO TBC possible lock for delay of disput or smth
        bytes32 contractorData;
        FeeConfig feeConfig;
        Status status;
    }

    modifier onlyClient() {
        if (msg.sender != client) revert Escrow__UnauthorizedAccount(msg.sender);
        _;
    }

    function initialize(address _client, address _treasury, address _admin, uint256 _feeClient, uint256 _feeContractor)
        external
    {
        if (initialized) revert Escrow__AlreadyInitialized();

        if (_client == address(0) || _treasury == address(0) || _admin == address(0)) {
            revert Escrow__ZeroAddressProvided();
        }
        if (_feeClient > MAX_BPS || _feeContractor > MAX_BPS) revert Escrow__FeeTooHigh();

        client = _client;
        treasury = _treasury;
        admin = _admin;

        feeClient = _feeClient;
        feeContractor = _feeContractor;

        initialized = true;
    }

    function deposit(Deposit calldata _deposit) external onlyClient {
        // TODO add validation for payment token

        uint256 feeAmount = _computeFeeAmount(_deposit.amount, uint256(_deposit.feeConfig));

        SafeTransferLib.safeTransferFrom(_deposit.paymentToken, msg.sender, address(this), _deposit.amount);
        SafeTransferLib.safeTransferFrom(_deposit.paymentToken, msg.sender, treasury, feeAmount);

        unchecked {
            currentContractId++;
        }

        Deposit storage D = deposits[currentContractId];
        D.paymentToken = _deposit.paymentToken;
        D.amount = _deposit.amount;
        D.timeLock = _deposit.timeLock;
        D.contractorData = _deposit.contractorData;
        D.feeConfig = _deposit.feeConfig;
        D.status = Status.PENDING;

        emit Deposited(
            msg.sender, currentContractId, _deposit.paymentToken, _deposit.amount, _deposit.timeLock, _deposit.feeConfig
        );
    }


    function _computeFeeAmount(uint256 _amount, uint256 _feeConfig) internal view returns (uint256 feeAmount) {
        if (_feeConfig == uint256(FeeConfig.FULL)) {
            return feeAmount = (_amount * (feeClient + feeContractor)) / MAX_BPS;
        }
        return feeAmount = (_amount * feeClient) / MAX_BPS;
    }


    function _computeDepositAmount(uint256 _amount, uint256 _feeConfig) internal view returns (uint256) {
        if (_feeConfig == uint256(FeeConfig.FULL)) {
            return _amount + (_amount * (feeClient + feeContractor)) / MAX_BPS;
        }
        return _amount + ((_amount * feeClient) / MAX_BPS);
    }

    function computeDepositAmount(uint256 _amount, uint256 _feeConfig) external view returns (uint256) {
        return _computeDepositAmount(_amount, _feeConfig);
    }

    function getCurrentContractId() external view returns (uint256) {
        return currentContractId;
    }




}
