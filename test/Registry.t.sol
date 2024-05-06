// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {Registry, IRegistry} from "src/modules/Registry.sol";
import {Escrow, IEscrow} from "src/Escrow.sol";
import {EscrowFactory, Ownable} from "src/EscrowFactory.sol";
import {EscrowFeeManager} from "src/modules/EscrowFeeManager.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract RegistryUnitTest is Test {
    Escrow escrow;
    Registry registry;
    ERC20Mock paymentToken;
    ERC20Mock newPaymentToken;
    EscrowFactory factory;
    EscrowFeeManager feeManager;

    address owner;
    address treasury;

    event PaymentTokenAdded(address token);
    event PaymentTokenRemoved(address token);
    event OwnershipTransferred(address indexed user, address indexed newOwner);
    event EscrowUpdated(address escrow);
    event FactoryUpdated(address factory);
    event FeeManagerUpdated(address feeManager);
    event TreasurySet(address treasury);

    function setUp() public {
        owner = makeAddr("owner");
        treasury = makeAddr("treasury");
        escrow = new Escrow();
        registry = new Registry(owner);
        paymentToken = new ERC20Mock();
        newPaymentToken = new ERC20Mock();
        factory = new EscrowFactory(address(registry), owner);
        feeManager = new EscrowFeeManager(3_00, 5_00, owner);
    }

    function test_setUpState() public view {
        assertTrue(address(registry).code.length > 0);
        assertEq(registry.owner(), address(owner));
        assertEq(registry.NATIVE_TOKEN(), address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
    }

    function test_addPaymentToken() public {
        assertFalse(registry.paymentTokens(address(paymentToken)));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.addPaymentToken(address(paymentToken));
        assertFalse(registry.paymentTokens(address(paymentToken)));
        vm.startPrank(address(owner)); //current owner
        vm.expectRevert(IRegistry.Registry__ZeroAddressProvided.selector);
        registry.addPaymentToken(address(0));
        assertFalse(registry.paymentTokens(address(paymentToken)));
        vm.expectEmit(true, false, false, true);
        emit PaymentTokenAdded(address(paymentToken));
        registry.addPaymentToken(address(paymentToken));
        assertTrue(registry.paymentTokens(address(paymentToken)));
        vm.expectRevert(IRegistry.Registry__TokenAlreadyAdded.selector);
        registry.addPaymentToken(address(paymentToken));
        vm.stopPrank();
    }

    function test_removePaymentToken() public {
        test_addPaymentToken();
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.removePaymentToken(address(paymentToken));
        assertTrue(registry.paymentTokens(address(paymentToken)));
        vm.startPrank(address(owner)); //current owner
        vm.expectEmit(true, false, false, true);
        emit PaymentTokenRemoved(address(paymentToken));
        registry.removePaymentToken(address(paymentToken));
        assertFalse(registry.paymentTokens(address(paymentToken)));
        vm.expectRevert(IRegistry.Registry__PaymentTokenNotRegistered.selector);
        registry.removePaymentToken(address(newPaymentToken));
        vm.stopPrank();
    }

    function test_transferOwnership() public {
        assertEq(registry.owner(), address(owner));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.transferOwnership(notOwner);
        assertEq(registry.owner(), address(owner));
        address newOwner = makeAddr("newOwner");
        vm.startPrank(address(owner)); //current owner
        vm.expectRevert(Ownable.NewOwnerIsZeroAddress.selector);
        registry.transferOwnership(address(0));
        vm.expectEmit(true, false, false, true);
        emit OwnershipTransferred(address(owner), newOwner);
        registry.transferOwnership(newOwner);
        assertEq(registry.owner(), newOwner);
        vm.stopPrank();
    }

    function test_updateEscrow() public {
        assertEq(registry.escrow(), address(0));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.updateEscrow(address(escrow));
        vm.startPrank(address(owner));
        vm.expectRevert(IRegistry.Registry__ZeroAddressProvided.selector);
        registry.updateEscrow(address(0));
        assertEq(registry.escrow(), address(0));
        vm.expectEmit(true, false, false, true);
        emit EscrowUpdated(address(escrow));
        registry.updateEscrow(address(escrow));
        assertEq(registry.escrow(), address(escrow));
        vm.stopPrank();
    }

    function test_updateFactory() public {
        assertEq(registry.factory(), address(0));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.updateFactory(address(factory));
        vm.startPrank(address(owner));
        vm.expectRevert(IRegistry.Registry__ZeroAddressProvided.selector);
        registry.updateFactory(address(0));
        assertEq(registry.factory(), address(0));
        vm.expectEmit(true, false, false, true);
        emit FactoryUpdated(address(factory));
        registry.updateFactory(address(factory));
        assertEq(registry.factory(), address(factory));
        vm.stopPrank();
    }

    function test_setTreasury() public {
        assertEq(registry.treasury(), address(0));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.setTreasury(address(treasury));
        vm.startPrank(address(owner));
        vm.expectRevert(IRegistry.Registry__ZeroAddressProvided.selector);
        registry.setTreasury(address(0));
        assertEq(registry.treasury(), address(0));
        vm.expectEmit(true, false, false, true);
        emit TreasurySet(address(treasury));
        registry.setTreasury(address(treasury));
        assertEq(registry.treasury(), address(treasury));
        vm.stopPrank();
    }

    function test_updateFeeManager() public {
        assertEq(registry.feeManager(), address(0));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.updateFeeManager(address(feeManager));
        vm.startPrank(address(owner));
        vm.expectRevert(IRegistry.Registry__ZeroAddressProvided.selector);
        registry.updateFeeManager(address(0));
        assertEq(registry.feeManager(), address(0));
        vm.expectEmit(true, false, false, true);
        emit FeeManagerUpdated(address(feeManager));
        registry.updateFeeManager(address(feeManager));
        assertEq(registry.feeManager(), address(feeManager));
        vm.stopPrank();
    }
}
