// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {Registry, IRegistry} from "src/Registry.sol";
import {Owned} from "src/libs/Owned.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract RegistryUnitTest is Test {
    Registry public registry;
    ERC20Mock public paymentToken;
    ERC20Mock public newPaymentToken;

    event PaymentTokenAdded(address token);
    event PaymentTokenRemoved(address token);
    event OwnershipTransferred(address indexed user, address indexed newOwner);

    function setUp() public {
        registry = new Registry();
        paymentToken = new ERC20Mock();
        newPaymentToken = new ERC20Mock();
    }

    function test_setUpState() public view {
        assertTrue(address(registry).code.length > 0);
        assertEq(registry.owner(), address(this));
        assertEq(registry.NATIVE_TOKEN(), address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
    }

    function test_addPaymentToken() public {
        assertFalse(registry.paymentTokens(address(paymentToken)));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(Owned.Owned__Unauthorized.selector);
        registry.addPaymentToken(address(paymentToken));
        assertFalse(registry.paymentTokens(address(paymentToken)));
        vm.startPrank(address(this)); //current owner
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
        vm.expectRevert(Owned.Owned__Unauthorized.selector);
        registry.removePaymentToken(address(paymentToken));
        assertTrue(registry.paymentTokens(address(paymentToken)));
        vm.startPrank(address(this)); //current owner
        vm.expectEmit(true, false, false, true);
        emit PaymentTokenRemoved(address(paymentToken));
        registry.removePaymentToken(address(paymentToken));
        assertFalse(registry.paymentTokens(address(paymentToken)));
        vm.expectRevert(IRegistry.Registry__PaymentTokenNotRegistered.selector);
        registry.removePaymentToken(address(newPaymentToken));
        vm.stopPrank();
    }

    function test_transferOwnership() public {
        assertEq(registry.owner(), address(this));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(Owned.Owned__Unauthorized.selector);
        registry.transferOwnership(notOwner);
        assertEq(registry.owner(), address(this));
        address newOwner = makeAddr("newOwner");
        vm.startPrank(address(this)); //current owner
        vm.expectRevert(Owned.Owned__ZeroAddressProvided.selector);
        registry.transferOwnership(address(0));
        vm.expectEmit(true, false, false, true);
        emit OwnershipTransferred(address(this), newOwner);
        registry.transferOwnership(newOwner);
        assertEq(registry.owner(), newOwner);
        vm.stopPrank();
    }
}