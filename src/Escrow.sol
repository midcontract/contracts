// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEscrow} from "./interfaces/IEscrow.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";
import {SafeTransferLib} from "src/libs/SafeTransferLib.sol";

import {console2} from "lib/forge-std/src/console2.sol";

contract Escrow is IEscrow {
    /// @notice The basis points used for calculating fees and percentages.
    uint256 public constant MAX_BPS = 100_00; // 100%

    IRegistry public registry;

    address public client;
    address public admin;

    uint256 public feeClient;
    uint256 public feeContractor;
    uint256 private currentContractId;

    /// @dev Indicates that the contract has been initialized.
    bool public initialized;

    mapping(uint256 contractId => Deposit depositInfo) public deposits;

    modifier onlyClient() {
        if (msg.sender != client) revert Escrow__UnauthorizedAccount(msg.sender);
        _;
    }

    function initialize(
        address _client,
        address _admin,
        address _registry,
        uint256 _feeClient,
        uint256 _feeContractor
    ) external {
        if (initialized) revert Escrow__AlreadyInitialized();

        if (_client == address(0) || _admin == address(0) || _registry == address(0)) {
            revert Escrow__ZeroAddressProvided();
        }
        if (_feeClient > MAX_BPS || _feeContractor > MAX_BPS) revert Escrow__FeeTooHigh();

        client = _client;
        admin = _admin;
        registry = IRegistry(_registry);

        feeClient = _feeClient;
        feeContractor = _feeContractor;

        initialized = true;
    }

    function deposit(Deposit calldata _deposit) external onlyClient {
        if (!registry.paymentTokens(_deposit.paymentToken)) revert Escrow__NotSupportedPaymentToken();

        uint256 depositAmount = _computeDepositAmount(_deposit.amount, uint256(_deposit.feeConfig));

        if (depositAmount == 0) revert Escrow__ZeroDepositAmount();

        SafeTransferLib.safeTransferFrom(_deposit.paymentToken, msg.sender, address(this), depositAmount);

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

    function withdraw(uint256 _contractId) external onlyClient {
        Deposit storage D = deposits[_contractId];
        if (uint256(D.status) != uint256(Status.PENDING)) revert Escrow__InvalidStatusForWithdraw(); // TODO test

        uint256 feeAmount;
        uint256 withdrawAmount;

        // console2.log("D.amount ", D.amount);

        // TODO TBC if withdrawAmount is full D.feeConfig, when fee is gonna pay
        if (uint256(D.feeConfig) == uint256(FeeConfig.FULL)) {
            feeAmount = D.amount * (feeClient + feeContractor) / MAX_BPS;
            withdrawAmount = D.amount - feeAmount;
        } else {
            feeAmount = D.amount * feeClient / MAX_BPS;
            withdrawAmount = D.amount - feeAmount;
        }

        // console2.log("feeAmount, withdrawAmount ", feeAmount, withdrawAmount);

        // TODO Update deposit amount
        D.amount = D.amount - (withdrawAmount + feeAmount);

        // TODO TBC change status

        SafeTransferLib.safeTransfer(D.paymentToken, msg.sender, withdrawAmount);
        if (feeAmount > 0) { // TODO test
            _sendPlatformFee(D.paymentToken, feeAmount);
        }

        emit Withdrawn(msg.sender, _contractId, D.paymentToken, withdrawAmount);
    }

    function submit(uint256 _contractId, bytes calldata _data, bytes32 _salt) external {
        Deposit storage D = deposits[_contractId];

        if (uint256(D.status) != uint256(Status.PENDING)) revert Escrow__InvalidStatusForSubmit(); // TODO test

        bytes32 contractorDataHash = _getContractorDataHash(_data, _salt);

        if (D.contractorData != contractorDataHash) revert Escrow__InvalidContractorDataHash();

        D.contractor = msg.sender;
        D.status = Status.SUBMITTED;

        emit Submitted(msg.sender, _contractId);
    }

    function approve(uint256 _contractId, uint256 _amountApprove, uint256 _amountAdditional, address _receiver)
        external
        onlyClient
    {
        if (_amountApprove == 0 && _amountAdditional == 0) revert Escrow__InvalidAmount();

        Deposit storage D = deposits[_contractId];

        if (uint256(D.status) != uint256(Status.SUBMITTED)) revert Escrow__InvalidStatusForApprove();

        if (D.contractor != _receiver) revert Escrow__UnauthorizedReceiver();

        if (_amountAdditional > 0) {
            _refill(_contractId, _amountAdditional);
        }

        if (_amountApprove > 0) {
            D.status = Status.PENDING; // TODO TBC the correct status
            if (D.amount >= (D.amountToClaim + _amountAdditional)) {
                D.amountToClaim += _amountApprove;
                emit Approved(_contractId, _amountApprove, _receiver);
            } else {
                revert Escrow__NotEnoughDeposit(); // TODO test
            }
        }
    }

    function _refill(uint256 _contractId, uint256 _amountAdditional) internal {
        Deposit storage D = deposits[_contractId];

        uint256 refillAmount = _computeDepositAmount(_amountAdditional, uint256(D.feeConfig));
        SafeTransferLib.safeTransferFrom(D.paymentToken, msg.sender, address(this), refillAmount);
        D.amount += _amountAdditional;
        emit Refilled(_contractId, _amountAdditional);
    }

    function claim(uint256 _contractId) external {
        Deposit storage D = deposits[_contractId];

        // TODO check the status

        if (D.contractor != msg.sender) revert Escrow__UnauthorizedAccount(msg.sender);

        if (D.amountToClaim == 0) revert Escrow__NotApproved();

        (uint256 claimAmount, uint256 feeAmount) = _computeClaimAmount(D.amountToClaim, uint256(D.feeConfig));

        D.amount = D.amount - D.amountToClaim;
        D.amountToClaim = 0;

        SafeTransferLib.safeTransfer(D.paymentToken, msg.sender, claimAmount);
        if (feeAmount > 0) {  // TODO test
            _sendPlatformFee(D.paymentToken, feeAmount);
        }

        // if (D.amount == 0) D.status = Status.COMPLETED; TBC

        emit Claimed(msg.sender, _contractId, D.paymentToken, claimAmount); //+depositAmount
    }

    function _computeClaimAmount(uint256 _amount, uint256 _feeConfig)
        internal
        view
        returns (uint256 claimAmount, uint256 feeAmount)
    {
        if (_feeConfig == uint256(FeeConfig.FULL)) {
            claimAmount = _amount;
            feeAmount = 0;
            return (claimAmount, feeAmount);
        }
        feeAmount = (_amount * feeContractor) / MAX_BPS;
        claimAmount = _amount - feeAmount; // TODO return claimAmount & feeAmount

        return (claimAmount, feeAmount);
    }

    function _getContractorDataHash(bytes calldata _data, bytes32 _salt) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_data, _salt));
    }

    function _computeFeeAmount(uint256 _amount, uint256 _feeConfig) internal view returns (uint256 feeAmount) {
        if (_feeConfig == uint256(FeeConfig.FULL)) {
            return feeAmount = (_amount * (feeClient + feeContractor)) / MAX_BPS;
        } else if (_feeConfig == uint256(FeeConfig.FREE)) {
            return feeAmount = 0;
        }
        return feeAmount = (_amount * feeClient) / MAX_BPS;
    }

    function _computeDepositAmount(uint256 _amount, uint256 _feeConfig) internal view returns (uint256) {
        // TODO tests
        if (_feeConfig == uint256(FeeConfig.FULL)) {
            return _amount + (_amount * (feeClient + feeContractor)) / MAX_BPS;
        } else if (_feeConfig == uint256(FeeConfig.ONLY_CLIENT)) {
            return _amount + ((_amount * feeClient) / MAX_BPS);
        } else if (_feeConfig == uint256(FeeConfig.ONLY_CONTRACTOR)) {
            return _amount + ((_amount * feeContractor) / MAX_BPS);
        } else if (_feeConfig == uint256(FeeConfig.FREE)) {
            return _amount;
        } else {
            revert Escrow__InvalidFeeConfig();
        }
    }

    function _sendPlatformFee(address _paymentToken, uint256 _feeAmount) internal {
        address treasury = IRegistry(registry).treasury();
        if (treasury == address(0)) revert Escrow__ZeroAddressProvided();  // TODO test
        SafeTransferLib.safeTransfer(_paymentToken, treasury, _feeAmount);
    }

    function getContractorDataHash(bytes calldata _data, bytes32 _salt) external pure returns (bytes32) {
        return _getContractorDataHash(_data, _salt);
    }

    function computeDepositAmount(uint256 _amount, uint256 _feeConfig) external view returns (uint256) {
        return _computeDepositAmount(_amount, _feeConfig);
    }

    function getCurrentContractId() external view returns (uint256) {
        return currentContractId;
    }
}
