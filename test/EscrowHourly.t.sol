// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {EscrowHourly, IEscrowHourly, Ownable} from "src/EscrowHourly.sol";
import {EscrowFeeManager, IEscrowFeeManager} from "src/modules/EscrowFeeManager.sol";
import {EscrowRegistry, IEscrowRegistry} from "src/modules/EscrowRegistry.sol";
import {Enums} from "src/libs/Enums.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {IEscrow} from "src/interfaces/IEscrow.sol";
import {MockRegistry} from "test/mocks/MockRegistry.sol";

contract EscrowHourlyUnitTest is Test {
    EscrowHourly escrow;
    EscrowRegistry registry;
    ERC20Mock paymentToken;
    ERC20Mock newPaymentToken;
    EscrowFeeManager feeManager;

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
    IEscrowHourly.ContractDetails contractDetails;

    struct ContractDetails {
        address paymentToken;
        uint256 prepaymentAmount;
        Enums.Status status;
    }

    struct Deposit {
        address contractor;
        uint256 amount;
        uint256 amountToClaim;
        Enums.FeeConfig feeConfig;
    }

    event Deposited(
        address indexed sender,
        uint256 indexed contractId,
        uint256 weekId,
        address paymentToken,
        uint256 totalDepositAmount
    );
    event Submitted(address indexed sender, uint256 indexed contractId, uint256 indexed weekId);
    event Approved(uint256 indexed contractId, uint256 indexed weekId, uint256 amountApprove, address receiver);
    event RefilledPrepayment(uint256 indexed contractId, uint256 amount);
    event RefilledWeekPayment(uint256 indexed contractId, uint256 indexed weekId, uint256 amount);
    event Claimed(uint256 indexed contractId, uint256 indexed weekId, uint256 indexed amount);
    event Withdrawn(uint256 indexed contractId, uint256 indexed weekId, uint256 amount);
    event ReturnRequested(uint256 contractId, uint256 weekId);
    event ReturnApproved(uint256 contractId, uint256 weekId, address sender);
    event ReturnCanceled(uint256 contractId, uint256 weekId);
    event DisputeCreated(uint256 contractId, uint256 weekId, address sender);
    event DisputeResolved(
        uint256 contractId, uint256 weekId, Enums.Winner winner, uint256 clientAmount, uint256 contractorAmount
    );

    function setUp() public {
        owner = makeAddr("owner");
        treasury = makeAddr("treasury");
        client = makeAddr("client");
        contractor = makeAddr("contractor");

        escrow = new EscrowHourly();
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

        contractDetails = IEscrowHourly.ContractDetails({
            paymentToken: address(paymentToken),
            prepaymentAmount: 1 ether,
            status: Enums.Status.ACTIVE
        });

        deposit = IEscrowHourly.Deposit({
            contractor: contractor,
            amount: 0,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY
        });
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
        escrow.initialize(client, owner, address(registry));
        assertEq(escrow.client(), client);
        assertEq(escrow.owner(), owner);
        assertEq(address(escrow.registry()), address(registry));
        assertEq(escrow.getCurrentContractId(), 0);
        assertTrue(escrow.initialized());
    }

    function test_initialize_reverts() public {
        assertFalse(escrow.initialized());
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.initialize(address(0), owner, address(registry));
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.initialize(client, address(0), address(registry));
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.initialize(client, owner, address(0));
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.initialize(address(0), address(0), address(0));
        escrow.initialize(client, owner, address(registry));
        assertTrue(escrow.initialized());
        vm.expectRevert(IEscrow.Escrow__AlreadyInitialized.selector);
        escrow.initialize(client, owner, address(registry));
    }

    // Helpers
    function _computeDepositAndFeeAmount(address _client, uint256 _depositAmount, Enums.FeeConfig _feeConfig)
        internal
        view
        returns (uint256 totalDepositAmount, uint256 feeApplied)
    {
        address feeManagerAddress = registry.feeManager();
        IEscrowFeeManager feeManager = IEscrowFeeManager(feeManagerAddress);
        (totalDepositAmount, feeApplied) = feeManager.computeDepositAmountAndFee(_client, _depositAmount, _feeConfig);

        return (totalDepositAmount, feeApplied);
    }

    function _computeClaimableAndFeeAmount(address _contractor, uint256 _claimAmount, Enums.FeeConfig _feeConfig)
        internal
        view
        returns (uint256 claimAmount, uint256 feeAmount, uint256 clientFee)
    {
        address feeManagerAddress = registry.feeManager();
        IEscrowFeeManager feeManager = IEscrowFeeManager(feeManagerAddress);
        (claimAmount, feeAmount, clientFee) =
            feeManager.computeClaimableAmountAndFee(_contractor, _claimAmount, _feeConfig);

        return (claimAmount, feeAmount, clientFee);
    }

    ///////////////////////////////////////////
    //            deposit tests              //
    ///////////////////////////////////////////

    function test_deposit_prepayment() public {
        test_initialize();
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 0);
        vm.startPrank(address(client));
        paymentToken.mint(address(client), 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        vm.expectEmit(true, true, true, true);
        emit Deposited(address(client), 1, 0, address(paymentToken), 1.03 ether);
        escrow.deposit(currentContractId, address(paymentToken), 1 ether, deposit);
        vm.stopPrank();
        currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        (address _contractor, uint256 _amount, uint256 _amountToClaim, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(escrow.getWeeksCount(currentContractId), 1);
    }

    function test_deposit_existing_contract() public {
        test_deposit_prepayment();
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        vm.startPrank(address(client));
        paymentToken.mint(address(client), 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        vm.expectEmit(true, true, true, true);
        emit Deposited(address(client), 1, 1, address(paymentToken), 1.03 ether);
        escrow.deposit(currentContractId, address(paymentToken), 1 ether, deposit);
        vm.stopPrank();
        // contract level
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        // week level
        (address _contractor, uint256 _amount, uint256 _amountToClaim, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, 1);
        assertEq(_contractor, contractor);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY

        (uint256 totalDepositAmount,) =
            _computeDepositAndFeeAmount(client, _prepaymentAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + totalDepositAmount); //2.06 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(escrow.getWeeksCount(currentContractId), 2);
    }

    function test_deposit_reverts() public {
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        vm.prank(client);
        escrow.deposit(0, address(paymentToken), 1 ether, deposit);
        test_initialize();
        address notClient = makeAddr("notClient");
        vm.prank(notClient);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.deposit(0, address(paymentToken), 1 ether, deposit);

        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidAmount.selector);
        escrow.deposit(0, address(paymentToken), 0 ether, deposit);

        ERC20Mock notPaymentToken = new ERC20Mock();
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__NotSupportedPaymentToken.selector);
        escrow.deposit(0, address(notPaymentToken), 1 ether, deposit);

        deposit = IEscrowHourly.Deposit({
            contractor: address(0),
            amount: 0,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY
        });
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.deposit(0, address(paymentToken), 1 ether, deposit);

        vm.startPrank(address(client));
        paymentToken.mint(address(client), 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        deposit = IEscrowHourly.Deposit({
            contractor: contractor,
            amount: 0,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY
        });
        vm.expectRevert(IEscrowHourly.Escrow__InvalidContractId.selector);
        escrow.deposit(1, address(paymentToken), 1 ether, deposit);
        vm.stopPrank();
    }

    function test_deposit_amountToClaim() public {
        test_initialize();
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 0);
        deposit = IEscrowHourly.Deposit({
            contractor: contractor,
            amount: 0,
            amountToClaim: 1 ether,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY
        });
        vm.startPrank(client);
        paymentToken.mint(address(client), 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        vm.expectEmit(true, true, true, true);
        emit Deposited(address(client), 1, 0, address(paymentToken), 1.03 ether);
        escrow.deposit(0, address(paymentToken), 0 ether, deposit);
        vm.stopPrank();
        currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        // contract level
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED
        // week level
        (address _contractor, uint256 _amount, uint256 _amountToClaim, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY

        (uint256 totalDepositAmount,) =
            _computeDepositAndFeeAmount(client, _amountToClaim, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), 1.03 ether);
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
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor, uint256 _amount, uint256 _amountToClaim, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        uint256 amountToMint = 1.03 ether;
        uint256 amountApprove = 1 ether;
        vm.startPrank(client);
        paymentToken.mint(address(client), amountToMint);
        paymentToken.approve(address(escrow), amountToMint);
        vm.expectEmit(true, true, true, true);
        emit Approved(currentContractId, weekId, amountApprove, contractor);
        escrow.approve(currentContractId, weekId, amountApprove, contractor);
        (_contractor, _amount, _amountToClaim,) = escrow.contractWeeks(currentContractId, weekId);
        // assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + totalDepositAmount); //amountApprove+fee
    }

    function test_approve_by_admin() public {
        test_deposit_prepayment();

        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor, uint256 _amount, uint256 _amountToClaim, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        uint256 amountApprove = 1.5 ether;
        vm.startPrank(owner);
        vm.expectRevert(IEscrowHourly.Escrow__InsufficientPrepayment.selector);
        escrow.approve(currentContractId, weekId, amountApprove, contractor);
        amountApprove = 1 ether;
        vm.expectEmit(true, true, true, true);
        emit Approved(currentContractId, weekId, amountApprove, contractor);
        escrow.approve(currentContractId, weekId, amountApprove, contractor);
        (_contractor, _amount, _amountToClaim,) = escrow.contractWeeks(currentContractId, weekId);
        // assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether - amountApprove); //0
        assertEq(uint256(_status), 2); //Status.APPROVED
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //prepaymentAmount+fee
    }

    function test_approve_reverts_UnauthorizedAccount() public {
        test_deposit_prepayment();
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor, uint256 _amount, uint256 _amountToClaim, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        uint256 amountApprove = 1.03 ether;
        vm.startPrank(address(this));
        paymentToken.mint(address(client), amountApprove);
        paymentToken.approve(address(escrow), amountApprove);
        vm.expectRevert(); //IEscrow.Escrow__UnauthorizedAccount.selector
        escrow.approve(currentContractId, weekId, amountApprove, contractor);
        (_contractor, _amount, _amountToClaim,) = escrow.contractWeeks(currentContractId, weekId);
        // assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
    }

    function test_approve_reverts_InvalidStatusForApprove() public {
        test_deposit_amountToClaim();
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amountToClaim,) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 1 ether);

        uint256 amountApprove = 1.03 ether;
        vm.startPrank(client);
        paymentToken.mint(address(client), amountApprove);
        paymentToken.approve(address(escrow), amountApprove);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusForApprove.selector);
        escrow.approve(currentContractId, weekId, amountApprove, contractor);
        (,, _amountToClaim,) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amountToClaim, 1 ether);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED
        vm.stopPrank();
    }

    function test_approve_reverts_UnauthorizedReceiver() public {
        test_deposit_prepayment();

        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amountToClaim, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        uint256 amountApprove = 1.03 ether;
        vm.startPrank(client);
        paymentToken.mint(address(client), amountApprove);
        paymentToken.approve(address(escrow), amountApprove);
        vm.expectRevert(IEscrow.Escrow__UnauthorizedReceiver.selector);
        escrow.approve(currentContractId, weekId, amountApprove, address(this));
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.stopPrank();
    }

    function test_approve_reverts_InvalidAmount() public {
        test_deposit_prepayment();

        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amountToClaim, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        uint256 amountApprove = 0 ether;
        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidAmount.selector);
        escrow.approve(currentContractId, weekId, amountApprove, contractor);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.stopPrank();
    }

    function test_approve_reverts_InvalidWeekId() public {
        test_deposit_prepayment();

        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amountToClaim, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        uint256 amountApprove = 1.03 ether;
        vm.startPrank(client);
        paymentToken.mint(address(client), amountApprove);
        paymentToken.approve(address(escrow), amountApprove);
        vm.expectRevert(IEscrowHourly.Escrow__InvalidWeekId.selector);
        escrow.approve(currentContractId, ++weekId, amountApprove, contractor);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.stopPrank();
    }

    ////////////////////////////////////////////
    //              refill tests              //
    ////////////////////////////////////////////

    function test_refill_prepayment() public {
        test_deposit_amountToClaim();
        uint256 currentContractId = escrow.getCurrentContractId();
        // contract level
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        // week level
        (address _contractor, uint256 _amount, uint256 _amountToClaim, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY

        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);

        uint256 amountAdditional = 1 ether;
        vm.startPrank(address(client));
        paymentToken.mint(address(client), totalDepositAmount);
        paymentToken.approve(address(escrow), totalDepositAmount);
        vm.expectEmit(true, true, true, true);
        emit RefilledPrepayment(currentContractId, amountAdditional);
        escrow.refill(currentContractId, weekId, amountAdditional, Enums.RefillType.PREPAYMENT);
        vm.stopPrank();
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, amountAdditional);
        assertEq(uint256(_status), 2); //Status.APPROVED

        (,, _amountToClaim,) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amountToClaim, 1 ether);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + totalDepositAmount); //2.06 ether
    }

    function test_refill_week_payment() public {
        test_deposit_amountToClaim();
        uint256 currentContractId = escrow.getCurrentContractId();
        // contract level
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        // week level
        (address _contractor, uint256 _amount, uint256 _amountToClaim, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY

        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);

        uint256 amountAdditional = 1 ether;
        vm.startPrank(address(client));
        paymentToken.mint(address(client), totalDepositAmount);
        paymentToken.approve(address(escrow), totalDepositAmount);
        vm.expectEmit(true, true, true, true);
        emit RefilledWeekPayment(currentContractId, weekId, amountAdditional);
        escrow.refill(currentContractId, weekId, amountAdditional, Enums.RefillType.WEEK_PAYMENT);
        vm.stopPrank();
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED

        (,, _amountToClaim,) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amountToClaim, 1 ether + amountAdditional);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + totalDepositAmount); //2.06 ether
    }

    function test_refill_reverts() public {
        test_deposit_amountToClaim();
        uint256 currentContractId = escrow.getCurrentContractId();
        // contract level
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        // week level
        (address _contractor, uint256 _amount, uint256 _amountToClaim, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY

        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);

        uint256 amountAdditional = 0 ether;
        vm.prank(address(this));
        vm.expectRevert(); // Escrow__UnauthorizedAccount()
        escrow.refill(currentContractId, weekId, 1 ether, Enums.RefillType.PREPAYMENT);
        vm.startPrank(client);
        paymentToken.mint(address(client), amountAdditional);
        paymentToken.approve(address(escrow), amountAdditional);
        vm.expectRevert(IEscrow.Escrow__InvalidAmount.selector);
        escrow.refill(currentContractId, weekId, amountAdditional, Enums.RefillType.WEEK_PAYMENT);
        vm.expectRevert(); //IEscrowHourly.Escrow__InvalidWeekId.selector
        escrow.refill(currentContractId, 2, 1 ether, Enums.RefillType.WEEK_PAYMENT);
        vm.stopPrank();

        (,, _amountToClaim,) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amountToClaim, 1 ether);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
    }

    ////////////////////////////////////////////
    //              claim tests               //
    ////////////////////////////////////////////

    function test_claim_clientCoversOnly() public {
        test_approve();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amountToClaim, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        (uint256 totalDepositAmount, uint256 feeApplied) =
            _computeDepositAndFeeAmount(client, _prepaymentAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY);

        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(contractor)), 0 ether);

        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
            _computeClaimableAndFeeAmount(contractor, _amountToClaim, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(feeApplied, clientFee);

        vm.startPrank(contractor);
        vm.expectEmit(true, true, true, true);
        emit Claimed(currentContractId, weekId, claimAmount);
        escrow.claim(currentContractId, weekId);

        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), feeAmount + clientFee);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);

        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 3); //Status.COMPLETED

        (,, _amountToClaim,) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amountToClaim, 0 ether);
        vm.stopPrank();
    }

    function test_claim_reverts() public {
        test_deposit_prepayment();

        uint256 currentContractId = escrow.getCurrentContractId();
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor, uint256 _amount, uint256 _amountToClaim, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);

        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusToClaim.selector);
        // vm.expectRevert(IEscrow.Escrow__NotApproved.selector); //TODO test
        escrow.claim(currentContractId, weekId);

        uint256 amountToMint = 1.03 ether;
        uint256 amountApprove = 1 ether;
        vm.startPrank(client);
        paymentToken.mint(address(client), amountToMint);
        paymentToken.approve(address(escrow), amountToMint);
        vm.expectEmit(true, true, true, true);
        emit Approved(currentContractId, weekId, amountApprove, contractor);
        escrow.approve(currentContractId, weekId, amountApprove, contractor);
        (_contractor, _amount, _amountToClaim,) = escrow.contractWeeks(currentContractId, weekId);
        // assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED
        vm.stopPrank();

        vm.prank(address(this));
        vm.expectRevert(); //IEscrow.Escrow__UnauthorizedAccount.selector
        escrow.claim(currentContractId, weekId);
        (_contractor, _amount, _amountToClaim,) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amountToClaim, amountApprove);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED
    }
    /*

    ///////////////////////////////////////////
    //           withdraw tests              //
    ///////////////////////////////////////////

    function test_withdraw_whenRefundApprovedByOwner() public {
        test_approveReturn_by_owner();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 1 ether);
        assertEq(uint256(_status), 7); //Status.REFUND_APPROVED

        (uint256 totalDepositAmount, uint256 feeAmount) =
            _computeDepositAndFeeAmount(client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (uint256 initialDepositAmount, uint256 initialFeeAmount) =
            _computeDepositAndFeeAmount(client, _amount, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(currentContractId, weekId, _amountToWithdraw + feeAmount);
        escrow.withdraw(currentContractId, weekId);
        (,, uint256 _amountAfter,, uint256 _amountToWithdrawAfter,,, Enums.Status _statusAfter) =
            escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amountAfter, 0 ether);
        assertEq(_amountToWithdrawAfter, 0 ether);
        assertEq(uint256(_statusAfter), 8); //Status.CANCELED
        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether); //totalDepositAmount - (_amountToWithdraw + feeAmount)
        assertEq(paymentToken.balanceOf(address(client)), _amountToWithdraw + feeAmount); //==totalDepositAmount = _amountToWithdraw + feeAmount
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee);
    }

    function test_withdraw_whenRefundApprovedByContractor() public {
        test_approveReturn_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 1 ether);
        assertEq(uint256(_status), 7); //Status.REFUND_APPROVED

        (uint256 totalDepositAmount, uint256 feeAmount) =
            _computeDepositAndFeeAmount(client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (uint256 initialDepositAmount, uint256 initialFeeAmount) =
            _computeDepositAndFeeAmount(client, _amount, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(currentContractId, weekId, totalDepositAmount);
        escrow.withdraw(currentContractId, weekId);
        (,, uint256 _amountAfter,, uint256 _amountToWithdrawAfter,,, Enums.Status _statusAfter) =
            escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amountAfter, 0 ether);
        assertEq(_amountToWithdrawAfter, 0 ether);
        assertEq(uint256(_statusAfter), 8); //Status.CANCELED
        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether); //totalDepositAmount - (_amountToWithdraw + feeAmount)
        assertEq(paymentToken.balanceOf(address(client)), totalDepositAmount); //==totalDepositAmount = _amountToWithdraw + feeAmount
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee);
    }

    function test_withdraw_whenDisputeResolved() public {
        test_resolveDispute_winnerClient();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, _amount);
        assertEq(uint256(_status), 6); //Status.RESOLVED

        (uint256 totalDepositAmount, uint256 feeAmount) =
            _computeDepositAndFeeAmount(client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (uint256 initialDepositAmount, uint256 initialFeeAmount) =
            _computeDepositAndFeeAmount(client, _amount, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(currentContractId, weekId, totalDepositAmount);
        escrow.withdraw(currentContractId, weekId);
        (,, uint256 _amountAfter,, uint256 _amountToWithdrawAfter,,, Enums.Status _statusAfter) =
            escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amountAfter, 0 ether);
        assertEq(_amountToWithdrawAfter, 0 ether);
        assertEq(uint256(_statusAfter), 8); //Status.CANCELED
        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee);
    }

    function test_withdraw_whenDisputeResolvedSplit() public {
        test_resolveDispute_winnerSplit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (
            address _contractor,
            ,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            ,
            ,
            Enums.Status _status
        ) = escrow.contractWeeks(currentContractId, 0);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0.5 ether);
        assertEq(_amountToWithdraw, 0.5 ether);
        assertEq(uint256(_status), 6); //Status.RESOLVED

        (uint256 totalDepositAmount, uint256 feeAmount) =
            _computeDepositAndFeeAmount(client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + feeAmount + _amountToClaim);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (uint256 initialDepositAmount, uint256 initialFeeAmount) =
            _computeDepositAndFeeAmount(client, _amount, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(currentContractId, 0, totalDepositAmount);
        escrow.withdraw(currentContractId, 0);
        (,, uint256 _amountAfter,, uint256 _amountToWithdrawAfter,,, Enums.Status _statusAfter) =
            escrow.contractWeeks(currentContractId, 0);
        assertEq(_amountAfter, 0.5 ether);
        assertEq(_amountToWithdrawAfter, 0 ether);
        assertEq(uint256(_statusAfter), 8); //Status.CANCELED
        assertEq(paymentToken.balanceOf(address(escrow)), 0.5 ether);
        assertEq(paymentToken.balanceOf(address(client)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee);
    }

    function test_withdraw_reverts_UnauthorizedAccount() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        address notClient = makeAddr("notClient");
        vm.prank(notClient);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.withdraw(currentContractId, --weekId);
    }

    function test_withdraw_reverts_InvalidStatusForWithdraw() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusToWithdraw.selector);
        escrow.withdraw(currentContractId, --weekId);
    }

    function test_withdraw_reverts_NoFundsAvailableForWithdraw() public {
        test_requestReturn_whenPending();
        assertEq(paymentToken.balanceOf(address(client)), 0);
        uint256 currentContractId = escrow.getCurrentContractId();
        (,,,,,,, Enums.Status _status) = escrow.contractWeeks(currentContractId, 0);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(client);
        escrow.createDispute(currentContractId, 0);
        (,,,,,,, _status) = escrow.contractWeeks(currentContractId, 0);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        vm.prank(owner);
        escrow.resolveDispute(currentContractId, 0, Enums.Winner.SPLIT, 0, 0.5 ether);
        (,,,,,,, _status) = escrow.contractWeeks(currentContractId, 0);
        assertEq(uint256(_status), 6); //Status.RESOLVED
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__NoFundsAvailableForWithdraw.selector);
        escrow.withdraw(currentContractId, 0);
        (,,,,,,, _status) = escrow.contractWeeks(currentContractId, 0);
        assertEq(uint256(_status), 6); //Status.RESOLVED
        assertEq(paymentToken.balanceOf(address(client)), 0);
    }

    ////////////////////////////////////////////
    //          return request tests          //
    ////////////////////////////////////////////

    function test_requestReturn_whenPending() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnRequested(currentContractId, weekId);
        escrow.requestReturn(currentContractId, weekId);
        (_contractor,, _amount,,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_reverts_UnauthorizedAccount() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.prank(contractor);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender);
        escrow.requestReturn(currentContractId, weekId);
        (_contractor,, _amount,,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_requestReturn_reverts_ReturnNotAllowed() public {
        test_requestReturn_whenPending();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__ReturnNotAllowed.selector);
        escrow.requestReturn(currentContractId, weekId);
        (_contractor,, _amount,,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_whenSubmitted() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnRequested(currentContractId, weekId);
        escrow.requestReturn(currentContractId, weekId);
        (_contractor,, _amount,,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_reverts_submitted_UnauthorizedAccount() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        vm.prank(address(this));
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender);
        escrow.requestReturn(currentContractId, weekId);
        (_contractor,, _amount,,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    function test_approveReturn_by_owner() public {
        test_requestReturn_whenPending();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit ReturnApproved(currentContractId, weekId, owner);
        escrow.approveReturn(currentContractId, weekId);
        (_contractor,, _amount,, _amountToWithdraw,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 1 ether);
        assertEq(uint256(_status), 7); //Status.REFUND_APPROVED
    }

    function test_approveReturn_by_contractor() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(contractor);
        vm.expectEmit(true, true, true, true);
        emit ReturnApproved(currentContractId, weekId, contractor);
        escrow.approveReturn(currentContractId, weekId);
        (_contractor,, _amount,, _amountToWithdraw,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 1 ether);
        assertEq(uint256(_status), 7); //Status.REFUND_APPROVED
    }

    function test_approveReturn_reverts_UnauthorizedToApproveReturn() public {
        test_requestReturn_whenPending();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__UnauthorizedToApproveReturn.selector);
        escrow.approveReturn(currentContractId, weekId);
        (_contractor,, _amount,, _amountToWithdraw,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 4); //Status.REFUND_APPROVED
    }

    function test_approveReturn_reverts_NoReturnRequested() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,,,,,,, Enums.Status _status) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__NoReturnRequested.selector);
        escrow.approveReturn(currentContractId, weekId);
        (_contractor,,,,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_approveReturn_reverts_submitted_NoReturnRequested() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,,,,,,, Enums.Status _status) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__NoReturnRequested.selector);
        escrow.approveReturn(currentContractId, weekId);
        (_contractor,,,,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    function test_cancelReturn() public {
        test_requestReturn_whenPending();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (,,,,,,, Enums.Status _status) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        Enums.Status status = Enums.Status.ACTIVE;
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnCanceled(currentContractId, weekId);
        escrow.cancelReturn(currentContractId, weekId, status);
        (,,,,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_cancelReturn_submitted() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,,,,,,, Enums.Status _status) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        Enums.Status status = Enums.Status.SUBMITTED;
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnCanceled(currentContractId, weekId);
        escrow.cancelReturn(currentContractId, weekId, status);
        (_contractor,,,,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    function test_cancelReturn_reverts() public {
        test_requestReturn_whenPending();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (,,,,,,, Enums.Status _status) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        Enums.Status status = Enums.Status.ACTIVE;
        vm.prank(owner);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.cancelReturn(currentContractId, weekId, status);
        (,,,,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        status = Enums.Status.CANCELED;
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusProvided.selector);
        escrow.cancelReturn(currentContractId, weekId, status);
        (,,,,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_cancelReturn_reverts_submitted() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        Enums.Status status = Enums.Status.RESOLVED;
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusProvided.selector);
        escrow.cancelReturn(currentContractId, weekId, status);
        (,,,,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_cancelReturn_reverts_submitted_NoReturnRequested() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,,,,,,, Enums.Status _status) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        Enums.Status status = Enums.Status.ACTIVE;
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__NoReturnRequested.selector);
        escrow.cancelReturn(currentContractId, weekId, status);
        (_contractor,,,,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    ////////////////////////////////////////////
    //              dispute tests             //
    ////////////////////////////////////////////

    function test_createDispute_by_client() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit DisputeCreated(currentContractId, weekId, client);
        escrow.createDispute(currentContractId, weekId);
        (_contractor,, _amount,,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    function test_createDispute_by_contractor() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(contractor);
        vm.expectEmit(true, true, true, true);
        emit DisputeCreated(currentContractId, weekId, contractor);
        escrow.createDispute(currentContractId, weekId);
        (_contractor,, _amount,,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    function test_createDispute_reverts_CreateDisputeNotAllowed() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__CreateDisputeNotAllowed.selector);
        escrow.createDispute(currentContractId, weekId);
        (_contractor,, _amount,,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_createDispute_reverts_UnauthorizedToApproveDispute() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(address(this));
        vm.expectRevert(IEscrow.Escrow__UnauthorizedToApproveDispute.selector);
        escrow.createDispute(currentContractId, weekId);
        (_contractor,, _amount,,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_resolveDispute_winnerClient() public {
        test_createDispute_by_client();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (
            address _contractor,
            ,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            ,
            ,
            Enums.Status _status
        ) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        Enums.Winner _winner = Enums.Winner.CLIENT;
        uint256 clientAmount = _amount;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(currentContractId, weekId, _winner, clientAmount, 0);
        escrow.resolveDispute(currentContractId, weekId, _winner, clientAmount, 0);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, clientAmount);
        assertEq(uint256(_status), 6); //Status.RESOLVED
    }

    function test_resolveDispute_winnerContractor() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (
            address _contractor,
            ,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            ,
            ,
            Enums.Status _status
        ) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        Enums.Winner _winner = Enums.Winner.CONTRACTOR;
        uint256 contractorAmount = _amount;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(currentContractId, weekId, _winner, 0, contractorAmount);
        escrow.resolveDispute(currentContractId, weekId, _winner, 0, contractorAmount);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, contractorAmount);
        assertEq(_amountToWithdraw, 0);
        assertEq(uint256(_status), 2); //Status.APPROVED
    }

    function test_resolveDispute_winnerSplit() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (
            address _contractor,
            ,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            ,
            ,
            Enums.Status _status
        ) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        Enums.Winner _winner = Enums.Winner.SPLIT;
        uint256 clientAmount = _amount / 2;
        uint256 contractorAmount = _amount / 2;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(currentContractId, weekId, _winner, clientAmount, contractorAmount);
        escrow.resolveDispute(currentContractId, weekId, _winner, clientAmount, contractorAmount);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0.5 ether);
        assertEq(_amountToWithdraw, 0.5 ether);
        assertEq(uint256(_status), 6); //Status.RESOLVED
    }

    function test_resolveDispute_winnerSplit_ZeroAllocationToEachParty() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (
            address _contractor,
            ,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            ,
            ,
            Enums.Status _status
        ) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        Enums.Winner _winner = Enums.Winner.SPLIT;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(currentContractId, weekId, _winner, 0, 0);
        escrow.resolveDispute(currentContractId, weekId, _winner, 0, 0);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 6); //Status.RESOLVED
    }

    function test_resolveDispute_reverts_DisputeNotActiveForThisDeposit() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (,,,,,,, Enums.Status _status) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__DisputeNotActiveForThisDeposit.selector);
        escrow.resolveDispute(currentContractId, weekId, Enums.Winner.CLIENT, 0, 0);
        (,,,,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_resolveDispute_reverts_UnauthorizedToApproveDispute() public {
        test_createDispute_by_client();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (,,,,,,, Enums.Status _status) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        vm.prank(address(this));
        vm.expectRevert(); //Unauthorized()
        escrow.resolveDispute(currentContractId, weekId, Enums.Winner.CONTRACTOR, 0, 0);
        (,,,,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    function test_resolveDispute_reverts_winnerClient_ResolutionExceedsDepositedAmount() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (
            address _contractor,
            ,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            ,
            ,
            Enums.Status _status
        ) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__ResolutionExceedsDepositedAmount.selector);
        escrow.resolveDispute(currentContractId, weekId, Enums.Winner.CLIENT, 1.1 ether, 0 ether);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    function test_resolveDispute_reverts_winnerContractor_ResolutionExceedsDepositedAmount() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (
            address _contractor,
            ,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            ,
            ,
            Enums.Status _status
        ) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__ResolutionExceedsDepositedAmount.selector);
        escrow.resolveDispute(currentContractId, weekId, Enums.Winner.CONTRACTOR, 0 ether, 1.1 ether);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    function test_resolveDispute_reverts_winnerSplit_ResolutionExceedsDepositedAmount() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (
            address _contractor,
            ,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            ,
            ,
            Enums.Status _status
        ) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__ResolutionExceedsDepositedAmount.selector);
        escrow.resolveDispute(currentContractId, weekId, Enums.Winner.SPLIT, 1 ether, 1 wei);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    function test_resolveDispute_reverts_InvalidWinnerSpecified() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (
            address _contractor,
            ,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            ,
            ,
            Enums.Status _status
        ) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        vm.prank(owner);
        // vm.expectRevert(IEscrow.Escrow__InvalidWinnerSpecified.selector);
        vm.expectRevert(); // panic: failed to convert value into enum type (0x21)
        escrow.resolveDispute(currentContractId, weekId, Enums.Winner(uint256(3)), _amount, 0); // Invalid enum value for Winner
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }
    */
}
