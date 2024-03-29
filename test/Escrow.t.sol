// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {Escrow, IEscrow} from "src/Escrow.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract EscrowUnitTest is Test {
    Escrow escrow;
    ERC20Mock paymentToken;

    address client;
    address treasury;
    address admin;

    Escrow.Deposit deposit;
    FeeConfig feeConfig;
    Status status;

    bytes32 contractorData;

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

    event Deposited(
        uint256 indexed contractId,
        address indexed sender,
        address indexed paymentToken,
        uint256 amount,
        uint256 timeLock,
        FeeConfig feeConfig
    );

    function setUp() public {
        client = makeAddr("client");
        treasury = makeAddr("treasury");
        admin = makeAddr("admin");
        escrow = new Escrow();
        paymentToken = new ERC20Mock();

        deposit = Escrow.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 1 ether,
            amountToClaim: 0 ether,
            timeLock: 0,
            contractorData: contractorData,
            feeConfig: IEscrow.FeeConfig.FULL,
            status: IEscrow.Status.PENDING
        });
    }

    function test_setUpState() public view {
        assertTrue(address(escrow).code.length > 0);
    }

    function test_initialize() public {
        assertFalse(escrow.initialized());
        escrow.initialize(client, treasury, admin, 3_00, 8_00);
        assertEq(escrow.client(), client);
        assertEq(escrow.treasury(), treasury);
        assertEq(escrow.admin(), admin);
        assertEq(escrow.feeClient(), 3_00);
        assertEq(escrow.feeContractor(), 8_00);
        assertEq(escrow.getCurrentContractId(), 0);
        assertTrue(escrow.initialized());
    }

    function test_Revert_initialize() public {
        assertFalse(escrow.initialized());
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.initialize(address(0), treasury, admin, 3_00, 8_00);
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.initialize(client, address(0), admin, 3_00, 8_00);
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.initialize(client, treasury, address(0), 3_00, 8_00);
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.initialize(address(0), address(0), address(0), 3_00, 8_00);
        vm.expectRevert(IEscrow.Escrow__FeeTooHigh.selector);
        escrow.initialize(client, treasury, admin, 101_00, 8_00);
        vm.expectRevert(IEscrow.Escrow__FeeTooHigh.selector);
        escrow.initialize(client, treasury, admin, 3_00, 101_00);
        vm.expectRevert(IEscrow.Escrow__FeeTooHigh.selector);
        escrow.initialize(client, treasury, admin, 101_00, 101_00);
        escrow.initialize(client, treasury, admin, 3_00, 8_00);
        assertTrue(escrow.initialized());
        vm.expectRevert(IEscrow.Escrow__AlreadyInitialized.selector);
        escrow.initialize(client, treasury, admin, 3_00, 8_00);
    }

    function test_deposit() public {
        test_initialize();
        vm.startPrank(address(client));
        paymentToken.mint(address(client), 1.11 ether);
        paymentToken.approve(address(escrow), 1.11 ether);
        vm.expectEmit(true, true, true, true);
        emit Deposited(1, address(client), address(paymentToken), 1.11 ether, 0, FeeConfig.FULL);
        escrow.deposit(deposit);
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        assertEq(paymentToken.balanceOf(address(escrow)), 1.11 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (
            address _contractor,
            address _paymentToken,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _timeLock,
            bytes32 _contractorData,
            IEscrow.FeeConfig _feeConfig,
            IEscrow.Status _status
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_timeLock, 0);
        assertEq(_contractorData, bytes32(0));
        assertEq(uint256(_feeConfig), 0); //IEscrow.FeeConfig.FULL
        assertEq(uint256(_status), 0); //Status.PENDING
    }

    function test_Revert_deposit() public {
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        vm.prank(client);
        escrow.deposit(deposit);
        test_initialize();
        address notClient = makeAddr("notClient");
        vm.prank(notClient);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.deposit(deposit);
    }
}
