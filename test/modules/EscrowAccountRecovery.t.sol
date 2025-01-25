// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test, console2 } from "forge-std/Test.sol";

import { ECDSA } from "@solbase/utils/ECDSA.sol";
import { ERC20Mock } from "@openzeppelin/mocks/token/ERC20Mock.sol";
import { SignatureChecker } from "@openzeppelin/utils/cryptography/SignatureChecker.sol";

import { EscrowAccountRecovery } from "src/modules/EscrowAccountRecovery.sol";
import { EscrowAdminManager, OwnedRoles } from "src/modules/EscrowAdminManager.sol";
import { EscrowFixedPrice, IEscrowFixedPrice } from "src/EscrowFixedPrice.sol";
import { EscrowMilestone, IEscrowMilestone } from "src/EscrowMilestone.sol";
import { EscrowHourly, IEscrowHourly } from "src/EscrowHourly.sol";
import { EscrowFeeManager, IEscrowFeeManager } from "src/modules/EscrowFeeManager.sol";
import { EscrowRegistry, IEscrowRegistry } from "src/modules/EscrowRegistry.sol";
import { Enums } from "src/common/Enums.sol";
import { IEscrow } from "src/interfaces/IEscrow.sol";
import { TestUtils } from "test/utils/TestUtils.sol";

contract EscrowAccountRecoveryUnitTest is Test, TestUtils {
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
    uint256 ownerPrKey;
    uint256 milestoneId;
    uint256 contractId = 1;

    bytes32 salt;
    bytes32 contractorData;
    bytes contractData;
    bytes signature;

    EscrowFixedPrice.DepositRequest deposit;
    EscrowAccountRecovery.RecoveryData recoveryInfo;
    IEscrowMilestone.Milestone[] milestones;
    IEscrowHourly.DepositRequest depositHourly;
    IEscrowHourly.ContractDetails contractDetails;
    IEscrowMilestone.DepositRequest depositMilestone;

    event AdminManagerUpdated(address adminManager);
    event RecoveryInitiated(address indexed sender, bytes32 indexed recoveryHash);
    event RecoveryExecuted(address indexed sender, bytes32 indexed recoveryHash);
    event RecoveryCanceled(address indexed sender, bytes32 indexed recoveryHash);
    event GuardianUpdated(address guardian);
    event RecoveryPeriodUpdated(uint256 recoveryPeriod);
    event ClientOwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ContractorOwnershipTransferred(
        uint256 indexed contractId, address indexed previousOwner, address indexed newOwner
    );
    event ContractorOwnershipTransferred(
        uint256 indexed contractId, uint256 indexed milestoneId, address previousOwner, address indexed newOwner
    );

    function setUp() public {
        (owner, ownerPrKey) = makeAddrAndKey("owner");
        guardian = makeAddr("guardian");
        treasury = makeAddr("treasury");
        client = makeAddr("client");
        contractor = makeAddr("contractor");
        new_client = makeAddr("new_client");
        new_contractor = makeAddr("new_contractor");

        adminManager = new EscrowAdminManager(owner);
        registry = new EscrowRegistry(owner);
        recovery = new EscrowAccountRecovery(address(adminManager), address(registry));
        escrow = new EscrowFixedPrice();
        paymentToken = new ERC20Mock();
        feeManager = new EscrowFeeManager(address(adminManager), 300, 500);
        escrowMilestone = new EscrowMilestone();
        escrowHourly = new EscrowHourly();

        vm.startPrank(owner);
        registry.addPaymentToken(address(paymentToken));
        registry.setFixedTreasury(treasury);
        registry.setHourlyTreasury(treasury);
        registry.setMilestoneTreasury(treasury);
        registry.updateFeeManager(address(feeManager));
        adminManager.addGuardian(guardian);
        vm.stopPrank();

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        contractorData = keccak256(abi.encodePacked(contractData, salt));
    }

    function test_setUpState() public view {
        assertTrue(address(recovery).code.length > 0);
        assertEq(address(recovery.adminManager()), address(adminManager));
        assertEq(address(recovery.registry()), address(registry));
        assertEq(recovery.MIN_RECOVERY_PERIOD(), 3 days);
    }

    function test_deployRecovery_reverts() public {
        vm.expectRevert(EscrowAccountRecovery.ZeroAddressProvided.selector);
        EscrowAccountRecovery newRecovery = new EscrowAccountRecovery(address(0), address(registry));
        vm.expectRevert(EscrowAccountRecovery.ZeroAddressProvided.selector);
        newRecovery = new EscrowAccountRecovery(address(adminManager), address(0));
        vm.expectRevert(EscrowAccountRecovery.ZeroAddressProvided.selector);
        newRecovery = new EscrowAccountRecovery(address(0), address(0));
        assertFalse(address(newRecovery).code.length > 0);
    }

    function initializeEscrowFixedPrice() public {
        assertFalse(escrow.initialized());
        escrow.initialize(client, address(adminManager), address(registry));
        assertTrue(escrow.initialized());
        uint256 depositAmount = 1.03 ether;
        vm.startPrank(address(client));
        paymentToken.mint(address(client), depositAmount);
        paymentToken.approve(address(escrow), depositAmount);
        deposit = IEscrowFixedPrice.DepositRequest({
            contractId: 1,
            contractor: contractor,
            paymentToken: address(paymentToken),
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.ACTIVE,
            escrow: address(escrow),
            expiration: block.timestamp + 3 hours,
            signature: getSignatureFixed(
                FixedPriceSignatureParams({
                    contractId: 1,
                    contractor: contractor,
                    proxy: address(escrow),
                    token: address(paymentToken),
                    amount: 1 ether,
                    feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                    contractorData: contractorData,
                    client: client,
                    ownerPrKey: ownerPrKey
                })
            )
        });

        escrow.deposit(deposit);
        vm.stopPrank();
    }

    function initializeEscrowMilestone() public {
        milestones.push(
            IEscrowMilestone.Milestone({
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

        bytes32 milestonesHash = hashMilestones(milestones);
        depositMilestone = IEscrowMilestone.DepositRequest({
            contractId: 1,
            paymentToken: address(paymentToken),
            milestonesHash: milestonesHash,
            escrow: address(escrowMilestone),
            expiration: uint256(block.timestamp + 3 hours),
            signature: getSignatureMilestone(
                MilestoneSignatureParams({
                    proxy: address(escrowMilestone),
                    client: client,
                    contractId: 1,
                    token: address(paymentToken),
                    milestonesHash: milestonesHash,
                    ownerPrKey: ownerPrKey
                })
            )
        });

        uint256 depositAmount = 1.03 ether;
        vm.startPrank(address(client));
        paymentToken.mint(address(client), depositAmount);
        paymentToken.approve(address(escrowMilestone), depositAmount);
        escrowMilestone.deposit(depositMilestone, milestones);
        vm.stopPrank();
    }

    function initializeEscrowHourly() public {
        uint256 depositAmount = 1 ether;
        depositHourly = IEscrowHourly.DepositRequest({
            contractId: 1,
            contractor: contractor,
            paymentToken: address(paymentToken),
            prepaymentAmount: depositAmount,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrowHourly),
            expiration: uint256(block.timestamp + 3 hours),
            signature: getSignatureHourly(
                HourlySignatureParams({
                    contractId: 1,
                    contractor: contractor,
                    proxy: address(escrowHourly),
                    token: address(paymentToken),
                    prepaymentAmount: depositAmount,
                    amountToClaim: 0 ether,
                    feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                    client: client,
                    ownerPrKey: ownerPrKey
                })
            )
        });

        assertFalse(escrowHourly.initialized());
        escrowHourly.initialize(client, address(adminManager), address(registry));
        assertTrue(escrowHourly.initialized());

        uint256 totalDepositAmount = 1.03 ether;
        vm.startPrank(address(client));
        paymentToken.mint(address(client), totalDepositAmount);
        paymentToken.approve(address(escrowHourly), totalDepositAmount);
        escrowHourly.deposit(depositHourly);
        vm.stopPrank();
    }

    function test_initiateRecovery_fixed_price_client() public {
        initializeEscrowFixedPrice();

        Enums.EscrowType escrowType = Enums.EscrowType.FIXED_PRICE;
        Enums.AccountTypeRecovery accountType = Enums.AccountTypeRecovery.CLIENT;
        bytes32 recoveryHash =
            recovery.getRecoveryHash(address(escrow), contractId, milestoneId, client, new_client, accountType);

        vm.prank(guardian);
        vm.expectEmit(true, false, false, true);
        emit RecoveryInitiated(guardian, recoveryHash);
        recovery.initiateRecovery(address(escrow), contractId, 0, client, new_client, escrowType, accountType);
        (
            address _escrow,
            address _oldAccount,
            uint256 _contractId,
            uint256 _milestoneId,
            uint256 _executeAfter,
            bool _executed,
            Enums.EscrowType _escrowType,
            Enums.AccountTypeRecovery _accountType
        ) = recovery.recoveryData(recoveryHash);
        assertEq(_escrow, address(escrow));
        assertEq(_oldAccount, client);
        assertEq(_contractId, contractId);
        assertEq(_milestoneId, 0);
        assertEq(_executeAfter, block.timestamp + 3 days);
        assertFalse(_executed);
        assertEq(uint256(_escrowType), 0);
        assertEq(uint256(_accountType), 0);
    }

    function test_initiateRecovery_reverts_Unauthorized() public {
        initializeEscrowFixedPrice();

        Enums.EscrowType escrowType = Enums.EscrowType.FIXED_PRICE;
        Enums.AccountTypeRecovery accountType = Enums.AccountTypeRecovery.CLIENT;
        bytes32 recoveryHash =
            recovery.getRecoveryHash(address(escrow), contractId, milestoneId, client, new_client, accountType);
        vm.prank(address(this)); //not a guardian
        vm.expectRevert(EscrowAccountRecovery.UnauthorizedAccount.selector);
        recovery.initiateRecovery(address(escrow), contractId, 0, client, new_client, escrowType, accountType);
        (,,,,, bool _executed,,) = recovery.recoveryData(recoveryHash);
        assertFalse(_executed);
    }

    function test_initiateRecovery_reverts_RecoveryAlreadyExecuted() public {
        test_executeRecovery_fixed_price_client();

        bytes32 recoveryHash = recovery.getRecoveryHash(
            address(escrow), contractId, milestoneId, client, new_client, Enums.AccountTypeRecovery.CLIENT
        );
        (,,,,, bool _executed,,) = recovery.recoveryData(recoveryHash);
        assertTrue(_executed);
        assertEq(escrow.client(), new_client);

        vm.prank(guardian);
        vm.expectRevert(EscrowAccountRecovery.RecoveryAlreadyExecuted.selector);
        recovery.initiateRecovery(
            address(escrow),
            contractId,
            0,
            client,
            new_client,
            Enums.EscrowType.FIXED_PRICE,
            Enums.AccountTypeRecovery.CLIENT
        );
    }

    function test_initiateRecovery_reverts_ZeroAddressProvided() public {
        initializeEscrowFixedPrice();

        Enums.EscrowType escrowType = Enums.EscrowType.FIXED_PRICE;
        Enums.AccountTypeRecovery accountType = Enums.AccountTypeRecovery.CLIENT;
        bytes32 recoveryHash =
            recovery.getRecoveryHash(address(escrow), contractId, milestoneId, client, new_client, accountType);
        vm.prank(guardian);
        vm.expectRevert(EscrowAccountRecovery.ZeroAddressProvided.selector);
        recovery.initiateRecovery(address(0), contractId, milestoneId, client, new_client, escrowType, accountType);
        (,,,,, bool _executed,,) = recovery.recoveryData(recoveryHash);
        assertFalse(_executed);
    }

    function test_initiateRecovery_reverts_SameAccountProvided() public {
        initializeEscrowFixedPrice();

        Enums.EscrowType escrowType = Enums.EscrowType.FIXED_PRICE;
        Enums.AccountTypeRecovery accountType = Enums.AccountTypeRecovery.CLIENT;
        bytes32 recoveryHash =
            recovery.getRecoveryHash(address(escrow), contractId, milestoneId, client, new_client, accountType);
        vm.prank(guardian);
        vm.expectRevert(EscrowAccountRecovery.SameAccountProvided.selector);
        recovery.initiateRecovery(
            address(escrow), contractId, milestoneId, new_client, new_client, escrowType, accountType
        );
        (,,,,, bool _executed,,) = recovery.recoveryData(recoveryHash);
        assertFalse(_executed);
    }

    function test_initiateRecovery_reverts_InvalidContractId() public {
        initializeEscrowFixedPrice();
        uint256 invalidContractId = 2;
        assertFalse(escrow.contractExists(invalidContractId));

        Enums.EscrowType escrowType = Enums.EscrowType.FIXED_PRICE;
        Enums.AccountTypeRecovery accountType = Enums.AccountTypeRecovery.CLIENT;
        bytes32 recoveryHash =
            recovery.getRecoveryHash(address(escrow), invalidContractId, milestoneId, client, new_client, accountType);
        vm.prank(guardian);
        vm.expectRevert(EscrowAccountRecovery.InvalidContractId.selector);
        recovery.initiateRecovery(
            address(escrow), invalidContractId, milestoneId, client, new_client, escrowType, accountType
        );
        (,,,,, bool _executed,,) = recovery.recoveryData(recoveryHash);
        assertFalse(_executed);
    }

    function test_initiateRecovery_reverts_MilestoneNotSupported() public {
        initializeEscrowFixedPrice();

        Enums.EscrowType escrowType = Enums.EscrowType.FIXED_PRICE;
        Enums.AccountTypeRecovery accountType = Enums.AccountTypeRecovery.CLIENT;
        bytes32 recoveryHash =
            recovery.getRecoveryHash(address(escrow), contractId, milestoneId, client, new_client, accountType);
        vm.prank(guardian);
        vm.expectRevert(EscrowAccountRecovery.MilestoneNotSupported.selector);
        recovery.initiateRecovery(
            address(escrow), contractId, ++milestoneId, client, new_client, escrowType, accountType
        );
        (,,,,, bool _executed,,) = recovery.recoveryData(recoveryHash);
        assertFalse(_executed);
    }

    function test_cancelRecovery() public {
        test_initiateRecovery_fixed_price_client();

        bytes32 recoveryHash = recovery.getRecoveryHash(
            address(escrow), contractId, milestoneId, client, new_client, Enums.AccountTypeRecovery.CLIENT
        );
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
        vm.expectRevert(EscrowAccountRecovery.RecoveryNotInitiated.selector);
        recovery.cancelRecovery(recoveryHash);
    }

    function test_cancelRecovery_reverts_when_blacklisted() public {
        test_initiateRecovery_fixed_price_client();

        bytes32 recoveryHash = recovery.getRecoveryHash(
            address(escrow), contractId, milestoneId, client, new_client, Enums.AccountTypeRecovery.CLIENT
        );
        vm.prank(owner);
        registry.addToBlacklist(client);
        assertTrue(registry.blacklist(client));
        vm.prank(client);
        vm.expectRevert(EscrowAccountRecovery.UnauthorizedAccount.selector);
        recovery.cancelRecovery(recoveryHash);
    }

    function test_executeRecovery_fixed_price_client() public {
        test_initiateRecovery_fixed_price_client();
        Enums.AccountTypeRecovery accountType = Enums.AccountTypeRecovery.CLIENT;

        bytes32 recoveryHash =
            recovery.getRecoveryHash(address(escrow), contractId, milestoneId, client, new_client, accountType);
        (
            address _escrow,
            address _oldAccount,
            uint256 _contractId,
            uint256 _milestoneId,
            uint256 _executeAfter,
            bool _executed,
            Enums.EscrowType _escrowType,
            Enums.AccountTypeRecovery _accountType
        ) = recovery.recoveryData(recoveryHash);
        assertEq(_escrow, address(escrow));
        assertEq(_oldAccount, client);
        assertEq(_contractId, contractId);
        assertEq(_milestoneId, 0);
        assertEq(_executeAfter, block.timestamp + 3 days);
        assertFalse(_executed);
        assertEq(uint256(_escrowType), 0);
        assertEq(uint256(_accountType), 0);

        vm.prank(new_client);
        vm.expectRevert(EscrowAccountRecovery.RecoveryPeriodStillPending.selector);
        recovery.executeRecovery(accountType, address(escrow), contractId, milestoneId, client);

        skip(3 days);
        bytes memory expectedRevertData =
            abi.encodeWithSelector(IEscrow.Escrow__UnauthorizedAccount.selector, address(recovery));
        vm.prank(new_client);
        vm.expectRevert(expectedRevertData);
        recovery.executeRecovery(accountType, address(escrow), contractId, milestoneId, client);

        vm.prank(owner);
        registry.setAccountRecovery(address(recovery));

        vm.prank(new_client);
        vm.expectRevert(EscrowAccountRecovery.RecoveryNotInitiated.selector);
        recovery.executeRecovery(Enums.AccountTypeRecovery.CONTRACTOR, address(escrow), contractId, milestoneId, client);

        vm.prank(new_client);
        vm.expectEmit(true, true, true, true);
        emit ClientOwnershipTransferred(client, new_client);
        vm.expectEmit(true, true, true, true);
        emit RecoveryExecuted(new_client, recoveryHash);
        recovery.executeRecovery(accountType, address(escrow), contractId, milestoneId, client);
        (,,,, _executeAfter, _executed,,) = recovery.recoveryData(recoveryHash);
        assertEq(_executeAfter, 0);
        assertTrue(_executed);
        assertEq(escrow.client(), new_client);

        vm.prank(new_client);
        vm.expectRevert(EscrowAccountRecovery.RecoveryAlreadyExecuted.selector);
        recovery.executeRecovery(accountType, address(escrow), contractId, milestoneId, client);
    }

    function test_executeRecovery_fixed_price_client_reverts_ZeroAddressProvided() public {
        test_initiateRecovery_fixed_price_client();
        vm.prank(owner);
        registry.setAccountRecovery(address(recovery));
        vm.prank(address(recovery));
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.transferClientOwnership(address(0));
    }

    function test_initiateRecovery_fixed_price_contractor() public {
        initializeEscrowFixedPrice();

        Enums.EscrowType escrowType = Enums.EscrowType.FIXED_PRICE;
        Enums.AccountTypeRecovery accountType = Enums.AccountTypeRecovery.CONTRACTOR;
        bytes32 recoveryHash =
            recovery.getRecoveryHash(address(escrow), contractId, milestoneId, contractor, new_contractor, accountType);

        vm.prank(guardian);
        vm.expectEmit(true, false, false, true);
        emit RecoveryInitiated(guardian, recoveryHash);
        recovery.initiateRecovery(address(escrow), contractId, 0, contractor, new_contractor, escrowType, accountType);
        (
            address _escrow,
            address _oldAccount,
            uint256 _contractId,
            uint256 _milestoneId,
            uint256 _executeAfter,
            bool _executed,
            Enums.EscrowType _escrowType,
            Enums.AccountTypeRecovery _accountType
        ) = recovery.recoveryData(recoveryHash);
        assertEq(_escrow, address(escrow));
        assertEq(_oldAccount, contractor);
        assertEq(_contractId, contractId);
        assertEq(_milestoneId, 0);
        assertEq(_executeAfter, block.timestamp + 3 days);
        assertFalse(_executed);
        assertEq(uint256(_escrowType), 0);
        assertEq(uint256(_accountType), 1);
    }

    function test_executeRecovery_fixed_price_contractor() public {
        test_initiateRecovery_fixed_price_contractor();
        Enums.AccountTypeRecovery accountType = Enums.AccountTypeRecovery.CONTRACTOR;

        bytes32 recoveryHash =
            recovery.getRecoveryHash(address(escrow), contractId, milestoneId, contractor, new_contractor, accountType);
        (
            address _escrow,
            address _oldAccount,
            uint256 _contractId,
            uint256 _milestoneId,
            uint256 _executeAfter,
            bool _executed,
            Enums.EscrowType _escrowType,
            Enums.AccountTypeRecovery _accountType
        ) = recovery.recoveryData(recoveryHash);
        assertEq(_escrow, address(escrow));
        assertEq(_oldAccount, contractor);
        assertEq(_contractId, contractId);
        assertEq(_milestoneId, 0);
        assertEq(_executeAfter, block.timestamp + 3 days);
        assertFalse(_executed);
        assertEq(uint256(_escrowType), 0);
        assertEq(uint256(_accountType), 1);

        (address _contractor,,,,,,,) = escrow.deposits(contractId);
        assertEq(_contractor, contractor);

        vm.prank(new_contractor);
        vm.expectRevert(EscrowAccountRecovery.RecoveryPeriodStillPending.selector);
        recovery.executeRecovery(accountType, address(escrow), contractId, milestoneId, contractor);

        skip(3 days);
        bytes memory expectedRevertData =
            abi.encodeWithSelector(IEscrow.Escrow__UnauthorizedAccount.selector, address(recovery));
        vm.prank(new_contractor);
        vm.expectRevert(expectedRevertData);
        recovery.executeRecovery(accountType, address(escrow), contractId, milestoneId, contractor);

        vm.prank(owner);
        registry.setAccountRecovery(address(recovery));

        vm.prank(new_contractor);
        vm.expectRevert(EscrowAccountRecovery.RecoveryNotInitiated.selector);
        recovery.executeRecovery(Enums.AccountTypeRecovery.CLIENT, address(escrow), contractId, milestoneId, contractor);

        vm.prank(new_contractor);
        vm.expectEmit(true, true, true, true);
        emit ContractorOwnershipTransferred(contractId, contractor, new_contractor);
        vm.expectEmit(true, true, true, true);
        emit RecoveryExecuted(new_contractor, recoveryHash);
        recovery.executeRecovery(accountType, address(escrow), contractId, milestoneId, contractor);
        (,,,, _executeAfter, _executed,,) = recovery.recoveryData(recoveryHash);
        assertEq(_executeAfter, 0);
        assertTrue(_executed);

        (_contractor,,,,,,,) = escrow.deposits(contractId);
        assertEq(_contractor, new_contractor);

        vm.prank(new_contractor);
        vm.expectRevert(EscrowAccountRecovery.RecoveryAlreadyExecuted.selector);
        recovery.executeRecovery(accountType, address(escrow), contractId, milestoneId, contractor);
    }

    function test_executeRecovery_fixed_price_contractor_reverts_ZeroAddressProvided() public {
        test_initiateRecovery_fixed_price_contractor();

        vm.prank(owner);
        registry.setAccountRecovery(address(recovery));
        vm.prank(address(recovery));
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.transferContractorOwnership(contractId, address(0));
    }

    function test_initiateRecovery_milestone_client() public {
        initializeEscrowMilestone();
        uint256 milestoneId_ = escrowMilestone.getMilestoneCount(contractId);
        Enums.EscrowType escrowType = Enums.EscrowType.MILESTONE;
        Enums.AccountTypeRecovery accountType = Enums.AccountTypeRecovery.CLIENT;
        bytes32 recoveryHash = recovery.getRecoveryHash(
            address(escrowMilestone), contractId, --milestoneId_, client, new_client, accountType
        );

        vm.prank(guardian);
        recovery.initiateRecovery(
            address(escrowMilestone), contractId, milestoneId_, client, new_client, escrowType, accountType
        );
        (
            address _escrow,
            address _oldAccount,
            uint256 _contractId,
            uint256 _milestoneId,
            uint256 _executeAfter,
            bool _executed,
            Enums.EscrowType _escrowType,
            Enums.AccountTypeRecovery _accountType
        ) = recovery.recoveryData(recoveryHash);
        assertEq(_escrow, address(escrowMilestone));
        assertEq(_oldAccount, client);
        assertEq(_contractId, contractId);
        assertEq(_milestoneId, milestoneId_); //0
        assertEq(_executeAfter, block.timestamp + 3 days);
        assertFalse(_executed);
        assertEq(uint256(_escrowType), 1);
        assertEq(uint256(_accountType), 0);
    }

    function test_initiateRecovery_milestone_reverts_InvalidMilestoneId() public {
        initializeEscrowMilestone();
        uint256 milestoneId_ = escrowMilestone.getMilestoneCount(contractId);
        Enums.EscrowType escrowType = Enums.EscrowType.MILESTONE;
        Enums.AccountTypeRecovery accountType = Enums.AccountTypeRecovery.CLIENT;
        bytes32 recoveryHash = recovery.getRecoveryHash(
            address(escrowMilestone), contractId, ++milestoneId_, client, new_client, accountType
        );
        vm.prank(guardian);
        vm.expectRevert(EscrowAccountRecovery.InvalidMilestoneId.selector);
        recovery.initiateRecovery(
            address(escrowMilestone), contractId, milestoneId_, client, new_client, escrowType, accountType
        );
        (,,,,, bool _executed,,) = recovery.recoveryData(recoveryHash);
        assertFalse(_executed);
    }

    function test_executeRecovery_milestone_client() public {
        test_initiateRecovery_milestone_client();
        Enums.AccountTypeRecovery accountType = Enums.AccountTypeRecovery.CLIENT;
        uint256 milestoneId_ = escrowMilestone.getMilestoneCount(contractId);
        bytes32 recoveryHash = recovery.getRecoveryHash(
            address(escrowMilestone), contractId, --milestoneId_, client, new_client, accountType
        );
        (
            address _escrow,
            address _oldAccount,
            uint256 _contractId,
            uint256 _milestoneId,
            uint256 _executeAfter,
            bool _executed,
            Enums.EscrowType _escrowType,
            Enums.AccountTypeRecovery _accountType
        ) = recovery.recoveryData(recoveryHash);
        assertEq(_escrow, address(escrowMilestone));
        assertEq(_oldAccount, client);
        assertEq(_contractId, contractId);
        assertEq(_milestoneId, milestoneId_);
        assertEq(_executeAfter, block.timestamp + 3 days);
        assertFalse(_executed);
        assertEq(uint256(_escrowType), 1);
        assertEq(uint256(_accountType), 0);

        vm.prank(new_client);
        vm.expectRevert(EscrowAccountRecovery.RecoveryPeriodStillPending.selector);
        recovery.executeRecovery(accountType, address(escrowMilestone), contractId, milestoneId, client);

        skip(3 days);
        bytes memory expectedRevertData =
            abi.encodeWithSelector(IEscrow.Escrow__UnauthorizedAccount.selector, address(recovery));
        vm.prank(new_client);
        vm.expectRevert(expectedRevertData);
        recovery.executeRecovery(accountType, address(escrowMilestone), contractId, milestoneId, client);

        vm.prank(owner);
        registry.setAccountRecovery(address(recovery));

        vm.prank(new_client);
        vm.expectRevert(EscrowAccountRecovery.RecoveryNotInitiated.selector);
        recovery.executeRecovery(
            Enums.AccountTypeRecovery.CONTRACTOR, address(escrowMilestone), contractId, milestoneId, client
        );

        vm.prank(new_client);
        vm.expectEmit(true, true, true, true);
        emit ClientOwnershipTransferred(client, new_client);
        vm.expectEmit(true, true, true, true);
        emit RecoveryExecuted(new_client, recoveryHash);
        recovery.executeRecovery(accountType, address(escrowMilestone), contractId, milestoneId, client);
        (,,,, _executeAfter, _executed,,) = recovery.recoveryData(recoveryHash);
        assertEq(_executeAfter, 0);
        assertTrue(_executed);
        assertEq(escrowMilestone.client(), new_client);

        vm.prank(new_client);
        vm.expectRevert(EscrowAccountRecovery.RecoveryAlreadyExecuted.selector);
        recovery.executeRecovery(accountType, address(escrowMilestone), contractId, milestoneId, client);
    }

    function test_executeRecovery_milestone_client_reverts_ZeroAddressProvided() public {
        test_initiateRecovery_milestone_client();
        vm.prank(owner);
        registry.setAccountRecovery(address(recovery));
        vm.prank(address(recovery));
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrowMilestone.transferClientOwnership(address(0));
    }

    function test_initiateRecovery_milestone_contractor() public {
        initializeEscrowMilestone();
        Enums.EscrowType escrowType = Enums.EscrowType.MILESTONE;
        Enums.AccountTypeRecovery accountType = Enums.AccountTypeRecovery.CONTRACTOR;
        bytes32 recoveryHash = recovery.getRecoveryHash(
            address(escrowMilestone), contractId, milestoneId, contractor, new_contractor, accountType
        );

        vm.prank(guardian);
        vm.expectEmit(true, false, false, true);
        emit RecoveryInitiated(guardian, recoveryHash);
        recovery.initiateRecovery(
            address(escrowMilestone), contractId, 0, contractor, new_contractor, escrowType, accountType
        );
        (
            address _escrow,
            address _oldAccount,
            uint256 _contractId,
            uint256 _milestoneId,
            uint256 _executeAfter,
            bool _executed,
            Enums.EscrowType _escrowType,
            Enums.AccountTypeRecovery _accountType
        ) = recovery.recoveryData(recoveryHash);
        assertEq(_escrow, address(escrowMilestone));
        assertEq(_oldAccount, contractor);
        assertEq(_contractId, contractId);
        assertEq(_milestoneId, 0);
        assertEq(_executeAfter, block.timestamp + 3 days);
        assertFalse(_executed);
        assertEq(uint256(_escrowType), 1);
        assertEq(uint256(_accountType), 1);
    }

    function test_executeRecovery_milestone_contractor() public {
        test_initiateRecovery_milestone_contractor();
        Enums.AccountTypeRecovery accountType = Enums.AccountTypeRecovery.CONTRACTOR;
        uint256 milestoneId_ = escrowMilestone.getMilestoneCount(contractId);
        bytes32 recoveryHash = recovery.getRecoveryHash(
            address(escrowMilestone), contractId, --milestoneId_, contractor, new_contractor, accountType
        );
        (
            address _escrow,
            address _oldAccount,
            uint256 _contractId,
            uint256 _milestoneId,
            uint256 _executeAfter,
            bool _executed,
            Enums.EscrowType _escrowType,
            Enums.AccountTypeRecovery _accountType
        ) = recovery.recoveryData(recoveryHash);
        assertEq(_escrow, address(escrowMilestone));
        assertEq(_oldAccount, contractor);
        assertEq(_contractId, contractId);
        assertEq(_milestoneId, 0);
        assertEq(_executeAfter, block.timestamp + 3 days);
        assertFalse(_executed);
        assertEq(uint256(_escrowType), 1);
        assertEq(uint256(_accountType), 1);

        (address _contractor,,,,,,) = escrowMilestone.contractMilestones(contractId, milestoneId_);
        assertEq(_contractor, contractor);

        vm.prank(new_contractor);
        vm.expectRevert(EscrowAccountRecovery.RecoveryPeriodStillPending.selector);
        recovery.executeRecovery(accountType, address(escrowMilestone), contractId, milestoneId_, contractor);

        skip(3 days);
        vm.prank(new_contractor);
        vm.expectRevert(abi.encodeWithSelector(IEscrow.Escrow__UnauthorizedAccount.selector, address(recovery)));
        recovery.executeRecovery(accountType, address(escrowMilestone), contractId, milestoneId, contractor);

        vm.prank(owner);
        registry.setAccountRecovery(address(recovery));

        vm.prank(new_contractor);
        vm.expectRevert(EscrowAccountRecovery.RecoveryNotInitiated.selector);
        recovery.executeRecovery(
            Enums.AccountTypeRecovery.CLIENT, address(escrowMilestone), contractId, milestoneId, contractor
        );

        vm.prank(new_contractor);
        vm.expectEmit(true, true, true, true);
        emit ContractorOwnershipTransferred(contractId, milestoneId, contractor, new_contractor);
        vm.expectEmit(true, true, true, true);
        emit RecoveryExecuted(new_contractor, recoveryHash);
        recovery.executeRecovery(accountType, address(escrowMilestone), contractId, milestoneId, contractor);
        (,,,, _executeAfter, _executed,,) = recovery.recoveryData(recoveryHash);
        assertEq(_executeAfter, 0);
        assertTrue(_executed);

        (_contractor,,,,,,) = escrowMilestone.contractMilestones(contractId, milestoneId);
        assertEq(_contractor, new_contractor);

        vm.prank(new_contractor);
        vm.expectRevert(EscrowAccountRecovery.RecoveryAlreadyExecuted.selector);
        recovery.executeRecovery(accountType, address(escrowMilestone), contractId, milestoneId, contractor);
    }

    function test_executeRecovery_milestone_contractor_reverts_ZeroAddressProvided() public {
        test_initiateRecovery_milestone_contractor();
        uint256 milestoneId_ = escrowMilestone.getMilestoneCount(contractId);
        vm.prank(owner);
        registry.setAccountRecovery(address(recovery));
        vm.prank(address(recovery));
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrowMilestone.transferContractorOwnership(contractId, --milestoneId_, address(0));
    }

    function test_initiateRecovery_hourly_client() public {
        initializeEscrowHourly();

        Enums.EscrowType escrowType = Enums.EscrowType.HOURLY;
        Enums.AccountTypeRecovery accountType = Enums.AccountTypeRecovery.CLIENT;
        bytes32 recoveryHash =
            recovery.getRecoveryHash(address(escrowHourly), contractId, milestoneId, client, new_client, accountType);

        vm.prank(guardian);
        recovery.initiateRecovery(address(escrowHourly), contractId, 0, client, new_client, escrowType, accountType);
        (
            address _escrow,
            address _oldAccount,
            uint256 _contractId,
            uint256 _milestoneId,
            uint256 _executeAfter,
            bool _executed,
            Enums.EscrowType _escrowType,
            Enums.AccountTypeRecovery _accountType
        ) = recovery.recoveryData(recoveryHash);
        assertEq(_escrow, address(escrowHourly));
        assertEq(_oldAccount, client);
        assertEq(_contractId, contractId);
        assertEq(_milestoneId, 0);
        assertEq(_executeAfter, block.timestamp + 3 days);
        assertFalse(_executed);
        assertEq(uint256(_escrowType), 2);
        assertEq(uint256(_accountType), 0);
    }

    function test_executeRecovery_hourly_client() public {
        test_initiateRecovery_hourly_client();
        Enums.AccountTypeRecovery accountType = Enums.AccountTypeRecovery.CLIENT;

        bytes32 recoveryHash =
            recovery.getRecoveryHash(address(escrowHourly), contractId, milestoneId, client, new_client, accountType);
        (
            address _escrow,
            address _oldAccount,
            uint256 _contractId,
            uint256 _milestoneId,
            uint256 _executeAfter,
            bool _executed,
            Enums.EscrowType _escrowType,
            Enums.AccountTypeRecovery _accountType
        ) = recovery.recoveryData(recoveryHash);
        assertEq(_escrow, address(escrowHourly));
        assertEq(_oldAccount, client);
        assertEq(_contractId, contractId);
        assertEq(_milestoneId, 0);
        assertEq(_executeAfter, block.timestamp + 3 days);
        assertFalse(_executed);
        assertEq(uint256(_escrowType), 2);
        assertEq(uint256(_accountType), 0);

        vm.prank(new_client);
        vm.expectRevert(EscrowAccountRecovery.RecoveryPeriodStillPending.selector);
        recovery.executeRecovery(accountType, address(escrowHourly), contractId, milestoneId, client);

        skip(3 days);
        bytes memory expectedRevertData =
            abi.encodeWithSelector(IEscrow.Escrow__UnauthorizedAccount.selector, address(recovery));
        vm.prank(new_client);
        vm.expectRevert(expectedRevertData);
        recovery.executeRecovery(accountType, address(escrowHourly), contractId, milestoneId, client);

        vm.prank(owner);
        registry.setAccountRecovery(address(recovery));

        vm.prank(new_client);
        vm.expectRevert(EscrowAccountRecovery.RecoveryNotInitiated.selector);
        recovery.executeRecovery(
            Enums.AccountTypeRecovery.CONTRACTOR, address(escrowHourly), contractId, milestoneId, client
        );

        vm.prank(new_client);
        vm.expectEmit(true, true, true, true);
        emit ClientOwnershipTransferred(client, new_client);
        vm.expectEmit(true, true, true, true);
        emit RecoveryExecuted(new_client, recoveryHash);
        recovery.executeRecovery(accountType, address(escrowHourly), contractId, milestoneId, client);
        (,,,, _executeAfter, _executed,,) = recovery.recoveryData(recoveryHash);
        assertEq(_executeAfter, 0);
        assertTrue(_executed);
        assertEq(escrowHourly.client(), new_client);

        vm.prank(new_client);
        vm.expectRevert(EscrowAccountRecovery.RecoveryAlreadyExecuted.selector);
        recovery.executeRecovery(accountType, address(escrowHourly), contractId, milestoneId, client);
    }

    function test_executeRecovery_hourly_client_reverts_ZeroAddressProvided() public {
        test_initiateRecovery_hourly_client();
        vm.prank(owner);
        registry.setAccountRecovery(address(recovery));
        vm.prank(address(recovery));
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrowHourly.transferClientOwnership(address(0));
    }

    function test_initiateRecovery_hourly_contractor() public {
        initializeEscrowHourly();

        Enums.EscrowType escrowType = Enums.EscrowType.HOURLY;
        Enums.AccountTypeRecovery accountType = Enums.AccountTypeRecovery.CONTRACTOR;
        bytes32 recoveryHash = recovery.getRecoveryHash(
            address(escrowHourly), contractId, milestoneId, contractor, new_contractor, accountType
        );

        vm.prank(guardian);
        vm.expectEmit(true, false, false, true);
        emit RecoveryInitiated(guardian, recoveryHash);
        recovery.initiateRecovery(
            address(escrowHourly), contractId, 0, contractor, new_contractor, escrowType, accountType
        );
        (
            address _escrow,
            address _oldAccount,
            uint256 _contractId,
            uint256 _milestoneId,
            uint256 _executeAfter,
            bool _executed,
            Enums.EscrowType _escrowType,
            Enums.AccountTypeRecovery _accountType
        ) = recovery.recoveryData(recoveryHash);
        assertEq(_escrow, address(escrowHourly));
        assertEq(_oldAccount, contractor);
        assertEq(_contractId, contractId);
        assertEq(_milestoneId, 0);
        assertEq(_executeAfter, block.timestamp + 3 days);
        assertFalse(_executed);
        assertEq(uint256(_escrowType), 2);
        assertEq(uint256(_accountType), 1);
    }

    function test_executeRecovery_hourly_contractor() public {
        test_initiateRecovery_hourly_contractor();
        Enums.AccountTypeRecovery accountType = Enums.AccountTypeRecovery.CONTRACTOR;

        bytes32 recoveryHash = recovery.getRecoveryHash(
            address(escrowHourly), contractId, milestoneId, contractor, new_contractor, accountType
        );
        (
            address _escrow,
            address _oldAccount,
            uint256 _contractId,
            uint256 _milestoneId,
            uint256 _executeAfter,
            bool _executed,
            Enums.EscrowType _escrowType,
            Enums.AccountTypeRecovery _accountType
        ) = recovery.recoveryData(recoveryHash);
        assertEq(_escrow, address(escrowHourly));
        assertEq(_oldAccount, contractor);
        assertEq(_contractId, contractId);
        assertEq(_milestoneId, 0);
        assertEq(_executeAfter, block.timestamp + 3 days);
        assertFalse(_executed);
        assertEq(uint256(_escrowType), 2);
        assertEq(uint256(_accountType), 1);

        (address _contractor,,,,,) = escrowHourly.contractDetails(contractId);
        assertEq(_contractor, contractor);

        vm.prank(new_contractor);
        vm.expectRevert(EscrowAccountRecovery.RecoveryPeriodStillPending.selector);
        recovery.executeRecovery(accountType, address(escrowHourly), contractId, milestoneId, contractor);

        skip(3 days);
        vm.prank(new_contractor);
        vm.expectRevert(abi.encodeWithSelector(IEscrow.Escrow__UnauthorizedAccount.selector, address(recovery)));
        recovery.executeRecovery(accountType, address(escrowHourly), contractId, milestoneId, contractor);

        vm.prank(owner);
        registry.setAccountRecovery(address(recovery));

        vm.prank(new_contractor);
        vm.expectRevert(EscrowAccountRecovery.RecoveryNotInitiated.selector);
        recovery.executeRecovery(
            Enums.AccountTypeRecovery.CLIENT, address(escrowHourly), contractId, milestoneId, contractor
        );

        vm.prank(new_contractor);
        vm.expectEmit(true, true, true, true);
        // emit ContractorOwnershipTransferred(contractId, contractor, new_contractor);
        // vm.expectEmit(true, true, true, true);
        emit RecoveryExecuted(new_contractor, recoveryHash);
        recovery.executeRecovery(accountType, address(escrowHourly), contractId, milestoneId, contractor);
        (,,,, _executeAfter, _executed,,) = recovery.recoveryData(recoveryHash);
        assertEq(_executeAfter, 0);
        assertTrue(_executed);

        (_contractor,,,,,) = escrowHourly.contractDetails(contractId);
        assertEq(_contractor, new_contractor);

        vm.prank(new_contractor);
        vm.expectRevert(EscrowAccountRecovery.RecoveryAlreadyExecuted.selector);
        recovery.executeRecovery(accountType, address(escrowHourly), contractId, milestoneId, contractor);
    }

    function test_executeRecovery_hourly_contractor_reverts_ZeroAddressProvided() public {
        test_initiateRecovery_hourly_contractor();

        vm.prank(owner);
        registry.setAccountRecovery(address(recovery));
        vm.prank(address(recovery));
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrowHourly.transferContractorOwnership(contractId, address(0));
    }

    function test_updateRecoveryPeriod() public {
        assertEq(recovery.recoveryPeriod(), 3 days);
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(EscrowAccountRecovery.UnauthorizedAccount.selector);
        recovery.updateRecoveryPeriod(7 days);
        vm.startPrank(owner);
        vm.expectRevert(EscrowAccountRecovery.RecoveryPeriodNotValid.selector);
        recovery.updateRecoveryPeriod(0);
        vm.expectRevert(EscrowAccountRecovery.RecoveryPeriodNotValid.selector);
        recovery.updateRecoveryPeriod(2 days);
        vm.expectRevert(EscrowAccountRecovery.RecoveryPeriodNotValid.selector);
        recovery.updateRecoveryPeriod(31 days);
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
