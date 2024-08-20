// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";

import {EscrowAdminManager, OwnedRoles} from "src/modules/EscrowAdminManager.sol";

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

    function setUp() public {
        admin = makeAddr("admin");
        guardian = makeAddr("guardian");
        newAdmin = makeAddr("newAdmin");
        notOwner = makeAddr("notOwner");
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
}
