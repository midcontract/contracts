// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {EscrowFixedPrice, IEscrowFixedPrice, Ownable} from "src/EscrowFixedPrice.sol";
import {EscrowFeeManager, IEscrowFeeManager} from "src/modules/EscrowFeeManager.sol";
import {EscrowRegistry, IEscrowRegistry} from "src/modules/EscrowRegistry.sol";
import {Enums} from "src/libs/Enums.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {IEscrow} from "src/interfaces/IEscrow.sol";
import {MockRegistry} from "test/mocks/MockRegistry.sol";

contract EscrowFixedPriceUnitTest is Test {
    EscrowFixedPrice escrow;
    EscrowRegistry registry;
    ERC20Mock paymentToken;
    ERC20Mock newPaymentToken;
    EscrowFeeManager feeManager;

    address client;
    address contractor;
    address treasury;
    address owner;

    EscrowFixedPrice.Deposit deposit;
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
        uint256 amountToWithdraw;
        bytes32 contractorData;
        Enums.FeeConfig feeConfig;
        Enums.Status status;
    }

    event Deposited(
        address indexed sender,
        uint256 indexed contractId,
        address paymentToken,
        uint256 amount,
        Enums.FeeConfig feeConfig
    );
    event Withdrawn(uint256 indexed contractId, address indexed paymentToken, uint256 amount);
    event Submitted(address indexed sender, uint256 indexed contractId);
    event Approved(uint256 indexed contractId, uint256 indexed amountApprove, address indexed receiver);
    event Refilled(uint256 indexed contractId, uint256 indexed amountAdditional);
    event Claimed(uint256 indexed contractId, address indexed paymentToken, uint256 amount);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event RegistryUpdated(address registry);
    event ReturnRequested(uint256 contractId);
    event ReturnApproved(uint256 contractId, address sender);
    event ReturnCanceled(uint256 contractId);
    event DisputeCreated(uint256 contractId, address sender);
    event DisputeResolved(uint256 contractId, Enums.Winner winner, uint256 clientAmount, uint256 contractorAmount);

    function setUp() public {
        owner = makeAddr("owner");
        treasury = makeAddr("treasury");
        client = makeAddr("client");
        contractor = makeAddr("contractor");

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
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.ACTIVE
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
        emit Deposited(address(client), 1, address(paymentToken), 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);
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
            uint256 _amountToWithdraw,
            bytes32 _contractorData,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);

        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 0); //Enums.Enums.FeeConfig.CLIENT_COVERS_ALL
        assertEq(uint256(_status), 0); //Status.ACTIVE
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
        deposit = IEscrowFixedPrice.Deposit({
            contractor: address(0),
            paymentToken: address(notPaymentToken),
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.ACTIVE
        });
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__NotSupportedPaymentToken.selector);
        escrow.deposit(deposit);

        deposit = IEscrowFixedPrice.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 0 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.ACTIVE
        });
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__ZeroDepositAmount.selector);
        escrow.deposit(deposit);
    }

    function test_deposit_reverts_NotSetFeeManager() public {
        // this test needs it's own setup
        EscrowFixedPrice escrow2 = new EscrowFixedPrice();
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
        escrow2.approve(currentContractId, 1 ether, contractor);

        vm.prank(owner);
        registry2.updateFeeManager(address(0));
        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__NotSetFeeManager.selector);
        escrow2.claim(currentContractId);
    }

    function test_deposit_withContractorAddress() public {
        test_initialize();
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
        vm.startPrank(address(client));
        paymentToken.mint(address(client), 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        vm.expectEmit(true, true, true, true);
        emit Deposited(address(client), 1, address(paymentToken), 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        escrow.deposit(deposit);
        vm.stopPrank();
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (
            address _contractor,
            address _paymentToken,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            bytes32 _contractorData,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    // helpers
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
    //           withdraw tests              //
    ///////////////////////////////////////////

    function test_withdraw_whenRefundApprovedByOwner() public {
        test_approveReturn_by_owner();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 1 ether);
        assertEq(uint256(_status), 7); //Status.REFUND_APPROVED

        (uint256 totalDepositAmount, uint256 feeAmount) =
            _computeDepositAndFeeAmount(client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ALL);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (uint256 initialDepositAmount, uint256 initialFeeAmount) =
            _computeDepositAndFeeAmount(client, _amount, Enums.FeeConfig.CLIENT_COVERS_ALL);
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(currentContractId, address(paymentToken), _amountToWithdraw + feeAmount);
        escrow.withdraw(currentContractId);
        (,, uint256 _amountAfter,, uint256 _amountToWithdrawAfter,,, Enums.Status _statusAfter) =
            escrow.deposits(currentContractId);
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
        (address _contractor,, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 1 ether);
        assertEq(uint256(_status), 7); //Status.REFUND_APPROVED

        (uint256 totalDepositAmount, uint256 feeAmount) =
            _computeDepositAndFeeAmount(client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ALL);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (uint256 initialDepositAmount, uint256 initialFeeAmount) =
            _computeDepositAndFeeAmount(client, _amount, Enums.FeeConfig.CLIENT_COVERS_ALL);
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(currentContractId, address(paymentToken), totalDepositAmount);
        escrow.withdraw(currentContractId);
        (,, uint256 _amountAfter,, uint256 _amountToWithdrawAfter,,, Enums.Status _statusAfter) =
            escrow.deposits(currentContractId);
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
        (address _contractor,, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.deposits(currentContractId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, _amount);
        assertEq(uint256(_status), 6); //Status.RESOLVED

        (uint256 totalDepositAmount, uint256 feeAmount) =
            _computeDepositAndFeeAmount(client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ALL);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (uint256 initialDepositAmount, uint256 initialFeeAmount) =
            _computeDepositAndFeeAmount(client, _amount, Enums.FeeConfig.CLIENT_COVERS_ALL);
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(currentContractId, address(paymentToken), totalDepositAmount);
        escrow.withdraw(currentContractId);
        (,, uint256 _amountAfter,, uint256 _amountToWithdrawAfter,,, Enums.Status _statusAfter) =
            escrow.deposits(currentContractId);
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
        ) = escrow.deposits(currentContractId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0.5 ether);
        assertEq(_amountToWithdraw, 0.5 ether);
        assertEq(uint256(_status), 6); //Status.RESOLVED

        (uint256 totalDepositAmount, uint256 feeAmount) =
            _computeDepositAndFeeAmount(client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ALL);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + feeAmount + _amountToClaim);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (uint256 initialDepositAmount, uint256 initialFeeAmount) =
            _computeDepositAndFeeAmount(client, _amount, Enums.FeeConfig.CLIENT_COVERS_ALL);
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(currentContractId, address(paymentToken), totalDepositAmount);
        escrow.withdraw(currentContractId);
        (,, uint256 _amountAfter,, uint256 _amountToWithdrawAfter,,, Enums.Status _statusAfter) =
            escrow.deposits(currentContractId);
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
        address notClient = makeAddr("notClient");
        vm.prank(notClient);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.withdraw(currentContractId);
    }

    function test_withdraw_reverts_InvalidStatusForWithdraw() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusToWithdraw.selector);
        escrow.withdraw(currentContractId);
    }

    function test_withdraw_reverts_NoFundsAvailableForWithdraw() public {
        test_requestReturn_whenPending();
        assertEq(paymentToken.balanceOf(address(client)), 0);
        uint256 currentContractId = escrow.getCurrentContractId();
        (,,,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(client);
        escrow.createDispute(currentContractId);
        (,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        vm.prank(owner);
        escrow.resolveDispute(currentContractId, Enums.Winner.SPLIT, 0, 0.5 ether);
        (,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 6); //Status.RESOLVED
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__NoFundsAvailableForWithdraw.selector);
        escrow.withdraw(currentContractId);
        (,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 6); //Status.RESOLVED
        assertEq(paymentToken.balanceOf(address(client)), 0);
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
        assertEq(uint256(_status), 0); //Status.ACTIVE

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
        assertEq(uint256(_status), 0); //Status.ACTIVE

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

    function test_submit_withContractorAddress() public {
        test_deposit_withContractorAddress();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,,,,, bytes32 _contractorData, Enums.FeeConfig _feeConfig, Enums.Status _status) =
            escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 0); //Status.ACTIVE

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);
        vm.prank(address(this));
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.submit(currentContractId, contractData, salt);
        vm.prank(contractor);
        vm.expectEmit(true, true, true, true);
        emit Submitted(contractor, currentContractId);
        escrow.submit(currentContractId, contractData, salt);
        (_contractor,,,,, _contractorData, _feeConfig, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_contractorData, contractorDataHash);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    function test_submit_reverts_UnauthorizedAccount() public {
        test_deposit_withContractorAddress();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,,,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 0); //Status.ACTIVE

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);
        vm.prank(address(this));
        vm.expectRevert(); //IEscrow.Escrow__UnauthorizedAccount.selector
        escrow.submit(currentContractId, contractData, salt);
        (_contractor,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_submit_reverts_InvalidStatusForSubmit() public {
        test_submit_withContractorAddress();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,,,,, bytes32 _contractorData,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);
        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusForSubmit.selector);
        escrow.submit(currentContractId, contractData, salt);
        (_contractor,,,,, _contractorData,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_contractorData, contractorDataHash);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    ////////////////////////////////////////////
    //             approve tests              //
    ////////////////////////////////////////////

    function test_approve() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        uint256 amountApprove = 1 ether;

        vm.startPrank(client);
        vm.expectEmit(true, true, true, true);
        emit Approved(currentContractId, amountApprove, contractor);
        escrow.approve(currentContractId, amountApprove, contractor);
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove);
        assertEq(uint256(_status), 2); //Status.APPROVED
        vm.stopPrank();
    }

    function test_approve_byOwner() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        uint256 amountApprove = 1 ether;

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit Approved(currentContractId, amountApprove, contractor);
        escrow.approve(currentContractId, amountApprove, contractor);
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove);
        assertEq(uint256(_status), 2); //Status.APPROVED
        vm.stopPrank();
    }

    function test_approve_reverts_UnauthorizedAccount() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        uint256 amountApprove = 1 ether;
        vm.startPrank(address(this));
        vm.expectRevert(); //IEscrow.Escrow__UnauthorizedAccount.selector
        escrow.approve(currentContractId, amountApprove, contractor);
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        vm.stopPrank();
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
        assertEq(uint256(_status), 0); //Status.ACTIVE

        uint256 amountApprove = 1 ether;
        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusForApprove.selector);
        escrow.approve(currentContractId, amountApprove, contractor);
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 0); //Status.ACTIVE
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

        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__UnauthorizedReceiver.selector);
        escrow.approve(currentContractId, amountApprove, address(0));
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        vm.expectRevert(IEscrow.Escrow__UnauthorizedReceiver.selector);
        escrow.approve(currentContractId, amountApprove, address(123));
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        vm.stopPrank();
    }

    function test_approve_reverts_InvalidAmount() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidAmount.selector);
        escrow.approve(currentContractId, 0, contractor);
        (,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        vm.stopPrank();
    }

    function test_approve_reverts_NotEnoughDeposit() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        uint256 amountApprove = 1.01 ether;
        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__NotEnoughDeposit.selector);
        escrow.approve(currentContractId, amountApprove, contractor);
        (,,, _amountToClaim,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        vm.stopPrank();
    }

    ////////////////////////////////////////////
    //              refill tests              //
    ////////////////////////////////////////////

    function test_refill() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (
            address _contractor,
            ,
            uint256 _amount,
            uint256 _amountToClaim,
            ,
            ,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_feeConfig), 0); //Enums.Enums.FeeConfig.CLIENT_COVERS_ALL
        assertEq(uint256(_status), 0); //Status.ACTIVE
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.08 ether
        uint256 amountAdditional = 1 ether;
        vm.startPrank(address(client));
        paymentToken.mint(address(client), totalDepositAmount);
        paymentToken.approve(address(escrow), totalDepositAmount);
        vm.expectEmit(true, true, true, true);
        emit Refilled(currentContractId, amountAdditional);
        escrow.refill(currentContractId, amountAdditional);
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + totalDepositAmount);
        (_contractor,, _amount, _amountToClaim,,, _feeConfig, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 2 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_feeConfig), 0); //Enums.Enums.FeeConfig.CLIENT_COVERS_ALL
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_refill_reverts() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (
            address _contractor,
            ,
            uint256 _amount,
            uint256 _amountToClaim,
            ,
            ,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_feeConfig), 0);
        assertEq(uint256(_status), 0);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.08 ether
        uint256 amountAdditional = 1 ether;
        vm.startPrank(address(this));
        paymentToken.mint(address(this), totalDepositAmount);
        paymentToken.approve(address(escrow), totalDepositAmount);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender);
        escrow.refill(currentContractId, amountAdditional);
        vm.stopPrank();
        vm.startPrank(address(client));
        paymentToken.mint(address(client), totalDepositAmount);
        paymentToken.approve(address(escrow), totalDepositAmount);
        vm.expectRevert(IEscrow.Escrow__InvalidAmount.selector);
        escrow.refill(currentContractId, 0 ether);
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
        assertEq(uint256(_status), 2); //Status.APPROVED

        (uint256 totalDepositAmount, uint256 feeApplied) =
            _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);

        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(contractor)), 0 ether);

        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
            _computeClaimableAndFeeAmount(contractor, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);
        assertEq(feeApplied, clientFee);

        vm.startPrank(contractor);
        vm.expectEmit(true, true, true, true);
        emit Claimed(currentContractId, _paymentToken, _amountToClaim);
        escrow.claim(currentContractId);
        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), feeAmount + clientFee);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);

        (,, uint256 _amountAfter, uint256 _amountToClaimAfter,,,, Enums.Status _statusAfter) =
            escrow.deposits(currentContractId);
        assertEq(_amountAfter, _amount - _amountToClaim);
        assertEq(_amountToClaimAfter, 0 ether);
        assertEq(uint256(_statusAfter), 3); //Status.COMPLETED
        vm.stopPrank();
    }

    function test_claim_reverts() public {
        uint256 amountApprove = 0 ether;
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (,, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove); //0
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusToClaim.selector);
        // vm.expectRevert(IEscrow.Escrow__NotApproved.selector); //TODO test
        escrow.claim(currentContractId);
        vm.prank(address(this));
        vm.expectRevert(); //IEscrow.Escrow__UnauthorizedAccount.selector
        escrow.claim(currentContractId);
        (,, _amount, _amountToClaim,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove); //0
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    function test_claim_clientCoversOnly() public {
        // this test need it's own setup
        test_initialize();
        deposit = IEscrowFixedPrice.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.ACTIVE
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
        vm.prank(client);
        escrow.approve(currentContractId, amountApprove, contractor);

        (address _contractor, address _paymentToken, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED

        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
            _computeClaimableAndFeeAmount(contractor, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(feeApplied, clientFee);

        vm.prank(contractor);
        escrow.claim(currentContractId);
        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), feeAmount + clientFee);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);
    }

    function test_claim_withSeveralDeposits() public {
        test_approve();

        (uint256 totalDepositAmount, uint256 feeApplied) =
            _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);

        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(contractor)), 0 ether);

        // create 2d deposit
        uint256 depositAmount2 = 1 ether;
        deposit = IEscrowFixedPrice.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: depositAmount2,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.ACTIVE
        });

        (uint256 depositAmount, uint256 feeApplied1) =
            _computeDepositAndFeeAmount(contractor, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertGt(depositAmount, depositAmount2);

        vm.startPrank(client);
        paymentToken.mint(address(client), depositAmount); //1.03 ether
        paymentToken.approve(address(escrow), depositAmount);
        escrow.deposit(deposit);
        vm.stopPrank();
        uint256 currentContractId_2 = escrow.getCurrentContractId();
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + depositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(contractor)), 0 ether);

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);
        vm.prank(contractor);
        escrow.submit(currentContractId_2, contractData, salt);

        uint256 amountApprove = 1 ether;
        vm.prank(client);
        escrow.approve(currentContractId_2, amountApprove, contractor);

        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
            _computeClaimableAndFeeAmount(contractor, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(feeApplied1, clientFee);
        assertEq(claimAmount, amountApprove - feeAmount);

        vm.prank(contractor);
        escrow.claim(currentContractId_2);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), feeAmount + clientFee);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);

        (uint256 _claimAmount, uint256 _feeAmount, uint256 _clientFee) =
            _computeClaimableAndFeeAmount(contractor, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);

        uint256 currentContractId_1 = --currentContractId_2;
        vm.prank(contractor);
        escrow.claim(currentContractId_1);
        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether); // totalDepositAmount - _claimAmount
        assertEq(paymentToken.balanceOf(address(treasury)), feeAmount + clientFee + _clientFee);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount + _claimAmount);
    }

    function test_claim_whenResolveDispute_winnerSplit() public {
        // this test need it's own setup
        test_initialize();
        deposit = IEscrowFixedPrice.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.ACTIVE
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
        (
            address _contractor,
            ,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            ,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        vm.prank(client);
        escrow.requestReturn(currentContractId);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED

        vm.prank(contractor);
        escrow.createDispute(currentContractId);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED

        // uint256 clientAmount = _amount / 2;
        // uint256 contractorAmount = _amount / 2;
        vm.prank(owner);
        escrow.resolveDispute(currentContractId, Enums.Winner.SPLIT, _amount / 2, _amount / 2);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0.5 ether);
        assertEq(_amountToWithdraw, 0.5 ether);
        assertEq(uint256(_status), 6); //Status.RESOLVED

        (uint256 totalDepositAmount, uint256 feeAmount) =
            _computeDepositAndFeeAmount(client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + feeAmount + _amountToClaim);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(contractor)), 0 ether);

        (, uint256 initialFeeAmount) = _computeDepositAndFeeAmount(client, _amount, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        // uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        escrow.withdraw(currentContractId);
        (,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_amount, 0.5 ether);
        assertEq(_amountToClaim, 0.5 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 8); //Status.CANCELED
        assertEq(paymentToken.balanceOf(address(escrow)), 0.5 ether);
        assertEq(paymentToken.balanceOf(address(client)), totalDepositAmount); //=0.5 ether
        assertEq(paymentToken.balanceOf(address(treasury)), initialFeeAmount - feeAmount);
        assertEq(paymentToken.balanceOf(address(contractor)), 0 ether);

        vm.startPrank(contractor);
        (uint256 claimAmount, uint256 claimFeeAmount, uint256 clientFee) = IEscrowFeeManager(feeManager)
            .computeClaimableAmountAndFee(contractor, _amountToClaim, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        escrow.claim(currentContractId);
        (,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 3); //Status.COMPLETED
        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), initialFeeAmount - feeAmount + claimFeeAmount);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);
        vm.stopPrank();
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
        EscrowRegistry newRegistry = new EscrowRegistry(owner);
        vm.expectEmit(true, false, false, true);
        emit RegistryUpdated(address(newRegistry));
        escrow.updateRegistry(address(newRegistry));
        assertEq(address(escrow.registry()), address(newRegistry));
        vm.stopPrank();
    }

    ////////////////////////////////////////////
    //          return request tests          //
    ////////////////////////////////////////////

    function test_requestReturn_whenPending() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnRequested(currentContractId);
        escrow.requestReturn(currentContractId);
        (_contractor,, _amount,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_reverts_UnauthorizedAccount() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.prank(contractor);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender);
        escrow.requestReturn(currentContractId);
        (_contractor,, _amount,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_requestReturn_reverts_ReturnNotAllowed() public {
        test_requestReturn_whenPending();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__ReturnNotAllowed.selector);
        escrow.requestReturn(currentContractId);
        (_contractor,, _amount,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_whenSubmitted() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnRequested(currentContractId);
        escrow.requestReturn(currentContractId);
        (_contractor,, _amount,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_reverts_submitted_UnauthorizedAccount() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        vm.prank(address(this));
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender);
        escrow.requestReturn(currentContractId);
        (_contractor,, _amount,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    function test_approveReturn_by_owner() public {
        test_requestReturn_whenPending();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit ReturnApproved(currentContractId, owner);
        escrow.approveReturn(currentContractId);
        (_contractor,, _amount,, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 1 ether);
        assertEq(uint256(_status), 7); //Status.REFUND_APPROVED
    }

    function test_approveReturn_by_contractor() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(contractor);
        vm.expectEmit(true, true, true, true);
        emit ReturnApproved(currentContractId, contractor);
        escrow.approveReturn(currentContractId);
        (_contractor,, _amount,, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 1 ether);
        assertEq(uint256(_status), 7); //Status.REFUND_APPROVED
    }

    function test_approveReturn_reverts_UnauthorizedToApproveReturn() public {
        test_requestReturn_whenPending();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__UnauthorizedToApproveReturn.selector);
        escrow.approveReturn(currentContractId);
        (_contractor,, _amount,, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 4); //Status.REFUND_APPROVED
    }

    function test_approveReturn_reverts_NoReturnRequested() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,,,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__NoReturnRequested.selector);
        escrow.approveReturn(currentContractId);
        (_contractor,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_approveReturn_reverts_submitted_NoReturnRequested() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,,,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__NoReturnRequested.selector);
        escrow.approveReturn(currentContractId);
        (_contractor,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    function test_cancelReturn() public {
        test_requestReturn_whenPending();
        uint256 currentContractId = escrow.getCurrentContractId();
        (,,,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        Enums.Status status = Enums.Status.ACTIVE;
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnCanceled(currentContractId);
        escrow.cancelReturn(currentContractId, status);
        (,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_cancelReturn_submitted() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,,,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        Enums.Status status = Enums.Status.SUBMITTED;
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnCanceled(currentContractId);
        escrow.cancelReturn(currentContractId, status);
        (_contractor,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    function test_cancelReturn_reverts() public {
        test_requestReturn_whenPending();
        uint256 currentContractId = escrow.getCurrentContractId();
        (,,,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        Enums.Status status = Enums.Status.ACTIVE;
        vm.prank(owner);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.cancelReturn(currentContractId, status);
        (,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        status = Enums.Status.CANCELED;
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusProvided.selector);
        escrow.cancelReturn(currentContractId, status);
        (,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_cancelReturn_reverts_submitted() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        Enums.Status status = Enums.Status.RESOLVED;
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusProvided.selector);
        escrow.cancelReturn(currentContractId, status);
        (,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_cancelReturn_reverts_submitted_NoReturnRequested() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,,,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        Enums.Status status = Enums.Status.ACTIVE;
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__NoReturnRequested.selector);
        escrow.cancelReturn(currentContractId, status);
        (_contractor,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    ////////////////////////////////////////////
    //              dispute tests             //
    ////////////////////////////////////////////

    // if client wants to dispute logged hours
    function test_createDispute_by_client() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit DisputeCreated(currentContractId, client);
        escrow.createDispute(currentContractId);
        (_contractor,, _amount,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    // if contractor doesn’t want to approve “Escrow Return Request”
    // or if a client doesn’t Approve Submitted work and sends Change Requests
    function test_createDispute_by_contractor() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(contractor);
        vm.expectEmit(true, true, true, true);
        emit DisputeCreated(currentContractId, contractor);
        escrow.createDispute(currentContractId);
        (_contractor,, _amount,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    function test_createDispute_reverts_CreateDisputeNotAllowed() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__CreateDisputeNotAllowed.selector);
        escrow.createDispute(currentContractId);
        (_contractor,, _amount,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_createDispute_reverts_UnauthorizedToApproveDispute() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(address(this));
        vm.expectRevert(IEscrow.Escrow__UnauthorizedToApproveDispute.selector);
        escrow.createDispute(currentContractId);
        (_contractor,, _amount,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_resolveDispute_winnerClient() public {
        test_createDispute_by_client();
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
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        Enums.Winner _winner = Enums.Winner.CLIENT;
        uint256 clientAmount = _amount;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(currentContractId, _winner, clientAmount, 0);
        escrow.resolveDispute(currentContractId, _winner, clientAmount, 0);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, clientAmount);
        assertEq(uint256(_status), 6); //Status.RESOLVED
    }

    function test_resolveDispute_winnerContractor() public {
        test_createDispute_by_contractor();
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
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        Enums.Winner _winner = Enums.Winner.CONTRACTOR;
        uint256 contractorAmount = _amount;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(currentContractId, _winner, 0, contractorAmount);
        escrow.resolveDispute(currentContractId, _winner, 0, contractorAmount);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, contractorAmount);
        assertEq(_amountToWithdraw, 0);
        assertEq(uint256(_status), 2); //Status.APPROVED
    }

    function test_resolveDispute_winnerSplit() public {
        test_createDispute_by_contractor();
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
        ) = escrow.deposits(currentContractId);
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
        emit DisputeResolved(currentContractId, _winner, clientAmount, contractorAmount);
        escrow.resolveDispute(currentContractId, _winner, clientAmount, contractorAmount);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0.5 ether);
        assertEq(_amountToWithdraw, 0.5 ether);
        assertEq(uint256(_status), 6); //Status.RESOLVED
    }

    function test_resolveDispute_winnerSplit_ZeroAllocationToEachParty() public {
        test_createDispute_by_contractor();
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
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        Enums.Winner _winner = Enums.Winner.SPLIT;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(currentContractId, _winner, 0, 0);
        escrow.resolveDispute(currentContractId, _winner, 0, 0);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 6); //Status.RESOLVED
    }

    function test_resolveDispute_reverts_DisputeNotActiveForThisDeposit() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (,,,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__DisputeNotActiveForThisDeposit.selector);
        escrow.resolveDispute(currentContractId, Enums.Winner.CLIENT, 0, 0);
        (,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_resolveDispute_reverts_UnauthorizedToApproveDispute() public {
        test_createDispute_by_client();
        uint256 currentContractId = escrow.getCurrentContractId();
        (,,,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        vm.prank(address(this));
        vm.expectRevert(); //Unauthorized()
        escrow.resolveDispute(currentContractId, Enums.Winner.CONTRACTOR, 0, 0);
        (,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    function test_resolveDispute_reverts_winnerClient_ResolutionExceedsDepositedAmount() public {
        test_createDispute_by_contractor();
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
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__ResolutionExceedsDepositedAmount.selector);
        escrow.resolveDispute(currentContractId, Enums.Winner.CLIENT, 1.1 ether, 0 ether);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    function test_resolveDispute_reverts_winnerContractor_ResolutionExceedsDepositedAmount() public {
        test_createDispute_by_contractor();
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
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__ResolutionExceedsDepositedAmount.selector);
        escrow.resolveDispute(currentContractId, Enums.Winner.CONTRACTOR, 0 ether, 1.1 ether);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    function test_resolveDispute_reverts_winnerSplit_ResolutionExceedsDepositedAmount() public {
        test_createDispute_by_contractor();
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
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__ResolutionExceedsDepositedAmount.selector);
        escrow.resolveDispute(currentContractId, Enums.Winner.SPLIT, 1 ether, 1 wei);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    function test_resolveDispute_reverts_InvalidWinnerSpecified() public {
        test_createDispute_by_contractor();
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
        ) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        vm.prank(owner);
        // vm.expectRevert(IEscrow.Escrow__InvalidWinnerSpecified.selector);
        vm.expectRevert(); // panic: failed to convert value into enum type (0x21)
        escrow.resolveDispute(currentContractId, Enums.Winner(uint256(4)), _amount, 0); // Invalid enum value for Winner
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }
}
