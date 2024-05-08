// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {EscrowFeeManager, IEscrowFeeManager, Ownable} from "src/modules/EscrowFeeManager.sol";
import {Enums} from "src/libs/Enums.sol";
import {MockEscrowFeeManager} from "test/mocks/MockEscrowFeeManager.sol";

contract EscrowFeeManagerUnitTest is Test {
    EscrowFeeManager feeManager;

    address owner;
    address client;
    address contractor;

    event DefaultFeesSet(uint256 coverage, uint256 claim);
    event SpecialFeesSet(address user, uint256 coverage, uint256 claim);

    function setUp() public {
        owner = makeAddr("owner");
        client = makeAddr("client");
        contractor = makeAddr("contractor");
        feeManager = new EscrowFeeManager(3_00, 5_00, owner);
    }

    function test_setUpState() public view {
        assertTrue(address(feeManager).code.length > 0);
        assertEq(feeManager.owner(), address(owner));
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
        vm.expectRevert(Ownable.Unauthorized.selector);
        feeManager.updateDefaultFees(0, 10_00);
        vm.startPrank(address(owner)); //current owner
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
        vm.expectRevert(Ownable.Unauthorized.selector);
        feeManager.setSpecialFees(client, 2_00, 3_50);
        vm.startPrank(address(owner)); //current owner
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

    function test_computeDepositAmount_defaultFees() public {
        uint256 depositAmount = 1 ether;
        (uint16 coverage, uint16 claim) = feeManager.defaultFees();
        assertEq(coverage, 3_00);
        assertEq(claim, 5_00);
        // CLIENT_COVERS_ALL
        uint256 feeAmount = depositAmount * (coverage + claim) / 100_00;
        Enums.FeeConfig feeConfig = Enums.FeeConfig.CLIENT_COVERS_ALL;
        (uint256 totalDepositAmount, uint256 feeApplied) =
            feeManager.computeDepositAmountAndFee(client, depositAmount, feeConfig);
        assertEq(totalDepositAmount, depositAmount + feeAmount);
        assertEq(feeApplied, feeAmount);
        // CLIENT_COVERS_ONLY
        feeAmount = depositAmount * coverage / 100_00;
        feeConfig = Enums.FeeConfig.CLIENT_COVERS_ONLY;
        (totalDepositAmount, feeApplied) = feeManager.computeDepositAmountAndFee(client, depositAmount, feeConfig);
        assertEq(totalDepositAmount, depositAmount + feeAmount);
        assertEq(feeApplied, feeAmount);
        // CONTRACTOR_COVERS_CLAIM
        feeConfig = Enums.FeeConfig.CONTRACTOR_COVERS_CLAIM;
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__UnsupportedFeeConfiguration.selector);
        (totalDepositAmount, feeApplied) = feeManager.computeDepositAmountAndFee(client, depositAmount, feeConfig);
        assertEq(totalDepositAmount, 0);
        assertEq(feeApplied, 0);
        // NO_FEES
        feeConfig = Enums.FeeConfig.NO_FEES;
        (totalDepositAmount, feeApplied) = feeManager.computeDepositAmountAndFee(client, depositAmount, feeConfig);
        assertEq(totalDepositAmount, depositAmount);
        assertEq(feeApplied, 0);
    }

    function test_computeDepositAmount_specialFees() public {
        uint256 depositAmount = 1 ether;
        vm.prank(owner);
        feeManager.setSpecialFees(client, 2_00, 3_50);
        (uint16 coverage, uint16 claim) = feeManager.specialFees(client);
        assertEq(coverage, 2_00);
        assertEq(claim, 3_50);
        // CLIENT_COVERS_ALL
        uint256 feeAmount = depositAmount * (coverage + claim) / 100_00;
        Enums.FeeConfig feeConfig = Enums.FeeConfig.CLIENT_COVERS_ALL;
        (uint256 totalDepositAmount, uint256 feeApplied) =
            feeManager.computeDepositAmountAndFee(client, depositAmount, feeConfig);
        assertEq(totalDepositAmount, depositAmount + feeAmount);
        assertEq(feeApplied, feeAmount);
        // CLIENT_COVERS_ONLY
        feeAmount = depositAmount * coverage / 100_00;
        feeConfig = Enums.FeeConfig.CLIENT_COVERS_ONLY;
        (totalDepositAmount, feeApplied) = feeManager.computeDepositAmountAndFee(client, depositAmount, feeConfig);
        assertEq(totalDepositAmount, depositAmount + feeAmount);
        assertEq(feeApplied, feeAmount);
        // CONTRACTOR_COVERS_CLAIM
        feeConfig = Enums.FeeConfig.CONTRACTOR_COVERS_CLAIM;
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__UnsupportedFeeConfiguration.selector);
        (totalDepositAmount, feeApplied) = feeManager.computeDepositAmountAndFee(client, depositAmount, feeConfig);
        assertEq(totalDepositAmount, 0);
        assertEq(feeApplied, 0);
        // NO_FEES
        feeConfig = Enums.FeeConfig.NO_FEES;
        (totalDepositAmount, feeApplied) = feeManager.computeDepositAmountAndFee(client, depositAmount, feeConfig);
        assertEq(totalDepositAmount, depositAmount);
        assertEq(feeApplied, 0);
    }

    function test_computeClaimableAmount_defaultFees() public view {
        uint256 claimedAmount = 1 ether;
        (uint16 coverage, uint16 claim) = feeManager.defaultFees();
        assertEq(coverage, 3_00);
        assertEq(claim, 5_00);
        // CLIENT_COVERS_ALL
        uint256 clientFeeApplied = claimedAmount * (coverage + claim) / 100_00;
        Enums.FeeConfig feeConfig = Enums.FeeConfig.CLIENT_COVERS_ALL;
        (uint256 claimableAmount, uint256 feeDeducted, uint256 clientFee) =
            feeManager.computeClaimableAmountAndFee(contractor, claimedAmount, feeConfig);
        assertEq(claimableAmount, claimedAmount);
        assertEq(feeDeducted, 0);
        assertEq(clientFee, clientFeeApplied);
        // CLIENT_COVERS_ONLY
        clientFeeApplied = claimedAmount * coverage / 100_00;
        uint256 feeAmount = claimedAmount * claim / 100_00;
        feeConfig = Enums.FeeConfig.CLIENT_COVERS_ONLY;
        (claimableAmount, feeDeducted, clientFee) =
            feeManager.computeClaimableAmountAndFee(contractor, claimedAmount, feeConfig);
        assertEq(claimableAmount, claimedAmount - feeAmount);
        assertEq(feeDeducted, feeAmount);
        assertEq(clientFee, clientFeeApplied);
        // CONTRACTOR_COVERS_CLAIM
        feeAmount = claimedAmount * claim / 100_00;
        feeConfig = Enums.FeeConfig.CONTRACTOR_COVERS_CLAIM;
        (claimableAmount, feeDeducted, clientFee) =
            feeManager.computeClaimableAmountAndFee(contractor, claimedAmount, feeConfig);
        assertEq(claimableAmount, claimedAmount - feeAmount);
        assertEq(feeDeducted, feeAmount);
        assertEq(clientFee, 0);
        // NO_FEES
        feeConfig = Enums.FeeConfig.NO_FEES;
        (claimableAmount, feeDeducted, clientFee) = feeManager.computeClaimableAmountAndFee(contractor, claimedAmount, feeConfig);
        assertEq(claimableAmount, claimedAmount);
        assertEq(feeDeducted, 0);
        assertEq(clientFee, 0);
    }

    function test_computeClaimableAmount_specialFees() public {
        uint256 claimedAmount = 1 ether;
        vm.prank(owner);
        feeManager.setSpecialFees(contractor, 2_00, 3_50);
        (uint16 coverage, uint16 claim) = feeManager.specialFees(contractor);
        assertEq(coverage, 2_00);
        assertEq(claim, 3_50);
        // CLIENT_COVERS_ALL
        uint256 clientFeeApplied = claimedAmount * (coverage + claim) / 100_00;
        Enums.FeeConfig feeConfig = Enums.FeeConfig.CLIENT_COVERS_ALL;
        (uint256 claimableAmount, uint256 feeDeducted, uint256 clientFee) =
            feeManager.computeClaimableAmountAndFee(contractor, claimedAmount, feeConfig);
        assertEq(claimableAmount, claimedAmount);
        assertEq(feeDeducted, 0);
        assertEq(clientFee, clientFeeApplied);
        // CLIENT_COVERS_ONLY
        clientFeeApplied = claimedAmount * coverage / 100_00;
        uint256 feeAmount = claimedAmount * claim / 100_00;
        feeConfig = Enums.FeeConfig.CLIENT_COVERS_ONLY;
        (claimableAmount, feeDeducted, clientFee) = feeManager.computeClaimableAmountAndFee(contractor, claimedAmount, feeConfig);
        assertEq(claimableAmount, claimedAmount - feeAmount);
        assertEq(feeDeducted, feeAmount);
        assertEq(clientFee, clientFeeApplied);
        // CONTRACTOR_COVERS_CLAIM
        feeAmount = claimedAmount * claim / 100_00;
        feeConfig = Enums.FeeConfig.CONTRACTOR_COVERS_CLAIM;
        (claimableAmount, feeDeducted, clientFee) = feeManager.computeClaimableAmountAndFee(contractor, claimedAmount, feeConfig);
        assertEq(claimableAmount, claimedAmount - feeAmount);
        assertEq(feeDeducted, feeAmount);
        assertEq(clientFee, 0);
        // NO_FEES
        feeConfig = Enums.FeeConfig.NO_FEES;
        (claimableAmount, feeDeducted, clientFee) = feeManager.computeClaimableAmountAndFee(contractor, claimedAmount, feeConfig);
        assertEq(claimableAmount, claimedAmount);
        assertEq(feeDeducted, 0);
        assertEq(clientFee, 0);
    }

    function test_computeDepositAndClaimableAmount_reverts() public {
        MockEscrowFeeManager mockFeeManager = new MockEscrowFeeManager(3_00, 5_00, owner);
        uint256 feeConfig = 4;
        vm.expectRevert(MockEscrowFeeManager.EscrowFeeManager__UnsupportedFeeConfiguration.selector);
        mockFeeManager.computeDepositAmountAndFee(client, 1 ether, feeConfig);
        vm.expectRevert(MockEscrowFeeManager.EscrowFeeManager__UnsupportedFeeConfiguration.selector);
        mockFeeManager.computeClaimableAmountAndFee(contractor, 1 ether, feeConfig);
        vm.prank(owner);
        feeManager.setSpecialFees(client, 2_00, 3_50);
        vm.expectRevert(MockEscrowFeeManager.EscrowFeeManager__UnsupportedFeeConfiguration.selector);
        mockFeeManager.computeDepositAmountAndFee(client, 1 ether, feeConfig);
        vm.expectRevert(MockEscrowFeeManager.EscrowFeeManager__UnsupportedFeeConfiguration.selector);
        mockFeeManager.computeClaimableAmountAndFee(contractor, 1 ether, feeConfig);
    }
}
