// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {EscrowFeeManager, IEscrowFeeManager, Owned} from "src/modules/EscrowFeeManager.sol";

contract EscrowFeeManagerUnitTest is Test {
    EscrowFeeManager feeManager;

    address client;
    address contractor;

    struct FeeRates {
        uint16 coverage; // Coverage fee percentage
        uint16 claim; // Claim fee percentage
    }

    event DefaultFeesSet(uint256 coverage, uint256 claim);
    event SpecialFeesSet(address user, uint256 coverage, uint256 claim);

    function setUp() public {
        client = makeAddr("client");
        contractor = makeAddr("contractor");
        feeManager = new EscrowFeeManager(3_00, 5_00);
    }

    function test_setUpState() public view {
        assertTrue(address(feeManager).code.length > 0);
        assertEq(feeManager.owner(), address(this));
        (uint16 coverage, uint16 claim) = feeManager.defaultFees();
        assertEq(coverage, 3_00);
        assertEq(claim, 5_00);
    }

    function test_updateDefaultFees() public {
        (uint16 coverage, uint16 claim) = feeManager.defaultFees();
        assertEq(coverage, 3_00);
        assertEq(claim, 5_00);
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(Owned.Owned__Unauthorized.selector);
        feeManager.updateDefaultFees(0, 10_00);
        vm.startPrank(address(this)); //current owner
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.updateDefaultFees(101_00, 10_00);
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.updateDefaultFees(10_00, 101_00);
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.updateDefaultFees(101_00, 101_00);
        (coverage, claim) = feeManager.defaultFees();
        assertEq(coverage, 3_00);
        assertEq(claim, 5_00);
        vm.expectEmit(true, true, true, true);
        emit DefaultFeesSet(2_00, 4_00);
        feeManager.updateDefaultFees(2_00, 4_00);
        (coverage, claim) = feeManager.defaultFees();
        assertEq(coverage, 2_00);
        assertEq(claim, 4_00);
    }

    function test_setSpecialFees() public {
        (uint16 coverage, uint16 claim) = feeManager.specialFees(client);
        assertEq(coverage, 0);
        assertEq(claim, 0);
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(Owned.Owned__Unauthorized.selector);
        feeManager.setSpecialFees(client, 2_00, 3_50);
        vm.startPrank(address(this)); //current owner
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setSpecialFees(client, 101_00, 3_50);
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setSpecialFees(client, 3_50, 101_00);
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setSpecialFees(client, 101_00, 101_00);
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__ZeroAddressProvided.selector);
        feeManager.setSpecialFees(address(0), 2_00, 3_50);
        (coverage, claim) = feeManager.specialFees(client);
        assertEq(coverage, 0);
        assertEq(claim, 0);
        vm.expectEmit(true, true, true, true);
        emit SpecialFeesSet(client, 2_00, 3_50);
        feeManager.setSpecialFees(client, 2_00, 3_50);
        (coverage, claim) = feeManager.specialFees(client);
        assertEq(coverage, 2_00);
        assertEq(claim, 3_50);
    }

    function test_getCoverageFee() public {
        assertEq(feeManager.getCoverageFee(client), 3_00);
        assertEq(feeManager.getClaimFee(client), 5_00);
        test_setSpecialFees();
        assertEq(feeManager.getCoverageFee(client), 2_00);
        assertEq(feeManager.getClaimFee(client), 3_50);
    }
}
