// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test, console2 } from "forge-std/Test.sol";

import { EscrowHourly, IEscrowHourly } from "src/EscrowHourly.sol";
import { EscrowAdminManager, OwnedRoles } from "src/modules/EscrowAdminManager.sol";
import { EscrowFeeManager, IEscrowFeeManager } from "src/modules/EscrowFeeManager.sol";
import { EscrowRegistry, IEscrowRegistry } from "src/modules/EscrowRegistry.sol";
import { Enums } from "src/libs/Enums.sol";
import { IEscrow } from "src/interfaces/IEscrow.sol";
import { MockRegistry } from "test/mocks/MockRegistry.sol";
import { MockUSDT } from "test/mocks/MockUSDT.sol";
import { ERC20Mock } from "@openzeppelin/mocks/token/ERC20Mock.sol";

contract EscrowHourlyUnitTest is Test {
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

    bytes32 contractorData;
    bytes32 salt;
    bytes contractData;

    Enums.FeeConfig feeConfig;
    Enums.Status status;

    IEscrowHourly.Deposit deposit;
    IEscrowHourly.WeeklyEntry weeklyEntry;
    IEscrowHourly.ContractDetails contractDetails;

    struct Deposit {
        address contractor;
        address paymentToken;
        uint256 prepaymentAmount;
        uint256 amountToClaim;
        uint256 amountToWithdraw;
        Enums.FeeConfig feeConfig;
    }

    struct ContractDetails {
        address contractor;
        address paymentToken;
        uint256 prepaymentAmount;
        uint256 amountToWithdraw;
        Enums.FeeConfig feeConfig;
        Enums.Status status;
    }

    struct WeeklyEntry {
        uint256 amountToClaim;
        Enums.Status weekStatus;
    }

    event Deposited(
        address indexed sender,
        uint256 indexed contractId,
        uint256 weekId,
        address paymentToken,
        uint256 totalDepositAmount
    );
    event Approved(
        address indexed approver, uint256 indexed contractId, uint256 weekId, uint256 amountApprove, address receiver
    );
    event RefilledPrepayment(address indexed sender, uint256 indexed contractId, uint256 amount);
    event RefilledWeekPayment(address indexed sender, uint256 indexed contractId, uint256 weekId, uint256 amount);
    event Claimed(address indexed contractor, uint256 indexed contractId, uint256 weekId, uint256 amount);
    event Withdrawn(address indexed withdrawer, uint256 indexed contractId, uint256 amount);
    event RegistryUpdated(address registry);
    event AdminManagerUpdated(address adminManager);
    event ReturnRequested(address indexed sender, uint256 indexed contractId);
    event ReturnApproved(address indexed approver, uint256 indexed contractId);
    event ReturnCanceled(address indexed sender, uint256 indexed contractId);
    event DisputeCreated(address indexed sender, uint256 indexed contractId, uint256 weekId);
    event DisputeResolved(
        address indexed approver,
        uint256 indexed contractId,
        uint256 weekId,
        Enums.Winner winner,
        uint256 clientAmount,
        uint256 contractorAmount
    );
    event BulkClaimed(
        address indexed contractor,
        uint256 indexed contractId,
        uint256 startWeekId,
        uint256 endWeekId,
        uint256 totalClaimedAmount,
        uint256 totalFeeAmount,
        uint256 totalClientFee
    );

    function setUp() public {
        owner = makeAddr("owner");
        treasury = makeAddr("treasury");
        client = makeAddr("client");
        contractor = makeAddr("contractor");

        escrow = new EscrowHourly();
        registry = new EscrowRegistry(owner);
        paymentToken = new ERC20Mock();
        feeManager = new EscrowFeeManager(300, 500, owner);
        adminManager = new EscrowAdminManager(owner);

        vm.startPrank(owner);
        registry.addPaymentToken(address(paymentToken));
        registry.setTreasury(treasury);
        registry.updateFeeManager(address(feeManager));
        vm.stopPrank();

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        contractorData = keccak256(abi.encodePacked(contractData, salt));

        deposit = IEscrowHourly.Deposit({
            contractor: contractor,
            paymentToken: address(paymentToken),
            prepaymentAmount: 1 ether,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY
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
        assertEq(escrow.getCurrentContractId(), 0);
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

    // Helpers
    function _computeDepositAndFeeAmount(
        address _escrow,
        uint256 _contractId,
        address _client,
        uint256 _depositAmount,
        Enums.FeeConfig _feeConfig
    ) internal view returns (uint256 totalDepositAmount, uint256 feeApplied) {
        address feeManagerAddress = registry.feeManager();
        IEscrowFeeManager _feeManager = IEscrowFeeManager(feeManagerAddress);
        (totalDepositAmount, feeApplied) =
            _feeManager.computeDepositAmountAndFee(_escrow, _contractId, _client, _depositAmount, _feeConfig);

        return (totalDepositAmount, feeApplied);
    }

    function _computeClaimableAndFeeAmount(
        address _escrow,
        uint256 _contractId,
        address _contractor,
        uint256 _claimAmount,
        Enums.FeeConfig _feeConfig
    ) internal view returns (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) {
        address feeManagerAddress = registry.feeManager();
        IEscrowFeeManager _feeManager = IEscrowFeeManager(feeManagerAddress);
        (claimAmount, feeAmount, clientFee) =
            _feeManager.computeClaimableAmountAndFee(_escrow, _contractId, _contractor, _claimAmount, _feeConfig);

        return (claimAmount, feeAmount, clientFee);
    }

    ///////////////////////////////////////////
    //            deposit tests              //
    ///////////////////////////////////////////

    function test_deposit_prepayment() public {
        test_initialize();
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 0);
        vm.startPrank(client);
        paymentToken.mint(client, 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        vm.expectEmit(true, true, true, true);
        emit Deposited(client, 1, 0, address(paymentToken), 1.03 ether);
        escrow.deposit(currentContractId, deposit);
        vm.stopPrank();
        currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
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
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        vm.startPrank(client);
        paymentToken.mint(client, 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        vm.expectEmit(true, true, true, true);
        emit Deposited(client, 1, 1, address(paymentToken), 1.03 ether);
        escrow.deposit(currentContractId, deposit);
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

        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + totalDepositAmount); //2.06ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(escrow.getWeeksCount(currentContractId), 2);
    }

    function test_deposit_reverts() public {
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        vm.prank(client);
        escrow.deposit(0, deposit);
        test_initialize();
        address notClient = makeAddr("notClient");
        vm.prank(notClient);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.deposit(0, deposit);

        deposit = IEscrowHourly.Deposit({
            contractor: contractor,
            paymentToken: address(paymentToken),
            prepaymentAmount: 0 ether,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY
        });
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidAmount.selector);
        escrow.deposit(0, deposit);

        ERC20Mock notPaymentToken = new ERC20Mock();
        deposit = IEscrowHourly.Deposit({
            contractor: contractor,
            paymentToken: address(notPaymentToken),
            prepaymentAmount: 1 ether,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY
        });
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__NotSupportedPaymentToken.selector);
        escrow.deposit(0, deposit);

        deposit = IEscrowHourly.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken),
            prepaymentAmount: 1 ether,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY
        });
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.deposit(0, deposit);

        vm.startPrank(address(client));
        paymentToken.mint(address(client), 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        deposit = IEscrowHourly.Deposit({
            contractor: contractor,
            paymentToken: address(paymentToken),
            prepaymentAmount: 1 ether,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY
        });
        vm.expectRevert(IEscrowHourly.Escrow__InvalidContractId.selector);
        escrow.deposit(1, deposit);
        vm.stopPrank();

        vm.prank(owner);
        registry.addToBlacklist(client);
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__BlacklistedAccount.selector);
        escrow.deposit(0, deposit);
    }

    function test_deposit_several_contracts() public {
        test_approve();
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);

        ERC20Mock new_token = new ERC20Mock();
        vm.prank(owner);
        registry.addPaymentToken(address(new_token));
        deposit = IEscrowHourly.Deposit({
            contractor: contractor,
            paymentToken: address(new_token),
            prepaymentAmount: 1 ether,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL
        });

        // deposit to the existing contractId
        vm.startPrank(client);
        new_token.mint(client, 1.03 ether);
        new_token.approve(address(escrow), 1.03 ether);
        paymentToken.mint(client, 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        escrow.deposit(currentContractId, deposit);
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

        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, 0);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, 1);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 1); //Status.ACTIVE
        assertEq(escrow.getWeeksCount(currentContractId), 2);

        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount * 3);

        address new_contractor = makeAddr("new_contractor");
        deposit = IEscrowHourly.Deposit({
            contractor: new_contractor,
            paymentToken: address(paymentToken),
            prepaymentAmount: 1 ether,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY
        });
        // create second contract
        vm.startPrank(client);
        paymentToken.mint(client, 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        escrow.deposit(0, deposit);
        vm.stopPrank();
        currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 2);
        assertEq(escrow.getWeeksCount(2), 1);

        // deposit to the second contract
        vm.startPrank(client);
        paymentToken.mint(client, 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        escrow.deposit(currentContractId, deposit);
        vm.stopPrank();
        (_contractor, _paymentToken, _prepaymentAmount, _amountToWithdraw, _feeConfig, _status) =
            escrow.contractDetails(2);
        assertEq(_contractor, new_contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 2 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 1); //Status.ACTIVE
        assertEq(escrow.getWeeksCount(2), 2);

        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount * 5);
    }

    function test_deposit_reverts_ContractorMismatch() public {
        test_deposit_prepayment();
        deposit = IEscrowHourly.Deposit({
            contractor: address(this),
            paymentToken: address(paymentToken),
            prepaymentAmount: 1 ether,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY
        });
        uint256 currentContractId = escrow.getCurrentContractId();
        vm.startPrank(client);
        paymentToken.mint(client, 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        vm.expectRevert(IEscrow.Escrow__ContractorMismatch.selector);
        escrow.deposit(currentContractId, deposit);
        vm.stopPrank();
    }

    function test_deposit_reverts_NotSetFeeManager() public {
        EscrowHourly escrow2 = new EscrowHourly();
        MockRegistry registry2 = new MockRegistry(owner);
        ERC20Mock paymentToken2 = new ERC20Mock();
        EscrowFeeManager feeManager2 = new EscrowFeeManager(300, 500, owner);

        vm.prank(owner);
        registry2.addPaymentToken(address(paymentToken2));
        escrow2.initialize(client, owner, address(registry2));

        uint256 depositAmount = 1 ether;
        uint256 totalDepositAmount = 1.03 ether;
        deposit = IEscrowHourly.Deposit({
            contractor: contractor,
            paymentToken: address(paymentToken2),
            prepaymentAmount: 0,
            amountToClaim: depositAmount,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY
        });

        vm.startPrank(address(client));
        paymentToken2.mint(address(client), totalDepositAmount);
        paymentToken2.approve(address(escrow2), totalDepositAmount);
        vm.expectRevert(IEscrow.Escrow__NotSetFeeManager.selector);
        escrow2.deposit(0, deposit);
        vm.stopPrank();

        vm.prank(owner);
        registry2.updateFeeManager(address(feeManager2));
        vm.startPrank(client);
        escrow2.deposit(0, deposit);
        vm.stopPrank();

        vm.prank(owner);
        registry2.updateFeeManager(address(0));

        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__NotSetFeeManager.selector);
        escrow2.claim(1, 0);
    }

    function test_deposit_amountToClaim() public {
        test_initialize();
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 0);
        deposit = IEscrowHourly.Deposit({
            contractor: contractor,
            paymentToken: address(paymentToken),
            prepaymentAmount: 0,
            amountToClaim: 1 ether,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY
        });
        vm.startPrank(client);
        paymentToken.mint(client, 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        vm.expectEmit(true, true, true, true);
        emit Deposited(client, 1, 0, address(paymentToken), 1.03 ether);
        escrow.deposit(0, deposit);
        vm.stopPrank();
        currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
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
        // week level
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, 0);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        (uint256 totalDepositAmount,) =
            _computeDepositAndFeeAmount(address(escrow), 1, client, _amountToClaim, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(escrow.getWeeksCount(currentContractId), 1);
    }

    ////////////////////////////////////////////
    //             approve tests              //
    ////////////////////////////////////////////

    function test_approve() public {
        test_deposit_prepayment();

        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
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
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
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

        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
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

        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
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

        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
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

        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
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

        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
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
        uint256 currentContractId = escrow.getCurrentContractId();
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
        uint256 currentContractId = escrow.getCurrentContractId();
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
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
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
        uint256 currentContractId = escrow.getCurrentContractId();
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

        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
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

        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
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

        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
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

    ////////////////////////////////////////////
    //              refill tests              //
    ////////////////////////////////////////////

    function test_refill_prepayment() public {
        test_deposit_amountToClaim();
        uint256 currentContractId = escrow.getCurrentContractId();
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

        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
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
        uint256 currentContractId = escrow.getCurrentContractId();
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

        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
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
        uint256 currentContractId = escrow.getCurrentContractId();
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

        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
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
        uint256 currentContractId = escrow.getCurrentContractId();
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

        (uint256 totalDepositAmount, uint256 feeApplied) = _computeDepositAndFeeAmount(
            address(escrow), 1, client, _prepaymentAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );

        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(contractor)), 0 ether);

        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) = _computeClaimableAndFeeAmount(
            address(escrow), 1, contractor, _amountToClaim, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(feeApplied, clientFee);

        vm.startPrank(contractor);
        vm.expectEmit(true, true, true, true);
        emit Claimed(contractor, 1, weekId, claimAmount);
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
        uint256 depositAmount = 1e6;
        uint256 depositAmountAndFee = 1.08e6;
        deposit = IEscrowHourly.Deposit({
            contractor: contractor,
            paymentToken: address(usdt),
            prepaymentAmount: 0 ether,
            amountToClaim: depositAmount,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL
        });

        test_initialize();
        // uint256 currentContractId = escrow.getCurrentContractId();
        vm.startPrank(client);
        usdt.mint(client, depositAmountAndFee);
        usdt.approve(address(escrow), depositAmountAndFee);
        escrow.deposit(0, deposit); //currentContractId
        vm.stopPrank();
        // currentContractId = escrow.getCurrentContractId();
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

        (uint256 claimAmount, uint256 contractorFee, uint256 clientFee) =
            _computeClaimableAndFeeAmount(address(escrow), 1, contractor, 1e6, Enums.FeeConfig.CLIENT_COVERS_ALL); //depositAmount=1e6

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
        uint256 currentContractId = escrow.getCurrentContractId();
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

        (uint256 claimAmount, uint256 contractorFee, uint256 clientFee) = _computeClaimableAndFeeAmount(
            address(escrow), 1, contractor, depositAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY
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
        uint256 currentContractId = escrow.getCurrentContractId();
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

        (uint256 totalDepositAmount, uint256 feeAmount) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + feeAmount + _amountToClaim);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (, uint256 initialFeeAmount) = _computeDepositAndFeeAmount(
            address(escrow), 1, client, _prepaymentAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY
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
        (claimAmount, feeAmount,) = _computeClaimableAndFeeAmount(
            address(escrow), 1, contractor, _amountToClaim, Enums.FeeConfig.CLIENT_COVERS_ONLY
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
        uint256 currentContractId = escrow.getCurrentContractId();
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

        uint256 currentContractId = escrow.getCurrentContractId();
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

        vm.prank(owner);
        registry.addToBlacklist(contractor);
        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__BlacklistedAccount.selector);
        escrow.claim(currentContractId, weekId);

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

        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        assertEq(weekId, 1);

        vm.startPrank(address(client));
        paymentToken.mint(address(client), amountToMint);
        paymentToken.approve(address(escrow), amountToMint);
        escrow.deposit(currentContractId, deposit);
        assertEq(paymentToken.balanceOf(address(escrow)), amountToMint * 3);
        currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        weekId = escrow.getWeeksCount(currentContractId);
        assertEq(weekId, 2);
        vm.stopPrank();

        vm.prank(owner);
        registry.addToBlacklist(contractor);
        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__BlacklistedAccount.selector);
        escrow.claimAll(currentContractId, 1, 1);
        vm.prank(owner);
        registry.removeFromBlacklist(contractor);

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

        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) = _computeClaimableAndFeeAmount(
            address(escrow), 1, contractor, amountApprove, Enums.FeeConfig.CLIENT_COVERS_ONLY
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
            contractor, currentContractId, startWeekId, endWeekId, claimAmount * 2, feeAmount * 2, clientFee * 2
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
        uint256 depositAmount = 1e6;
        uint256 depositAmountAndFee = 1.03e6;
        deposit = IEscrowHourly.Deposit({
            contractor: contractor,
            paymentToken: address(usdt),
            prepaymentAmount: 0 ether,
            amountToClaim: depositAmount,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY
        });

        test_initialize();
        uint256 currentContractId = escrow.getCurrentContractId();
        // make a deposit with prepaymentAmount == 0
        vm.startPrank(client);
        usdt.mint(client, depositAmountAndFee);
        usdt.approve(address(escrow), depositAmountAndFee);
        escrow.deposit(currentContractId, deposit);
        vm.stopPrank();
        currentContractId = escrow.getCurrentContractId();
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
        escrow.deposit(currentContractId, deposit);
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
        escrow.deposit(currentContractId, deposit);
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

        (uint256 claimAmount, uint256 contractorFee, uint256 clientFee) =
            _computeClaimableAndFeeAmount(address(escrow), 1, contractor, 1e6, Enums.FeeConfig.CLIENT_COVERS_ONLY);
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
        uint256 depositAmount = 1e6;
        uint256 depositAmountAndFee = 1.03e6;
        deposit = IEscrowHourly.Deposit({
            contractor: contractor,
            paymentToken: address(usdt),
            prepaymentAmount: 0 ether,
            amountToClaim: depositAmount,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY
        });

        test_initialize();
        uint256 currentContractId = escrow.getCurrentContractId();
        // make a deposit with prepaymentAmount == 0
        vm.startPrank(client);
        usdt.mint(client, depositAmountAndFee);
        usdt.approve(address(escrow), depositAmountAndFee);
        escrow.deposit(currentContractId, deposit);
        vm.stopPrank();
        currentContractId = escrow.getCurrentContractId();
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
        escrow.deposit(currentContractId, deposit);
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
        escrow.deposit(currentContractId, deposit);
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

        (uint256 claimAmount, uint256 contractorFee, uint256 clientFee) =
            _computeClaimableAndFeeAmount(address(escrow), 1, contractor, 1e6, Enums.FeeConfig.CLIENT_COVERS_ONLY);

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

        (claimAmount, contractorFee, clientFee) =
            _computeClaimableAndFeeAmount(address(escrow), 1, contractor, 1e6, Enums.FeeConfig.CLIENT_COVERS_ONLY);

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
        deposit = IEscrowHourly.Deposit({
            contractor: contractor,
            paymentToken: address(usdt),
            prepaymentAmount: 0 ether,
            amountToClaim: depositAmount,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY
        });

        test_initialize();
        // uint256 currentContractId = escrow.getCurrentContractId();// =0
        // make a deposit with prepaymentAmount == 0
        vm.startPrank(client);
        usdt.mint(client, depositAmountAndFee);
        usdt.approve(address(escrow), depositAmountAndFee);
        escrow.deposit(0, deposit);
        vm.stopPrank();
        // currentContractId = escrow.getCurrentContractId();
        // uint256 weekId1 = escrow.getWeeksCount(currentContractId);
        // assertEq(currentContractId, 1);
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
        deposit = IEscrowHourly.Deposit({
            contractor: contractor,
            paymentToken: address(usdt),
            prepaymentAmount: 0 ether,
            amountToClaim: depositAmount,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY
        });

        vm.startPrank(client);
        usdt.mint(client, depositAmountAndFee);
        usdt.approve(address(escrow), depositAmountAndFee);
        escrow.deposit(1, deposit);
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
        deposit = IEscrowHourly.Deposit({
            contractor: contractor,
            paymentToken: address(usdt),
            prepaymentAmount: 0 ether,
            amountToClaim: depositAmount,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY
        });
        vm.startPrank(client);
        usdt.mint(client, depositAmountAndFee);
        usdt.approve(address(escrow), depositAmountAndFee);
        escrow.deposit(1, deposit);
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

        (uint256 claimAmount, uint256 contractorFee, uint256 clientFee) =
            _computeClaimableAndFeeAmount(address(escrow), 1, contractor, 1e6, Enums.FeeConfig.CLIENT_COVERS_ONLY);

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

        (claimAmount, contractorFee, clientFee) =
            _computeClaimableAndFeeAmount(address(escrow), 1, contractor, 1e6, Enums.FeeConfig.CLIENT_COVERS_ONLY);

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
        uint256 currentContractId = escrow.getCurrentContractId();
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

        (uint256 totalDepositAmount, uint256 feeAmount) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + feeAmount + _amountToClaim);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (, uint256 initialFeeAmount) = _computeDepositAndFeeAmount(
            address(escrow), 1, client, _prepaymentAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY
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
        (claimAmount, feeAmount,) = _computeClaimableAndFeeAmount(
            address(escrow), 1, contractor, _amountToClaim, Enums.FeeConfig.CLIENT_COVERS_ONLY
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
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_weekStatus), 3); //Status.APPROVED

        // 1st claim after auto approval befor refill
        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) = _computeClaimableAndFeeAmount(
            address(escrow), 1, contractor, _amountToClaim, Enums.FeeConfig.CLIENT_COVERS_ONLY
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

        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
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

        (uint256 claimAmount2, uint256 feeAmount2, uint256 clientFee2) = _computeClaimableAndFeeAmount(
            address(escrow), 1, contractor, _amountToClaim, Enums.FeeConfig.CLIENT_COVERS_ONLY
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
        uint256 currentContractId = escrow.getCurrentContractId();
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
        emit Deposited(client, 1, 1, address(paymentToken), 1.03 ether);
        escrow.deposit(currentContractId, deposit);
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
        test_initialize();
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 0);
        deposit = IEscrowHourly.Deposit({
            contractor: contractor,
            paymentToken: address(paymentToken),
            prepaymentAmount: 0,
            amountToClaim: 1 ether,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY
        });
        vm.startPrank(client);
        paymentToken.mint(client, 2.06 ether);
        paymentToken.approve(address(escrow), 2.06 ether);
        vm.expectEmit(true, true, true, true);
        emit Deposited(client, 1, 0, address(paymentToken), 1.03 ether);
        // 1st deposit
        escrow.deposit(0, deposit);
        currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        assertEq(escrow.getWeeksCount(currentContractId), 1);
        uint256 weeksCount = escrow.getWeeksCount(currentContractId);
        uint256 weekId1 = --weeksCount;
        // 2d deposit to the created contractId on previous step
        escrow.deposit(currentContractId, deposit);
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

        (uint256 totalDepositAmount,) =
            _computeDepositAndFeeAmount(address(escrow), 1, client, _amountToClaim, Enums.FeeConfig.CLIENT_COVERS_ONLY);
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
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 1 ether);
        assertEq(uint256(_status), 8); //Status.REFUND_APPROVED
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrow.weeklyEntries(currentContractId, 0);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 1); //Status.ACTIVE

        (uint256 totalDepositAmount, uint256 feeAmount) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (, uint256 initialFeeAmount) = _computeDepositAndFeeAmount(
            address(escrow), 1, client, _prepaymentAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(client, currentContractId, _amountToWithdraw + feeAmount);
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
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 1 ether);
        assertEq(uint256(_status), 8); //Status.REFUND_APPROVED
        (uint256 _amountToClaim,) = escrow.weeklyEntries(currentContractId, 0);
        assertEq(_amountToClaim, 0 ether);

        (uint256 totalDepositAmount, uint256 feeAmount) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (, uint256 initialFeeAmount) = _computeDepositAndFeeAmount(
            address(escrow), 1, client, _prepaymentAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(client, currentContractId, _amountToWithdraw + feeAmount);
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
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, _prepaymentAmount);
        assertEq(uint256(_status), 7); //Status.RESOLVED

        (uint256 _amountToClaim,) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, 0 ether);

        (uint256 totalDepositAmount, uint256 feeAmount) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (, uint256 initialFeeAmount) = _computeDepositAndFeeAmount(
            address(escrow), 1, client, _prepaymentAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(client, currentContractId, totalDepositAmount);
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
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, _prepaymentAmount / 2);
        assertEq(uint256(_status), 7); //Status.RESOLVED

        (uint256 _amountToClaim,) = escrow.weeklyEntries(currentContractId, --weekId);
        assertEq(_amountToClaim, _prepaymentAmount / 2);

        (uint256 totalDepositAmount, uint256 feeAmount) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + feeAmount + _amountToClaim);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (, uint256 initialFeeAmount) = _computeDepositAndFeeAmount(
            address(escrow), 1, client, _prepaymentAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(client, currentContractId, totalDepositAmount);
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
        uint256 currentContractId = escrow.getCurrentContractId();
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

        (uint256 claimAmount, uint256 contractorFeeAmount, uint256 clientFee) =
            _computeClaimableAndFeeAmount(address(escrow), 1, contractor, 0.5 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        (clientFee);

        vm.prank(contractor);
        escrow.claim(currentContractId, weekId);

        (_amountToClaim, _weekStatus) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_weekStatus), 4); //Status.COMPLETED

        (,,,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 4); //Status.COMPLETED

        (uint256 withdrawAmount, uint256 clientFeeAmount) =
            _computeDepositAndFeeAmount(address(escrow), 1, client, 0.5 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);

        vm.prank(client);
        escrow.withdraw(currentContractId);

        (,,,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 9); //Status.CANCELED

        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);
        assertEq(paymentToken.balanceOf(address(client)), withdrawAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), contractorFeeAmount + clientFeeAmount);
    }

    function test_withdraw_reverts_UnauthorizedAccount() public {
        test_deposit_prepayment();
        uint256 currentContractId = escrow.getCurrentContractId();
        address notClient = makeAddr("notClient");
        vm.prank(notClient);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.withdraw(currentContractId);
    }

    function test_withdraw_reverts_InvalidStatusForWithdraw() public {
        test_deposit_amountToClaim();
        uint256 currentContractId = escrow.getCurrentContractId();
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusToWithdraw.selector);
        escrow.withdraw(currentContractId);
    }

    function test_withdraw_reverts_NoFundsAvailableForWithdraw() public {
        test_requestReturn_whenActive();
        assertEq(paymentToken.balanceOf(address(client)), 0);
        uint256 currentContractId = escrow.getCurrentContractId();
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

    function test_withdraw_reverts_BlacklistedAccount() public {
        test_resolveDispute_winnerClient();
        uint256 currentContractId = escrow.getCurrentContractId();
        vm.prank(owner);
        registry.addToBlacklist(client);
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__BlacklistedAccount.selector);
        escrow.withdraw(currentContractId);
    }

    function test_withdraw_reverts_InvalidStatusForWithdraw_canceled() public {
        test_withdraw_whenRefundApprovedByOwner();
        uint256 currentContractId = escrow.getCurrentContractId();
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
        uint256 currentContractId = escrow.getCurrentContractId();
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
        uint256 currentContractId = escrow.getCurrentContractId();
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
        uint256 currentContractId = escrow.getCurrentContractId();
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
        uint256 currentContractId = escrow.getCurrentContractId();
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
        uint256 currentContractId = escrow.getCurrentContractId();
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
        uint256 currentContractId = escrow.getCurrentContractId();
        (,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit ReturnApproved(owner, currentContractId);
        escrow.approveReturn(currentContractId);
        (,, _prepaymentAmount, _amountToWithdraw,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 1 ether);
        assertEq(uint256(_status), 8); //Status.REFUND_APPROVED
    }

    function test_approveReturn_by_contractor() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        (,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(contractor);
        vm.expectEmit(true, true, true, true);
        emit ReturnApproved(contractor, currentContractId);
        escrow.approveReturn(currentContractId);
        (,, _prepaymentAmount, _amountToWithdraw,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 1 ether);
        assertEq(uint256(_status), 8); //Status.REFUND_APPROVED
    }

    function test_approveReturn_reverts_UnauthorizedToApproveReturn() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
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
        uint256 currentContractId = escrow.getCurrentContractId();
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
        uint256 currentContractId = escrow.getCurrentContractId();
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        status = Enums.Status.ACTIVE;
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnCanceled(client, currentContractId);
        escrow.cancelReturn(currentContractId, status);
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
    }

    function test_cancelReturn_reverts() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(owner);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.cancelReturn(currentContractId, status);
        (,,,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        status = Enums.Status.CANCELED;
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusProvided.selector);
        escrow.cancelReturn(currentContractId, status);
        (,,,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
    }

    function test_cancelReturn_reverts_NoReturnRequested() public {
        test_deposit_prepayment();
        uint256 currentContractId = escrow.getCurrentContractId();
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__NoReturnRequested.selector);
        escrow.cancelReturn(currentContractId, status);
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
    }

    ////////////////////////////////////////////
    //              dispute tests             //
    ////////////////////////////////////////////

    function test_createDispute_by_client() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit DisputeCreated(client, currentContractId, --weekId);
        escrow.createDispute(currentContractId, weekId);
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED
    }

    function test_createDispute_by_contractor() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (,, uint256 _prepaymentAmount,,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(contractor);
        vm.expectEmit(true, true, true, true);
        emit DisputeCreated(contractor, currentContractId, --weekId);
        escrow.createDispute(currentContractId, weekId);
        (,, _prepaymentAmount,,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED
    }

    function test_createDispute_reverts_CreateDisputeNotAllowed() public {
        test_deposit_prepayment();
        uint256 currentContractId = escrow.getCurrentContractId();
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
        uint256 currentContractId = escrow.getCurrentContractId();
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
        uint256 currentContractId = escrow.getCurrentContractId();
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
        emit DisputeResolved(owner, currentContractId, weekId, _winner, clientAmount, 0);
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
        uint256 currentContractId = escrow.getCurrentContractId();
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
        emit DisputeResolved(owner, currentContractId, weekId, _winner, 0, contractorAmount);
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
        uint256 currentContractId = escrow.getCurrentContractId();
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
        emit DisputeResolved(owner, currentContractId, weekId, _winner, clientAmount, contractorAmount);
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
        uint256 currentContractId = escrow.getCurrentContractId();
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
        emit DisputeResolved(owner, currentContractId, weekId, _winner, 0, 0);
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
        uint256 currentContractId = escrow.getCurrentContractId();
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
        uint256 currentContractId = escrow.getCurrentContractId();
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
        uint256 currentContractId = escrow.getCurrentContractId();
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
        uint256 currentContractId = escrow.getCurrentContractId();
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
        uint256 currentContractId = escrow.getCurrentContractId();
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

    function test_resolveDispute_reverts_InvalidWinnerSpecified() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (,, uint256 _prepaymentAmount, uint256 _amountToWithdraw,, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED

        vm.prank(owner);
        // vm.expectRevert(IEscrow.Escrow__InvalidWinnerSpecified.selector);
        vm.expectRevert(); // panic: failed to convert value into enum type (0x21)
        escrow.resolveDispute(currentContractId, --weekId, Enums.Winner(uint256(4)), 1 ether, 0); //Invalid enum value
            // for Winner
        (uint256 _amountToClaim,) = escrow.weeklyEntries(currentContractId, weekId);
        assertEq(_amountToClaim, 0 ether);
        (,,, _amountToWithdraw,, _status) = escrow.contractDetails(currentContractId);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED
    }

    ////////////////////////////////////////////
    //      ownership & management tests      //
    ////////////////////////////////////////////

    function test_updateRegistry() public {
        test_initialize();
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
        test_initialize();
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
