// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEscrow} from "./interfaces/IEscrow.sol";

contract Escrow is IEscrow {
    /// @notice The basis points used for calculating fees and percentages.
    uint256 public constant MAX_BPS = 100_00; // 100%

    address public client;
    address public treasury;
    address public admin;

    uint256 public feeClient;
    uint256 public feeContractor;
    uint256 public nextContractId;

    /// @dev Indicates that the contract has been initialized.
    bool public initialized;

    mapping(uint256 contractId => Deposit depositInfo) public deposits;

    struct Deposit {
        address contractor;
        address paymentToken; // TokenRegistery
        uint256 amount;
        uint256 amountToClaim;
        uint256 timeLock; // possible lock for delay of disput or smth
        bytes32 contractorData;
        FeeConfig feeConfig;
        Status status;
    }

    modifier onlyClient() {
        if (msg.sender != client) revert Escrow__UnauthorizedAccount(msg.sender);
        _;
    }

    function initialize(
        address _client,
        address _treasury,
        address _admin,
        uint256 _feeClient,
        uint256 _feeContractor
    ) external {
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
        
        unchecked {
            nextContractId++;
        }

        Deposit storage D = deposits[nextContractId];
        D.paymentToken = _deposit.paymentToken;
        D.amount = _deposit.amount;
        D.timeLock = _deposit.timeLock;
        D.contractorData = _deposit.contractorData;
        D.feeConfig = _deposit.feeConfig;
        D.status = Status.PENDING;

        // emit Deposited()
    }
}
