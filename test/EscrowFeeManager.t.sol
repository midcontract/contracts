// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {EscrowFeeManager, IEscrowFeeManager, Owned} from "src/EscrowFeeManager.sol";

contract EscrowFeeManagerUnitTest is Test {
    EscrowFeeManager feeManager;

    address client;
    address contractor;

    uint256 defaultCoverageFee;
    uint256 defaultClaimFee;

    event DefaultFeesSet(uint256 coverageFee, uint256 claimFee);
    event SpecialFeesSet(address user, uint256 coverageFee, uint256 claimFee);

    function setUp() public {
        client = makeAddr("client");
        contractor = makeAddr("contractor");
        feeManager = new EscrowFeeManager(3_00, 5_00);
    }

    function test_setUpState() public view {
        assertTrue(address(feeManager).code.length > 0);
        assertEq(feeManager.owner(), address(this));
        assertEq(feeManager.defaultCoverageFee(), 3_00);
        assertEq(feeManager.defaultClaimFee(), 5_00);
    }

    function test_setDefaultFees() public {
        assertEq(feeManager.defaultCoverageFee(), 3_00);
        assertEq(feeManager.defaultClaimFee(), 5_00);
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(Owned.Owned__Unauthorized.selector);
        feeManager.setDefaultFees(0, 10_00);
        vm.startPrank(address(this)); //current owner
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setDefaultFees(101_00, 10_00);
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setDefaultFees(10_00, 101_00);
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setDefaultFees(101_00, 101_00);
        assertEq(feeManager.defaultCoverageFee(), 3_00);
        assertEq(feeManager.defaultClaimFee(), 5_00);
        vm.expectEmit(true, true, true, true);
        emit DefaultFeesSet(2_00, 4_00);
        feeManager.setDefaultFees(2_00, 4_00);
        assertEq(feeManager.defaultCoverageFee(), 2_00);
        assertEq(feeManager.defaultClaimFee(), 4_00);
    }

    function test_setSpecialFees() public {
        assertEq(feeManager.specialCoverageFee(client), 0);
        assertEq(feeManager.specialClaimFee(contractor), 0);
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
        assertEq(feeManager.specialCoverageFee(client), 0);
        assertEq(feeManager.specialClaimFee(contractor), 0);
        vm.expectEmit(true, true, true, true);
        emit SpecialFeesSet(client, 2_00, 3_50);
        feeManager.setSpecialFees(client, 2_00, 3_50);
        assertEq(feeManager.specialCoverageFee(client), 2_00);
        assertEq(feeManager.specialClaimFee(client), 3_50);
    }

    function test_getCoverageFee() public {
        assertEq(feeManager.getCoverageFee(client), 3_00);
        assertEq(feeManager.getClaimFee(client), 5_00);
        test_setSpecialFees();
        assertEq(feeManager.getCoverageFee(client), 2_00);
        assertEq(feeManager.getClaimFee(client), 3_50);
    }
}