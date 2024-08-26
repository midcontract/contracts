// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";

import {EscrowAccountRecovery} from "src/modules/EscrowAccountRecovery.sol";
import {EscrowAdminManager, OwnedRoles} from "src/modules/EscrowAdminManager.sol";
import {EscrowFixedPrice, IEscrowFixedPrice} from "src/EscrowFixedPrice.sol";
import {EscrowMilestone, IEscrowMilestone} from "src/EscrowMilestone.sol";
import {EscrowHourly, IEscrowHourly} from "src/EscrowHourly.sol";
import {EscrowFeeManager, IEscrowFeeManager} from "src/modules/EscrowFeeManager.sol";
import {EscrowRegistry, IEscrowRegistry} from "src/modules/EscrowRegistry.sol";
import {IEscrow} from "src/interfaces/IEscrow.sol";
import {Enums} from "src/libs/Enums.sol";
import {ERC20Mock} from "@openzeppelin/mocks/token/ERC20Mock.sol";

contract EscrowAccountRecoveryUnitTest is Test {
    EscrowAccountRecovery recovery;
    EscrowFixedPrice escrow;
    EscrowMilestone escrowMilestone;
    EscrowHourly escrowHourly;
    EscrowRegistry registry;
    ERC20Mock paymentToken;
    EscrowFeeManager feeManager;
    EscrowAdminManager adminManager;

    address owner;
    address guardian;
    address treasury;
    address client;
    address contractor;
    address new_client;
    address new_contractor;

    bytes contractData;
    bytes32 contractorData;
    bytes32 salt;

    EscrowFixedPrice.Deposit deposit;
    EscrowAccountRecovery.RecoveryData recoveryInfo;
    IEscrowMilestone.Deposit[] deposits;
    IEscrowHourly.Deposit depositHourly;
    IEscrowHourly.ContractDetails contractDetails;

    event AdminManagerUpdated(address adminManager);
    event RecoveryInitiated(address indexed sender, bytes32 indexed recoveryHash);
    event RecoveryExecuted(address indexed sender, bytes32 indexed recoveryHash);
    event RecoveryCanceled(address indexed sender, bytes32 indexed recoveryHash);
    event GuardianUpdated(address guardian);
    event RecoveryPeriodUpdated(uint256 recoveryPeriod);
    event ClientOwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ContractorOwnershipTransferred(uint256 contractId, address indexed previousOwner, address indexed newOwner);
    event ContractorOwnershipTransferred(
        uint256 contractId, uint256 milestoneId, address indexed previousOwner, address indexed newOwner
    );

    function setUp() public {
        owner = makeAddr("owner");
        guardian = makeAddr("guardian");
        treasury = makeAddr("treasury");
        client = makeAddr("client");
        contractor = makeAddr("contractor");
        new_client = makeAddr("new_client");
        new_contractor = makeAddr("new_contractor");

        adminManager = new EscrowAdminManager(owner);
        recovery = new EscrowAccountRecovery(address(adminManager));
        escrow = new EscrowFixedPrice();
        registry = new EscrowRegistry(owner);
        paymentToken = new ERC20Mock();
        feeManager = new EscrowFeeManager(3_00, 5_00, owner);
        escrowMilestone = new EscrowMilestone();
        escrowHourly = new EscrowHourly();

        vm.startPrank(owner);
        registry.addPaymentToken(address(paymentToken));
        registry.setTreasury(treasury);
        registry.updateFeeManager(address(feeManager));
        adminManager.addGuardian(guardian);
        vm.stopPrank();

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        contractorData = keccak256(abi.encodePacked(contractData, salt));

        deposit = IEscrowFixedPrice.Deposit({
            contractor: contractor,
            paymentToken: address(paymentToken),
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.ACTIVE
        });
    }

    function test_setUpState() public view {
        assertTrue(address(recovery).code.length > 0);
        assertEq(address(recovery.adminManager()), address(adminManager));
        assertEq(recovery.MIN_RECOVERY_PERIOD(), 3 days);
    }

    // helpers
    function initializeEscrowFixedPrice() public {
        assertFalse(escrow.initialized());
        escrow.initialize(client, address(adminManager), address(registry));
        assertTrue(escrow.initialized());
        uint256 depositAmount = 1.03 ether;
        vm.startPrank(address(client));
        paymentToken.mint(address(client), depositAmount);
        paymentToken.approve(address(escrow), depositAmount);
        escrow.deposit(deposit);
        vm.stopPrank();
    }

    function initializeEscrowMilestone() public {
        deposits.push(
            IEscrowMilestone.Deposit({
                contractor: contractor,
                amount: 1 ether,
                amountToClaim: 0,
                amountToWithdraw: 0,
                contractorData: contractorData,
                feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                status: Enums.Status.ACTIVE
            })
        );
        assertFalse(escrowMilestone.initialized());
        escrowMilestone.initialize(client, address(adminManager), address(registry));
        assertTrue(escrowMilestone.initialized());

        uint256 depositAmount = 1.03 ether;
        vm.startPrank(address(client));
        paymentToken.mint(address(client), depositAmount);
        paymentToken.approve(address(escrowMilestone), depositAmount);
        escrowMilestone.deposit(0, address(paymentToken), deposits);
        vm.stopPrank();
    }

    function initializeEscrowHourly() public {
        contractDetails = IEscrowHourly.ContractDetails({
            paymentToken: address(paymentToken),
            prepaymentAmount: 1 ether,
            status: Enums.Status.ACTIVE
        });
        depositHourly = IEscrowHourly.Deposit({
            contractor: contractor,
            amountToClaim: 0,
            amountToWithdraw: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY
        });

        assertFalse(escrowHourly.initialized());
        escrowHourly.initialize(client, address(adminManager), address(registry));
        assertTrue(escrowHourly.initialized());

        uint256 depositAmount = 1 ether;
        uint256 totalDepositAmount = 1.03 ether;
        vm.startPrank(address(client));
        paymentToken.mint(address(client), totalDepositAmount);
        paymentToken.approve(address(escrowHourly), totalDepositAmount);
        escrowHourly.deposit(0, address(paymentToken), depositAmount, depositHourly);
        vm.stopPrank();
    }

    function test_initiateRecovery_client() public {
        initializeEscrowFixedPrice();
        uint256 contractId = escrow.getCurrentContractId();
        Enums.EscrowType escrowType = Enums.EscrowType.FIXED_PRICE;
        bytes32 recoveryHash = recovery.getRecoveryHash(address(escrow), client, new_client);

        vm.prank(guardian);
        vm.expectEmit(true, false, false, true);
        emit RecoveryInitiated(guardian, recoveryHash);
        recovery.initiateRecovery(address(escrow), contractId, 0, client, new_client, escrowType);
        (
            address _escrow,
            address _oldAccount,
            uint256 _contractId,
            uint256 _milestoneId,
            uint256 _executeAfter,
            bool _executed,
            bool _confirmed,
            Enums.EscrowType _escrowType
        ) = recovery.recoveryData(recoveryHash);
        assertEq(_escrow, address(escrow));
        assertEq(_oldAccount, client);
        assertEq(_contractId, contractId);
        assertEq(_milestoneId, 0);
        assertEq(_executeAfter, block.timestamp + 3 days);
        assertFalse(_executed);
        assertTrue(_confirmed);
        assertEq(uint256(_escrowType), 0);
    }

    function test_cancelRecovery() public {
        test_initiateRecovery_client();
        bytes32 recoveryHash = recovery.getRecoveryHash(address(escrow), client, new_client);
        vm.prank(owner);
        vm.expectRevert(EscrowAccountRecovery.UnauthorizedAccount.selector);
        recovery.cancelRecovery(recoveryHash);
        vm.prank(client);
        vm.expectEmit(true, false, false, true);
        emit RecoveryCanceled(client, recoveryHash);
        recovery.cancelRecovery(recoveryHash);
        (,,,, uint256 _executeAfter, bool _executed,,) = recovery.recoveryData(recoveryHash);
        assertEq(_executeAfter, 0);
        assertTrue(_executed);
        vm.prank(client);
        vm.expectRevert(EscrowAccountRecovery.RecoveryNotConfirmed.selector);
        recovery.cancelRecovery(recoveryHash);
    }

    function test_executeRecovery_client_fixed_price() public {
        test_initiateRecovery_client();
        Enums.AccountTypeRecovery accountType = Enums.AccountTypeRecovery.CLIENT;
        uint256 contractId = escrow.getCurrentContractId();
        bytes32 recoveryHash = recovery.getRecoveryHash(address(escrow), client, new_client);
        (
            address _escrow,
            address _oldAccount,
            uint256 _contractId,
            uint256 _milestoneId,
            uint256 _executeAfter,
            bool _executed,
            bool _confirmed,
            Enums.EscrowType _escrowType
        ) = recovery.recoveryData(recoveryHash);
        assertEq(_escrow, address(escrow));
        assertEq(_oldAccount, client);
        assertEq(_contractId, contractId);
        assertEq(_milestoneId, 0);
        assertEq(_executeAfter, block.timestamp + 3 days);
        assertFalse(_executed);
        assertTrue(_confirmed);
        assertEq(uint256(_escrowType), 0);

        vm.prank(new_client);
        vm.expectRevert(EscrowAccountRecovery.RecoveryPeriodStillPending.selector);
        recovery.executeRecovery(accountType, address(escrow), client);

        skip(3 days);
        vm.prank(address(this));
        vm.expectRevert(EscrowAccountRecovery.RecoveryNotConfirmed.selector);
        recovery.executeRecovery(accountType, address(escrow), client);

        bytes memory expectedRevertData =
            abi.encodeWithSelector(IEscrow.Escrow__UnauthorizedAccount.selector, address(recovery));
        vm.prank(new_client);
        vm.expectRevert(expectedRevertData);
        recovery.executeRecovery(accountType, address(escrow), client);

        vm.prank(owner);
        registry.setAccountRecovery(address(recovery));

        vm.prank(new_client);
        vm.expectEmit(true, true, true, true);
        emit ClientOwnershipTransferred(client, new_client);
        vm.expectEmit(true, true, true, true);
        emit RecoveryExecuted(new_client, recoveryHash);
        recovery.executeRecovery(accountType, address(escrow), client);
        (,,,, _executeAfter, _executed,,) = recovery.recoveryData(recoveryHash);
        assertEq(_executeAfter, 0);
        assertTrue(_executed);
        assertEq(escrow.client(), new_client);

        vm.prank(new_client);
        vm.expectRevert(EscrowAccountRecovery.RecoveryAlreadyExecuted.selector);
        recovery.executeRecovery(accountType, address(escrow), client);
    }

    function test_initiateRecovery_contractor_fixed_price() public {
        initializeEscrowFixedPrice();
        uint256 contractId = escrow.getCurrentContractId();
        Enums.EscrowType escrowType = Enums.EscrowType.FIXED_PRICE;
        bytes32 recoveryHash = recovery.getRecoveryHash(address(escrow), contractor, new_contractor);

        vm.prank(guardian);
        vm.expectEmit(true, false, false, true);
        emit RecoveryInitiated(guardian, recoveryHash);
        recovery.initiateRecovery(address(escrow), contractId, 0, contractor, new_contractor, escrowType);
        (
            address _escrow,
            address _oldAccount,
            uint256 _contractId,
            uint256 _milestoneId,
            uint256 _executeAfter,
            bool _executed,
            bool _confirmed,
            Enums.EscrowType _escrowType
        ) = recovery.recoveryData(recoveryHash);
        assertEq(_escrow, address(escrow));
        assertEq(_oldAccount, contractor);
        assertEq(_contractId, contractId);
        assertEq(_milestoneId, 0);
        assertEq(_executeAfter, block.timestamp + 3 days);
        assertFalse(_executed);
        assertTrue(_confirmed);
        assertEq(uint256(_escrowType), 0);
    }

    function test_executeRecovery_contractor_fixed_price() public {
        test_initiateRecovery_contractor_fixed_price();
        Enums.AccountTypeRecovery accountType = Enums.AccountTypeRecovery.CONTRACTOR;
        uint256 contractId = escrow.getCurrentContractId();
        bytes32 recoveryHash = recovery.getRecoveryHash(address(escrow), contractor, new_contractor);
        (
            address _escrow,
            address _oldAccount,
            uint256 _contractId,
            uint256 _milestoneId,
            uint256 _executeAfter,
            bool _executed,
            bool _confirmed,
            Enums.EscrowType _escrowType
        ) = recovery.recoveryData(recoveryHash);
        assertEq(_escrow, address(escrow));
        assertEq(_oldAccount, contractor);
        assertEq(_contractId, contractId);
        assertEq(_milestoneId, 0);
        assertEq(_executeAfter, block.timestamp + 3 days);
        assertFalse(_executed);
        assertTrue(_confirmed);
        assertEq(uint256(_escrowType), 0);

        (address _contractor,,,,,,,) = escrow.deposits(contractId);
        assertEq(_contractor, contractor);

        vm.prank(new_contractor);
        vm.expectRevert(EscrowAccountRecovery.RecoveryPeriodStillPending.selector);
        recovery.executeRecovery(accountType, address(escrow), contractor);

        skip(3 days);
        vm.prank(address(this));
        vm.expectRevert(EscrowAccountRecovery.RecoveryNotConfirmed.selector);
        recovery.executeRecovery(accountType, address(escrow), new_contractor);

        bytes memory expectedRevertData =
            abi.encodeWithSelector(IEscrow.Escrow__UnauthorizedAccount.selector, address(recovery));
        vm.prank(new_contractor);
        vm.expectRevert(expectedRevertData);
        recovery.executeRecovery(accountType, address(escrow), contractor);

        vm.prank(owner);
        registry.setAccountRecovery(address(recovery));

        vm.prank(new_contractor);
        vm.expectEmit(true, true, true, true);
        emit ContractorOwnershipTransferred(contractId, contractor, new_contractor);
        vm.expectEmit(true, true, true, true);
        emit RecoveryExecuted(new_contractor, recoveryHash);
        recovery.executeRecovery(accountType, address(escrow), contractor);
        (,,,, _executeAfter, _executed,,) = recovery.recoveryData(recoveryHash);
        assertEq(_executeAfter, 0);
        assertTrue(_executed);

        (_contractor,,,,,,,) = escrow.deposits(contractId);
        assertEq(_contractor, new_contractor);

        vm.prank(new_contractor);
        vm.expectRevert(EscrowAccountRecovery.RecoveryAlreadyExecuted.selector);
        recovery.executeRecovery(accountType, address(escrow), contractor);
    }

    function test_initiateRecovery_milestone_contractor() public {
        initializeEscrowMilestone();
        uint256 contractId = escrowMilestone.getCurrentContractId();
        Enums.EscrowType escrowType = Enums.EscrowType.MILESTONE;
        bytes32 recoveryHash = recovery.getRecoveryHash(address(escrowMilestone), contractor, new_contractor);

        vm.prank(guardian);
        vm.expectEmit(true, false, false, true);
        emit RecoveryInitiated(guardian, recoveryHash);
        recovery.initiateRecovery(address(escrowMilestone), contractId, 0, contractor, new_contractor, escrowType);
        (
            address _escrow,
            address _oldAccount,
            uint256 _contractId,
            uint256 _milestoneId,
            uint256 _executeAfter,
            bool _executed,
            bool _confirmed,
            Enums.EscrowType _escrowType
        ) = recovery.recoveryData(recoveryHash);
        assertEq(_escrow, address(escrowMilestone));
        assertEq(_oldAccount, contractor);
        assertEq(_contractId, contractId);
        assertEq(_milestoneId, 0);
        assertEq(_executeAfter, block.timestamp + 3 days);
        assertFalse(_executed);
        assertTrue(_confirmed);
        assertEq(uint256(_escrowType), 1);
    }

    function test_executeRecovery_contractor_milestone() public {
        test_initiateRecovery_milestone_contractor();
        Enums.AccountTypeRecovery accountType = Enums.AccountTypeRecovery.CONTRACTOR;
        uint256 contractId = escrowMilestone.getCurrentContractId();
        uint256 milestoneId = escrowMilestone.getMilestoneCount(contractId);
        bytes32 recoveryHash = recovery.getRecoveryHash(address(escrowMilestone), contractor, new_contractor);
        (
            address _escrow,
            address _oldAccount,
            uint256 _contractId,
            uint256 _milestoneId,
            uint256 _executeAfter,
            bool _executed,
            bool _confirmed,
            Enums.EscrowType _escrowType
        ) = recovery.recoveryData(recoveryHash);
        assertEq(_escrow, address(escrowMilestone));
        assertEq(_oldAccount, contractor);
        assertEq(_contractId, contractId);
        assertEq(_milestoneId, 0);
        assertEq(_executeAfter, block.timestamp + 3 days);
        assertFalse(_executed);
        assertTrue(_confirmed);
        assertEq(uint256(_escrowType), 1);

        (address _contractor,,,,,,) = escrowMilestone.contractMilestones(contractId, --milestoneId);
        assertEq(_contractor, contractor);

        vm.prank(new_contractor);
        vm.expectRevert(EscrowAccountRecovery.RecoveryPeriodStillPending.selector);
        recovery.executeRecovery(accountType, address(escrowMilestone), contractor);

        skip(3 days);
        vm.prank(address(this));
        vm.expectRevert(EscrowAccountRecovery.RecoveryNotConfirmed.selector);
        recovery.executeRecovery(accountType, address(escrowMilestone), new_contractor);

        vm.prank(new_contractor);
        vm.expectRevert(abi.encodeWithSelector(IEscrow.Escrow__UnauthorizedAccount.selector, address(recovery)));
        recovery.executeRecovery(accountType, address(escrowMilestone), contractor);

        vm.prank(owner);
        registry.setAccountRecovery(address(recovery));

        vm.prank(new_contractor);
        vm.expectEmit(true, true, true, true);
        emit ContractorOwnershipTransferred(contractId, milestoneId, contractor, new_contractor);
        vm.expectEmit(true, true, true, true);
        emit RecoveryExecuted(new_contractor, recoveryHash);
        recovery.executeRecovery(accountType, address(escrowMilestone), contractor);
        (,,,, _executeAfter, _executed,,) = recovery.recoveryData(recoveryHash);
        assertEq(_executeAfter, 0);
        assertTrue(_executed);

        (_contractor,,,,,,) = escrowMilestone.contractMilestones(contractId, milestoneId);
        assertEq(_contractor, new_contractor);

        vm.prank(new_contractor);
        vm.expectRevert(EscrowAccountRecovery.RecoveryAlreadyExecuted.selector);
        recovery.executeRecovery(accountType, address(escrowMilestone), contractor);
    }

    function test_initiateRecovery_hourly_contractor() public {
        initializeEscrowHourly();
        uint256 contractId = escrowHourly.getCurrentContractId();
        Enums.EscrowType escrowType = Enums.EscrowType.HOURLY;
        bytes32 recoveryHash = recovery.getRecoveryHash(address(escrowHourly), contractor, new_contractor);

        vm.prank(guardian);
        vm.expectEmit(true, false, false, true);
        emit RecoveryInitiated(guardian, recoveryHash);
        recovery.initiateRecovery(address(escrowHourly), contractId, 0, contractor, new_contractor, escrowType);
        (
            address _escrow,
            address _oldAccount,
            uint256 _contractId,
            uint256 _milestoneId,
            uint256 _executeAfter,
            bool _executed,
            bool _confirmed,
            Enums.EscrowType _escrowType
        ) = recovery.recoveryData(recoveryHash);
        assertEq(_escrow, address(escrowHourly));
        assertEq(_oldAccount, contractor);
        assertEq(_contractId, contractId);
        assertEq(_milestoneId, 0);
        assertEq(_executeAfter, block.timestamp + 3 days);
        assertFalse(_executed);
        assertTrue(_confirmed);
        assertEq(uint256(_escrowType), 2);
    }

    function test_executeRecovery_contractor_hourly() public {
        test_initiateRecovery_hourly_contractor();
        Enums.AccountTypeRecovery accountType = Enums.AccountTypeRecovery.CONTRACTOR;
        uint256 contractId = escrowHourly.getCurrentContractId();
        bytes32 recoveryHash = recovery.getRecoveryHash(address(escrowHourly), contractor, new_contractor);
        (
            address _escrow,
            address _oldAccount,
            uint256 _contractId,
            uint256 _milestoneId,
            uint256 _executeAfter,
            bool _executed,
            bool _confirmed,
            Enums.EscrowType _escrowType
        ) = recovery.recoveryData(recoveryHash);
        assertEq(_escrow, address(escrowHourly));
        assertEq(_oldAccount, contractor);
        assertEq(_contractId, contractId);
        assertEq(_milestoneId, 0);
        assertEq(_executeAfter, block.timestamp + 3 days);
        assertFalse(_executed);
        assertTrue(_confirmed);
        assertEq(uint256(_escrowType), 2);

        (address _contractor,,,) = escrowHourly.contractWeeks(contractId, 0);
        assertEq(_contractor, contractor);

        vm.prank(new_contractor);
        vm.expectRevert(EscrowAccountRecovery.RecoveryPeriodStillPending.selector);
        recovery.executeRecovery(accountType, address(escrowHourly), contractor);

        skip(3 days);
        vm.prank(address(this));
        vm.expectRevert(EscrowAccountRecovery.RecoveryNotConfirmed.selector);
        recovery.executeRecovery(accountType, address(escrowHourly), new_contractor);

        vm.prank(new_contractor);
        vm.expectRevert(abi.encodeWithSelector(IEscrow.Escrow__UnauthorizedAccount.selector, address(recovery)));
        recovery.executeRecovery(accountType, address(escrowHourly), contractor);

        vm.prank(owner);
        registry.setAccountRecovery(address(recovery));

        vm.prank(new_contractor);
        vm.expectEmit(true, true, true, true);
        emit ContractorOwnershipTransferred(contractId, contractor, new_contractor);
        vm.expectEmit(true, true, true, true);
        emit RecoveryExecuted(new_contractor, recoveryHash);
        recovery.executeRecovery(accountType, address(escrowHourly), contractor);
        (,,,, _executeAfter, _executed,,) = recovery.recoveryData(recoveryHash);
        assertEq(_executeAfter, 0);
        assertTrue(_executed);

        (_contractor,,,) = escrowHourly.contractWeeks(contractId, 0);
        assertEq(_contractor, new_contractor);

        vm.prank(new_contractor);
        vm.expectRevert(EscrowAccountRecovery.RecoveryAlreadyExecuted.selector);
        recovery.executeRecovery(accountType, address(escrowHourly), contractor);
    }

    function test_updateRecoveryPeriod() public {
        assertEq(recovery.recoveryPeriod(), 3 days);
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(EscrowAccountRecovery.UnauthorizedAccount.selector);
        recovery.updateRecoveryPeriod(7 days);
        vm.startPrank(owner);
        vm.expectRevert(EscrowAccountRecovery.RecoveryPeriodTooSmall.selector);
        recovery.updateRecoveryPeriod(0);
        vm.expectRevert(EscrowAccountRecovery.RecoveryPeriodTooSmall.selector);
        recovery.updateRecoveryPeriod(2 days);
        vm.expectEmit(true, true, true, true);
        emit RecoveryPeriodUpdated(7 days);
        recovery.updateRecoveryPeriod(7 days);
        assertEq(recovery.recoveryPeriod(), 7 days);
        vm.stopPrank();
    }

    function test_updateAdminManager() public {
        assertEq(address(recovery.adminManager()), address(adminManager));
        EscrowAdminManager newAdminManager = new EscrowAdminManager(owner);
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(EscrowAccountRecovery.UnauthorizedAccount.selector);
        recovery.updateAdminManager(address(newAdminManager));

        vm.startPrank(owner);
        vm.expectRevert(EscrowAccountRecovery.ZeroAddressProvided.selector);
        recovery.updateAdminManager(address(0));
        assertEq(address(recovery.adminManager()), address(adminManager));

        vm.expectEmit(true, false, false, true);
        emit AdminManagerUpdated(address(newAdminManager));
        recovery.updateAdminManager(address(newAdminManager));
        assertEq(address(recovery.adminManager()), address(newAdminManager));
        vm.stopPrank();
    }
}
