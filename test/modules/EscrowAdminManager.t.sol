// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test, console2 } from "forge-std/Test.sol";

import { EscrowAdminManager, IEscrowAdminManager, OwnedRoles } from "src/modules/EscrowAdminManager.sol";
import { MockFailingReceiver } from "test/mocks/MockFailingReceiver.sol";

contract EscrowAdminManagerUnitTest is Test {
    EscrowAdminManager adminManager;
    address admin;
    address guardian;
    address initialOwner;
    address pendingOwner;
    address randomUser;
    address newAdmin;
    address notOwner;

    event RolesUpdated(address indexed user, uint256 indexed roles);
    event ETHWithdrawn(address receiver, uint256 amount);

    function setUp() public {
        admin = makeAddr("admin");
        guardian = makeAddr("guardian");
        newAdmin = makeAddr("newAdmin");
        notOwner = makeAddr("notOwner");
        randomUser = makeAddr("randomUser");
        pendingOwner = makeAddr("pendingOwner");
        initialOwner = makeAddr("initialOwner");
        adminManager = new EscrowAdminManager(initialOwner);
    }

    function test_setUpState() public view {
        assertTrue(address(adminManager).code.length > 0);
        assertEq(adminManager.owner(), initialOwner);
        assertTrue(adminManager.hasAnyRole(initialOwner, 2));
        assertTrue(adminManager.isAdmin(initialOwner));
        assertFalse(adminManager.isGuardian(initialOwner));
        assertFalse(adminManager.isStrategist(initialOwner));
    }

    function test_addAmin() public {
        assertFalse(adminManager.isAdmin(notOwner));
        vm.prank(notOwner);
        vm.expectRevert(OwnedRoles.Unauthorized.selector);
        adminManager.addAdmin(notOwner);
        assertFalse(adminManager.isAdmin(notOwner));
        assertFalse(adminManager.isAdmin(newAdmin));
        vm.prank(initialOwner);
        vm.expectEmit(true, true, true, true);
        emit RolesUpdated(newAdmin, 2);
        adminManager.addAdmin(newAdmin);
        assertTrue(adminManager.isAdmin(newAdmin));
    }

    function test_removeAdmin() public {
        test_addAmin();
        assertTrue(adminManager.isAdmin(newAdmin));
        vm.prank(notOwner);
        vm.expectRevert(OwnedRoles.Unauthorized.selector);
        adminManager.removeAdmin(newAdmin);
        assertTrue(adminManager.isAdmin(newAdmin));
        vm.prank(initialOwner);
        vm.expectEmit(true, true, true, true);
        emit RolesUpdated(newAdmin, 0);
        adminManager.removeAdmin(newAdmin);
        assertFalse(adminManager.isAdmin(newAdmin));
    }

    function test_addGuardian() public {
        assertFalse(adminManager.isGuardian(notOwner));
        vm.prank(notOwner);
        vm.expectRevert(OwnedRoles.Unauthorized.selector);
        adminManager.addGuardian(notOwner);
        assertFalse(adminManager.isGuardian(notOwner));
        assertFalse(adminManager.isGuardian(newAdmin));
        vm.prank(initialOwner);
        vm.expectEmit(true, true, true, true);
        emit RolesUpdated(newAdmin, 4);
        adminManager.addGuardian(newAdmin);
        assertTrue(adminManager.isGuardian(newAdmin));
    }

    function test_removeGuardian() public {
        test_addGuardian();
        assertTrue(adminManager.isGuardian(newAdmin));
        vm.prank(notOwner);
        vm.expectRevert(OwnedRoles.Unauthorized.selector);
        adminManager.removeGuardian(newAdmin);
        assertTrue(adminManager.isGuardian(newAdmin));
        vm.prank(initialOwner);
        vm.expectEmit(true, true, true, true);
        emit RolesUpdated(newAdmin, 0);
        adminManager.removeGuardian(newAdmin);
        assertFalse(adminManager.isGuardian(newAdmin));
    }

    function test_addStrategist() public {
        assertFalse(adminManager.isStrategist(notOwner));
        vm.prank(notOwner);
        vm.expectRevert(OwnedRoles.Unauthorized.selector);
        adminManager.addStrategist(notOwner);
        assertFalse(adminManager.isStrategist(notOwner));
        assertFalse(adminManager.isStrategist(newAdmin));
        vm.prank(initialOwner);
        vm.expectEmit(true, true, true, true);
        emit RolesUpdated(newAdmin, 8);
        adminManager.addStrategist(newAdmin);
        assertTrue(adminManager.isStrategist(newAdmin));
    }

    function test_removeStrategist() public {
        test_addStrategist();
        assertTrue(adminManager.isStrategist(newAdmin));
        vm.prank(notOwner);
        vm.expectRevert(OwnedRoles.Unauthorized.selector);
        adminManager.removeStrategist(newAdmin);
        assertTrue(adminManager.isStrategist(newAdmin));
        vm.prank(initialOwner);
        vm.expectEmit(true, true, true, true);
        emit RolesUpdated(newAdmin, 0);
        adminManager.removeStrategist(newAdmin);
        assertFalse(adminManager.isStrategist(newAdmin));
    }

    function test_addDaoAccount() public {
        assertFalse(adminManager.isDao(notOwner));
        vm.prank(notOwner);
        vm.expectRevert(OwnedRoles.Unauthorized.selector);
        adminManager.addDaoAccount(notOwner);
        assertFalse(adminManager.isDao(notOwner));
        assertFalse(adminManager.isDao(newAdmin));
        vm.prank(initialOwner);
        vm.expectEmit(true, true, true, true);
        emit RolesUpdated(newAdmin, 16);
        adminManager.addDaoAccount(newAdmin);
        assertTrue(adminManager.isDao(newAdmin));
    }

    function test_removeDaoAccount() public {
        test_addDaoAccount();
        assertTrue(adminManager.isDao(newAdmin));
        vm.prank(notOwner);
        vm.expectRevert(OwnedRoles.Unauthorized.selector);
        adminManager.removeStrategist(newAdmin);
        assertTrue(adminManager.isDao(newAdmin));
        vm.prank(initialOwner);
        vm.expectEmit(true, true, true, true);
        emit RolesUpdated(newAdmin, 0);
        adminManager.removeDaoAccount(newAdmin);
        assertFalse(adminManager.isDao(newAdmin));
    }

    function test_transferOwnership() public {
        address newOwner = makeAddr("newOwner");
        assertNotEq(adminManager.owner(), newOwner);
        assertEq(adminManager.owner(), initialOwner);

        vm.prank(randomUser);
        vm.expectRevert(OwnedRoles.Unauthorized.selector);
        adminManager.transferOwnership(randomUser);

        vm.prank(initialOwner);
        adminManager.transferOwnership(newOwner);
        assertEq(adminManager.owner(), newOwner);
        assertNotEq(adminManager.owner(), initialOwner);
    }

    function test_completeOwnershipHandover() public {
        vm.prank(randomUser);
        adminManager.requestOwnershipHandover();

        vm.prank(randomUser);
        vm.expectRevert(OwnedRoles.Unauthorized.selector);
        adminManager.completeOwnershipHandover(pendingOwner);

        vm.prank(initialOwner);
        adminManager.cancelOwnershipHandover();

        vm.prank(initialOwner);
        vm.expectRevert(OwnedRoles.NoHandoverRequest.selector);
        adminManager.completeOwnershipHandover(pendingOwner);

        assertNotEq(adminManager.owner(), pendingOwner);

        vm.prank(pendingOwner);
        adminManager.requestOwnershipHandover();

        vm.warp(block.timestamp + 172_801); // Fast forward time to simulate handover period

        vm.prank(initialOwner);
        vm.expectRevert(OwnedRoles.NoHandoverRequest.selector);
        adminManager.completeOwnershipHandover(pendingOwner);

        vm.prank(pendingOwner);
        adminManager.requestOwnershipHandover();

        skip(1 days);
        vm.prank(initialOwner);
        adminManager.completeOwnershipHandover(pendingOwner);
        assertEq(adminManager.owner(), pendingOwner);
        assertNotEq(adminManager.owner(), initialOwner);
    }

    function test_withdraw_eth() public {
        vm.deal(address(adminManager), 10 ether);
        vm.prank(notOwner);
        vm.expectRevert(OwnedRoles.Unauthorized.selector);
        adminManager.withdrawETH(notOwner);
        vm.startPrank(initialOwner);
        vm.expectRevert(IEscrowAdminManager.ZeroAddressProvided.selector);
        adminManager.withdrawETH(address(0));
        vm.expectEmit(true, false, false, true);
        emit ETHWithdrawn(initialOwner, 10 ether);
        adminManager.withdrawETH(initialOwner);
        assertEq(initialOwner.balance, 10 ether, "Receiver did not receive the correct amount of ETH");
        assertEq(address(adminManager).balance, 0, "AdminManager contract balance should be zero");
        vm.deal(address(adminManager), 10 ether);
        MockFailingReceiver failingReceiver = new MockFailingReceiver();
        vm.expectRevert(IEscrowAdminManager.ETHTransferFailed.selector);
        adminManager.withdrawETH(address(failingReceiver));
        vm.stopPrank();
    }
}
