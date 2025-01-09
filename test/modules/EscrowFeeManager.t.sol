// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test, console2 } from "forge-std/Test.sol";

import { ECDSA } from "@solbase/utils/ECDSA.sol";
import { ERC20Mock } from "@openzeppelin/mocks/token/ERC20Mock.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import { EscrowFeeManager, IEscrowFeeManager, OwnedThreeStep } from "src/modules/EscrowFeeManager.sol";
import { EscrowAdminManager, OwnedRoles } from "src/modules/EscrowAdminManager.sol";
import { EscrowFixedPrice, IEscrowFixedPrice } from "src/EscrowFixedPrice.sol";
import { EscrowRegistry } from "src/modules/EscrowRegistry.sol";
import { Enums } from "src/common/Enums.sol";

contract EscrowFeeManagerUnitTest is Test {
    EscrowFeeManager feeManager;
    EscrowFixedPrice escrow;
    EscrowRegistry registry;
    ERC20Mock paymentToken;
    address owner;
    address client;
    address contractor;
    uint256 ownerPrKey;

    event DefaultFeesSet(uint16 coverage, uint16 claim);
    event UserSpecificFeesSet(address indexed user, uint16 coverage, uint16 claim);
    event InstanceFeesSet(address indexed instance, uint16 coverage, uint16 claim);
    event ContractSpecificFeesSet(address indexed instance, uint256 indexed contractId, uint16 coverage, uint16 claim);
    event ContractSpecificFeesReset(address indexed instance, uint256 indexed contractId);
    event InstanceSpecificFeesReset(address indexed instance);
    event UserSpecificFeesReset(address indexed user);

    function setUp() public {
        (owner, ownerPrKey) = makeAddrAndKey("owner");
        client = makeAddr("client");
        contractor = makeAddr("contractor");
        feeManager = new EscrowFeeManager(300, 500, owner);
        escrow = new EscrowFixedPrice();
        registry = new EscrowRegistry(owner);
    }

    ///////////////////////////////////////////
    //               helpers                 //
    ///////////////////////////////////////////

    function initialize_escrow() public {
        paymentToken = new ERC20Mock();
        EscrowAdminManager adminManager = new EscrowAdminManager(owner);
        vm.startPrank(owner);
        registry.addPaymentToken(address(paymentToken));
        registry.updateFeeManager(address(feeManager));
        vm.stopPrank();
        escrow.initialize(client, address(adminManager), address(registry));
        assertTrue(escrow.initialized());
    }

    function create_deposit() public {
        initialize_escrow();
        // Sign deposit authorization
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    client,
                    uint256(1),
                    address(contractor),
                    address(paymentToken),
                    uint256(1 ether),
                    Enums.FeeConfig.CLIENT_COVERS_ONLY,
                    keccak256(abi.encodePacked(bytes("contract_data"), keccak256(abi.encodePacked(uint256(42))))),
                    uint256(block.timestamp + 3 hours),
                    address(escrow)
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrKey, ethSignedHash); // Admin signs
        bytes memory signature = abi.encodePacked(r, s, v);

        EscrowFixedPrice.DepositRequest memory deposit = IEscrowFixedPrice.DepositRequest({
            contractId: 1,
            contractor: address(contractor),
            paymentToken: address(paymentToken),
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: keccak256(abi.encodePacked(bytes("contract_data"), keccak256(abi.encodePacked(uint256(42))))),
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.ACTIVE,
            escrow: address(escrow),
            expiration: block.timestamp + 3 hours,
            signature: signature
        });

        vm.startPrank(client);
        paymentToken.mint(client, 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        escrow.deposit(deposit);
        vm.stopPrank();
    }

    ///////////////////////////////////////////
    //        setup & function tests         //
    ///////////////////////////////////////////

    function test_setUpState() public view {
        assertTrue(address(feeManager).code.length > 0);
        assertEq(feeManager.owner(), address(owner));
        assertEq(feeManager.MAX_BPS(), 10_000);
        assertEq(feeManager.MAX_FEE_BPS(), 5000);
        (uint16 coverage, uint16 claim) = feeManager.defaultFees();
        assertEq(coverage, 300);
        assertEq(claim, 500);
    }

    function test_setDefaultFees() public {
        create_deposit();
        EscrowFeeManager.FeeRates memory rates = feeManager.getApplicableFees(address(escrow), 0, client);
        assertEq(rates.coverage, 300);
        assertEq(rates.claim, 500);
        (uint16 coverage, uint16 claim) = feeManager.defaultFees();
        assertEq(coverage, 300);
        assertEq(claim, 500);
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        feeManager.setDefaultFees(0, 1000);
        vm.startPrank(address(owner)); //current owner
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setDefaultFees(5100, 5000);
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setDefaultFees(5000, 5100);
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setDefaultFees(5100, 5100);
        (coverage, claim) = feeManager.defaultFees();
        assertEq(coverage, 300);
        assertEq(claim, 500);
        vm.expectEmit(true, true, true, true);
        emit DefaultFeesSet(5000, 5000);
        feeManager.setDefaultFees(5000, 5000);
        (coverage, claim) = feeManager.defaultFees();
        assertEq(coverage, 5000);
        assertEq(claim, 5000);
        rates = feeManager.getApplicableFees(address(escrow), 0, client);
        assertEq(rates.coverage, 5000);
        assertEq(rates.claim, 5000);
        rates = feeManager.getApplicableFees(address(escrow), 0, contractor);
        assertEq(rates.coverage, 5000);
        assertEq(rates.claim, 5000);
        feeManager.setDefaultFees(200, 400);
        (coverage, claim) = feeManager.defaultFees();
        assertEq(coverage, 200);
        assertEq(claim, 400);
        vm.stopPrank();
    }

    function test_setUserSpecificFees() public {
        create_deposit();
        (uint16 coverage, uint16 claim) = feeManager.userSpecificFees(client);
        assertEq(coverage, 0);
        assertEq(claim, 0);
        EscrowFeeManager.FeeRates memory rates = feeManager.getApplicableFees(address(escrow), 0, client);
        assertEq(rates.coverage, 300);
        assertEq(rates.claim, 500);
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        feeManager.setUserSpecificFees(client, 200, 350);
        vm.startPrank(address(owner)); //current owner
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setUserSpecificFees(client, 5100, 350);
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setUserSpecificFees(client, 350, 5100);
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setUserSpecificFees(client, 5100, 5100);
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__ZeroAddressProvided.selector);
        feeManager.setUserSpecificFees(address(0), 200, 350);
        (coverage, claim) = feeManager.userSpecificFees(client);
        assertEq(coverage, 0);
        assertEq(claim, 0);
        vm.expectEmit(true, true, true, true);
        emit UserSpecificFeesSet(client, 200, 350);
        feeManager.setUserSpecificFees(client, 200, 350);
        vm.stopPrank();
        (coverage, claim) = feeManager.userSpecificFees(client);
        assertEq(coverage, 200);
        assertEq(claim, 350);
        rates = feeManager.getApplicableFees(address(escrow), 1, client);
        assertEq(rates.coverage, 200);
        assertEq(rates.claim, 350);
    }

    function test_setInstanceFees() public {
        test_setUserSpecificFees();
        (uint16 coverage, uint16 claim) = feeManager.instanceFees(address(escrow));
        assertEq(coverage, 0);
        assertEq(claim, 0);
        EscrowFeeManager.FeeRates memory rates = feeManager.getApplicableFees(address(escrow), 0, client);
        assertEq(rates.coverage, 200);
        assertEq(rates.claim, 350);
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        feeManager.setInstanceFees(address(escrow), 200, 350);
        vm.startPrank(address(owner));
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setInstanceFees(address(escrow), 5100, 350);
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setInstanceFees(address(escrow), 350, 5100);
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setInstanceFees(address(escrow), 5100, 5100);
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__ZeroAddressProvided.selector);
        feeManager.setInstanceFees(address(0), 200, 350);
        (coverage, claim) = feeManager.instanceFees(address(escrow));
        assertEq(coverage, 0);
        assertEq(claim, 0);
        vm.expectEmit(true, true, true, true);
        emit InstanceFeesSet(address(escrow), 250, 450);
        feeManager.setInstanceFees(address(escrow), 250, 450);
        vm.stopPrank();
        (coverage, claim) = feeManager.userSpecificFees(client);
        assertEq(coverage, 200);
        assertEq(claim, 350);
        (coverage, claim) = feeManager.instanceFees(address(escrow));
        assertEq(coverage, 250);
        assertEq(claim, 450);
        rates = feeManager.getApplicableFees(address(escrow), 1, client);
        assertEq(rates.coverage, 250);
        assertEq(rates.claim, 450);
    }

    function test_setContractSpecificFees() public {
        test_setInstanceFees();
        uint256 contractId = 1;
        (uint16 coverage, uint16 claim) = feeManager.instanceFees(address(escrow));
        assertEq(coverage, 250);
        assertEq(claim, 450);
        (coverage, claim) = feeManager.contractSpecificFees(address(escrow), contractId);
        assertEq(coverage, 0);
        assertEq(claim, 0);
        EscrowFeeManager.FeeRates memory rates = feeManager.getApplicableFees(address(escrow), contractId, client);
        assertEq(rates.coverage, 250);
        assertEq(rates.claim, 450);
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        feeManager.setContractSpecificFees(address(escrow), contractId, 200, 350);
        vm.startPrank(address(owner));
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setContractSpecificFees(address(escrow), contractId, 5100, 350);
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setContractSpecificFees(address(escrow), contractId, 350, 5100);
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__FeeTooHigh.selector);
        feeManager.setContractSpecificFees(address(escrow), contractId, 5100, 5100);
        vm.expectRevert(IEscrowFeeManager.EscrowFeeManager__ZeroAddressProvided.selector);
        feeManager.setContractSpecificFees(address(0), contractId, 200, 350);
        (coverage, claim) = feeManager.contractSpecificFees(address(escrow), contractId);
        assertEq(coverage, 0);
        assertEq(claim, 0);
        vm.expectEmit(true, true, true, true);
        emit ContractSpecificFeesSet(address(escrow), contractId, 150, 500);
        feeManager.setContractSpecificFees(address(escrow), contractId, 150, 500);
        vm.stopPrank();
        (coverage, claim) = feeManager.userSpecificFees(client);
        assertEq(coverage, 200);
        assertEq(claim, 350);
        (coverage, claim) = feeManager.userSpecificFees(contractor);
        assertEq(coverage, 0);
        assertEq(claim, 0);
        (coverage, claim) = feeManager.instanceFees(address(escrow));
        assertEq(coverage, 250);
        assertEq(claim, 450);
        (coverage, claim) = feeManager.instanceFees(address(this));
        assertEq(coverage, 0);
        assertEq(claim, 0);
        (coverage, claim) = feeManager.contractSpecificFees(address(escrow), contractId);
        assertEq(coverage, 150);
        assertEq(claim, 500);
        (coverage, claim) = feeManager.contractSpecificFees(address(this), contractId);
        assertEq(coverage, 0);
        assertEq(claim, 0);
        rates = feeManager.getApplicableFees(address(escrow), contractId, client);
        assertEq(rates.coverage, 150);
        assertEq(rates.claim, 500);
        rates = feeManager.getApplicableFees(address(escrow), contractId, contractor);
        assertEq(rates.coverage, 150);
        assertEq(rates.claim, 500);
    }

    function test_resetUserSpecificFees() public {
        test_setUserSpecificFees();
        (uint16 coverage, uint16 claim) = feeManager.defaultFees();
        assertEq(coverage, 300);
        assertEq(claim, 500);
        (coverage, claim) = feeManager.userSpecificFees(client);
        assertEq(coverage, 200);
        assertEq(claim, 350);
        EscrowFeeManager.FeeRates memory rates = feeManager.getApplicableFees(address(escrow), 1, client);
        assertEq(rates.coverage, 200);
        assertEq(rates.claim, 350);
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        feeManager.resetUserSpecificFees(client);
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit UserSpecificFeesReset(client);
        feeManager.resetUserSpecificFees(client);
        vm.stopPrank();
        (coverage, claim) = feeManager.userSpecificFees(client);
        assertEq(coverage, 0);
        assertEq(claim, 0);
        rates = feeManager.getApplicableFees(address(escrow), 1, client);
        assertEq(rates.coverage, 300);
        assertEq(rates.claim, 500);
        (coverage, claim) = feeManager.defaultFees();
        assertEq(coverage, 300);
        assertEq(claim, 500);
    }

    function test_resetInstanceSpecificFees() public {
        test_setInstanceFees();
        (uint16 coverage, uint16 claim) = feeManager.defaultFees();
        assertEq(coverage, 300);
        assertEq(claim, 500);
        (coverage, claim) = feeManager.instanceFees(address(escrow));
        assertEq(coverage, 250);
        assertEq(claim, 450);
        EscrowFeeManager.FeeRates memory rates = feeManager.getApplicableFees(address(escrow), 1, client);
        assertEq(rates.coverage, 250);
        assertEq(rates.claim, 450);
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        feeManager.resetInstanceSpecificFees(address(escrow));
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit InstanceSpecificFeesReset(address(escrow));
        feeManager.resetInstanceSpecificFees(address(escrow));
        vm.stopPrank();
        (coverage, claim) = feeManager.instanceFees(address(escrow));
        assertEq(coverage, 0);
        assertEq(claim, 0);
        (coverage, claim) = feeManager.defaultFees();
        assertEq(coverage, 300);
        assertEq(claim, 500);
        (coverage, claim) = feeManager.userSpecificFees(client);
        assertEq(coverage, 200);
        assertEq(claim, 350);
        rates = feeManager.getApplicableFees(address(escrow), 1, client);
        assertEq(rates.coverage, 200);
        assertEq(rates.claim, 350);
    }

    function test_resetContractSpecificFees() public {
        test_setContractSpecificFees();
        uint256 contractId = 1;
        (uint16 coverage, uint16 claim) = feeManager.defaultFees();
        assertEq(coverage, 300);
        assertEq(claim, 500);
        (coverage, claim) = feeManager.contractSpecificFees(address(escrow), contractId);
        assertEq(coverage, 150);
        assertEq(claim, 500);
        EscrowFeeManager.FeeRates memory rates = feeManager.getApplicableFees(address(escrow), 1, client);
        assertEq(rates.coverage, 150);
        assertEq(rates.claim, 500);
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        feeManager.resetContractSpecificFees(address(escrow), contractId);
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit ContractSpecificFeesReset(address(escrow), contractId);
        feeManager.resetContractSpecificFees(address(escrow), contractId);
        vm.stopPrank();
        (coverage, claim) = feeManager.defaultFees();
        assertEq(coverage, 300);
        assertEq(claim, 500);
        (coverage, claim) = feeManager.instanceFees(address(escrow));
        assertEq(coverage, 250);
        assertEq(claim, 450);
        (coverage, claim) = feeManager.contractSpecificFees(address(escrow), contractId);
        assertEq(coverage, 0);
        assertEq(claim, 0);
        rates = feeManager.getApplicableFees(address(escrow), 1, client);
        assertEq(rates.coverage, 250);
        assertEq(rates.claim, 450);
    }

    function test_resetAllToDefault() public {
        test_setContractSpecificFees();
        uint256 contractId = 1;
        (uint16 coverage, uint16 claim) = feeManager.defaultFees();
        assertEq(coverage, 300);
        assertEq(claim, 500);
        (coverage, claim) = feeManager.userSpecificFees(client);
        assertEq(coverage, 200);
        assertEq(claim, 350);
        (coverage, claim) = feeManager.instanceFees(address(escrow));
        assertEq(coverage, 250);
        assertEq(claim, 450);
        (coverage, claim) = feeManager.contractSpecificFees(address(escrow), contractId);
        assertEq(coverage, 150);
        assertEq(claim, 500);
        EscrowFeeManager.FeeRates memory rates = feeManager.getApplicableFees(address(escrow), 1, client);
        assertEq(rates.coverage, 150);
        assertEq(rates.claim, 500);
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        feeManager.resetAllToDefault(address(escrow), contractId, client);
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit ContractSpecificFeesReset(address(escrow), contractId);
        emit InstanceSpecificFeesReset(address(escrow));
        emit UserSpecificFeesReset(client);
        feeManager.resetAllToDefault(address(escrow), contractId, client);
        vm.stopPrank();
        (coverage, claim) = feeManager.userSpecificFees(client);
        assertEq(coverage, 0);
        assertEq(claim, 0);
        (coverage, claim) = feeManager.instanceFees(address(escrow));
        assertEq(coverage, 0);
        assertEq(claim, 0);
        (coverage, claim) = feeManager.contractSpecificFees(address(escrow), contractId);
        assertEq(coverage, 0);
        assertEq(claim, 0);
        (coverage, claim) = feeManager.defaultFees();
        assertEq(coverage, 300);
        assertEq(claim, 500);
        rates = feeManager.getApplicableFees(address(escrow), 1, client);
        assertEq(rates.coverage, 300);
        assertEq(rates.claim, 500);
    }

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
