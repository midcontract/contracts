// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {Escrow, IEscrow} from "src/Escrow.sol";

contract EscrowUnitTest is Test {
    Escrow escrow;

    address client;
    address treasury;
    address admin;

    function setUp() public {
        client = makeAddr("client");
        treasury = makeAddr("treasury");
        admin = makeAddr("admin");
        escrow = new Escrow();
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
        assertEq(escrow.nextContractId(), 0);
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

}