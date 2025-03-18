// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test, console2 } from "forge-std/Test.sol";

import { ECDSA } from "@solbase/utils/ECDSA.sol";
import { ERC20Mock } from "@openzeppelin/mocks/token/ERC20Mock.sol";
import { SignatureChecker } from "@openzeppelin/utils/cryptography/SignatureChecker.sol";

import { EscrowHourly, IEscrowHourly } from "src/EscrowHourly.sol";
import { EscrowAdminManager, OwnedRoles } from "src/modules/EscrowAdminManager.sol";
import { EscrowFeeManager, IEscrowFeeManager } from "src/modules/EscrowFeeManager.sol";
import { EscrowRegistry, IEscrowRegistry } from "src/modules/EscrowRegistry.sol";
import { Enums } from "src/common/Enums.sol";
import { IEscrow } from "src/interfaces/IEscrow.sol";
import { MockRegistry } from "test/mocks/MockRegistry.sol";
import { MockUSDT } from "test/mocks/MockUSDT.sol";
import { TestUtils } from "test/utils/TestUtils.sol";

contract EscrowHourlyUnitTest is Test, TestUtils {
    EscrowHourly escrow;
    EscrowRegistry registry;
    ERC20Mock paymentToken;
    ERC20Mock newPaymentToken;
    EscrowFeeManager feeManager;
    EscrowAdminManager adminManager;

    address client;
    address contractor;
    address treasury;
    address owner;
    uint256 ownerPrKey;
    uint256 expirationTimestamp;

    bytes32 salt;
    bytes32 contractorData;
    bytes contractData;
    bytes signature;

    Enums.FeeConfig feeConfig;
    Enums.Status status;

    IEscrowHourly.DepositRequest deposit;
    IEscrowHourly.WeeklyEntry weeklyEntry;
    IEscrowHourly.ContractDetails contractDetails;

    event Deposited(
        address indexed sender,
        uint256 indexed contractId,
        uint256 weekId,
        uint256 totalDepositAmount,
        address indexed contractor
    );
    event Approved(
        address indexed approver, uint256 indexed contractId, uint256 weekId, uint256 amountApprove, address receiver
    );
    event RefilledPrepayment(address indexed sender, uint256 indexed contractId, uint256 amount);
    event RefilledWeekPayment(address indexed sender, uint256 indexed contractId, uint256 weekId, uint256 amount);
    event Claimed(
        address indexed contractor,
        uint256 indexed contractId,
        uint256 weekId,
        uint256 amount,
        uint256 feeAmount,
        address indexed client
    );
    event Withdrawn(address indexed withdrawer, uint256 indexed contractId, uint256 amount, uint256 feeAmount);
    event RegistryUpdated(address registry);
    event AdminManagerUpdated(address adminManager);
    event ReturnRequested(address indexed sender, uint256 indexed contractId);
    event ReturnApproved(address indexed approver, uint256 indexed contractId, address indexed client);
    event ReturnCanceled(address indexed sender, uint256 indexed contractId);
    event DisputeCreated(address indexed sender, uint256 indexed contractId, uint256 weekId, address indexed client);
    event DisputeResolved(
        address indexed approver,
        uint256 indexed contractId,
        uint256 weekId,
        Enums.Winner winner,
        uint256 clientAmount,
        uint256 contractorAmount,
        address indexed client
    );
    event BulkClaimed(
        address indexed contractor,
        uint256 indexed contractId,
        uint256 startWeekId,
        uint256 endWeekId,
        uint256 totalClaimedAmount,
        uint256 totalFeeAmount,
        uint256 totalClientFee,
        address indexed client
    );

    function setUp() public {
        (owner, ownerPrKey) = makeAddrAndKey("owner");
        treasury = makeAddr("treasury");
        client = makeAddr("client");
        contractor = makeAddr("contractor");

        escrow = new EscrowHourly();
        registry = new EscrowRegistry(owner);
        paymentToken = new ERC20Mock();
        adminManager = new EscrowAdminManager(owner);
        feeManager = new EscrowFeeManager(address(adminManager), 300, 500);

        vm.startPrank(owner);
        registry.addPaymentToken(address(paymentToken));
        registry.setFixedTreasury(treasury);
        registry.setHourlyTreasury(treasury);
        registry.setMilestoneTreasury(treasury);
        registry.updateFeeManager(address(feeManager));
        vm.stopPrank();

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        contractorData = keccak256(abi.encodePacked(contractData, salt));
        expirationTimestamp = uint256(block.timestamp + 3 hours);

        deposit = IEscrowHourly.DepositRequest({
            contractId: 1,
            contractor: contractor,
            paymentToken: address(paymentToken),
            prepaymentAmount: 1 ether,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrow),
            expiration: expirationTimestamp,
            signature: getSignatureHourly(
                HourlySignatureParams({
                    contractId: 1,
                    contractor: address(contractor),
                    proxy: address(escrow),
                    token: address(paymentToken),
                    prepaymentAmount: 1 ether,
                    amountToClaim: 0 ether,
                    feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                    client: client,
                    ownerPrKey: ownerPrKey
                })
            )
        });

        weeklyEntry = IEscrowHourly.WeeklyEntry({ amountToClaim: 0, weekStatus: Enums.Status.NONE });
    }

    ///////////////////////////////////////////
    //        setup & initialize tests       //
    ///////////////////////////////////////////

    function test_setUpState() public view {
        assertTrue(address(escrow).code.length > 0);
        assertTrue(registry.paymentTokens(address(paymentToken)));
    }

    function test_initialize() public {
        assertFalse(escrow.initialized());
        escrow.initialize(client, address(adminManager), address(registry));
        assertEq(escrow.client(), client);
        assertEq(address(escrow.adminManager()), address(adminManager));
        assertEq(address(escrow.registry()), address(registry));
        assertFalse(escrow.contractExists(1));
        assertTrue(escrow.initialized());
    }

    function test_initialize_reverts() public {
        assertFalse(escrow.initialized());
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.initialize(address(0), address(adminManager), address(registry));
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.initialize(client, address(0), address(registry));
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.initialize(client, address(adminManager), address(0));
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.initialize(address(0), address(0), address(0));
        escrow.initialize(client, address(adminManager), address(registry));
        assertTrue(escrow.initialized());
        vm.expectRevert(IEscrow.Escrow__AlreadyInitialized.selector);
        escrow.initialize(client, address(adminManager), address(registry));
    }

    ///////////////////////////////////////////
    //            deposit tests              //
    ///////////////////////////////////////////

    function test_deposit_prepayment() public {
        escrow.initialize(client, address(adminManager), address(registry));
        uint256 currentContractId = 1;
        vm.startPrank(client);
        paymentToken.mint(client, 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        vm.expectEmit(true, true, true, true);
        emit Deposited(client, 1, 0, 1.03 ether, contractor);
        escrow.deposit(deposit);
        vm.stopPrank();
        (uint256 totalDepositAmount,) = computeDepositAndFeeAmount(
            address(registry), address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (
            address _contractor,
            address _paymentToken,
            uint256 _prepaymentAmount,
            uint256 _amountToWithdraw,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 1); //Status.ACTIVE
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, 0);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 1); //Status.ACTIVE
        assertEq(escrow.getWeeksCount(currentContractId), 1);
    }

    function test_deposit_existing_contract() public {
        test_deposit_prepayment();
        uint256 currentContractId = 1;
        vm.startPrank(client);
        paymentToken.mint(client, 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        vm.expectEmit(true, true, true, true);
        emit Deposited(client, 1, 1, 1.03 ether, contractor);
        escrow.deposit(deposit);
        vm.stopPrank();
        // contract level
        (
            address _contractor,
            address _paymentToken,
            uint256 _prepaymentAmount,
            uint256 _amountToWithdraw,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractDetails(currentContractId);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether * 2);
        assertEq(_contractor, contractor);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 1); //Status.ACTIVE
        // week level
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, 1);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 1); //Status.ACTIVE

        (uint256 totalDepositAmount,) = computeDepositAndFeeAmount(
            address(registry), address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + totalDepositAmount); //2.06ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(escrow.getWeeksCount(currentContractId), 2);
    }

    function test_deposit_reverts() public {
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        vm.prank(client);
        escrow.deposit(deposit);
        escrow.initialize(client, address(adminManager), address(registry));
        address notClient = makeAddr("notClient");
        vm.prank(notClient);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.deposit(deposit);

        deposit = IEscrowHourly.DepositRequest({
            contractId: uint256(1),
            contractor: contractor,
            paymentToken: address(paymentToken),
            prepaymentAmount: 0 ether,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrow),
            expiration: expirationTimestamp,
            signature: getSignatureHourly(
                HourlySignatureParams({
                    contractId: 1,
                    contractor: address(contractor),
                    proxy: address(escrow),
                    token: address(paymentToken),
                    prepaymentAmount: 0 ether,
                    amountToClaim: 0 ether,
                    feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                    client: client,
                    ownerPrKey: ownerPrKey
                })
            )
        });
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidAmount.selector);
        escrow.deposit(deposit);

        ERC20Mock notPaymentToken = new ERC20Mock();
        deposit = IEscrowHourly.DepositRequest({
            contractId: uint256(1),
            contractor: contractor,
            paymentToken: address(notPaymentToken),
            prepaymentAmount: 1 ether,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrow),
            expiration: expirationTimestamp,
            signature: getSignatureHourly(
                HourlySignatureParams({
                    contractId: 1,
                    contractor: address(contractor),
                    proxy: address(escrow),
                    token: address(notPaymentToken),
                    prepaymentAmount: 1 ether,
                    amountToClaim: 0 ether,
                    feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                    client: client,
                    ownerPrKey: ownerPrKey
                })
            )
        });
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__NotSupportedPaymentToken.selector);
        escrow.deposit(deposit);

        deposit = IEscrowHourly.DepositRequest({
            contractId: uint256(1),
            contractor: address(0),
            paymentToken: address(paymentToken),
            prepaymentAmount: 1 ether,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrow),
            expiration: expirationTimestamp,
            signature: getSignatureHourly(
                HourlySignatureParams({
                    contractId: 1,
                    contractor: address(0),
                    proxy: address(escrow),
                    token: address(paymentToken),
                    prepaymentAmount: 1 ether,
                    amountToClaim: 0 ether,
                    feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                    client: client,
                    ownerPrKey: ownerPrKey
                })
            )
        });
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.deposit(deposit);

        vm.startPrank(address(client));
        paymentToken.mint(address(client), 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        deposit = IEscrowHourly.DepositRequest({
            contractId: uint256(0),
            contractor: contractor,
            paymentToken: address(paymentToken),
            prepaymentAmount: 1 ether,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrow),
            expiration: expirationTimestamp,
            signature: getSignatureHourly(
                HourlySignatureParams({
                    contractId: uint256(0),
                    contractor: address(contractor),
                    proxy: address(escrow),
                    token: address(paymentToken),
                    prepaymentAmount: 1 ether,
                    amountToClaim: 0 ether,
                    feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                    client: client,
                    ownerPrKey: ownerPrKey
                })
            )
        });
        vm.expectRevert(IEscrowHourly.Escrow__InvalidContractId.selector);
        escrow.deposit(deposit);
        vm.stopPrank();

        vm.prank(owner);
        registry.addToBlacklist(client);
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__BlacklistedAccount.selector);
        escrow.deposit(deposit);
    }

    ERC20Mock new_token = new ERC20Mock();
    address new_contractor = makeAddr("new_contractor");

    function test_deposit_several_contracts() public {
        test_approve();
        // uint256 currentContractId = 1;
        deposit = IEscrowHourly.DepositRequest({
            contractId: uint256(1), //currentContractId
            contractor: contractor,
            paymentToken: address(paymentToken),
            prepaymentAmount: 1 ether,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            escrow: address(escrow),
            expiration: expirationTimestamp,
            signature: getSignatureHourly(
                HourlySignatureParams({
                    contractId: uint256(1),
                    contractor: address(contractor),
                    proxy: address(escrow),
                    token: address(paymentToken),
                    prepaymentAmount: 1 ether,
                    amountToClaim: 0 ether,
                    feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
                    client: client,
                    ownerPrKey: ownerPrKey
                })
            )
        });

        // deposit to the existing contractId
        vm.startPrank(client);
        paymentToken.mint(client, 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        escrow.deposit(deposit);
        vm.stopPrank();
        (
            address _contractor,
            address _paymentToken,
            uint256 _prepaymentAmount,
            uint256 _amountToWithdraw,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractDetails(1);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 2 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 1); //Status.ACTIVE

        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(1, 0); //currentContractId
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(1, 1); //currentContractId
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 1); //Status.ACTIVE
        assertEq(escrow.getWeeksCount(1), 2); //currentContractId

        (uint256 totalDepositAmount,) = computeDepositAndFeeAmount(
            address(registry), address(escrow), 1, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount * 3);

        vm.prank(owner);
        registry.addPaymentToken(address(new_token));
        deposit = IEscrowHourly.DepositRequest({
            contractId: uint256(2),
            contractor: new_contractor,
            paymentToken: address(new_token),
            prepaymentAmount: 1 ether,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrow),
            expiration: expirationTimestamp,
            signature: getSignatureHourly(
                HourlySignatureParams({
                    contractId: uint256(2),
                    contractor: address(new_contractor),
                    proxy: address(escrow),
                    token: address(new_token),
                    prepaymentAmount: 1 ether,
                    amountToClaim: 0 ether,
                    feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                    client: client,
                    ownerPrKey: ownerPrKey
                })
            )
        });
        // create second contract
        vm.startPrank(client);
        new_token.mint(client, 1.03 ether);
        new_token.approve(address(escrow), 1.03 ether);
        escrow.deposit(deposit);
        vm.stopPrank();
        // uint256 currentContractId2 = 2;
        assertEq(escrow.getWeeksCount(2), 1); //currentContractId2

        // deposit to the second contract
        deposit = IEscrowHourly.DepositRequest({
            contractId: uint256(2),
            contractor: new_contractor,
            paymentToken: address(new_token),
            prepaymentAmount: 1 ether,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrow),
            expiration: expirationTimestamp,
            signature: getSignatureHourly(
                HourlySignatureParams({
                    contractId: uint256(2),
                    contractor: address(new_contractor),
                    proxy: address(escrow),
                    token: address(new_token),
                    prepaymentAmount: 1 ether,
                    amountToClaim: 0 ether,
                    feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                    client: client,
                    ownerPrKey: ownerPrKey
                })
            )
        });
        vm.startPrank(client);
        new_token.mint(client, 1.03 ether);
        new_token.approve(address(escrow), 1.03 ether);
        escrow.deposit(deposit);
        vm.stopPrank();
        (_contractor, _paymentToken, _prepaymentAmount, _amountToWithdraw, _feeConfig, _status) =
            escrow.contractDetails(2);
        assertEq(_contractor, new_contractor);
        assertEq(address(_paymentToken), address(new_token));
        assertEq(_prepaymentAmount, 2 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 1); //Status.ACTIVE
        assertEq(escrow.getWeeksCount(2), 2);

        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount * 3);
        assertEq(new_token.balanceOf(address(escrow)), totalDepositAmount * 2);
    }

    function test_deposit_reverts_ContractorMismatch() public {
        test_deposit_prepayment();
        deposit = IEscrowHourly.DepositRequest({
            contractId: uint256(1),
            contractor: address(this),
            paymentToken: address(paymentToken),
            prepaymentAmount: 1 ether,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrow),
            expiration: expirationTimestamp,
            signature: getSignatureHourly(
                HourlySignatureParams({
                    contractId: uint256(1),
                    contractor: address(this),
                    proxy: address(escrow),
                    token: address(paymentToken),
                    prepaymentAmount: 1 ether,
                    amountToClaim: 0 ether,
                    feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                    client: client,
                    ownerPrKey: ownerPrKey
                })
            )
        });
        vm.startPrank(client);
        paymentToken.mint(client, 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        vm.expectRevert(IEscrow.Escrow__ContractorMismatch.selector);
        escrow.deposit(deposit);
        vm.stopPrank();
    }

    function test_deposit_reverts_PaymentTokenMismatch() public {
        test_deposit_prepayment();
        newPaymentToken = new ERC20Mock();
        vm.prank(owner);
        registry.addPaymentToken(address(newPaymentToken));

        deposit = IEscrowHourly.DepositRequest({
            contractId: uint256(1),
            contractor: contractor,
            paymentToken: address(newPaymentToken),
            prepaymentAmount: 1 ether,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrow),
            expiration: expirationTimestamp,
            signature: getSignatureHourly(
                HourlySignatureParams({
                    contractId: uint256(1),
                    contractor: address(contractor),
                    proxy: address(escrow),
                    token: address(newPaymentToken),
                    prepaymentAmount: 1 ether,
                    amountToClaim: 0 ether,
                    feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                    client: client,
                    ownerPrKey: ownerPrKey
                })
            )
        });
        vm.startPrank(client);
        paymentToken.mint(client, 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        vm.expectRevert(IEscrow.Escrow__PaymentTokenMismatch.selector);
        escrow.deposit(deposit);
        vm.stopPrank();
    }

    function test_deposit_reverts_NotSetFeeManager() public {
        EscrowHourly escrow2 = new EscrowHourly();
        MockRegistry registry2 = new MockRegistry(owner);
        ERC20Mock paymentToken2 = new ERC20Mock();
        EscrowFeeManager feeManager2 = new EscrowFeeManager(address(adminManager), 300, 500);

        vm.prank(owner);
        registry2.addPaymentToken(address(paymentToken2));
        escrow2.initialize(client, address(adminManager), address(registry2));

        uint256 depositAmount = 1 ether;
        uint256 totalDepositAmount = 1.03 ether;
        deposit = IEscrowHourly.DepositRequest({
            contractId: 1,
            contractor: contractor,
            paymentToken: address(paymentToken2),
            prepaymentAmount: 0,
            amountToClaim: depositAmount,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrow2),
            expiration: expirationTimestamp,
            signature: getSignatureHourly(
                HourlySignatureParams({
                    contractId: uint256(1),
                    contractor: address(contractor),
                    proxy: address(escrow2),
                    token: address(paymentToken2),
                    prepaymentAmount: 0 ether,
                    amountToClaim: depositAmount,
                    feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                    client: client,
                    ownerPrKey: ownerPrKey
                })
            )
        });

        vm.startPrank(address(client));
        paymentToken2.mint(address(client), totalDepositAmount);
        paymentToken2.approve(address(escrow2), totalDepositAmount);
        vm.expectRevert(IEscrow.Escrow__NotSetFeeManager.selector);
        escrow2.deposit(deposit);
        vm.stopPrank();

        vm.prank(owner);
        registry2.updateFeeManager(address(feeManager2));
        vm.startPrank(client);
        escrow2.deposit(deposit);
        vm.stopPrank();

        vm.prank(owner);
        registry2.updateFeeManager(address(0));

        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__NotSetFeeManager.selector);
        escrow2.claim(1, 0);
    }

    function test_deposit_amountToClaim() public {
        escrow.initialize(client, address(adminManager), address(registry));
        uint256 currentContractId = 1;
        // Generate hash using contract function
        bytes32 depositHash = escrow.getDepositHash(
            client,
            currentContractId,
            contractor,
            address(paymentToken),
            0 ether, // prepaymentAmount
            1 ether, // amountToClaim
            Enums.FeeConfig.CLIENT_COVERS_ONLY,
            expirationTimestamp
        );

        // Sign the hash using admin's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrKey, depositHash);
        bytes memory _signature = abi.encodePacked(r, s, v);

        // Create deposit request with signature
        deposit = IEscrowHourly.DepositRequest({
            contractId: currentContractId,
            contractor: contractor,
            paymentToken: address(paymentToken),
            prepaymentAmount: 0,
            amountToClaim: 1 ether,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrow),
            expiration: expirationTimestamp,
            signature: _signature
        });

        // Simulate client deposit transaction
        vm.startPrank(client);
        paymentToken.mint(client, 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        vm.expectEmit(true, true, true, true);
        emit Deposited(client, 1, 0, 1.03 ether, contractor);
        escrow.deposit(deposit);
        vm.stopPrank();

        // Contract-level assertions
        (
            address _contractor,
            address _paymentToken,
            uint256 _prepaymentAmount,
            uint256 _amountToWithdraw,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 3); //Status.APPROVED

        // Week-level assertions
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, 0);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        // Validate deposit amount including fees
        (uint256 totalDepositAmount,) = computeDepositAndFeeAmount(
            address(registry), address(escrow), 1, client, _amountToClaim, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        // assertEq(escrow.getWeeksCount(currentContractId), 1);
    }

    function test_deposit_reverts_InvalidSignature() public {
        escrow.initialize(client, address(adminManager), address(registry));
        deposit = IEscrowHourly.DepositRequest({
            contractId: uint256(1),
            contractor: contractor,
            paymentToken: address(paymentToken),
            prepaymentAmount: 0,
            amountToClaim: 1 ether,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrow),
            expiration: expirationTimestamp,
            signature: abi.encodePacked("invalidSignature") // Set an intentionally invalid signature
         });
        vm.startPrank(client);
        paymentToken.mint(client, 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        vm.expectRevert(IEscrow.Escrow__InvalidSignature.selector);
        escrow.deposit(deposit);
        vm.stopPrank();
    }

    function test_deposit_reverts_InvalidSignature_DifferentSigner() public {
        escrow.initialize(client, address(adminManager), address(registry));
        (, uint256 fakeAdminPrKey) = makeAddrAndKey("fakeAdmin");
        bytes32 fakeSignedHash = ECDSA.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    client,
                    uint256(1),
                    contractor,
                    address(paymentToken),
                    uint256(1 ether),
                    uint256(0),
                    Enums.FeeConfig.CLIENT_COVERS_ALL,
                    expirationTimestamp,
                    address(escrow)
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(fakeAdminPrKey, fakeSignedHash);
        bytes memory fakeSignature = abi.encodePacked(r, s, v);
        deposit = IEscrowHourly.DepositRequest({
            contractId: uint256(1),
            contractor: contractor,
            paymentToken: address(paymentToken),
            prepaymentAmount: 0,
            amountToClaim: 1 ether,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrow),
            expiration: expirationTimestamp,
            signature: fakeSignature
        });
        vm.startPrank(client);
        paymentToken.mint(client, 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        vm.expectRevert(IEscrow.Escrow__InvalidSignature.selector);
        escrow.deposit(deposit);
        vm.stopPrank();
    }

    function test_deposit_reverts_AuthorizationExpired() public {
        escrow.initialize(client, address(adminManager), address(registry));
        deposit = IEscrowHourly.DepositRequest({
            contractId: uint256(1),
            contractor: contractor,
            paymentToken: address(paymentToken),
            prepaymentAmount: 0,
            amountToClaim: 1 ether,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrow),
            expiration: expirationTimestamp,
            signature: getSignatureHourly(
                HourlySignatureParams({
                    contractId: uint256(1),
                    contractor: address(contractor),
                    proxy: address(escrow),
                    token: address(paymentToken),
                    prepaymentAmount: 0 ether,
                    amountToClaim: 1 ether,
                    feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                    client: client,
                    ownerPrKey: ownerPrKey
                })
            )
        });
        skip(4 hours);
        vm.startPrank(client);
        paymentToken.mint(client, 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        vm.expectRevert(IEscrow.Escrow__AuthorizationExpired.selector);
        escrow.deposit(deposit);
        vm.stopPrank();
    }

    function test_deposit_revertsContractIdAlreadyExists() public {
        // Initialize the escrow contract
        escrow.initialize(client, address(adminManager), address(registry));

        // Ensure the contract is properly initialized
        assertTrue(escrow.initialized());

        uint256 contractId = 1;

        // Compute the storage slot for `paymentToken` in `contractDetails[contractId]`
        bytes32 baseSlot = bytes32(uint256(3)); // Base slot for `contractDetails`
        bytes32 mappingSlot = keccak256(abi.encodePacked(contractId, baseSlot)); // Slot for the mapping key
        bytes32 paymentTokenSlot = bytes32(uint256(mappingSlot) + 1); // Offset for `paymentToken`

        // struct ContractDetails {
        //     address contractor; // slot offset: 0
        //     address paymentToken; // slot offset: 1
        //     Enums.FeeConfig feeConfig; // slot offset: 2
        //     uint256 prepaymentAmount; // slot offset: 3
        // }

        // Simulate a pre-existing contract by setting `paymentToken` in `contractDetails`
        vm.store(address(escrow), paymentTokenSlot, bytes32(uint256(uint160(address(paymentToken)))));

        // Prepare a deposit request
        deposit = IEscrowHourly.DepositRequest({
            contractId: contractId,
            contractor: contractor,
            paymentToken: address(paymentToken),
            prepaymentAmount: 1 ether,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrow),
            expiration: expirationTimestamp,
            signature: getSignatureHourly(
                HourlySignatureParams({
                    contractId: contractId,
                    contractor: address(contractor),
                    proxy: address(escrow),
                    token: address(paymentToken),
                    prepaymentAmount: 1 ether,
                    amountToClaim: 0 ether,
                    feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                    client: client,
                    ownerPrKey: ownerPrKey
                })
            )
        });

        // Start acting as the client
        vm.startPrank(client);

        // Mint and approve payment token
        paymentToken.mint(client, 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);

        // Expect revert due to pre-existing contract ID
        vm.expectRevert(IEscrow.Escrow__ContractIdAlreadyExists.selector);
        escrow.deposit(deposit);

        // Stop acting as the client
        vm.stopPrank();
    }

    ////////////////////////////////////////////
    //             approve tests              //
    ////////////////////////////////////////////

    function test_approve() public {
        test_deposit_prepayment();

        uint256 currentContractId = 1;
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = computeDepositAndFeeAmount(
            address(registry), address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (
            address _contractor,
            address _paymentToken,
            uint256 _prepaymentAmount,
            ,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 1); //Status.ACTIVE

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 1); //Status.ACTIVE
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        uint256 amountToMint = 1.03 ether;
        uint256 amountApprove = 1 ether;
        vm.startPrank(client);
        paymentToken.mint(client, amountToMint);
        paymentToken.approve(address(escrow), amountToMint);
        vm.expectEmit(true, true, true, true);
        emit Approved(client, currentContractId, weekId, amountApprove, contractor);
        escrow.approve(currentContractId, weekId, amountApprove, contractor);
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId);
        // assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.APPROVED
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + totalDepositAmount); //amountApprove+fee
    }

    function test_approve_with_requestReturn() public {
        test_deposit_prepayment();
        uint256 currentContractId = 1;
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = computeDepositAndFeeAmount(
            address(registry), address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 1); //Status.ACTIVE
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        vm.prank(client);
        escrow.requestReturn(currentContractId);
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED

        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 1); //Status.ACTIVE

        uint256 amountToMint = 1.03 ether;
        uint256 amountApprove = 1 ether;
        vm.startPrank(client);
        paymentToken.mint(client, amountToMint);
        paymentToken.approve(address(escrow), amountToMint);
        vm.expectEmit(true, true, true, true);
        emit Approved(client, currentContractId, weekId, amountApprove, contractor);
        escrow.approve(currentContractId, weekId, amountApprove, contractor);
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.stopPrank();
    }

    function test_adminApprove_prepayment_equal_amount_to_approve() public {
        test_deposit_prepayment();

        uint256 currentContractId = 1;
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = computeDepositAndFeeAmount(
            address(registry), address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (
            address _contractor,
            address _paymentToken,
            uint256 _prepaymentAmount,
            uint256 _amountToWithdraw,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 1); //Status.ACTIVE

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 1); //Status.ACTIVE
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        uint256 amountApprove = 1 ether;
        address notOwner = address(0x123);
        bytes memory expectedRevertData = abi.encodeWithSelector(IEscrow.Escrow__UnauthorizedAccount.selector, notOwner);
        vm.prank(notOwner);
        vm.expectRevert(expectedRevertData);
        escrow.adminApprove(currentContractId, weekId, amountApprove, contractor, false);

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit Approved(owner, currentContractId, weekId, amountApprove, contractor);
        escrow.adminApprove(currentContractId, weekId, amountApprove, contractor, false);
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, amountApprove);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether - amountApprove); //0
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //prepaymentAmount+fee
    }

    function test_adminApprove_prepayment_bigger_amount_to_approve() public {
        test_deposit_prepayment();

        uint256 currentContractId = 1;
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = computeDepositAndFeeAmount(
            address(registry), address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (
            address _contractor,
            address _paymentToken,
            uint256 _prepaymentAmount,
            uint256 _amountToWithdraw,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 1); //Status.ACTIVE

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 1); //Status.ACTIVE
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        uint256 amountApprove = 0.5 ether;
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit Approved(owner, currentContractId, weekId, amountApprove, contractor);
        escrow.adminApprove(currentContractId, weekId, amountApprove, contractor, false);
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, amountApprove);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0.5 ether); //_prepaymentAmount - amountApprove
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //prepaymentAmount+fee
    }

    function test_adminApprove_prepayment_less_than_amount_to_approve() public {
        test_deposit_prepayment();

        uint256 currentContractId = 1;
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = computeDepositAndFeeAmount(
            address(registry), address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (
            address _contractor,
            address _paymentToken,
            uint256 _prepaymentAmount,
            uint256 _amountToWithdraw,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 1); //Status.ACTIVE

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 1); //Status.ACTIVE
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        uint256 amountApprove = 1.5 ether;
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit Approved(owner, currentContractId, weekId, amountApprove, contractor);
        escrow.adminApprove(currentContractId, weekId, amountApprove, contractor, false);
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, _prepaymentAmount);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0 ether); //0
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //prepaymentAmount+fee
    }

    function test_adminApprove_prepayment_bigger_amount_to_approve_initializeNewWeek_zero_weekId() public {
        test_deposit_prepayment();

        uint256 currentContractId = 1;
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = computeDepositAndFeeAmount(
            address(registry), address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (
            address _contractor,
            address _paymentToken,
            uint256 _prepaymentAmount,
            uint256 _amountToWithdraw,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 1); //Status.ACTIVE

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 1); //Status.ACTIVE
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        uint256 amountApprove = 0.5 ether;
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit Approved(owner, currentContractId, weekId, amountApprove, contractor);
        escrow.adminApprove(currentContractId, weekId, amountApprove, contractor, true);
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, amountApprove);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED
        assertEq(escrow.getWeeksCount(currentContractId), 1);
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0.5 ether); //_prepaymentAmount - amountApprove
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //prepaymentAmount+fee
    }

    function test_adminApprove_prepayment_bigger_amount_to_approve_initializeNewWeek() public {
        test_deposit_prepayment();

        uint256 currentContractId = 1;
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = computeDepositAndFeeAmount(
            address(registry), address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (
            address _contractor,
            address _paymentToken,
            uint256 _prepaymentAmount,
            uint256 _amountToWithdraw,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 1); //Status.ACTIVE

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 1); //Status.ACTIVE
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        uint256 amountApprove = 0.5 ether;
        weekId = escrow.getWeeksCount(currentContractId);
        vm.startPrank(owner);
        vm.expectRevert(IEscrowHourly.Escrow__InvalidWeekId.selector);
        escrow.adminApprove(currentContractId, weekId, amountApprove, contractor, false);
        vm.expectRevert(IEscrow.Escrow__InvalidAmount.selector);
        escrow.adminApprove(currentContractId, weekId, 0, contractor, true);
        vm.expectEmit(true, true, true, true);
        emit Approved(owner, currentContractId, weekId, amountApprove, contractor);
        escrow.adminApprove(currentContractId, weekId, amountApprove, contractor, true);
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, amountApprove);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED
        assertEq(escrow.getWeeksCount(currentContractId), 2);
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0.5 ether); //_prepaymentAmount - amountApprove
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //prepaymentAmount+fee
    }

    function test_adminApprove_reverts_InvalidStatusForApprove() public {
        test_requestReturn_whenActive();
        assertEq(paymentToken.balanceOf(address(client)), 0);
        uint256 currentContractId = 1;
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED

        uint256 amountApprove = 1.03 ether;
        vm.startPrank(owner);
        paymentToken.mint(address(client), amountApprove);
        paymentToken.approve(address(escrow), amountApprove);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusForApprove.selector);
        escrow.adminApprove(currentContractId, --weekId, amountApprove, contractor, true);
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.stopPrank();
    }

    function test_adminApprove_reverts_UnauthorizedReceiver() public {
        test_deposit_prepayment();
        uint256 currentContractId = 1;
        (address _contractor,, uint256 _prepaymentAmount,,,) = escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_prepaymentAmount, 1 ether);

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 1); //Status.ACTIVE

        vm.startPrank(owner);
        vm.expectRevert(IEscrow.Escrow__UnauthorizedReceiver.selector);
        escrow.adminApprove(currentContractId, weekId, _prepaymentAmount, owner, false);
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 1); //Status.ACTIVE
        vm.stopPrank();
    }

    function test_approve_reverts_UnauthorizedAccount() public {
        test_deposit_prepayment();
        uint256 currentContractId = 1;
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = computeDepositAndFeeAmount(
            address(registry), address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (
            address _contractor,
            address _paymentToken,
            uint256 _prepaymentAmount,
            ,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 1); //Status.ACTIVE

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 1); //Status.ACTIVE
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        uint256 amountApprove = 1.03 ether;
        vm.startPrank(address(this));
        paymentToken.mint(address(client), amountApprove);
        paymentToken.approve(address(escrow), amountApprove);
        vm.expectRevert(); //IEscrow.Escrow__UnauthorizedAccount.selector
        escrow.approve(currentContractId, weekId, amountApprove, contractor);
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId);
        // assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 1); //Status.ACTIVE
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);

        assertFalse(registry.blacklist(address(client)));
        vm.prank(owner);
        registry.addToBlacklist(client);
        assertTrue(registry.blacklist(address(client)));

        vm.startPrank(client);
        paymentToken.mint(address(client), amountApprove);
        paymentToken.approve(address(escrow), amountApprove);
        vm.expectRevert(IEscrow.Escrow__BlacklistedAccount.selector);
        escrow.approve(currentContractId, weekId, amountApprove, contractor);
        vm.stopPrank();
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
    }

    function test_approve_reverts_InvalidStatusForApprove() public {
        test_deposit_amountToClaim();
        uint256 currentContractId = 1;
        assertEq(currentContractId, 1);
        (address _contractor, address _paymentToken, uint256 _prepaymentAmount,,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_status), 3); //Status.APPROVED
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        uint256 amountApprove = 1.03 ether;
        vm.startPrank(client);
        paymentToken.mint(address(client), amountApprove);
        paymentToken.approve(address(escrow), amountApprove);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusForApprove.selector);
        escrow.approve(currentContractId, weekId, amountApprove, contractor);
        (_amountToClaim,) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, 1 ether);
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_status), 3); //Status.APPROVED
        vm.stopPrank();
    }

    function test_approve_reverts_UnauthorizedReceiver() public {
        test_deposit_prepayment();

        uint256 currentContractId = 1;
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = computeDepositAndFeeAmount(
            address(registry), address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (
            address _contractor,
            address _paymentToken,
            uint256 _prepaymentAmount,
            ,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 1); //Status.ACTIVE

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (uint256 _amountToClaim,) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 0 ether);
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        uint256 amountApprove = 1.03 ether;
        vm.startPrank(client);
        paymentToken.mint(address(client), amountApprove);
        paymentToken.approve(address(escrow), amountApprove);
        vm.expectRevert(IEscrow.Escrow__UnauthorizedReceiver.selector);
        escrow.approve(currentContractId, weekId, amountApprove, address(this));
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.stopPrank();
    }

    function test_approve_reverts_InvalidAmount() public {
        test_deposit_prepayment();

        uint256 currentContractId = 1;
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = computeDepositAndFeeAmount(
            address(registry), address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (
            address _contractor,
            address _paymentToken,
            uint256 _prepaymentAmount,
            ,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 1); //Status.ACTIVE

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (uint256 _amountToClaim,) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 0 ether);
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        uint256 amountApprove = 0 ether;
        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidAmount.selector);
        escrow.approve(currentContractId, weekId, amountApprove, contractor);
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.stopPrank();
    }

    function test_approve_reverts_InvalidWeekId() public {
        test_deposit_prepayment();

        uint256 currentContractId = 1;
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = computeDepositAndFeeAmount(
            address(registry), address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (address _contractor, address _paymentToken, uint256 _prepaymentAmount,,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (uint256 _amountToClaim,) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 0 ether);
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        uint256 amountApprove = 1.03 ether;
        vm.startPrank(client);
        paymentToken.mint(address(client), amountApprove);
        paymentToken.approve(address(escrow), amountApprove);
        vm.expectRevert(IEscrowHourly.Escrow__InvalidWeekId.selector);
        escrow.approve(currentContractId, ++weekId, amountApprove, contractor);
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.stopPrank();
    }

    function test_approve_after_resolveDispute_winnerSplit() public {
        test_withdraw_after_claim_partly();
        uint256 contractId = 1;
        uint256 weekId = escrow.getWeeksCount(contractId);
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(contractId, --weekId);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED
        (,,,,, Enums.Status _status) = escrow.contractDetails(contractId);
        assertEq(uint256(_status), 9); //Status.CANCELED

        uint256 amountApprove = 1.03 ether;
        vm.startPrank(client);
        paymentToken.mint(address(client), amountApprove);
        paymentToken.approve(address(escrow), amountApprove);
        escrow.approve(contractId, weekId, 1 ether, contractor);
        vm.stopPrank();

        (, _weekStatus) = escrow.weeklyEntries(contractId, weekId);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED
        (,,,,, _status) = escrow.contractDetails(contractId);
        assertEq(uint256(_status), 3); //Status.APPROVED
    }

    function test_approve_after_resolveDispute_winnerSplit2() public {
        test_resolveDispute_winnerSplit();
        uint256 contractId = 1;
        uint256 weekId = escrow.getWeeksCount(contractId);
        (address _contractor,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(contractId);
        assertEq(_contractor, contractor);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, _prepaymentAmount / 2);
        assertEq(uint256(_status), 7); //Status.RESOLVED

        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(contractId, --weekId);
        assertEq(_amountToClaim, _prepaymentAmount / 2);
        assertEq(uint256(_weekStatus), 7); //Status.RESOLVED

        uint256 amountApprove = 1.03 ether;
        vm.startPrank(client);
        paymentToken.mint(address(client), amountApprove);
        paymentToken.approve(address(escrow), amountApprove);
        escrow.approve(contractId, weekId, 1 ether, contractor);
        vm.stopPrank();

        (, _weekStatus) = escrow.weeklyEntries(contractId, weekId);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED
        (,,,,, _status) = escrow.contractDetails(contractId);
        assertEq(uint256(_status), 3); //Status.APPROVED
    }


    ////////////////////////////////////////////
    //              refill tests              //
    ////////////////////////////////////////////

    function test_refill_prepayment() public {
        test_deposit_amountToClaim();
        uint256 currentContractId = 1;
        // contract level
        (
            address _contractor,
            address _paymentToken,
            uint256 _prepaymentAmount,
            uint256 _amountToWithdraw,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 3); //Status.APPROVED

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        // week level
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        (uint256 totalDepositAmount,) = computeDepositAndFeeAmount(
            address(registry), address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);

        uint256 amountAdditional = 1 ether;
        vm.startPrank(client);
        paymentToken.mint(client, totalDepositAmount);
        paymentToken.approve(address(escrow), totalDepositAmount);
        vm.expectEmit(true, true, true, true);
        emit RefilledPrepayment(client, currentContractId, amountAdditional);
        escrow.refill(currentContractId, weekId, amountAdditional, Enums.RefillType.PREPAYMENT);
        vm.stopPrank();
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, amountAdditional);
        assertEq(uint256(_status), 3); //Status.APPROVED

        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + totalDepositAmount); //2.06 ether
    }

    function test_refill_week_payment() public {
        test_deposit_amountToClaim();
        uint256 currentContractId = 1;
        // contract level
        (
            address _contractor,
            address _paymentToken,
            uint256 _prepaymentAmount,
            uint256 _amountToWithdraw,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 3); //Status.APPROVED

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        // week level
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        (uint256 totalDepositAmount,) = computeDepositAndFeeAmount(
            address(registry), address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);

        uint256 amountAdditional = 1 ether;
        vm.startPrank(client);
        paymentToken.mint(client, totalDepositAmount);
        paymentToken.approve(address(escrow), totalDepositAmount);
        vm.expectEmit(true, true, true, true);
        emit RefilledWeekPayment(client, currentContractId, weekId, amountAdditional);
        escrow.refill(currentContractId, weekId, amountAdditional, Enums.RefillType.WEEK_PAYMENT);
        vm.stopPrank();
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_status), 3); //Status.APPROVED

        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, 1 ether + amountAdditional);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + totalDepositAmount); //2.06 ether
    }

    function test_refill_reverts() public {
        test_deposit_amountToClaim();
        uint256 currentContractId = 1;
        // contract level
        (
            address _contractor,
            address _paymentToken,
            uint256 _prepaymentAmount,
            uint256 _amountToWithdraw,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 3); //Status.APPROVED

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        // week level
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        (uint256 totalDepositAmount,) = computeDepositAndFeeAmount(
            address(registry), address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);

        uint256 amountAdditional = 0 ether;
        uint256 invalidWeekId = escrow.getWeeksCount(currentContractId); // Out-of-bounds
        vm.prank(address(this));
        vm.expectRevert(); // Escrow__UnauthorizedAccount()
        escrow.refill(currentContractId, weekId, 1 ether, Enums.RefillType.PREPAYMENT);
        vm.startPrank(client);
        paymentToken.mint(address(client), amountAdditional);
        paymentToken.approve(address(escrow), amountAdditional);
        vm.expectRevert(IEscrow.Escrow__InvalidAmount.selector);
        escrow.refill(currentContractId, weekId, amountAdditional, Enums.RefillType.WEEK_PAYMENT);
        vm.expectRevert(IEscrowHourly.Escrow__InvalidWeekId.selector);
        escrow.refill(currentContractId, invalidWeekId, 1 ether, Enums.RefillType.WEEK_PAYMENT);
        vm.stopPrank();

        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);

        vm.prank(owner);
        registry.removePaymentToken(address(paymentToken));
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__NotSupportedPaymentToken.selector);
        escrow.refill(currentContractId, weekId, 1 ether, Enums.RefillType.PREPAYMENT);

        vm.prank(owner);
        registry.addToBlacklist(client);
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__BlacklistedAccount.selector);
        escrow.refill(currentContractId, weekId, 1 ether, Enums.RefillType.PREPAYMENT);
        vm.prank(owner);
        registry.removeFromBlacklist(client);
        vm.prank(client);
        vm.expectRevert(); //TransferFromFailed
        escrow.refill(currentContractId, weekId, 1 ether, Enums.RefillType.PREPAYMENT);
    }

    ////////////////////////////////////////////
    //              claim tests               //
    ////////////////////////////////////////////

    function test_claim_clientCoversOnly() public {
        test_approve();
        uint256 currentContractId = 1;
        (
            address _contractor,
            address _paymentToken,
            uint256 _prepaymentAmount,
            ,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 1); //Status.ACTIVE

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        (uint256 totalDepositAmount, uint256 feeApplied) = computeDepositAndFeeAmount(
            address(registry), address(escrow), 1, client, _prepaymentAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );

        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(contractor)), 0 ether);

        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) = computeClaimableAndFeeAmount(
            address(registry), address(escrow), 1, contractor, _amountToClaim, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(feeApplied, clientFee);

        vm.startPrank(contractor);
        vm.expectEmit(true, true, true, true);
        emit Claimed(contractor, 1, weekId, claimAmount, feeAmount, client);
        escrow.claim(1, weekId); //currentContractId

        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), feeAmount + clientFee);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);

        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(1);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 4); //Status.COMPLETED

        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(1, weekId);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED
        vm.stopPrank();
    }

    function test_claim_clientCoversAll() public {
        MockUSDT usdt = new MockUSDT();
        vm.prank(owner);
        registry.addPaymentToken(address(usdt));
        uint256 currentContractId = 1;
        uint256 depositAmount = 1e6;
        uint256 depositAmountAndFee = 1.08e6;
        deposit = IEscrowHourly.DepositRequest({
            contractId: currentContractId,
            contractor: contractor,
            paymentToken: address(usdt),
            prepaymentAmount: 0 ether,
            amountToClaim: depositAmount,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            escrow: address(escrow),
            expiration: expirationTimestamp,
            signature: getSignatureHourly(
                HourlySignatureParams({
                    contractId: currentContractId,
                    contractor: address(contractor),
                    proxy: address(escrow),
                    token: address(usdt),
                    prepaymentAmount: 0 ether,
                    amountToClaim: depositAmount,
                    feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
                    client: client,
                    ownerPrKey: ownerPrKey
                })
            )
        });

        escrow.initialize(client, address(adminManager), address(registry));
        vm.startPrank(client);
        usdt.mint(client, depositAmountAndFee);
        usdt.approve(address(escrow), depositAmountAndFee);
        escrow.deposit(deposit);
        vm.stopPrank();
        uint256 weekId = escrow.getWeeksCount(1);
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(1, --weekId);
        assertEq(_amountToClaim, depositAmount);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED
        // assertEq(currentContractId, 1);
        (, address _paymentToken, uint256 _prepaymentAmount,, Enums.FeeConfig _feeConfig, Enums.Status _status) =
            escrow.contractDetails(1);
        assertEq(address(_paymentToken), address(usdt));
        assertEq(_prepaymentAmount, 0);
        assertEq(uint256(_feeConfig), 0); //Enums.Enums.FeeConfig.CLIENT_COVERS_ALL
        assertEq(uint256(_status), 3); //Status.APPROVED

        assertEq(usdt.balanceOf(address(escrow)), depositAmountAndFee);
        assertEq(usdt.balanceOf(address(treasury)), 0);
        assertEq(usdt.balanceOf(address(client)), 0);
        assertEq(usdt.balanceOf(address(contractor)), 0);

        (uint256 claimAmount, uint256 contractorFee, uint256 clientFee) = computeClaimableAndFeeAmount(
            address(registry), address(escrow), 1, contractor, 1e6, Enums.FeeConfig.CLIENT_COVERS_ALL
        ); //depositAmount=1e6

        vm.prank(contractor);
        escrow.claim(1, weekId);

        assertEq(usdt.balanceOf(address(escrow)), 0);
        assertEq(usdt.balanceOf(address(treasury)), contractorFee + clientFee);
        assertEq(usdt.balanceOf(address(client)), 0);
        assertEq(usdt.balanceOf(address(contractor)), claimAmount);

        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(1, weekId);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED
        (,,,,, _status) = escrow.contractDetails(1);
        assertEq(uint256(_status), 4); //Status.COMPLETED
    }

    function test_claim_whenResolveDispute_winnerContractor() public {
        test_resolveDispute_winnerContractor();
        uint256 currentContractId = 1;
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 7); //Status.RESOLVED
        (uint256 _amountToClaim,) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 1 ether);

        uint256 depositAmount = 1 ether;
        uint256 depositAmountAndFee = 1.03 ether;

        assertEq(paymentToken.balanceOf(address(escrow)), depositAmountAndFee);
        assertEq(paymentToken.balanceOf(address(treasury)), 0);
        assertEq(paymentToken.balanceOf(address(contractor)), 0);
        assertEq(paymentToken.balanceOf(address(client)), 0);

        vm.prank(client);
        vm.expectRevert();
        escrow.withdraw(currentContractId);

        (uint256 claimAmount, uint256 contractorFee, uint256 clientFee) = computeClaimableAndFeeAmount(
            address(registry), address(escrow), 1, contractor, depositAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );

        vm.prank(contractor);
        escrow.claim(currentContractId, weekId);

        assertEq(
            paymentToken.balanceOf(address(escrow)), depositAmountAndFee - (claimAmount + contractorFee + clientFee)
        );
        assertEq(paymentToken.balanceOf(address(treasury)), contractorFee + clientFee);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0);

        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_status), 4); //Status.COMPLETED
    }

    function test_claim_whenResolveDispute_winnerSplit() public {
        test_resolveDispute_winnerSplit();
        uint256 currentContractId = 1;
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 0.5 ether);
        assertEq(uint256(_status), 7); //Status.RESOLVED

        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, --weekId); // todo
            // _weekStatus
        assertEq(_amountToClaim, 0.5 ether);
        assertEq(uint256(_weekStatus), 7); //Status.RESOLVED

        (uint256 totalDepositAmount, uint256 feeAmount) = computeDepositAndFeeAmount(
            address(registry),
            address(escrow),
            currentContractId,
            client,
            _amountToWithdraw,
            Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + feeAmount + _amountToClaim);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (, uint256 initialFeeAmount) = computeDepositAndFeeAmount(
            address(registry), address(escrow), 1, client, _prepaymentAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        escrow.withdraw(currentContractId);

        (,, _prepaymentAmount, _amountToWithdraw,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0.5 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 9); //Status.CANCELED

        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, 0.5 ether);
        assertEq(uint256(_weekStatus), 7); //Status.RESOLVED

        assertEq(paymentToken.balanceOf(address(escrow)), 0.5 ether);
        assertEq(paymentToken.balanceOf(address(client)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee);

        uint256 claimAmount;
        (claimAmount, feeAmount,) = computeClaimableAndFeeAmount(
            address(registry), address(escrow), 1, contractor, _amountToClaim, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );

        vm.startPrank(contractor);
        escrow.claim(currentContractId, weekId);

        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_status), 4); //Status.COMPLETED

        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED
        vm.stopPrank();

        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee + feeAmount);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);
    }

    function test_claim_whenResolveDispute_winnerSplit_reverts_NotApproved() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = 1;
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED

        (uint256 _amountToClaim,) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 0 ether);

        vm.prank(owner);
        escrow.resolveDispute(currentContractId, weekId, Enums.Winner.SPLIT, _prepaymentAmount / 2, 0);

        vm.startPrank(contractor);
        vm.expectRevert(IEscrow.Escrow__NotApproved.selector);
        escrow.claim(currentContractId, weekId);
    }

    function test_claim_reverts() public {
        test_deposit_prepayment();

        uint256 currentContractId = 1;
        (address _contractor, address _paymentToken, uint256 _prepaymentAmount,,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 1); //Status.ACTIVE

        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusToClaim.selector);
        escrow.claim(currentContractId, weekId);

        uint256 amountToMint = 1.03 ether;
        uint256 amountApprove = 1 ether;
        vm.startPrank(client);
        paymentToken.mint(client, amountToMint);
        paymentToken.approve(address(escrow), amountToMint);
        vm.expectEmit(true, true, true, true);
        emit Approved(client, currentContractId, weekId, amountApprove, contractor);
        escrow.approve(currentContractId, weekId, amountApprove, contractor);
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, amountApprove);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.stopPrank();

        vm.prank(address(this));
        vm.expectRevert(); //IEscrow.Escrow__UnauthorizedAccount.selector
        escrow.claim(currentContractId, weekId);
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, amountApprove);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE

        MockRegistry mockRegistry = new MockRegistry(owner);
        vm.startPrank(owner);
        mockRegistry.addPaymentToken(address(paymentToken));
        // mockRegistry.setTreasury(treasury);
        mockRegistry.updateFeeManager(address(feeManager));
        escrow.updateRegistry(address(mockRegistry));
        vm.stopPrank();

        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.claim(currentContractId, weekId);
    }

    function test_claimAll() public {
        test_approve();
        // uint256 prepaymentAmount = 1.03 ether;
        uint256 amountToMint = 1.03 ether;
        uint256 amountApprove = 1 ether;

        assertEq(paymentToken.balanceOf(address(escrow)), amountToMint + amountToMint); //prepaymentAmount+amountToMint=2.06
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);

        uint256 currentContractId = 1;
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        assertEq(weekId, 1);

        vm.startPrank(address(client));
        paymentToken.mint(address(client), amountToMint);
        paymentToken.approve(address(escrow), amountToMint);
        escrow.deposit(deposit);
        assertEq(paymentToken.balanceOf(address(escrow)), amountToMint * 3);
        currentContractId = 1;
        assertEq(currentContractId, 1);
        weekId = escrow.getWeeksCount(currentContractId);
        assertEq(weekId, 2);
        vm.stopPrank();

        // vm.prank(contractor);
        // vm.expectRevert(IEscrow.Escrow__InvalidStatusToClaim.selector);
        // escrow.claimAll(currentContractId, 1, 1);

        vm.startPrank(address(client));
        paymentToken.mint(address(client), amountToMint);
        paymentToken.approve(address(escrow), amountToMint);
        escrow.approve(currentContractId, 1, amountApprove, contractor);
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, amountApprove * 2);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, 1);
        assertEq(_amountToClaim, amountApprove);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED
        vm.stopPrank();

        assertEq(paymentToken.balanceOf(address(escrow)), amountToMint * 4);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(contractor)), 0 ether);

        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) = computeClaimableAndFeeAmount(
            address(registry), address(escrow), 1, contractor, amountApprove, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );

        assertEq(escrow.getWeeksCount(currentContractId), 2);
        uint256 startWeekId = 0;
        uint256 endWeekId = 1;

        vm.prank(address(this));
        vm.expectRevert(abi.encodeWithSelector(IEscrow.Escrow__UnauthorizedAccount.selector, address(this)));
        escrow.claimAll(currentContractId, startWeekId, endWeekId);

        vm.startPrank(contractor);
        vm.expectRevert(IEscrow.Escrow__InvalidRange.selector);
        escrow.claimAll(currentContractId, 1, 0);
        vm.expectRevert(IEscrow.Escrow__OutOfRange.selector);
        escrow.claimAll(currentContractId, 0, 2);
        vm.expectEmit(true, true, true, true);
        emit BulkClaimed(
            contractor, currentContractId, startWeekId, endWeekId, claimAmount * 2, feeAmount * 2, clientFee * 2, client
        );
        escrow.claimAll(currentContractId, startWeekId, endWeekId);
        vm.stopPrank();

        (,,,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 4); //Status.COMPLETED

        assertEq(paymentToken.balanceOf(address(escrow)), amountToMint * 2);
        assertEq(
            paymentToken.balanceOf(address(escrow)), (1.03 ether * 4) - claimAmount * 2 - feeAmount * 2 - clientFee * 2
        );
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount * 2);
        assertEq(paymentToken.balanceOf(address(treasury)), feeAmount * 2 + clientFee * 2);
    }

    function test_claimAll_full_amount() public {
        MockUSDT usdt = new MockUSDT();
        vm.prank(owner);
        registry.addPaymentToken(address(usdt));
        uint256 currentContractId = 1;
        uint256 depositAmount = 1e6;
        uint256 depositAmountAndFee = 1.03e6;
        deposit = IEscrowHourly.DepositRequest({
            contractId: currentContractId,
            contractor: contractor,
            paymentToken: address(usdt),
            prepaymentAmount: 0 ether,
            amountToClaim: depositAmount,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrow),
            expiration: expirationTimestamp,
            signature: getSignatureHourly(
                HourlySignatureParams({
                    contractId: currentContractId,
                    contractor: address(contractor),
                    proxy: address(escrow),
                    token: address(usdt),
                    prepaymentAmount: 0 ether,
                    amountToClaim: depositAmount,
                    feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                    client: client,
                    ownerPrKey: ownerPrKey
                })
            )
        });

        escrow.initialize(client, address(adminManager), address(registry));
        // make a deposit with prepaymentAmount == 0
        vm.startPrank(client);
        usdt.mint(client, depositAmountAndFee);
        usdt.approve(address(escrow), depositAmountAndFee);
        escrow.deposit(deposit);
        vm.stopPrank();
        currentContractId = 1;
        // uint256 weekId1 = escrow.getWeeksCount(currentContractId);
        assertEq(currentContractId, 1);
        (
            address _contractor,
            address _paymentToken,
            uint256 _prepaymentAmount,
            ,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(usdt));
        assertEq(_prepaymentAmount, 0);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 3); //Status.APPROVED

        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, 0); //--weekId1
        assertEq(_amountToClaim, depositAmount);
        assertEq(escrow.getWeeksCount(currentContractId), 1);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        assertEq(usdt.balanceOf(address(escrow)), depositAmountAndFee); //1.03e6
        assertEq(usdt.balanceOf(address(treasury)), 0 ether);
        assertEq(usdt.balanceOf(address(client)), 0 ether);
        assertEq(usdt.balanceOf(address(contractor)), 0 ether);

        // 2d deposit
        vm.startPrank(client);
        usdt.mint(client, depositAmountAndFee);
        usdt.approve(address(escrow), depositAmountAndFee);
        escrow.deposit(deposit);
        vm.stopPrank();

        // uint256 weekId2 = escrow.getWeeksCount(currentContractId);
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, 1); //--weekId2
        assertEq(_amountToClaim, depositAmount);
        assertEq(escrow.getWeeksCount(currentContractId), 2);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        assertEq(usdt.balanceOf(address(escrow)), depositAmountAndFee * 2); //2.06e6
        assertEq(usdt.balanceOf(address(treasury)), 0 ether);
        assertEq(usdt.balanceOf(address(client)), 0 ether);
        assertEq(usdt.balanceOf(address(contractor)), 0 ether);

        // 3rd deposit
        vm.startPrank(client);
        usdt.mint(client, depositAmountAndFee);
        usdt.approve(address(escrow), depositAmountAndFee);
        escrow.deposit(deposit);
        vm.stopPrank();

        // uint256 weekId3 = escrow.getWeeksCount(currentContractId);
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, 2); //--weekId3
        assertEq(_amountToClaim, depositAmount);
        assertEq(escrow.getWeeksCount(currentContractId), 3);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        assertEq(usdt.balanceOf(address(escrow)), depositAmountAndFee * 3); //3.09e6
        assertEq(usdt.balanceOf(address(treasury)), 0 ether);
        assertEq(usdt.balanceOf(address(client)), 0 ether);
        assertEq(usdt.balanceOf(address(contractor)), 0 ether);

        (uint256 claimAmount, uint256 contractorFee, uint256 clientFee) = computeClaimableAndFeeAmount(
            address(registry), address(escrow), 1, contractor, 1e6, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        (claimAmount);

        // uint256 startWeekId = 0;
        // uint256 endWeekId = 2;
        vm.prank(contractor);
        escrow.claimAll(1, 0, 2); //currentContractId, startWeekId, endWeekId

        assertEq(usdt.balanceOf(address(escrow)), 0);
        assertEq(usdt.balanceOf(address(treasury)), contractorFee * 3 + clientFee * 3);
        assertEq(usdt.balanceOf(address(client)), 0 ether);
        assertEq(usdt.balanceOf(address(contractor)), 1e6 * 3 - contractorFee * 3);

        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(1, 0);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(1, 1);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(1, 2);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED

        (,,,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 4); //Status.COMPLETED
    }

    function test_claimAll_twoOfTree_already_claimed() public {
        MockUSDT usdt = new MockUSDT();
        vm.prank(owner);
        registry.addPaymentToken(address(usdt));
        uint256 currentContractId = 1;
        uint256 depositAmount = 1e6;
        uint256 depositAmountAndFee = 1.03e6;
        deposit = IEscrowHourly.DepositRequest({
            contractId: currentContractId,
            contractor: contractor,
            paymentToken: address(usdt),
            prepaymentAmount: 0 ether,
            amountToClaim: depositAmount,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrow),
            expiration: expirationTimestamp,
            signature: getSignatureHourly(
                HourlySignatureParams({
                    contractId: currentContractId,
                    contractor: address(contractor),
                    proxy: address(escrow),
                    token: address(usdt),
                    prepaymentAmount: 0 ether,
                    amountToClaim: depositAmount,
                    feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                    client: client,
                    ownerPrKey: ownerPrKey
                })
            )
        });

        escrow.initialize(client, address(adminManager), address(registry));
        // make a deposit with prepaymentAmount == 0
        vm.startPrank(client);
        usdt.mint(client, depositAmountAndFee);
        usdt.approve(address(escrow), depositAmountAndFee);
        escrow.deposit(deposit);
        vm.stopPrank();
        // uint256 weekId1 = escrow.getWeeksCount(currentContractId);
        (
            address _contractor,
            address _paymentToken,
            uint256 _prepaymentAmount,
            ,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(usdt));
        assertEq(_prepaymentAmount, 0);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 3); //Status.APPROVED

        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, 0); //--weekId1
        assertEq(_amountToClaim, depositAmount);
        assertEq(escrow.getWeeksCount(currentContractId), 1);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        assertEq(usdt.balanceOf(address(escrow)), depositAmountAndFee); //1.03e6
        assertEq(usdt.balanceOf(address(treasury)), 0 ether);
        assertEq(usdt.balanceOf(address(client)), 0 ether);
        assertEq(usdt.balanceOf(address(contractor)), 0 ether);

        // 2d deposit
        vm.startPrank(client);
        usdt.mint(client, depositAmountAndFee);
        usdt.approve(address(escrow), depositAmountAndFee);
        escrow.deposit(deposit);
        vm.stopPrank();

        // uint256 weekId2 = escrow.getWeeksCount(currentContractId);
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, 1); //--weekId2
        assertEq(_amountToClaim, depositAmount);
        assertEq(escrow.getWeeksCount(currentContractId), 2);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        assertEq(usdt.balanceOf(address(escrow)), depositAmountAndFee * 2); //2.06e6
        assertEq(usdt.balanceOf(address(treasury)), 0 ether);
        assertEq(usdt.balanceOf(address(client)), 0 ether);
        assertEq(usdt.balanceOf(address(contractor)), 0 ether);

        // 3rd deposit
        vm.startPrank(client);
        usdt.mint(client, depositAmountAndFee);
        usdt.approve(address(escrow), depositAmountAndFee);
        escrow.deposit(deposit);
        vm.stopPrank();

        // uint256 weekId3 = escrow.getWeeksCount(currentContractId);
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, 2); //--weekId3
        assertEq(_amountToClaim, depositAmount);
        assertEq(escrow.getWeeksCount(currentContractId), 3);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        assertEq(usdt.balanceOf(address(escrow)), depositAmountAndFee * 3); //3.09e6
        assertEq(usdt.balanceOf(address(treasury)), 0 ether);
        assertEq(usdt.balanceOf(address(client)), 0 ether);
        assertEq(usdt.balanceOf(address(contractor)), 0 ether);

        (uint256 claimAmount, uint256 contractorFee, uint256 clientFee) = computeClaimableAndFeeAmount(
            address(registry), address(escrow), 1, contractor, 1e6, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );

        vm.prank(contractor);
        escrow.claim(1, 1); //currentContractId, weekId2

        assertEq(usdt.balanceOf(address(escrow)), depositAmountAndFee * 3 - 1.03e6); //3.09e6
        assertEq(usdt.balanceOf(address(treasury)), contractorFee + clientFee);
        assertEq(usdt.balanceOf(address(client)), 0 ether);
        assertEq(usdt.balanceOf(address(contractor)), claimAmount);

        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(1, 0);
        assertEq(_amountToClaim, 1e6);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(1, 1);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(1, 2);
        assertEq(_amountToClaim, 1e6);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        (claimAmount, contractorFee, clientFee) = computeClaimableAndFeeAmount(
            address(registry), address(escrow), 1, contractor, 1e6, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );

        // uint256 startWeekId = 0;
        // uint256 endWeekId = 2;
        vm.prank(contractor);
        escrow.claimAll(1, 0, 2); //currentContractId, startWeekId, endWeekId

        assertEq(usdt.balanceOf(address(escrow)), 0);
        assertEq(usdt.balanceOf(address(treasury)), (contractorFee + clientFee) * 3);
        assertEq(usdt.balanceOf(address(client)), 0 ether);
        assertEq(usdt.balanceOf(address(contractor)), claimAmount * 3);

        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(1, 0);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(1, 1);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(1, 2);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED
    }

    function test_claimAll_twoOfTree_another_contractor() public {
        MockUSDT usdt = new MockUSDT();
        vm.prank(owner);
        registry.addPaymentToken(address(usdt));
        uint256 depositAmount = 1e6;
        uint256 depositAmountAndFee = 1.03e6;
        deposit = IEscrowHourly.DepositRequest({
            contractId: uint256(1),
            contractor: contractor,
            paymentToken: address(usdt),
            prepaymentAmount: 0 ether,
            amountToClaim: depositAmount,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrow),
            expiration: expirationTimestamp,
            signature: getSignatureHourly(
                HourlySignatureParams({
                    contractId: uint256(1),
                    contractor: address(contractor),
                    proxy: address(escrow),
                    token: address(usdt),
                    prepaymentAmount: 0 ether,
                    amountToClaim: depositAmount,
                    feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                    client: client,
                    ownerPrKey: ownerPrKey
                })
            )
        });

        escrow.initialize(client, address(adminManager), address(registry));
        // uint256 currentContractId = 1;// =0
        // make a deposit with prepaymentAmount == 0
        vm.startPrank(client);
        usdt.mint(client, depositAmountAndFee);
        usdt.approve(address(escrow), depositAmountAndFee);
        escrow.deposit(deposit);
        vm.stopPrank();
        (
            address _contractor,
            address _paymentToken,
            uint256 _prepaymentAmount,
            ,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractDetails(1);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(usdt));
        assertEq(_prepaymentAmount, 0);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 3); //Status.APPROVED

        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(1, 0); //--weekId1
        assertEq(_amountToClaim, depositAmount);
        assertEq(escrow.getWeeksCount(1), 1);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        assertEq(usdt.balanceOf(address(escrow)), depositAmountAndFee); //1.03e6
        assertEq(usdt.balanceOf(address(treasury)), 0 ether);
        assertEq(usdt.balanceOf(address(client)), 0 ether);
        assertEq(usdt.balanceOf(address(contractor)), 0 ether);

        // 2d deposit
        // address new_contractor = makeAddr("new_contractor");
        deposit = IEscrowHourly.DepositRequest({
            contractId: uint256(1),
            contractor: contractor,
            paymentToken: address(usdt),
            prepaymentAmount: 0 ether,
            amountToClaim: 1e6, //depositAmount
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrow),
            expiration: expirationTimestamp,
            signature: getSignatureHourly(
                HourlySignatureParams({
                    contractId: uint256(1),
                    contractor: address(contractor),
                    proxy: address(escrow),
                    token: address(usdt),
                    prepaymentAmount: 0 ether,
                    amountToClaim: 1e6,
                    feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                    client: client,
                    ownerPrKey: ownerPrKey
                })
            )
        });

        vm.startPrank(client);
        usdt.mint(client, depositAmountAndFee);
        usdt.approve(address(escrow), depositAmountAndFee);
        escrow.deposit(deposit); //1, deposit
        vm.stopPrank();

        // uint256 weekId2 = escrow.getWeeksCount(currentContractId);
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(1, 1); //--weekId2

        assertEq(_amountToClaim, depositAmount);
        assertEq(escrow.getWeeksCount(1), 2);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        assertEq(usdt.balanceOf(address(escrow)), depositAmountAndFee * 2); //2.06e6
        assertEq(usdt.balanceOf(address(treasury)), 0 ether);
        assertEq(usdt.balanceOf(address(client)), 0 ether);
        assertEq(usdt.balanceOf(address(contractor)), 0 ether);
        // assertEq(usdt.balanceOf(address(new_contractor)), 0 ether);

        // 3rd deposit
        deposit = IEscrowHourly.DepositRequest({
            contractId: 1,
            contractor: contractor,
            paymentToken: address(usdt),
            prepaymentAmount: 0 ether,
            amountToClaim: 1e6,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrow),
            expiration: expirationTimestamp,
            signature: getSignatureHourly(
                HourlySignatureParams({
                    contractId: uint256(1),
                    contractor: address(contractor),
                    proxy: address(escrow),
                    token: address(usdt),
                    prepaymentAmount: 0 ether,
                    amountToClaim: 1e6,
                    feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                    client: client,
                    ownerPrKey: ownerPrKey
                })
            )
        });
        vm.startPrank(client);
        usdt.mint(client, depositAmountAndFee);
        usdt.approve(address(escrow), depositAmountAndFee);
        escrow.deposit(deposit); //1, deposit
        vm.stopPrank();

        // uint256 weekId3 = escrow.getWeeksCount(currentContractId);
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(1, 2); //--weekId3
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, depositAmount);
        assertEq(escrow.getWeeksCount(1), 3);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        assertEq(usdt.balanceOf(address(escrow)), depositAmountAndFee * 3); //3.09e6
        assertEq(usdt.balanceOf(address(treasury)), 0 ether);
        assertEq(usdt.balanceOf(address(client)), 0 ether);
        assertEq(usdt.balanceOf(address(contractor)), 0 ether);

        (uint256 claimAmount, uint256 contractorFee, uint256 clientFee) = computeClaimableAndFeeAmount(
            address(registry), address(escrow), 1, contractor, 1e6, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );

        // vm.prank(new_contractor);
        // escrow.claim(1, 1); //currentContractId, weekId2
        vm.prank(contractor);
        escrow.claim(1, 1); //currentContractId, weekId2
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(1, 1);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED

        assertEq(usdt.balanceOf(address(escrow)), 1.03e6 * 3 - 1.03e6); //3.09e6
        assertEq(usdt.balanceOf(address(treasury)), contractorFee + clientFee);
        assertEq(usdt.balanceOf(address(client)), 0 ether);
        assertEq(usdt.balanceOf(address(contractor)), claimAmount);

        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(1, 0);
        assertEq(_amountToClaim, 1e6);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(1, 1);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(1, 2);
        assertEq(_amountToClaim, 1e6);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        (claimAmount, contractorFee, clientFee) = computeClaimableAndFeeAmount(
            address(registry), address(escrow), 1, contractor, 1e6, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );

        // uint256 startWeekId = 0;
        // uint256 endWeekId = 2;
        vm.prank(contractor);
        escrow.claimAll(1, 0, 2); //currentContractId, startWeekId, endWeekId

        assertEq(usdt.balanceOf(address(escrow)), 0);
        assertEq(usdt.balanceOf(address(treasury)), (contractorFee + clientFee) * 3);
        assertEq(usdt.balanceOf(address(client)), 0 ether);
        assertEq(usdt.balanceOf(address(contractor)), claimAmount * 3);

        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(1, 0);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(1, 1);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(1, 2);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED
    }

    function test_claimAll_whenResolveDispute_winnerSplit() public {
        test_resolveDispute_winnerSplit();
        uint256 currentContractId = 1;
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 0.5 ether);
        assertEq(uint256(_status), 7); //Status.RESOLVED

        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 0.5 ether);
        assertEq(uint256(_weekStatus), 7); //Status.RESOLVED

        (uint256 totalDepositAmount, uint256 feeAmount) = computeDepositAndFeeAmount(
            address(registry),
            address(escrow),
            currentContractId,
            client,
            _amountToWithdraw,
            Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + feeAmount + _amountToClaim);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (, uint256 initialFeeAmount) = computeDepositAndFeeAmount(
            address(registry), address(escrow), 1, client, _prepaymentAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        escrow.withdraw(currentContractId);

        (,, _prepaymentAmount, _amountToWithdraw,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0.5 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 9); //Status.CANCELED

        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, 0.5 ether);
        assertEq(uint256(_weekStatus), 7); //Status.RESOLVED

        assertEq(paymentToken.balanceOf(address(escrow)), 0.5 ether);
        assertEq(paymentToken.balanceOf(address(client)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee);

        uint256 claimAmount;
        (claimAmount, feeAmount,) = computeClaimableAndFeeAmount(
            address(registry), address(escrow), 1, contractor, _amountToClaim, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );

        vm.startPrank(contractor);
        escrow.claimAll(currentContractId, 0, 0);

        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_status), 4); //Status.COMPLETED

        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, 0);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED
        vm.stopPrank();

        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee + feeAmount);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);
    }

    function test_claim_after_autoApprove_and_refill() public {
        test_adminApprove_prepayment_less_than_amount_to_approve();
        uint256 currentContractId = 1;
        assertEq(currentContractId, 1);
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        // 1st claim after auto approval befor refill
        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) = computeClaimableAndFeeAmount(
            address(registry), address(escrow), 1, contractor, _amountToClaim, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );

        vm.startPrank(contractor);
        escrow.claim(currentContractId, weekId);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED
        vm.stopPrank();

        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_status), 4); //Status.COMPLETED

        (uint256 totalDepositAmount,) = computeDepositAndFeeAmount(
            address(registry), address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount - (claimAmount + feeAmount + clientFee));

        // refill more funds by client
        uint256 amountAdditional = 1 ether;
        vm.startPrank(client);
        paymentToken.mint(client, totalDepositAmount);
        paymentToken.approve(address(escrow), totalDepositAmount);
        escrow.refill(currentContractId, weekId, amountAdditional, Enums.RefillType.WEEK_PAYMENT);
        vm.stopPrank();

        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_status), 3); //Status.APPROVED

        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, amountAdditional);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        (uint256 claimAmount2, uint256 feeAmount2, uint256 clientFee2) = computeClaimableAndFeeAmount(
            address(registry), address(escrow), 1, contractor, _amountToClaim, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );

        // 2d claim that is after refill
        vm.startPrank(contractor);
        escrow.claim(1, weekId); //currentContractId
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount + claimAmount2);
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(1, weekId);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(1);
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_status), 4); //Status.COMPLETED
        vm.stopPrank();

        assertEq(
            paymentToken.balanceOf(address(escrow)),
            (totalDepositAmount - (claimAmount + feeAmount + clientFee))
                - (totalDepositAmount - (claimAmount2 + feeAmount2 + clientFee2))
        );
        assertEq(paymentToken.balanceOf(address(escrow)), 0);
        assertEq(paymentToken.balanceOf(address(treasury)), (feeAmount + clientFee) + (feeAmount2 + clientFee2));
    }

    function test_create_new_week_after_full_claim_previous_one() public {
        test_claim_after_autoApprove_and_refill();
        uint256 currentContractId = 1;
        assertEq(currentContractId, 1);

        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_status), 4); //Status.COMPLETED

        uint256 weekId1 = escrow.getWeeksCount(currentContractId);
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, --weekId1);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED

        vm.startPrank(client);
        paymentToken.mint(client, 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        vm.expectEmit(true, true, true, true);
        emit Deposited(client, 1, 1, 1.03 ether, contractor);
        escrow.deposit(deposit);
        vm.stopPrank();

        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId1);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED
        uint256 weekId2 = escrow.getWeeksCount(currentContractId);
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, --weekId2);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 1); //Status.ACTIVE
        assertEq(paymentToken.balanceOf(address(escrow)), 1.03 ether);
    }

    function test_claim_after_previous_claim() public {
        escrow.initialize(client, address(adminManager), address(registry));
        uint256 currentContractId = 1;
        deposit = IEscrowHourly.DepositRequest({
            contractId: currentContractId,
            contractor: contractor,
            paymentToken: address(paymentToken),
            prepaymentAmount: 0,
            amountToClaim: 1 ether,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrow),
            expiration: expirationTimestamp,
            signature: getSignatureHourly(
                HourlySignatureParams({
                    contractId: currentContractId,
                    contractor: address(contractor),
                    proxy: address(escrow),
                    token: address(paymentToken),
                    prepaymentAmount: 0 ether,
                    amountToClaim: 1 ether,
                    feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                    client: client,
                    ownerPrKey: ownerPrKey
                })
            )
        });
        vm.startPrank(client);
        paymentToken.mint(client, 2.06 ether);
        paymentToken.approve(address(escrow), 2.06 ether);
        vm.expectEmit(true, true, true, true);
        emit Deposited(client, 1, 0, 1.03 ether, contractor);
        // 1st deposit
        escrow.deposit(deposit);
        assertEq(escrow.getWeeksCount(currentContractId), 1);
        uint256 weeksCount = escrow.getWeeksCount(currentContractId);
        uint256 weekId1 = --weeksCount;
        // 2d deposit to the created contractId on previous step
        escrow.deposit(deposit);
        assertEq(escrow.getWeeksCount(currentContractId), 2);
        vm.stopPrank();

        weeksCount = escrow.getWeeksCount(currentContractId);
        uint256 weekId2 = --weeksCount;

        // contract level
        (
            address _contractor,
            address _paymentToken,
            uint256 _prepaymentAmount,
            uint256 _amountToWithdraw,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 3); //Status.APPROVED
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, weekId1);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        (uint256 totalDepositAmount,) = computeDepositAndFeeAmount(
            address(registry), address(escrow), 1, client, _amountToClaim, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + totalDepositAmount); //2.06 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(escrow.getWeeksCount(currentContractId), 2);

        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId2);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        vm.startPrank(contractor);
        escrow.claim(currentContractId, 0);
        (,,,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 3); //Status.APPROVED
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId1);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED

        escrow.claim(currentContractId, 1);
        (,,,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 4); //Status.COMPLETED
        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId2);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED
    }

    ///////////////////////////////////////////
    //           withdraw tests              //
    ///////////////////////////////////////////

    function test_withdraw_whenRefundApprovedByOwner() public {
        test_approveReturn_by_owner();
        uint256 currentContractId = 1;
        (address _contractor,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 1 ether);
        assertEq(uint256(_status), 8); //Status.REFUND_APPROVED
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, 0);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 1); //Status.ACTIVE

        (uint256 totalDepositAmount, uint256 feeAmount) = computeDepositAndFeeAmount(
            address(registry),
            address(escrow),
            currentContractId,
            client,
            _amountToWithdraw,
            Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (, uint256 initialFeeAmount) = computeDepositAndFeeAmount(
            address(registry), address(escrow), 1, client, _prepaymentAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(client, currentContractId, _amountToWithdraw + feeAmount, platformFee);
        escrow.withdraw(currentContractId);

        (,, uint256 _prepaymentAmountAfter, uint256 _amountToWithdrawAfter,, Enums.Status _statusAfter) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmountAfter, 0 ether);
        assertEq(_amountToWithdrawAfter, 0 ether);
        assertEq(uint256(_statusAfter), 9); //Status.CANCELED

        (uint256 _amountAfter, Enums.Status _weekStatusAfter) = escrow.weeklyEntries(1, 0); //currentContractId=1
        assertEq(_amountAfter, 0 ether);
        assertEq(uint256(_weekStatusAfter), 1); //Status.ACTIVE

        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether); //totalDepositAmount-(_amountToWithdraw+feeAmount)
        assertEq(paymentToken.balanceOf(address(client)), _amountToWithdraw + feeAmount); //totalDepositAmount=_amountToWithdraw+feeAmount
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee);
    }

    function test_withdraw_whenRefundApprovedByContractor() public {
        test_approveReturn_by_contractor();
        uint256 currentContractId = 1;
        (address _contractor,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 1 ether);
        assertEq(uint256(_status), 8); //Status.REFUND_APPROVED
        (uint256 _amountToClaim,) = escrow.weeklyEntries(currentContractId, 0);
        assertEq(_amountToClaim, 0 ether);

        (uint256 totalDepositAmount, uint256 feeAmount) = computeDepositAndFeeAmount(
            address(registry),
            address(escrow),
            currentContractId,
            client,
            _amountToWithdraw,
            Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (, uint256 initialFeeAmount) = computeDepositAndFeeAmount(
            address(registry), address(escrow), 1, client, _prepaymentAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(client, currentContractId, _amountToWithdraw + feeAmount, platformFee);
        escrow.withdraw(currentContractId);

        (,, uint256 _prepaymentAmountAfter, uint256 _amountToWithdrawAfter,, Enums.Status _statusAfter) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmountAfter, 0 ether);
        assertEq(_amountToWithdrawAfter, 0 ether);
        assertEq(uint256(_statusAfter), 9); //Status.CANCELED

        (uint256 _amountAfter,) = escrow.weeklyEntries(currentContractId, 0);
        assertEq(_amountAfter, 0 ether);

        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether); //totalDepositAmount-(_amountToWithdraw+feeAmount)
        assertEq(paymentToken.balanceOf(address(client)), totalDepositAmount); //totalDepositAmount=_amountToWithdraw+feeAmount
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee);
    }

    function test_withdraw_whenDisputeResolved() public {
        test_resolveDispute_winnerClient();
        uint256 currentContractId = 1;
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, _prepaymentAmount);
        assertEq(uint256(_status), 7); //Status.RESOLVED

        (uint256 _amountToClaim,) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 0 ether);

        (uint256 totalDepositAmount, uint256 feeAmount) = computeDepositAndFeeAmount(
            address(registry),
            address(escrow),
            currentContractId,
            client,
            _amountToWithdraw,
            Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (, uint256 initialFeeAmount) = computeDepositAndFeeAmount(
            address(registry), address(escrow), 1, client, _prepaymentAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(client, currentContractId, totalDepositAmount, platformFee);
        escrow.withdraw(currentContractId);

        (,, _prepaymentAmount, _amountToWithdraw,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 9); //Status.CANCELED

        (_amountToClaim,) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, 0 ether);

        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee);
    }

    function test_withdraw_whenDisputeResolvedSplit() public {
        test_resolveDispute_winnerSplit();
        uint256 currentContractId = 1;
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, _prepaymentAmount / 2);
        assertEq(uint256(_status), 7); //Status.RESOLVED

        (uint256 _amountToClaim,) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, _prepaymentAmount / 2);

        (uint256 totalDepositAmount, uint256 feeAmount) = computeDepositAndFeeAmount(
            address(registry),
            address(escrow),
            currentContractId,
            client,
            _amountToWithdraw,
            Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + feeAmount + _amountToClaim);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (, uint256 initialFeeAmount) = computeDepositAndFeeAmount(
            address(registry), address(escrow), 1, client, _prepaymentAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(client, currentContractId, totalDepositAmount, platformFee);
        escrow.withdraw(currentContractId);

        (,, _prepaymentAmount, _amountToWithdraw,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0.5 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 9); //Status.CANCELED

        (_amountToClaim,) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, 0.5 ether);

        assertEq(paymentToken.balanceOf(address(escrow)), 0.5 ether);
        assertEq(paymentToken.balanceOf(address(client)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee);
    }

    function test_withdraw_after_claim_partly() public {
        test_resolveDispute_winnerSplit();
        uint256 currentContractId = 1;
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, _prepaymentAmount / 2);
        assertEq(uint256(_status), 7); //Status.RESOLVED

        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, _prepaymentAmount / 2);
        assertEq(uint256(_weekStatus), 7); //Status.RESOLVED

        (uint256 claimAmount, uint256 contractorFeeAmount, uint256 clientFee) = computeClaimableAndFeeAmount(
            address(registry), address(escrow), 1, contractor, 0.5 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        (clientFee);

        vm.prank(contractor);
        escrow.claim(currentContractId, weekId);

        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED

        (,,,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 4); //Status.COMPLETED

        (uint256 withdrawAmount, uint256 clientFeeAmount) = computeDepositAndFeeAmount(
            address(registry), address(escrow), 1, client, 0.5 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );

        vm.prank(client);
        escrow.withdraw(currentContractId);

        (,,,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 9); //Status.CANCELED

        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);
        assertEq(paymentToken.balanceOf(address(client)), withdrawAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), contractorFeeAmount + clientFeeAmount);
    }

    function test_withdraw_after_return_request_then_refill() public {
        test_withdraw_whenRefundApprovedByOwner();
        uint256 currentContractId = 1;
        (address _contractor,, uint256 _prepaymentAmount,,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_status), 9); //Status.CANCELED
        (, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, 0);
        assertEq(uint256(_weekStatus), 1); //Status.ACTIVE
        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether);
        uint256 amountAdditional = 1 ether;
        (uint256 totalDepositAmount,) = computeDepositAndFeeAmount(
            address(registry),
            address(escrow),
            currentContractId,
            client,
            amountAdditional,
            Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        vm.startPrank(client);
        paymentToken.mint(client, totalDepositAmount);
        paymentToken.approve(address(escrow), totalDepositAmount);
        escrow.refill(currentContractId, 0, amountAdditional, Enums.RefillType.PREPAYMENT);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        escrow.requestReturn(currentContractId);
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.stopPrank();
    }

    function test_withdraw_reverts_UnauthorizedAccount() public {
        test_deposit_prepayment();
        uint256 currentContractId = 1;
        address notClient = makeAddr("notClient");
        vm.prank(notClient);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.withdraw(currentContractId);
    }

    function test_withdraw_reverts_InvalidStatusForWithdraw() public {
        test_deposit_amountToClaim();
        uint256 currentContractId = 1;
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusToWithdraw.selector);
        escrow.withdraw(currentContractId);
    }

    function test_withdraw_reverts_NoFundsAvailableForWithdraw() public {
        test_requestReturn_whenActive();
        assertEq(paymentToken.balanceOf(address(client)), 0);
        uint256 currentContractId = 1;
        (,,,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(client);
        escrow.createDispute(currentContractId, 0);
        (,,,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 6); //Status.DISPUTED
        vm.prank(owner);
        escrow.resolveDispute(currentContractId, 0, Enums.Winner.SPLIT, 0, 0.5 ether);
        (,,,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 7); //Status.RESOLVED
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__NoFundsAvailableForWithdraw.selector);
        escrow.withdraw(currentContractId);
        (,,,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 7); //Status.RESOLVED
        assertEq(paymentToken.balanceOf(address(client)), 0);
    }

    function test_withdraw_reverts_InvalidStatusForWithdraw_canceled() public {
        test_withdraw_whenRefundApprovedByOwner();
        uint256 currentContractId = 1;
        (,,,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 9); //Status.CANCELED
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusToWithdraw.selector);
        escrow.withdraw(currentContractId);
    }

    ////////////////////////////////////////////
    //          return request tests          //
    ////////////////////////////////////////////

    function test_requestReturn_whenActive() public {
        test_deposit_prepayment();
        uint256 currentContractId = 1;
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnRequested(client, currentContractId);
        escrow.requestReturn(currentContractId);
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_whenApproved() public {
        test_approve();
        uint256 currentContractId = 1;
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnRequested(client, currentContractId);
        escrow.requestReturn(currentContractId);
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
    }

    // claim::if (C.prepaymentAmount == 0) C.status = Enums.Status.COMPLETED;
    function test_requestReturn_whenCompleted() public {
        test_claim_clientCoversOnly();
        uint256 currentContractId = 1;
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 4); //Status.COMPLETED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnRequested(client, currentContractId);
        escrow.requestReturn(currentContractId);
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_reverts_UnauthorizedAccount() public {
        test_deposit_prepayment();
        uint256 currentContractId = 1;
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.prank(contractor);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender);
        escrow.requestReturn(currentContractId);
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
    }

    function test_requestReturn_reverts_ReturnNotAllowed() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = 1;
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__ReturnNotAllowed.selector);
        escrow.requestReturn(currentContractId);
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
    }

    function test_approveReturn_by_owner() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = 1;
        (,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit ReturnApproved(owner, currentContractId, client);
        escrow.approveReturn(currentContractId);
        (,, _prepaymentAmount, _amountToWithdraw,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 1 ether);
        assertEq(uint256(_status), 8); //Status.REFUND_APPROVED
    }

    function test_approveReturn_by_contractor() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = 1;
        (,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(contractor);
        vm.expectEmit(true, true, true, true);
        emit ReturnApproved(contractor, currentContractId, client);
        escrow.approveReturn(currentContractId);
        (,, _prepaymentAmount, _amountToWithdraw,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 1 ether);
        assertEq(uint256(_status), 8); //Status.REFUND_APPROVED
    }

    function test_approveReturn_reverts_UnauthorizedToApproveReturn() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = 1;
        (,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(address(this));
        vm.expectRevert(IEscrow.Escrow__UnauthorizedToApproveReturn.selector);
        escrow.approveReturn(currentContractId);
        (,, _prepaymentAmount, _amountToWithdraw,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
    }

    function test_approveReturn_reverts_NoReturnRequested() public {
        test_deposit_prepayment();
        uint256 currentContractId = 1;
        (,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__NoReturnRequested.selector);
        escrow.approveReturn(currentContractId);
        (,, _prepaymentAmount, _amountToWithdraw,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
    }

    function test_cancelReturn() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = 1;
        assertEq(uint256(escrow.previousStatuses(currentContractId)), 1); //Status.ACTIVE
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnCanceled(client, currentContractId);
        escrow.cancelReturn(currentContractId);
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        assertEq(uint256(escrow.previousStatuses(currentContractId)), 0); //Status.NONE
    }

    function test_cancelReturn_reverts() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = 1;
        assertEq(uint256(escrow.previousStatuses(currentContractId)), 1); //Status.ACTIVE
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(owner);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.cancelReturn(currentContractId);
        (,,,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        assertEq(uint256(escrow.previousStatuses(currentContractId)), 1); //Status.ACTIVE
    }

    function test_cancelReturn_reverts_NoReturnRequested() public {
        test_deposit_prepayment();
        uint256 currentContractId = 1;
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__NoReturnRequested.selector);
        escrow.cancelReturn(currentContractId);
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
    }

    ////////////////////////////////////////////
    //              dispute tests             //
    ////////////////////////////////////////////

    function test_createDispute_by_client() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = 1;
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit DisputeCreated(client, currentContractId, --weekId, client);
        escrow.createDispute(currentContractId, weekId);
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED
    }

    function test_createDispute_by_contractor() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = 1;
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(contractor);
        vm.expectEmit(true, true, true, true);
        emit DisputeCreated(contractor, currentContractId, --weekId, client);
        escrow.createDispute(currentContractId, weekId);
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED
    }

    function test_createDispute_reverts_CreateDisputeNotAllowed() public {
        test_deposit_prepayment();
        uint256 currentContractId = 1;
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__CreateDisputeNotAllowed.selector);
        escrow.createDispute(currentContractId, 0);
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
    }

    function test_createDispute_reverts_UnauthorizedToApproveDispute() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = 1;
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(address(this));
        vm.expectRevert(IEscrow.Escrow__UnauthorizedToApproveDispute.selector);
        escrow.createDispute(currentContractId, --weekId);
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
    }

    function test_resolveDispute_winnerClient() public {
        test_createDispute_by_client();
        uint256 currentContractId = 1;
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED

        (uint256 _amountToClaim,) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 0 ether);

        Enums.Winner _winner = Enums.Winner.CLIENT;
        uint256 clientAmount = _prepaymentAmount;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(owner, currentContractId, weekId, _winner, clientAmount, 0, client);
        escrow.resolveDispute(currentContractId, weekId, _winner, clientAmount, 0);
        (_amountToClaim,) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, 0 ether);

        (,, _prepaymentAmount, _amountToWithdraw,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, clientAmount);
        assertEq(uint256(_status), 7); //Status.RESOLVED
    }

    function test_resolveDispute_winnerContractor() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = 1;
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED

        (uint256 _amountToClaim,) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 0 ether);

        Enums.Winner _winner = Enums.Winner.CONTRACTOR;
        uint256 contractorAmount = _prepaymentAmount;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(owner, currentContractId, weekId, _winner, 0, contractorAmount, client);
        escrow.resolveDispute(currentContractId, weekId, _winner, 0, contractorAmount);
        (_amountToClaim,) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, _prepaymentAmount);

        (,, _prepaymentAmount, _amountToWithdraw,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 7); //Status.RESOLVED
    }

    function test_resolveDispute_winnerSplit() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = 1;
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED

        (uint256 _amountToClaim,) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 0 ether);

        Enums.Winner _winner = Enums.Winner.SPLIT;
        uint256 clientAmount = _prepaymentAmount / 2;
        uint256 contractorAmount = _prepaymentAmount / 2;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(owner, currentContractId, weekId, _winner, clientAmount, contractorAmount, client);
        escrow.resolveDispute(currentContractId, weekId, _winner, clientAmount, contractorAmount);
        (_amountToClaim,) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, clientAmount);

        (,, _prepaymentAmount, _amountToWithdraw,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, contractorAmount);
        assertEq(uint256(_status), 7); //Status.RESOLVED
    }

    function test_resolveDispute_winnerSplit_ZeroAllocationToEachParty() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = 1;
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED

        (uint256 _amountToClaim,) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 0 ether);

        Enums.Winner _winner = Enums.Winner.SPLIT;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(owner, currentContractId, weekId, _winner, 0, 0, client);
        escrow.resolveDispute(currentContractId, weekId, _winner, 0, 0);
        (_amountToClaim,) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, 0 ether);

        (,, _prepaymentAmount, _amountToWithdraw,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 7); //Status.RESOLVED
    }

    function test_resolveDispute_reverts_DisputeNotActiveForThisDeposit() public {
        test_deposit_prepayment();
        uint256 currentContractId = 1;
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__DisputeNotActiveForThisDeposit.selector);
        escrow.resolveDispute(currentContractId, --weekId, Enums.Winner.CLIENT, 0, 0);
        (,,,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 1); //Status.ACTIVE
    }

    function test_resolveDispute_reverts_UnauthorizedToApproveDispute() public {
        test_createDispute_by_client();
        uint256 currentContractId = 1;
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED
        vm.prank(address(this));
        vm.expectRevert(); //Unauthorized()
        escrow.resolveDispute(currentContractId, weekId, Enums.Winner.CONTRACTOR, 0, 0);
        (,,,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 6); //Status.DISPUTED
    }

    function test_resolveDispute_reverts_winnerClient_ResolutionExceedsDepositedAmount() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = 1;
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED

        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__ResolutionExceedsDepositedAmount.selector);
        escrow.resolveDispute(currentContractId, --weekId, Enums.Winner.CLIENT, 1.1 ether, 0 ether);
        (uint256 _amountToClaim,) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, 0 ether);
        (,,, _amountToWithdraw,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED
    }

    function test_resolveDispute_reverts_winnerContractor_ResolutionExceedsDepositedAmount() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = 1;
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED

        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__ResolutionExceedsDepositedAmount.selector);
        escrow.resolveDispute(currentContractId, --weekId, Enums.Winner.CONTRACTOR, 0 ether, 1.1 ether);
        (uint256 _amountToClaim,) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, 0 ether);
        (,,, _amountToWithdraw,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED
    }

    function test_resolveDispute_reverts_winnerSplit_ResolutionExceedsDepositedAmount() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = 1;
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED

        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__ResolutionExceedsDepositedAmount.selector);
        escrow.resolveDispute(currentContractId, --weekId, Enums.Winner.SPLIT, 1 ether, 1 wei);
        (uint256 _amountToClaim,) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, 0 ether);
        (,,, _amountToWithdraw,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED
    }

    // function test_resolveDispute_reverts_InvalidWinnerSpecified() public {
    //     test_createDispute_by_contractor();
    //     uint256 currentContractId = 1;
    //     uint256 weekId = escrow.getWeeksCount(currentContractId);
    //     (,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
    //         escrow.contractDetails(currentContractId);
    //     assertEq(_prepaymentAmount, 1 ether);
    //     assertEq(uint256(_status), 6); //Status.DISPUTED

    //     vm.prank(owner);

    //     vm.expectRevert(bytes4(keccak256("Panic(uint256)"))); // Handles Solidity panic
    //     // vm.expectRevert(); // panic: failed to convert value into enum type (0x21)
    //     // vm.expectRevert(IEscrow.Escrow__InvalidWinnerSpecified.selector);
    //     escrow.resolveDispute(currentContractId, --weekId, Enums.Winner(uint256(4)), 1 ether, 0); //Invalid enum
    // value
    //         // for Winner
    //     (uint256 _amountToClaim,) = escrow.weeklyEntries(currentContractId, weekId);
    //     assertEq(_amountToClaim, 0 ether);
    //     (,,, _amountToWithdraw,, _status) = escrow.contractDetails(currentContractId);
    //     assertEq(_amountToWithdraw, 0 ether);
    //     assertEq(uint256(_status), 6); //Status.DISPUTED
    // }

    ////////////////////////////////////////////
    //      ownership & management tests      //
    ////////////////////////////////////////////

    function test_updateRegistry() public {
        escrow.initialize(client, address(adminManager), address(registry));
        assertEq(address(escrow.registry()), address(registry));
        address notOwner = makeAddr("notOwner");
        bytes memory expectedRevertData =
            abi.encodeWithSelector(IEscrow.Escrow__UnauthorizedAccount.selector, address(notOwner));
        vm.prank(notOwner);
        vm.expectRevert(expectedRevertData);
        escrow.updateRegistry(address(registry));
        vm.startPrank(address(owner));
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.updateRegistry(address(0));
        assertEq(address(escrow.registry()), address(registry));
        EscrowRegistry newRegistry = new EscrowRegistry(owner);
        vm.expectEmit(true, false, false, true);
        emit RegistryUpdated(address(newRegistry));
        escrow.updateRegistry(address(newRegistry));
        assertEq(address(escrow.registry()), address(newRegistry));
        vm.stopPrank();
    }

    function test_updateAdminManager() public {
        escrow.initialize(client, address(adminManager), address(registry));
        assertEq(address(escrow.adminManager()), address(adminManager));
        EscrowAdminManager newAdminManager = new EscrowAdminManager(owner);
        address notOwner = makeAddr("notOwner");
        bytes memory expectedRevertData =
            abi.encodeWithSelector(IEscrow.Escrow__UnauthorizedAccount.selector, address(notOwner));
        vm.prank(notOwner);
        vm.expectRevert(expectedRevertData);
        escrow.updateAdminManager(address(newAdminManager));

        vm.startPrank(owner);
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.updateAdminManager(address(0));
        assertEq(address(escrow.adminManager()), address(adminManager));

        vm.expectEmit(true, false, false, true);
        emit AdminManagerUpdated(address(newAdminManager));
        escrow.updateAdminManager(address(newAdminManager));
        assertEq(address(escrow.adminManager()), address(newAdminManager));
        vm.stopPrank();
    }
}
