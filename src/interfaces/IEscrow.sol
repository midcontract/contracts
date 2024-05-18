// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Enums} from "src/libs/Enums.sol";

interface IEscrow {
    error Escrow__AlreadyInitialized();

    error Escrow__UnauthorizedAccount(address account);

    error Escrow__ZeroAddressProvided();

    error Escrow__FeeTooHigh();

    error Escrow__InvalidStatusToWithdraw();

    error Escrow__InvalidStatusForSubmit();

    error Escrow__InvalidContractorDataHash();

    error Escrow__InvalidStatusForApprove();

    error Escrow__NotEnoughDeposit();

    error Escrow__UnauthorizedReceiver();

    error Escrow__InvalidAmount();

    error Escrow__NotApproved();

    error Escrow__NotSupportedPaymentToken();

    error Escrow__ZeroDepositAmount();

    error Escrow__InvalidFeeConfig();

    error Escrow__NotSetFeeManager();

    struct Deposit {
        address contractor;
        address paymentToken;
        uint256 amount;
        uint256 amountToClaim;
        uint256 timeLock; // TODO TBC possible lock for delay of disput or smth
        bytes32 contractorData;
        Enums.FeeConfig feeConfig;
        Enums.Status status;
    }

    event Deposited(
        address indexed sender,
        uint256 indexed contractId,
        address indexed paymentToken,
        uint256 amount,
        uint256 timeLock,
        Enums.FeeConfig feeConfig
    );

    event Withdrawn(address indexed sender, uint256 indexed contractId, address indexed paymentToken, uint256 amount);

    event Submitted(address indexed sender, uint256 indexed contractId);

    event Approved(uint256 indexed contractId, uint256 indexed amountApprove, address indexed receiver);

    event Refilled(uint256 indexed contractId, uint256 indexed amountAdditional);

    event Claimed(address indexed sender, uint256 indexed contractId, address indexed paymentToken, uint256 amount);

    /// @notice Emitted when the registry address is updated in the escrow.
    /// @param registry The new registry address.
    event RegistryUpdated(address registry);
}
