// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {Escrow, IEscrow, Ownable} from "src/Escrow.sol";
import {EscrowFeeManager, IEscrowFeeManager} from "src/modules/EscrowFeeManager.sol";
import {Registry, IRegistry} from "src/modules/Registry.sol";
import {Enums} from "src/libs/Enums.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {MockRegistry} from "test/mocks/MockRegistry.sol";

contract EscrowUnitTest is Test {
    Escrow escrow;
    Registry registry;
    ERC20Mock paymentToken;
    ERC20Mock newPaymentToken;
    EscrowFeeManager feeManager;

    address client;
    address contractor;
    address treasury;
    address owner;

    Escrow.Deposit deposit;
    Enums.FeeConfig feeConfig;
    Enums.Status status;

    bytes32 contractorData;
    bytes32 salt;
    bytes contractData;

    struct Deposit {
        address contractor;
        address paymentToken;
        uint256 amount;
        uint256 amountToClaim;
        uint256 timeLock;
        bytes32 contractorData;
        Enums.FeeConfig feeConfig;
        Enums.Status status;
    }

    event Deposited(
        address indexed sender,
        uint256 indexed contractId,
        address indexed paymentToken,
        uint256 amount,
        uint256 timeLock,
        Enums.FeeConfig feeConfig
    );

    event Withdrawn(address indexed sender, uint256 indexed contractId, address indexed paymentToken, uint256 amount);
    event Submitted(address indexed sender, uint256 indexed contractId);
    event Approved(uint256 indexed contractId, uint256 indexed amountApprove, address indexed receiver);
    event Refilled(uint256 indexed contractId, uint256 indexed amountAdditional);
    event Claimed(address indexed sender, uint256 indexed contractId, address indexed paymentToken, uint256 amount);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event RegistryUpdated(address registry);

    function setUp() public {
        owner = makeAddr("owner");
        treasury = makeAddr("treasury");
        client = makeAddr("client");
        contractor = makeAddr("contractor");
        
        escrow = new Escrow();
        registry = new Registry(owner);
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

        deposit = IEscrow.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 1 ether,
            amountToClaim: 0 ether,
            timeLock: 0,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.PENDING
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

    ///////////////////////////////////////////
    //            deposit tests              //
    ///////////////////////////////////////////

    function test_deposit() public {
        test_initialize();
        vm.startPrank(address(client));
        paymentToken.mint(address(client), 1.08 ether);
        paymentToken.approve(address(escrow), 1.08 ether);
        vm.expectEmit(true, true, true, true);
        emit Deposited(address(client), 1, address(paymentToken), 1 ether, 0, Enums.FeeConfig.CLIENT_COVERS_ALL);
        escrow.deposit(deposit);
        vm.stopPrank();
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.08 ether
        // assertEq(paymentToken.balanceOf(address(treasury)), 0.11 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (
            address _contractor,
            address _paymentToken,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _timeLock,
            bytes32 _contractorData,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_timeLock, 0);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 0); //Enums.Enums.FeeConfig.CLIENT_COVERS_ALL
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
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.PENDING
        });
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__NotSupportedPaymentToken.selector);
        escrow.deposit(deposit);

        deposit = IEscrow.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 0 ether,
            amountToClaim: 0 ether,
            timeLock: 0,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.PENDING
        });
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__ZeroDepositAmount.selector);
        escrow.deposit(deposit);
    }

    function test_deposit_reverts_NotSetFeeManager() public {
        // this test needs it's own setup
        Escrow escrow2 = new Escrow();
        MockRegistry registry2 = new MockRegistry(owner);
        ERC20Mock paymentToken2 = new ERC20Mock();
        EscrowFeeManager feeManager2 = new EscrowFeeManager(3_00, 5_00, owner);
        vm.prank(owner);
        registry2.addPaymentToken(address(paymentToken));
        escrow2.initialize(client, owner, address(registry2));
        vm.startPrank(address(client));
        paymentToken.mint(address(client), 1.08 ether);
        paymentToken.approve(address(escrow2), 1.08 ether);
        vm.expectRevert(IEscrow.Escrow__NotSetFeeManager.selector);
        escrow2.deposit(deposit);
        vm.stopPrank();
        vm.prank(owner);
        registry2.updateFeeManager(address(feeManager));
        vm.prank(client);
        escrow2.deposit(deposit);

        uint256 currentContractId = escrow2.getCurrentContractId();
        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);
        vm.prank(contractor);
        escrow2.submit(currentContractId, contractData, salt);
        vm.prank(client);
        escrow2.approve(currentContractId, 1 ether, 0, contractor);

        vm.prank(owner);
        registry2.updateFeeManager(address(0));
        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__NotSetFeeManager.selector);
        escrow2.claim(currentContractId);
    }

    // helpers
    function _computeDepositAndFeeAmount(address _client, uint256 _depositAmount, Enums.FeeConfig _feeConfig)
        internal
        view
        returns (uint256 totalDepositAmount, uint256 feeApplied)
    {
        address feeManagerAddress = registry.feeManager();
        IEscrowFeeManager feeManager = IEscrowFeeManager(feeManagerAddress);
        (uint256 totalDepositAmount, uint256 feeApplied) =
            feeManager.computeDepositAmountAndFee(_client, _depositAmount, _feeConfig);

        return (totalDepositAmount, feeApplied);
    }

    function _computeClaimableAndFeeAmount(address _contractor, uint256 _claimAmount, Enums.FeeConfig _feeConfig)
        internal
        view
        returns (uint256 claimAmount, uint256 feeAmount)
    {
        address feeManagerAddress = registry.feeManager();
        IEscrowFeeManager feeManager = IEscrowFeeManager(feeManagerAddress);
        (uint256 claimAmount, uint256 feeAmount) =
            feeManager.computeClaimableAmountAndFee(_contractor, _claimAmount, _feeConfig);

        return (claimAmount, feeAmount);
    }

    ///////////////////////////////////////////
    //           withdraw tests              //
    ///////////////////////////////////////////

    function test_withdraw() public {
        test_deposit();
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        // assertEq(paymentToken.balanceOf(address(treasury)), 0.11 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);

        uint256 currentContractId = escrow.getCurrentContractId();
        (,, uint256 _amount, uint256 _amountToClaim,,, Enums.FeeConfig _feeConfig, Enums.Status _status) =
            escrow.deposits(currentContractId);

        (uint256 withdrawAmount, uint256 feeAmount) = _computeDepositAndFeeAmount(client, _amount, _feeConfig);

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(client, currentContractId, address(paymentToken), withdrawAmount);
        escrow.withdraw(currentContractId);
        (,, uint256 _amountAfter,,,,, Enums.Status _statusAfter) = escrow.deposits(currentContractId);
        assertEq(_amountAfter, 0);
        // TODO add assert for Enums.Status _statusAfter if it's changed
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount - (_amount + feeAmount));
        assertEq(paymentToken.balanceOf(address(client)), 0 ether + withdrawAmount); //==totalDepositAmount
    }

    function test_withdraw_reverts_UnauthorizedAccount() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        address notClient = makeAddr("notClient");
        vm.prank(notClient);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.withdraw(currentContractId);
        vm.prank(client);
        escrow.withdraw(currentContractId);
    }

    function test_withdraw_reverts_InvalidStatusForWithdraw() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusForWithdraw.selector);
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
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
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
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
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
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
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
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        uint256 amountApprove = 0 ether;
        uint256 amountAdditional = 0.5 ether;

        uint256 escrowBalanceBefore = paymentToken.balanceOf(address(escrow));
        vm.startPrank(client);
        (uint256 depositAmount,) =
            _computeDepositAndFeeAmount(client, amountAdditional, Enums.FeeConfig.CLIENT_COVERS_ALL);
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
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        uint256 amountApprove = 1 ether;
        uint256 amountAdditional = 0.5 ether;

        uint256 escrowBalanceBefore = paymentToken.balanceOf(address(escrow));
        vm.startPrank(client);
        (uint256 depositAmount,) =
            _computeDepositAndFeeAmount(client, amountAdditional, Enums.FeeConfig.CLIENT_COVERS_ALL);
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
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
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
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
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
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
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

    function test_claim_clientCoversAll() public {
        test_approve();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor, address _paymentToken, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_status), 0); //Status.PENDING

        (uint256 totalDepositAmount, uint256 feeApplied) =
            _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);

        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        // assertEq(paymentToken.balanceOf(address(treasury)), 0.11 ether);
        assertEq(paymentToken.balanceOf(address(contractor)), 0 ether);

        vm.startPrank(contractor);
        vm.expectEmit(true, true, true, true);
        emit Claimed(contractor, currentContractId, _paymentToken, _amountToClaim);
        escrow.claim(currentContractId);
        assertEq(paymentToken.balanceOf(address(escrow)), feeApplied);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(contractor)), 1 ether);

        (,, uint256 _amountAfter, uint256 _amountToClaimAfter,,,, Enums.Status _statusAfter) =
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
        (,, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) = escrow.deposits(currentContractId);
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

    // claim full amount and transfer to treasury

    function test_claim_clientCoversOnly() public {
        // this test need it's own setup
        test_initialize();
        deposit = IEscrow.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 1 ether,
            amountToClaim: 0 ether,
            timeLock: 0,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.PENDING
        });

        (uint256 depositAmount, uint256 feeApplied) =
            _computeDepositAndFeeAmount(contractor, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);

        vm.startPrank(client);
        paymentToken.mint(address(client), depositAmount); //1.03 ether
        paymentToken.approve(address(escrow), depositAmount);
        escrow.deposit(deposit);
        vm.stopPrank();
        uint256 currentContractId = escrow.getCurrentContractId();

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);
        vm.prank(contractor);
        escrow.submit(currentContractId, contractData, salt);

        uint256 amountApprove = 1 ether;
        uint256 amountAdditional = 0 ether;
        vm.prank(client);
        escrow.approve(currentContractId, amountApprove, amountAdditional, contractor);
        
        (address _contractor, address _paymentToken, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_status), 0); //Status.PENDING

        (uint256 claimAmount, uint256 feeAmount) =
            _computeClaimableAndFeeAmount(contractor, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        
        vm.prank(contractor);
        escrow.claim(currentContractId);
        assertEq(paymentToken.balanceOf(address(escrow)), feeApplied);
        assertEq(paymentToken.balanceOf(address(treasury)), feeAmount);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);
    }

    ////////////////////////////////////////////
    //      ownership & management tests      //
    ////////////////////////////////////////////

    function test_transferOwnership() public {
        test_initialize();
        assertEq(escrow.owner(), owner);
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        escrow.transferOwnership(notOwner);
        vm.startPrank(owner); //current owner
        vm.expectRevert(Ownable.NewOwnerIsZeroAddress.selector);
        escrow.transferOwnership(address(0));
        address newOwner = makeAddr("newOwner");
        vm.expectEmit(true, false, false, true);
        emit OwnershipTransferred(owner, newOwner);
        escrow.transferOwnership(newOwner);
        vm.stopPrank();
    }

    function test_updateRegistry() public {
        test_initialize();
        assertEq(address(escrow.registry()), address(registry));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        escrow.updateRegistry(address(registry));
        vm.startPrank(address(owner));
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
        escrow.updateRegistry(address(0));
        assertEq(address(escrow.registry()), address(registry));
        Registry newRegistry = new Registry(owner);
        vm.expectEmit(true, false, false, true);
        emit RegistryUpdated(address(newRegistry));
        escrow.updateRegistry(address(newRegistry));
        assertEq(address(escrow.registry()), address(newRegistry));
        vm.stopPrank();
    }
}
