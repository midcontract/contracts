// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test, console2 } from "forge-std/Test.sol";

import { EscrowFeeManager, IEscrowFeeManager, OwnedThreeStep } from "src/modules/EscrowFeeManager.sol";
import { EscrowFixedPrice } from "src/EscrowFixedPrice.sol";
import { Enums } from "src/libs/Enums.sol";

contract EscrowFeeManagerUnitTest is Test {
    EscrowFeeManager feeManager;
    EscrowFixedPrice escrow;
    address owner;
    address client;
    address contractor;

    event DefaultFeesSet(uint16 coverage, uint16 claim);
    event UserSpecificFeesSet(address indexed user, uint16 coverage, uint16 claim);

    function setUp() public {
        owner = makeAddr("owner");
        client = makeAddr("client");
        contractor = makeAddr("contractor");
        feeManager = new EscrowFeeManager(300, 500, owner);
        escrow = new EscrowFixedPrice();
    }

    function test_setUpState() public view {
        assertTrue(address(feeManager).code.length > 0);
        assertEq(feeManager.owner(), address(owner));
        (uint16 coverage, uint16 claim) = feeManager.defaultFees();
        assertEq(coverage, 300);
        assertEq(claim, 500);
    }

    function test_setDefaultFees() public {
        (uint16 coverage, uint16 claim) = feeManager.defaultFees();
        assertEq(coverage, 300);
        assertEq(claim, 500);
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        feeManager.setDefaultFees(0, 1000);
        vm.startPrank(address(owner)); //current owner
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setDefaultFees(10_100, 1000);
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setDefaultFees(1000, 10_100);
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setDefaultFees(10_100, 10_100);
        (coverage, claim) = feeManager.defaultFees();
        assertEq(coverage, 300);
        assertEq(claim, 500);
        vm.expectEmit(true, true, true, true);
        emit DefaultFeesSet(200, 400);
        feeManager.setDefaultFees(200, 400);
        (coverage, claim) = feeManager.defaultFees();
        assertEq(coverage, 200);
        assertEq(claim, 400);
    }

    function test_setUserSpecificFees() public {
        (uint16 coverage, uint16 claim) = feeManager.userSpecificFees(client);
        assertEq(coverage, 0);
        assertEq(claim, 0);
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        feeManager.setUserSpecificFees(client, 200, 350);
        vm.startPrank(address(owner)); //current owner
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setUserSpecificFees(client, 10_100, 350);
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setUserSpecificFees(client, 350, 10_100);
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setUserSpecificFees(client, 10_100, 10_100);
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__ZeroAddressProvided.selector);
        feeManager.setUserSpecificFees(address(0), 200, 350);
        (coverage, claim) = feeManager.userSpecificFees(client);
        assertEq(coverage, 0);
        assertEq(claim, 0);
        vm.expectEmit(true, true, true, true);
        emit UserSpecificFeesSet(client, 200, 350);
        feeManager.setUserSpecificFees(client, 200, 350);
        (coverage, claim) = feeManager.userSpecificFees(client);
        assertEq(coverage, 200);
        assertEq(claim, 350);
    }

    // function test_getCoverageFee() public {
    //     assertEq(feeManager.getCoverageFee(client), 300);
    //     assertEq(feeManager.getClaimFee(client), 500);
    //     test_setUserSpecificFees();
    //     assertEq(feeManager.getCoverageFee(client), 200);
    //     assertEq(feeManager.getClaimFee(client), 350);
    // }

    function test_computeDepositAmount_defaultFees() public {
        uint256 depositAmount = 1 ether;
        (uint16 coverage, uint16 claim) = feeManager.defaultFees();
        assertEq(coverage, 300);
        assertEq(claim, 500);
        // CLIENT_COVERS_ALL
        uint256 feeAmount = depositAmount * (coverage + claim) / 10_000;
        Enums.FeeConfig feeConfig = Enums.FeeConfig.CLIENT_COVERS_ALL;
        (uint256 totalDepositAmount, uint256 feeApplied) =
            feeManager.computeDepositAmountAndFee(address(escrow), 1, client, depositAmount, feeConfig);
        assertEq(totalDepositAmount, depositAmount + feeAmount);
        assertEq(feeApplied, feeAmount);
        // CLIENT_COVERS_ONLY
        feeAmount = depositAmount * coverage / 10_000;
        feeConfig = Enums.FeeConfig.CLIENT_COVERS_ONLY;
        (totalDepositAmount, feeApplied) =
            feeManager.computeDepositAmountAndFee(address(escrow), 1, client, depositAmount, feeConfig);
        assertEq(totalDepositAmount, depositAmount + feeAmount);
        assertEq(feeApplied, feeAmount);
        // CONTRACTOR_COVERS_CLAIM
        feeConfig = Enums.FeeConfig.CONTRACTOR_COVERS_CLAIM;
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__UnsupportedFeeConfiguration.selector);
        (totalDepositAmount, feeApplied) =
            feeManager.computeDepositAmountAndFee(address(escrow), 1, client, depositAmount, feeConfig);
        assertEq(totalDepositAmount, 0);
        assertEq(feeApplied, 0);
        // NO_FEES
        feeConfig = Enums.FeeConfig.NO_FEES;
        (totalDepositAmount, feeApplied) =
            feeManager.computeDepositAmountAndFee(address(escrow), 1, client, depositAmount, feeConfig);
        assertEq(totalDepositAmount, depositAmount);
        assertEq(feeApplied, 0);
    }

    function test_computeDepositAmount_specialFees() public {
        uint256 depositAmount = 1 ether;
        vm.prank(owner);
        feeManager.setUserSpecificFees(client, 200, 350);
        (uint16 coverage, uint16 claim) = feeManager.userSpecificFees(client);
        assertEq(coverage, 200);
        assertEq(claim, 350);
        // CLIENT_COVERS_ALL
        uint256 feeAmount = depositAmount * (coverage + claim) / 10_000;
        Enums.FeeConfig feeConfig = Enums.FeeConfig.CLIENT_COVERS_ALL;
        (uint256 totalDepositAmount, uint256 feeApplied) =
            feeManager.computeDepositAmountAndFee(address(escrow), 1, client, depositAmount, feeConfig);
        assertEq(totalDepositAmount, depositAmount + feeAmount);
        assertEq(feeApplied, feeAmount);
        // CLIENT_COVERS_ONLY
        feeAmount = depositAmount * coverage / 10_000;
        feeConfig = Enums.FeeConfig.CLIENT_COVERS_ONLY;
        (totalDepositAmount, feeApplied) =
            feeManager.computeDepositAmountAndFee(address(escrow), 1, client, depositAmount, feeConfig);
        assertEq(totalDepositAmount, depositAmount + feeAmount);
        assertEq(feeApplied, feeAmount);
        // CONTRACTOR_COVERS_CLAIM
        feeConfig = Enums.FeeConfig.CONTRACTOR_COVERS_CLAIM;
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__UnsupportedFeeConfiguration.selector);
        (totalDepositAmount, feeApplied) =
            feeManager.computeDepositAmountAndFee(address(escrow), 1, client, depositAmount, feeConfig);
        assertEq(totalDepositAmount, 0);
        assertEq(feeApplied, 0);
        // NO_FEES
        feeConfig = Enums.FeeConfig.NO_FEES;
        (totalDepositAmount, feeApplied) =
            feeManager.computeDepositAmountAndFee(address(escrow), 1, client, depositAmount, feeConfig);
        assertEq(totalDepositAmount, depositAmount);
        assertEq(feeApplied, 0);
    }

    function test_computeClaimableAmount_defaultFees() public {
        uint256 claimedAmount = 1 ether;
        (uint16 coverage, uint16 claim) = feeManager.defaultFees();
        assertEq(coverage, 300);
        assertEq(claim, 500);
        // CLIENT_COVERS_ALL
        uint256 clientFeeApplied = claimedAmount * (coverage + claim) / 10_000;
        Enums.FeeConfig feeConfig = Enums.FeeConfig.CLIENT_COVERS_ALL;
        (uint256 claimableAmount, uint256 feeDeducted, uint256 clientFee) =
            feeManager.computeClaimableAmountAndFee(address(escrow), 1, contractor, claimedAmount, feeConfig);
        assertEq(claimableAmount, claimedAmount);
        assertEq(feeDeducted, 0);
        assertEq(clientFee, clientFeeApplied);
        // CLIENT_COVERS_ONLY
        clientFeeApplied = claimedAmount * coverage / 10_000;
        uint256 feeAmount = claimedAmount * claim / 10_000;
        feeConfig = Enums.FeeConfig.CLIENT_COVERS_ONLY;
        (claimableAmount, feeDeducted, clientFee) =
            feeManager.computeClaimableAmountAndFee(address(escrow), 1, contractor, claimedAmount, feeConfig);
        assertEq(claimableAmount, claimedAmount - feeAmount);
        assertEq(feeDeducted, feeAmount);
        assertEq(clientFee, clientFeeApplied);
        // CONTRACTOR_COVERS_CLAIM
        feeAmount = claimedAmount * claim / 10_000;
        feeConfig = Enums.FeeConfig.CONTRACTOR_COVERS_CLAIM;
        (claimableAmount, feeDeducted, clientFee) =
            feeManager.computeClaimableAmountAndFee(address(escrow), 1, contractor, claimedAmount, feeConfig);
        assertEq(claimableAmount, claimedAmount - feeAmount);
        assertEq(feeDeducted, feeAmount);
        assertEq(clientFee, 0);
        // NO_FEES
        feeConfig = Enums.FeeConfig.NO_FEES;
        (claimableAmount, feeDeducted, clientFee) =
            feeManager.computeClaimableAmountAndFee(address(escrow), 1, contractor, claimedAmount, feeConfig);
        assertEq(claimableAmount, claimedAmount);
        assertEq(feeDeducted, 0);
        assertEq(clientFee, 0);
        // INVALID
        feeConfig = Enums.FeeConfig.INVALID;
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__UnsupportedFeeConfiguration.selector);
        (claimableAmount, feeDeducted, clientFee) =
            feeManager.computeClaimableAmountAndFee(address(escrow), 1, contractor, claimedAmount, feeConfig);
        assertEq(claimableAmount, 0);
        assertEq(feeDeducted, 0);
        assertEq(clientFee, 0);
    }

    function test_computeClaimableAmount_specialFees() public {
        uint256 claimedAmount = 1 ether;
        vm.prank(owner);
        feeManager.setUserSpecificFees(contractor, 200, 350);
        (uint16 coverage, uint16 claim) = feeManager.userSpecificFees(contractor);
        assertEq(coverage, 200);
        assertEq(claim, 350);
        // CLIENT_COVERS_ALL
        uint256 clientFeeApplied = claimedAmount * (coverage + claim) / 10_000;
        Enums.FeeConfig feeConfig = Enums.FeeConfig.CLIENT_COVERS_ALL;
        (uint256 claimableAmount, uint256 feeDeducted, uint256 clientFee) =
            feeManager.computeClaimableAmountAndFee(address(escrow), 1, contractor, claimedAmount, feeConfig);
        assertEq(claimableAmount, claimedAmount);
        assertEq(feeDeducted, 0);
        assertEq(clientFee, clientFeeApplied);
        // CLIENT_COVERS_ONLY
        clientFeeApplied = claimedAmount * coverage / 10_000;
        uint256 feeAmount = claimedAmount * claim / 10_000;
        feeConfig = Enums.FeeConfig.CLIENT_COVERS_ONLY;
        (claimableAmount, feeDeducted, clientFee) =
            feeManager.computeClaimableAmountAndFee(address(escrow), 1, contractor, claimedAmount, feeConfig);
        assertEq(claimableAmount, claimedAmount - feeAmount);
        assertEq(feeDeducted, feeAmount);
        assertEq(clientFee, clientFeeApplied);
        // CONTRACTOR_COVERS_CLAIM
        feeAmount = claimedAmount * claim / 10_000;
        feeConfig = Enums.FeeConfig.CONTRACTOR_COVERS_CLAIM;
        (claimableAmount, feeDeducted, clientFee) =
            feeManager.computeClaimableAmountAndFee(address(escrow), 1, contractor, claimedAmount, feeConfig);
        assertEq(claimableAmount, claimedAmount - feeAmount);
        assertEq(feeDeducted, feeAmount);
        assertEq(clientFee, 0);
        // NO_FEES
        feeConfig = Enums.FeeConfig.NO_FEES;
        (claimableAmount, feeDeducted, clientFee) =
            feeManager.computeClaimableAmountAndFee(address(escrow), 1, contractor, claimedAmount, feeConfig);
        assertEq(claimableAmount, claimedAmount);
        assertEq(feeDeducted, 0);
        assertEq(clientFee, 0);
    }
}
