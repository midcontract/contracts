// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {Escrow, IEscrow} from "src/Escrow.sol";
import {Registry, IRegistry} from "src/Registry.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract EscrowUnitTest is Test {
    uint256 constant MAX_BPS = 100_00; // 100%

    Escrow public escrow;
    Registry public registry;
    ERC20Mock public paymentToken;
    ERC20Mock public newPaymentToken;

    address public client;
    address public treasury;
    address public admin;
    address public contractor;

    Escrow.Deposit public deposit;
    FeeConfig public feeConfig;
    Status public status;

    bytes32 public contractorData;
    bytes32 public salt;
    bytes public contractData;

    struct Deposit {
        address contractor;
        address paymentToken;
        uint256 amount;
        uint256 amountToClaim;
        uint256 timeLock;
        bytes32 contractorData;
        FeeConfig feeConfig;
        Status status;
    }

    enum FeeConfig {
        FULL,
        ONLY_CLIENT,
        ONLY_CONTRACTOR,
        FREE
    }

    enum Status {
        PENDING,
        SUBMITTED,
        APPROVED
    }

    event Deposited(
        address indexed sender,
        uint256 indexed contractId,
        address indexed paymentToken,
        uint256 amount,
        uint256 timeLock,
        FeeConfig feeConfig
    );

    event Withdrawn(address indexed sender, uint256 indexed contractId, address indexed paymentToken, uint256 amount);

    event Submitted(address indexed sender, uint256 indexed contractId);

    event Approved(uint256 indexed contractId, uint256 indexed amountApprove, address indexed receiver);

    event Refilled(uint256 indexed contractId, uint256 indexed amountAdditional);

    event Claimed(address indexed sender, uint256 indexed contractId, address indexed paymentToken, uint256 amount);

    function setUp() public {
        client = makeAddr("client");
        treasury = makeAddr("treasury");
        admin = makeAddr("admin");
        contractor = makeAddr("contractor");
        escrow = new Escrow();
        registry = new Registry();
        paymentToken = new ERC20Mock();
        registry.addPaymentToken(address(paymentToken));
        registry.setTreasury(treasury);

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        contractorData = keccak256(abi.encodePacked(contractData, salt));

        deposit = IEscrow.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 1 ether,
            amountToClaim: 0 ether,
            timeLock: 0,
            contractorData: contractorData,
            feeConfig: IEscrow.FeeConfig.FULL,
            status: IEscrow.Status.PENDING
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
        escrow.initialize(client, admin, address(registry), 3_00, 8_00);
        assertEq(escrow.client(), client);
        assertEq(escrow.admin(), admin);
        assertEq(address(escrow.registry()), address(registry));
        assertEq(escrow.feeClient(), 3_00);
        assertEq(escrow.feeContractor(), 8_00);
        assertEq(escrow.getCurrentContractId(), 0);
        assertTrue(escrow.initialized());
    }

    function test_initialize_reverts() public {
        assertFalse(escrow.initialized());
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.initialize(address(0), admin, address(registry), 3_00, 8_00);
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.initialize(client, address(0), address(registry), 3_00, 8_00);
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.initialize(client, admin, address(0), 3_00, 8_00);
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.initialize(address(0), address(registry), address(0), 3_00, 8_00);
        vm.expectRevert(IEscrow.Escrow__FeeTooHigh.selector);
        escrow.initialize(client, admin, address(registry), 101_00, 8_00);
        vm.expectRevert(IEscrow.Escrow__FeeTooHigh.selector);
        escrow.initialize(client, admin, address(registry), 3_00, 101_00);
        vm.expectRevert(IEscrow.Escrow__FeeTooHigh.selector);
        escrow.initialize(client, admin, address(registry), 101_00, 101_00);
        escrow.initialize(client, admin, address(registry), 3_00, 8_00);
        assertTrue(escrow.initialized());
        vm.expectRevert(IEscrow.Escrow__AlreadyInitialized.selector);
        escrow.initialize(client, admin, address(registry), 3_00, 8_00);
    }

    ///////////////////////////////////////////
    //            deposit tests              //
    ///////////////////////////////////////////

    function test_deposit() public {
        test_initialize();
        vm.startPrank(address(client));
        paymentToken.mint(address(client), 1.11 ether);
        paymentToken.approve(address(escrow), 1.11 ether);
        vm.expectEmit(true, true, true, true);
        emit Deposited(address(client), 1, address(paymentToken), 1 ether, 0, FeeConfig.FULL);
        escrow.deposit(deposit);
        vm.stopPrank();
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        assertEq(paymentToken.balanceOf(address(escrow)), 1.11 ether);
        // assertEq(paymentToken.balanceOf(address(treasury)), 0.11 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (
            address _contractor,
            address _paymentToken,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _timeLock,
            bytes32 _contractorData,
            IEscrow.FeeConfig _feeConfig,
            IEscrow.Status _status
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_timeLock, 0);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 0); //IEscrow.FeeConfig.FULL
        assertEq(uint256(_status), 0); //Status.PENDING
    }

    function test_deposit_reverts() public {
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        vm.prank(client);
        escrow.deposit(deposit);
        test_initialize();
        address notClient = makeAddr("notClient");
        vm.prank(notClient);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.deposit(deposit);

        ERC20Mock notPaymentToken = new ERC20Mock();
        deposit = IEscrow.Deposit({
            contractor: address(0),
            paymentToken: address(notPaymentToken),
            amount: 1 ether,
            amountToClaim: 0 ether,
            timeLock: 0,
            contractorData: contractorData,
            feeConfig: IEscrow.FeeConfig.FULL,
            status: IEscrow.Status.PENDING
        });
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__NotSupportedPaymentToken.selector);
        escrow.deposit(deposit);
    }

    function test_computeDepositAmount() public {
        test_initialize();
        uint256 depositAmount = 1 ether;
        uint256 configFeeFull = 0;
        uint256 netDepositAmount =
            depositAmount + (depositAmount * (escrow.feeClient() + escrow.feeContractor())) / MAX_BPS;
        assertEq(escrow.computeDepositAmount(depositAmount, configFeeFull), netDepositAmount);
        configFeeFull = 1;
        netDepositAmount = depositAmount + (depositAmount * (escrow.feeClient())) / MAX_BPS;
        assertEq(escrow.computeDepositAmount(depositAmount, configFeeFull), netDepositAmount);
    }

    // helper
    function _computeFeeAmount(uint256 _amount, uint256 _feeConfig)
        internal
        view
        returns (uint256 feeAmount, uint256 withdrawAmount)
    {
        if (_feeConfig == 0) {
            // uint256(FeeConfig.FULL)
            feeAmount = (_amount * (escrow.feeClient() + escrow.feeContractor())) / MAX_BPS;
            withdrawAmount = _amount - feeAmount;
            return (feeAmount, withdrawAmount);
        }
        feeAmount = (_amount * escrow.feeClient()) / MAX_BPS;
        withdrawAmount = _amount - feeAmount;
        return (feeAmount, withdrawAmount);
    }

    ///////////////////////////////////////////
    //           withdraw tests              //
    ///////////////////////////////////////////

    function test_withdraw() public {
        test_deposit();
        assertEq(paymentToken.balanceOf(address(escrow)), 1.11 ether);
        // assertEq(paymentToken.balanceOf(address(treasury)), 0.11 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);

        uint256 currentContractId = escrow.getCurrentContractId();
        (,, uint256 _amount, uint256 _amountToClaim,,, IEscrow.FeeConfig _feeConfig, IEscrow.Status _status) =
            escrow.deposits(currentContractId);

        (uint256 feeAmount, uint256 withdrawAmount) = _computeFeeAmount(_amount, uint256(_feeConfig));

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(client, currentContractId, address(paymentToken), withdrawAmount);
        escrow.withdraw(currentContractId);
        (,, uint256 _amountAfter,,,,, IEscrow.Status _statusAfter) = escrow.deposits(currentContractId);
        assertEq(_amountAfter, 0);
        // TODO add assert for IEscrow.Status _statusAfter if it's changed
        assertEq(paymentToken.balanceOf(address(escrow)), feeAmount); //0.11 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0.11 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether + withdrawAmount);
    }

    function test_withdraw_reverts() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        address notClient = makeAddr("notClient");
        vm.prank(notClient);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.withdraw(currentContractId);
        vm.prank(client);
        escrow.withdraw(currentContractId);
    }

    ///////////////////////////////////////////
    //             submit tests              //
    ///////////////////////////////////////////

    function test_submit() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (
            address _contractor,
            ,
            uint256 _amount,
            uint256 _amountToClaim,
            ,
            bytes32 _contractorData,
            IEscrow.FeeConfig _feeConfig,
            IEscrow.Status _status
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 0); //Status.PENDING

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);
        vm.prank(contractor);
        vm.expectEmit(true, true, true, true);
        emit Submitted(contractor, currentContractId);
        escrow.submit(currentContractId, contractData, salt);
        (_contractor,, _amount, _amountToClaim,,, _feeConfig, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_contractorData, contractorDataHash);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    function test_submit_reverts() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (
            address _contractor,
            ,
            uint256 _amount,
            uint256 _amountToClaim,
            ,
            bytes32 _contractorData,
            IEscrow.FeeConfig _feeConfig,
            IEscrow.Status _status
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 0); //Status.PENDING

        contractData = bytes("contract_data_");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);
        vm.startPrank(contractor);
        vm.expectRevert(IEscrow.Escrow__InvalidContractorDataHash.selector);
        escrow.submit(currentContractId, contractData, salt);
        assertEq(_contractor, address(0));

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(41)));
        contractorDataHash = escrow.getContractorDataHash(contractData, salt);
        vm.startPrank(contractor);
        vm.expectRevert(IEscrow.Escrow__InvalidContractorDataHash.selector);
        escrow.submit(currentContractId, contractData, salt);
        assertEq(_contractor, address(0));
        vm.stopPrank();
    }

    ////////////////////////////////////////////
    //        approve & refill tests          //
    ////////////////////////////////////////////

    // amountApprove > 0, amountAdditional == 0
    function test_approve() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (
            address _contractor,
            ,
            uint256 _amount,
            uint256 _amountToClaim,
            ,
            bytes32 _contractorData,
            IEscrow.FeeConfig _feeConfig,
            IEscrow.Status _status
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        uint256 amountApprove = 1 ether;
        uint256 amountAdditional = 0 ether;

        vm.startPrank(client);
        vm.expectEmit(true, true, true, true);
        emit Approved(currentContractId, amountApprove, contractor);
        escrow.approve(currentContractId, amountApprove, amountAdditional, contractor);
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove);
        assertEq(uint256(_status), 0); //Status.PENDING
        vm.stopPrank();
    }

    // amountApprove == 0, amountAdditional > 0
    function test_approve2() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (
            address _contractor,
            ,
            uint256 _amount,
            uint256 _amountToClaim,
            ,
            bytes32 _contractorData,
            IEscrow.FeeConfig _feeConfig,
            IEscrow.Status _status
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        uint256 amountApprove = 0 ether;
        uint256 amountAdditional = 0.5 ether;

        uint256 escrowBalanceBefore = paymentToken.balanceOf(address(escrow));
        vm.startPrank(client);
        uint256 depositAmount = escrow.computeDepositAmount(amountAdditional, uint256(FeeConfig.FULL));
        paymentToken.mint(address(client), depositAmount);
        paymentToken.approve(address(escrow), depositAmount);
        vm.expectEmit(true, true, true, true);
        emit Refilled(currentContractId, amountAdditional);
        escrow.approve(currentContractId, amountApprove, amountAdditional, contractor);
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_amount, 1 ether + amountAdditional);
        assertEq(_amountToClaim, amountApprove); //0
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(address(escrow)), escrowBalanceBefore + depositAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
    }

    // amountApprove > 0, amountAdditional > 0
    function test_approve_refill() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (
            address _contractor,
            ,
            uint256 _amount,
            uint256 _amountToClaim,
            ,
            bytes32 _contractorData,
            IEscrow.FeeConfig _feeConfig,
            IEscrow.Status _status
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        uint256 amountApprove = 1 ether;
        uint256 amountAdditional = 0.5 ether;

        uint256 escrowBalanceBefore = paymentToken.balanceOf(address(escrow));
        vm.startPrank(client);
        uint256 depositAmount = escrow.computeDepositAmount(amountAdditional, uint256(FeeConfig.FULL));
        paymentToken.mint(address(client), depositAmount);
        paymentToken.approve(address(escrow), depositAmount);
        vm.expectEmit(true, true, true, true);
        emit Refilled(currentContractId, amountAdditional);
        vm.expectEmit(true, true, true, true);
        emit Approved(currentContractId, amountApprove, contractor);
        escrow.approve(currentContractId, amountApprove, amountAdditional, contractor);
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_amount, 1 ether + amountAdditional);
        assertEq(_amountToClaim, amountApprove);
        assertEq(uint256(_status), 0); //Status.PENDING
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(address(escrow)), escrowBalanceBefore + depositAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
    }

    function test_approve_reverts_InvalidStatusForApprove() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (
            address _contractor,
            ,
            uint256 _amount,
            uint256 _amountToClaim,
            ,
            bytes32 _contractorData,
            IEscrow.FeeConfig _feeConfig,
            IEscrow.Status _status
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 0); //Status.PENDING

        uint256 amountApprove = 1 ether;
        uint256 amountAdditional = 0 ether;

        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusForApprove.selector);
        escrow.approve(currentContractId, amountApprove, amountAdditional, contractor);
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 0); //Status.PENDING
        vm.stopPrank();
    }

    function test_approve_reverts_UnauthorizedReceiver() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (
            address _contractor,
            ,
            uint256 _amount,
            uint256 _amountToClaim,
            ,
            bytes32 _contractorData,
            IEscrow.FeeConfig _feeConfig,
            IEscrow.Status _status
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        uint256 amountApprove = 1 ether;
        uint256 amountAdditional = 0 ether;

        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__UnauthorizedReceiver.selector);
        escrow.approve(currentContractId, amountApprove, amountAdditional, address(0));
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        vm.expectRevert(IEscrow.Escrow__UnauthorizedReceiver.selector);
        escrow.approve(currentContractId, amountApprove, amountAdditional, address(123));
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        vm.stopPrank();
    }

    function test_approve_reverts_InvalidAmount() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (
            address _contractor,
            ,
            uint256 _amount,
            uint256 _amountToClaim,
            ,
            bytes32 _contractorData,
            IEscrow.FeeConfig _feeConfig,
            IEscrow.Status _status
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidAmount.selector);
        escrow.approve(currentContractId, 0, 0, contractor);
        (,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        vm.stopPrank();
    }

    ////////////////////////////////////////////
    //              claim tests               //
    ////////////////////////////////////////////

    function test_claim() public {
        test_approve();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor, address _paymentToken, uint256 _amount, uint256 _amountToClaim,,,, IEscrow.Status _status)
        = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_status), 0); //Status.PENDING

        assertEq(paymentToken.balanceOf(address(escrow)), 1.11 ether);
        // assertEq(paymentToken.balanceOf(address(treasury)), 0.11 ether);
        assertEq(paymentToken.balanceOf(address(contractor)), 0 ether);

        vm.startPrank(contractor);
        vm.expectEmit(true, true, true, true);
        emit Claimed(contractor, currentContractId, _paymentToken, _amountToClaim);
        escrow.claim(currentContractId);
        assertEq(paymentToken.balanceOf(address(escrow)), 0.11 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(contractor)), 1 ether);

        (,, uint256 _amountAfter, uint256 _amountToClaimAfter,,,, IEscrow.Status _statusAfter) =
            escrow.deposits(currentContractId);
        assertEq(_amountAfter, _amount - _amountToClaim);
        assertEq(_amountToClaimAfter, 0 ether);
        assertEq(uint256(_statusAfter), 0); //Status.PENDING - CLAIMED
        vm.stopPrank();
    }

    function test_claim_reverts() public {
        uint256 amountApprove = 0 ether;
        uint256 amountAdditional = 0.5 ether;
        test_approve2();
        uint256 currentContractId = escrow.getCurrentContractId();
        (,, uint256 _amount, uint256 _amountToClaim,,,, IEscrow.Status _status) = escrow.deposits(currentContractId);
        assertEq(_amount, 1 ether + amountAdditional);
        assertEq(_amountToClaim, amountApprove); //0
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__NotApproved.selector);
        escrow.claim(currentContractId);
        vm.prank(address(this));
        vm.expectRevert(); //IEscrow.Escrow__UnauthorizedAccount.selector
        escrow.claim(currentContractId);
        (,, _amount, _amountToClaim,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_amount, 1 ether + amountAdditional);
        assertEq(_amountToClaim, amountApprove); //0
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    // test feeAmount > 0, claim full amount and transfer to treasury
}
