// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {EscrowFactory} from "src/EscrowFactory.sol";
import {Escrow, IEscrow} from "src/Escrow.sol";
import {Registry, IRegistry} from "src/Registry.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract EscrowFactoryUnitTest is Test {
    EscrowFactory public factory;
    Escrow public escrow;
    Registry public registry;
    ERC20Mock public paymentToken;

    address public client;
    address public treasury;
    address public admin;
    address public contractor;

    Escrow.Deposit public deposit;
    FeeConfig public feeConfig;
    Status public status;

    bytes32 public contractorData;
    bytes32 public salt;
    bytes public contractData;

    struct Deposit {
        address contractor;
        address paymentToken;
        uint256 amount;
        uint256 amountToClaim;
        uint256 timeLock;
        bytes32 contractorData;
        FeeConfig feeConfig;
        Status status;
    }

    enum FeeConfig {
        FULL,
        ONLY_CLIENT,
        ONLY_CONTRACTOR,
        FREE
    }

    enum Status {
        PENDING,
        SUBMITTED,
        APPROVED
    }

    function setUp() public {
        client = makeAddr("client");
        treasury = makeAddr("treasury");
        admin = makeAddr("admin");
        contractor = makeAddr("contractor");
        escrow = new Escrow();
        registry = new Registry();
        paymentToken = new ERC20Mock();
        registry.addPaymentToken(address(paymentToken));

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        contractorData = keccak256(abi.encodePacked(contractData, salt));

        deposit = IEscrow.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 1 ether,
            amountToClaim: 0 ether,
            timeLock: 0,
            contractorData: contractorData,
            feeConfig: IEscrow.FeeConfig.FULL,
            status: IEscrow.Status.PENDING
        });

        factory = new EscrowFactory(address(registry));
    }

    function test_setUpState() public view {
        assertTrue(address(factory).code.length > 0);
        assertEq(factory.owner(), address(this));
        assertEq(address(factory.registry()), address(registry));
    }
}