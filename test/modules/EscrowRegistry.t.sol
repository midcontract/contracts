// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test, console2 } from "forge-std/Test.sol";

import { EscrowRegistry, IEscrowRegistry, OwnedThreeStep } from "src/modules/EscrowRegistry.sol";
import { EscrowAdminManager, OwnedRoles } from "src/modules/EscrowAdminManager.sol";
import { EscrowFixedPrice, IEscrowFixedPrice } from "src/EscrowFixedPrice.sol";
import { EscrowFactory } from "src/EscrowFactory.sol";
import { EscrowFeeManager } from "src/modules/EscrowFeeManager.sol";
import { ERC20Mock } from "@openzeppelin/mocks/token/ERC20Mock.sol";
import { MockFailingReceiver } from "test/mocks/MockFailingReceiver.sol";

contract EscrowRegistryUnitTest is Test {
    EscrowFixedPrice escrow;
    EscrowRegistry registry;
    ERC20Mock paymentToken;
    ERC20Mock newPaymentToken;
    EscrowFactory factory;
    EscrowFeeManager feeManager;
    EscrowAdminManager adminManager;

    address owner;
    address accountRecovery;
    address fixedTreasury;
    address hourlyTreasury;
    address milestoneTreasury;

    event PaymentTokenAdded(address token);
    event PaymentTokenRemoved(address token);
    event OwnerUpdateInitiated(address indexed user, address indexed ownerCandidate);
    event OwnershipTransferred(address indexed user, address indexed newOwner);
    event EscrowUpdated(address escrow);
    event FactoryUpdated(address factory);
    event FeeManagerUpdated(address feeManager);
    event TreasurySet(address treasury);
    event AccountRecoverySet(address accountRecovery);
    event AdminManagerSet(address adminManager);
    event Blacklisted(address indexed user);
    event Whitelisted(address indexed user);
    event ETHWithdrawn(address receiver, uint256 amount);

    function setUp() public {
        owner = makeAddr("owner");
        fixedTreasury = makeAddr("fixedTreasury");
        hourlyTreasury = makeAddr("hourlyTreasury");
        milestoneTreasury = makeAddr("milestoneTreasury");
        accountRecovery = makeAddr("accountRecovery");
        adminManager = new EscrowAdminManager(owner);
        escrow = new EscrowFixedPrice();
        registry = new EscrowRegistry(owner);
        paymentToken = new ERC20Mock();
        newPaymentToken = new ERC20Mock();
        factory = new EscrowFactory(address(adminManager), address(registry), owner);
        feeManager = new EscrowFeeManager(address(adminManager), 300, 500);
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
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        registry.addPaymentToken(address(paymentToken));
        assertFalse(registry.paymentTokens(address(paymentToken)));
        vm.startPrank(address(owner)); //current owner
        vm.expectRevert(IEscrowRegistry.ZeroAddressProvided.selector);
        registry.addPaymentToken(address(0));
        assertFalse(registry.paymentTokens(address(paymentToken)));
        vm.expectEmit(true, false, false, true);
        emit PaymentTokenAdded(address(paymentToken));
        registry.addPaymentToken(address(paymentToken));
        assertTrue(registry.paymentTokens(address(paymentToken)));
        vm.expectRevert(IEscrowRegistry.TokenAlreadyAdded.selector);
        registry.addPaymentToken(address(paymentToken));
        vm.stopPrank();
    }

    function test_removePaymentToken() public {
        test_addPaymentToken();
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        registry.removePaymentToken(address(paymentToken));
        assertTrue(registry.paymentTokens(address(paymentToken)));
        vm.startPrank(address(owner)); //current owner
        vm.expectEmit(true, false, false, true);
        emit PaymentTokenRemoved(address(paymentToken));
        registry.removePaymentToken(address(paymentToken));
        assertFalse(registry.paymentTokens(address(paymentToken)));
        vm.expectRevert(IEscrowRegistry.PaymentTokenNotRegistered.selector);
        registry.removePaymentToken(address(newPaymentToken));
        vm.stopPrank();
    }

    function test_transferOwnership() public {
        // Ensure the initial owner is correctly set
        assertEq(registry.owner(), address(owner));

        // Create addresses for notOwner and newOwner
        address notOwner = makeAddr("notOwner");
        address newOwner = makeAddr("newOwner");

        // Try to transfer ownership from an unauthorized address (should revert)
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        registry.transferOwnership(notOwner);

        // Try to confirm ownership from the foundation before initiating (should revert)
        vm.prank(owner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        registry.confirmOwner();

        // Initiate ownership transfer from the foundation
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit OwnerUpdateInitiated(owner, newOwner);
        registry.transferOwnership(newOwner);

        // Try to confirm ownership from a non-candidate address (should revert)
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        registry.confirmOwner();

        // Confirm ownership transfer from the new owner (first step)
        vm.prank(newOwner);
        registry.confirmOwner();

        // Try to confirm ownership from the new owner again (should revert as it's not confirmed by owner yet)
        vm.prank(newOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        registry.confirmOwner();

        // Confirm ownership transfer from the owner (second step)
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(owner, newOwner);
        registry.confirmOwner();

        // Ensure the new owner is correctly set
        assertEq(registry.owner(), newOwner);

        // Ensure renounce ownership functionality works
        vm.prank(newOwner);
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(newOwner, address(0));
        registry.renounceOwner();

        // Ensure ownership is now renounced
        assertEq(registry.owner(), address(0));
    }

    function test_updateEscrowFixedPrice() public {
        assertEq(registry.escrowFixedPrice(), address(0));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        registry.updateEscrowFixedPrice(address(escrow));
        vm.startPrank(address(owner));
        vm.expectRevert(IEscrowRegistry.ZeroAddressProvided.selector);
        registry.updateEscrowFixedPrice(address(0));
        assertEq(registry.escrowFixedPrice(), address(0));
        vm.expectEmit(true, false, false, true);
        emit EscrowUpdated(address(escrow));
        registry.updateEscrowFixedPrice(address(escrow));
        assertEq(registry.escrowFixedPrice(), address(escrow));
        vm.stopPrank();
    }

    function test_updateEscrowMilestone() public {
        assertEq(registry.escrowMilestone(), address(0));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        registry.updateEscrowMilestone(address(escrow));
        vm.startPrank(address(owner));
        vm.expectRevert(IEscrowRegistry.ZeroAddressProvided.selector);
        registry.updateEscrowMilestone(address(0));
        assertEq(registry.escrowMilestone(), address(0));
        vm.expectEmit(true, false, false, true);
        emit EscrowUpdated(address(escrow));
        registry.updateEscrowMilestone(address(escrow));
        assertEq(registry.escrowMilestone(), address(escrow));
        vm.stopPrank();
    }

    function test_updateEscrowHourly() public {
        assertEq(registry.escrowHourly(), address(0));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        registry.updateEscrowHourly(address(escrow));
        vm.startPrank(address(owner));
        vm.expectRevert(IEscrowRegistry.ZeroAddressProvided.selector);
        registry.updateEscrowHourly(address(0));
        assertEq(registry.escrowHourly(), address(0));
        vm.expectEmit(true, false, false, true);
        emit EscrowUpdated(address(escrow));
        registry.updateEscrowHourly(address(escrow));
        assertEq(registry.escrowHourly(), address(escrow));
        vm.stopPrank();
    }

    function test_updateFactory() public {
        assertEq(registry.factory(), address(0));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        registry.updateFactory(address(factory));
        vm.startPrank(address(owner));
        vm.expectRevert(IEscrowRegistry.ZeroAddressProvided.selector);
        registry.updateFactory(address(0));
        assertEq(registry.factory(), address(0));
        vm.expectEmit(true, false, false, true);
        emit FactoryUpdated(address(factory));
        registry.updateFactory(address(factory));
        assertEq(registry.factory(), address(factory));
        vm.stopPrank();
    }

    function test_setFixedTreasury() public {
        assertEq(registry.fixedTreasury(), address(0));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        registry.setFixedTreasury(address(fixedTreasury));
        vm.startPrank(address(owner));
        vm.expectRevert(IEscrowRegistry.ZeroAddressProvided.selector);
        registry.setFixedTreasury(address(0));
        assertEq(registry.fixedTreasury(), address(0));
        vm.expectEmit(true, false, false, true);
        emit TreasurySet(address(fixedTreasury));
        registry.setFixedTreasury(address(fixedTreasury));
        assertEq(registry.fixedTreasury(), address(fixedTreasury));
        vm.stopPrank();
    }

    function test_setHourlyTreasury() public {
        assertEq(registry.hourlyTreasury(), address(0));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        registry.setHourlyTreasury(address(hourlyTreasury));
        vm.startPrank(address(owner));
        vm.expectRevert(IEscrowRegistry.ZeroAddressProvided.selector);
        registry.setHourlyTreasury(address(0));
        assertEq(registry.hourlyTreasury(), address(0));
        vm.expectEmit(true, false, false, true);
        emit TreasurySet(address(hourlyTreasury));
        registry.setHourlyTreasury(address(hourlyTreasury));
        assertEq(registry.hourlyTreasury(), address(hourlyTreasury));
        vm.stopPrank();
    }

    function test_setMilestoneTreasury() public {
        assertEq(registry.milestoneTreasury(), address(0));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        registry.setMilestoneTreasury(address(milestoneTreasury));
        vm.startPrank(address(owner));
        vm.expectRevert(IEscrowRegistry.ZeroAddressProvided.selector);
        registry.setMilestoneTreasury(address(0));
        assertEq(registry.milestoneTreasury(), address(0));
        vm.expectEmit(true, false, false, true);
        emit TreasurySet(address(milestoneTreasury));
        registry.setMilestoneTreasury(address(milestoneTreasury));
        assertEq(registry.milestoneTreasury(), address(milestoneTreasury));
        vm.stopPrank();
    }

    function test_updateFeeManager() public {
        assertEq(registry.feeManager(), address(0));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        registry.updateFeeManager(address(feeManager));
        vm.startPrank(address(owner));
        vm.expectRevert(IEscrowRegistry.ZeroAddressProvided.selector);
        registry.updateFeeManager(address(0));
        assertEq(registry.feeManager(), address(0));
        vm.expectEmit(true, false, false, true);
        emit FeeManagerUpdated(address(feeManager));
        registry.updateFeeManager(address(feeManager));
        assertEq(registry.feeManager(), address(feeManager));
        vm.stopPrank();
    }

    function test_setAccountRecovery() public {
        assertEq(registry.accountRecovery(), address(0));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        registry.setAccountRecovery(address(accountRecovery));
        vm.startPrank(address(owner));
        vm.expectRevert(IEscrowRegistry.ZeroAddressProvided.selector);
        registry.setAccountRecovery(address(0));
        assertEq(registry.accountRecovery(), address(0));
        vm.expectEmit(true, false, false, true);
        emit AccountRecoverySet(accountRecovery);
        registry.setAccountRecovery(address(accountRecovery));
        assertEq(registry.accountRecovery(), address(accountRecovery));
        vm.stopPrank();
    }

    function test_setAdminManager() public {
        assertEq(registry.adminManager(), address(0));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        registry.setAdminManager(address(adminManager));
        vm.startPrank(address(owner));
        vm.expectRevert(IEscrowRegistry.ZeroAddressProvided.selector);
        registry.setAdminManager(address(0));
        assertEq(registry.adminManager(), address(0));
        vm.expectEmit(true, false, false, true);
        emit AdminManagerSet(address(adminManager));
        registry.setAdminManager(address(adminManager));
        assertEq(registry.adminManager(), address(adminManager));
        vm.stopPrank();
    }

    function test_addToBlacklist() public {
        address malicious_user = makeAddr("malicious_user");
        assertFalse(registry.blacklist(malicious_user));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        registry.addToBlacklist(owner);
        assertFalse(registry.blacklist(owner));
        vm.startPrank(address(owner));
        vm.expectRevert(IEscrowRegistry.ZeroAddressProvided.selector);
        registry.addToBlacklist(address(0));
        vm.expectEmit(true, false, false, true);
        emit Blacklisted(malicious_user);
        registry.addToBlacklist(malicious_user);
        assertTrue(registry.blacklist(malicious_user));
        vm.stopPrank();
    }

    function test_removeFromBlacklist() public {
        address malicious_user = makeAddr("malicious_user");
        vm.prank(owner);
        registry.addToBlacklist(malicious_user);
        assertTrue(registry.blacklist(malicious_user));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        registry.removeFromBlacklist(malicious_user);
        vm.startPrank(address(owner));
        vm.expectRevert(IEscrowRegistry.ZeroAddressProvided.selector);
        registry.removeFromBlacklist(address(0));
        vm.expectEmit(true, false, false, true);
        emit Whitelisted(malicious_user);
        registry.removeFromBlacklist(malicious_user);
        assertFalse(registry.blacklist(malicious_user));
        vm.stopPrank();
    }

    function test_withdraw_eth() public {
        vm.deal(address(registry), 10 ether);
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        registry.withdrawETH(notOwner);
        vm.startPrank(owner);
        vm.expectRevert(IEscrowRegistry.ZeroAddressProvided.selector);
        registry.withdrawETH(address(0));
        vm.expectEmit(true, false, false, true);
        emit ETHWithdrawn(owner, 10 ether);
        registry.withdrawETH(owner);
        assertEq(owner.balance, 10 ether, "Receiver did not receive the correct amount of ETH");
        assertEq(address(registry).balance, 0, "Registry contract balance should be zero");
        vm.deal(address(registry), 10 ether);
        MockFailingReceiver failingReceiver = new MockFailingReceiver();
        vm.expectRevert(IEscrowRegistry.ETHTransferFailed.selector);
        registry.withdrawETH(address(failingReceiver));
        vm.stopPrank();
    }
}
