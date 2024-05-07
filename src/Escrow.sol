// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEscrow} from "./interfaces/IEscrow.sol";
import {IEscrowFeeManager} from "./interfaces/IEscrowFeeManager.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";
import {Enums} from "src/libs/Enums.sol";
import {Ownable} from "src/libs/Ownable.sol";
import {SafeTransferLib} from "src/libs/SafeTransferLib.sol";

import {console2} from "lib/forge-std/src/console2.sol";

contract Escrow is IEscrow, Ownable {
    IRegistry public registry;

    address public client;

    uint256 private currentContractId;

    /// @dev Indicates that the contract has been initialized.
    bool public initialized;

    mapping(uint256 contractId => Deposit depositInfo) public deposits;

    mapping(uint256 contractId => uint256 totalDepositAmount) public totalDeposited;

    modifier onlyClient() {
        if (msg.sender != client) revert Escrow__UnauthorizedAccount(msg.sender);
        _;
    }

    function initialize(address _client, address _owner, address _registry) external {
        if (initialized) revert Escrow__AlreadyInitialized();

        if (_client == address(0) || _owner == address(0) || _registry == address(0)) {
            revert Escrow__ZeroAddressProvided();
        }

        client = _client;
        registry = IRegistry(_registry);
        _initializeOwner(_owner);

        initialized = true;
    }

    function deposit(Deposit calldata _deposit) external onlyClient {
        if (!registry.paymentTokens(_deposit.paymentToken)) revert Escrow__NotSupportedPaymentToken();

        if (_deposit.amount == 0) revert Escrow__ZeroDepositAmount();

        (uint256 totalDepositAmount, uint256 feeApplied) =
            _computeDepositAmountAndFee(msg.sender, _deposit.amount, _deposit.feeConfig);

        SafeTransferLib.safeTransferFrom(_deposit.paymentToken, msg.sender, address(this), totalDepositAmount);

        unchecked {
            currentContractId++;
        }

        Deposit storage D = deposits[currentContractId];
        D.paymentToken = _deposit.paymentToken;
        D.amount = _deposit.amount;
        D.timeLock = _deposit.timeLock;
        D.contractorData = _deposit.contractorData;
        D.feeConfig = _deposit.feeConfig;
        D.status = Enums.Status.PENDING;

        emit Deposited(
            msg.sender, currentContractId, _deposit.paymentToken, _deposit.amount, _deposit.timeLock, _deposit.feeConfig
        );
    }

    function withdraw(uint256 _contractId) external onlyClient {
        Deposit storage D = deposits[_contractId];
        if (uint256(D.status) != uint256(Enums.Status.PENDING)) revert Escrow__InvalidStatusForWithdraw(); // TODO test

        (uint256 withdrawAmount, uint256 feeAmount) = _computeDepositAmountAndFee(msg.sender, D.amount, D.feeConfig);

        // TODO Update deposit amount
        D.amount = D.amount - (withdrawAmount - feeAmount);
       
        // allows to withdraw totalDepositAmount: depositAmount + feeAmmount
        SafeTransferLib.safeTransfer(D.paymentToken, msg.sender, withdrawAmount);

        // TODO TBC change status: D.status = Status.CANCELLED;

        emit Withdrawn(msg.sender, _contractId, D.paymentToken, withdrawAmount);
    }

    function submit(uint256 _contractId, bytes calldata _data, bytes32 _salt) external {
        Deposit storage D = deposits[_contractId];

        if (uint256(D.status) != uint256(Enums.Status.PENDING)) revert Escrow__InvalidStatusForSubmit(); // TODO test

        bytes32 contractorDataHash = _getContractorDataHash(_data, _salt);

        if (D.contractorData != contractorDataHash) revert Escrow__InvalidContractorDataHash(); // TODO check not zero

        D.contractor = msg.sender;
        D.status = Enums.Status.SUBMITTED;

        emit Submitted(msg.sender, _contractId);
    }

    function approve(uint256 _contractId, uint256 _amountApprove, uint256 _amountAdditional, address _receiver)
        external
        onlyClient
    {
        if (_amountApprove == 0 && _amountAdditional == 0) revert Escrow__InvalidAmount();

        Deposit storage D = deposits[_contractId];

        if (uint256(D.status) != uint256(Enums.Status.SUBMITTED)) revert Escrow__InvalidStatusForApprove();

        if (D.contractor != _receiver) revert Escrow__UnauthorizedReceiver();

        if (_amountAdditional > 0) {
            _refill(_contractId, _amountAdditional);
        }

        if (_amountApprove > 0) {
            D.status = Enums.Status.PENDING; // TODO TBC the correct status
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

        (uint256 totalAmountAdditional, uint256 feeApplied) =
            _computeDepositAmountAndFee(msg.sender, _amountAdditional, D.feeConfig);

        SafeTransferLib.safeTransferFrom(D.paymentToken, msg.sender, address(this), totalAmountAdditional);
        D.amount += _amountAdditional;
        emit Refilled(_contractId, _amountAdditional);
    }

    function claim(uint256 _contractId) external {
        Deposit storage D = deposits[_contractId];

        // TODO check the status

        if (D.contractor != msg.sender) revert Escrow__UnauthorizedAccount(msg.sender);

        if (D.amountToClaim == 0) revert Escrow__NotApproved();

        (uint256 claimAmount, uint256 feeAmount) =
            _computeClaimableAmountAndFee(msg.sender, D.amountToClaim, D.feeConfig);

        D.amount = D.amount - D.amountToClaim;
        D.amountToClaim = 0;

        SafeTransferLib.safeTransfer(D.paymentToken, msg.sender, claimAmount);
        if (feeAmount > 0) {
            // TODO test
            _sendPlatformFee(D.paymentToken, feeAmount);
        } else {
            // feeAmount = _computeCoverageFee(D.amountToClaim, uint256(D.feeConfig));
            // _sendPlatformFee(D.paymentToken, feeAmount);
        }

        // if (D.amount == 0) D.status = Status.COMPLETED; TBC

        emit Claimed(msg.sender, _contractId, D.paymentToken, claimAmount); //+depositAmount
    }

    function _computeDepositAmountAndFee(address _client, uint256 _depositAmount, Enums.FeeConfig _feeConfig)
        internal
        returns (uint256 totalDepositAmount, uint256 feeApplied)
    {
        address feeManagerAddress = registry.feeManager();
        if (feeManagerAddress == address(0)) revert Escrow__NotSetFeeManager();
        IEscrowFeeManager feeManager = IEscrowFeeManager(feeManagerAddress); // Cast to the interface

        (uint256 totalDepositAmount, uint256 feeApplied) =
            feeManager.computeDepositAmountAndFee(_client, _depositAmount, _feeConfig);

        return (totalDepositAmount, feeApplied);
    }

    function _computeClaimableAmountAndFee(address _contractor, uint256 _claimedAmount, Enums.FeeConfig _feeConfig)
        internal
        returns (uint256 claimableAmount, uint256 feeDeducted)
    {
        address feeManagerAddress = registry.feeManager();
        if (feeManagerAddress == address(0)) revert Escrow__NotSetFeeManager();
        IEscrowFeeManager feeManager = IEscrowFeeManager(feeManagerAddress); // Cast to the interface

        (uint256 claimableAmount, uint256 feeDeducted) =
            feeManager.computeClaimableAmountAndFee(_contractor, _claimedAmount, _feeConfig);

        return (claimableAmount, feeDeducted);
    }

    function _sendPlatformFee(address _paymentToken, uint256 _feeAmount) internal {
        address treasury = IRegistry(registry).treasury();
        if (treasury == address(0)) revert Escrow__ZeroAddressProvided(); // TODO test
        SafeTransferLib.safeTransfer(_paymentToken, treasury, _feeAmount);
    }

    function _getContractorDataHash(bytes calldata _data, bytes32 _salt) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_data, _salt));
    }

    function getContractorDataHash(bytes calldata _data, bytes32 _salt) external pure returns (bytes32) {
        return _getContractorDataHash(_data, _salt);
    }

    function getCurrentContractId() external view returns (uint256) {
        return currentContractId;
    }

    /// @notice Updates the registry address used for fetching escrow implementations.
    /// @param _registry New registry address.
    function updateRegistry(address _registry) external onlyOwner {
        if (_registry == address(0)) revert Escrow__ZeroAddressProvided();
        registry = IRegistry(_registry);
        emit RegistryUpdated(_registry);
    }
}
