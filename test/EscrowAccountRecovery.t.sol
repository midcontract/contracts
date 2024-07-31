// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {EscrowFixedPrice, IEscrowFixedPrice} from "src/EscrowFixedPrice.sol";
import {EscrowAccountRecovery} from "src/modules/EscrowAccountRecovery.sol";
import {EscrowFeeManager, IEscrowFeeManager} from "src/modules/EscrowFeeManager.sol";
import {EscrowRegistry, IEscrowRegistry} from "src/modules/EscrowRegistry.sol";
import {IEscrow} from "src/interfaces/IEscrow.sol";
import {Enums} from "src/libs/Enums.sol";

contract EscrowAccountRecoveryUnitTest is Test {
    EscrowAccountRecovery recovery;
    EscrowFixedPrice escrow;
    EscrowRegistry registry;
    ERC20Mock paymentToken;
    EscrowFeeManager feeManager;

    address owner;
    address guardian;
    address treasury;
    address client;
    address contractor;
    address new_client;

    bytes contractData;
    bytes32 contractorData;
    bytes32 salt;

    EscrowFixedPrice.Deposit deposit;
    EscrowAccountRecovery.RecoveryData recoveryInfo;

    event RecoveryInitiated(address indexed sender, bytes32 indexed recoveryHash);
    event RecoveryExecuted(address indexed sender, bytes32 indexed recoveryHash);
    event RecoveryCanceled(address indexed sender, bytes32 indexed recoveryHash);
    event GuardianUpdated(address guardian);
    event ClientOwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setUp() public {
        owner = makeAddr("owner");
        guardian = makeAddr("guardian");
        treasury = makeAddr("treasury");
        client = makeAddr("client");
        contractor = makeAddr("contractor");
        new_client = makeAddr("new_client");

        recovery = new EscrowAccountRecovery(owner, guardian);
        escrow = new EscrowFixedPrice();
        registry = new EscrowRegistry(owner);
        paymentToken = new ERC20Mock();
        feeManager = new EscrowFeeManager(3_00, 5_00, owner);

        vm.startPrank(owner);
        registry.addPaymentToken(address(paymentToken));
        registry.setTreasury(treasury);
        registry.updateFeeManager(address(feeManager));
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
        assertEq(recovery.owner(), address(owner));
        assertEq(recovery.guardian(), address(guardian));
        assertEq(recovery.MIN_RECOVERY_PERIOD(), 3 days);
    }

    // helpers
    function initializeEscrowFixedPrice() public {
        assertFalse(escrow.initialized());
        escrow.initialize(client, owner, address(registry));
        assertTrue(escrow.initialized());
        uint256 depositAmount = 1.03 ether;
        vm.startPrank(address(client));
        paymentToken.mint(address(client), depositAmount);
        paymentToken.approve(address(escrow), depositAmount);
        escrow.deposit(deposit);
        vm.stopPrank();
    }

    function test_initiateRecovery() public {
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
        test_initiateRecovery();
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
        test_initiateRecovery();
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

    // after executeRecovery
    function test_executeRecovery_reverts() public {}

    function test_updateGuardian() public {
        assertEq(recovery.guardian(), guardian);
        address notGuardian = makeAddr("notGuardian");
        vm.prank(notGuardian);
        vm.expectRevert(EscrowAccountRecovery.InvalidGuardian.selector);
        recovery.updateGuardian(notGuardian);
        assertEq(recovery.guardian(), guardian);
        address newGuardian = makeAddr("newGuardian");
        vm.startPrank(guardian);
        vm.expectRevert(EscrowAccountRecovery.ZeroAddressProvided.selector);
        recovery.updateGuardian(address(0));
        vm.expectEmit(true, true, true, true);
        emit GuardianUpdated(newGuardian);
        recovery.updateGuardian(newGuardian);
        assertEq(recovery.guardian(), newGuardian);
        vm.stopPrank();
    }
}
