// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test, console2 } from "forge-std/Test.sol";

import { EscrowFixedPrice, IEscrowFixedPrice } from "src/EscrowFixedPrice.sol";
import { EscrowAdminManager, OwnedRoles } from "src/modules/EscrowAdminManager.sol";
import { EscrowFeeManager, IEscrowFeeManager } from "src/modules/EscrowFeeManager.sol";
import { EscrowRegistry, IEscrowRegistry } from "src/modules/EscrowRegistry.sol";
import { Enums } from "src/common/Enums.sol";
import { IEscrow } from "src/interfaces/IEscrow.sol";
import { MockRegistry } from "test/mocks/MockRegistry.sol";
import { MockDAI } from "test/mocks/MockDAI.sol";
import { MockUSDT } from "test/mocks/MockUSDT.sol";
import { ERC20Mock } from "@openzeppelin/mocks/token/ERC20Mock.sol";

contract EscrowFixedPriceUnitTest is Test {
    EscrowFixedPrice escrow;
    EscrowRegistry registry;
    ERC20Mock paymentToken;
    ERC20Mock newPaymentToken;
    EscrowFeeManager feeManager;
    EscrowAdminManager adminManager;

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

    event Deposited(address indexed depositor, uint256 indexed contractId, uint256 amount, address indexed contractor);
    event Withdrawn(address indexed withdrawer, uint256 indexed contractId, uint256 amount, uint256 feeAmount);
    event Submitted(address indexed sender, uint256 indexed contractId);
    event Approved(
        address indexed approver, uint256 indexed contractId, uint256 amountApprove, address indexed receiver
    );
    event Refilled(address indexed sender, uint256 indexed contractId, uint256 amountAdditional);
    event Claimed(address indexed contractor, uint256 indexed contractId, uint256 amount, uint256 feeAmount);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event RegistryUpdated(address registry);
    event AdminManagerUpdated(address adminManager);
    event ReturnRequested(address indexed sender, uint256 contractId);
    event ReturnApproved(address indexed approver, uint256 contractId);
    event ReturnCanceled(address indexed sender, uint256 contractId);
    event DisputeCreated(address indexed sender, uint256 contractId);
    event DisputeResolved(
        address indexed approver,
        uint256 contractId,
        Enums.Winner winner,
        uint256 clientAmount,
        uint256 contractorAmount
    );

    function setUp() public {
        owner = makeAddr("owner");
        treasury = makeAddr("treasury");
        client = makeAddr("client");
        contractor = makeAddr("contractor");

        escrow = new EscrowFixedPrice();
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

    ///////////////////////////////////////////
    //            deposit tests              //
    ///////////////////////////////////////////

    function test_deposit() public {
        test_initialize();
        vm.startPrank(client);
        paymentToken.mint(client, 1.08 ether);
        paymentToken.approve(address(escrow), 1.08 ether);
        vm.expectEmit(true, true, true, true);
        emit Deposited(client, 1, 1.08 ether, address(0));
        escrow.deposit(deposit);
        vm.stopPrank();
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL
        );
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
        assertEq(uint256(_status), 1); //Status.ACTIVE
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

        vm.prank(owner);
        registry.addToBlacklist(client);
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__BlacklistedAccount.selector);
        escrow.deposit(deposit);
    }

    function test_deposit_reverts_NotSetFeeManager() public {
        // this test needs it's own setup
        EscrowFixedPrice escrow2 = new EscrowFixedPrice();
        MockRegistry registry2 = new MockRegistry(owner);
        ERC20Mock paymentToken2 = new ERC20Mock();
        EscrowFeeManager feeManager2 = new EscrowFeeManager(300, 500, owner);
        deposit = IEscrowFixedPrice.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken2),
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.ACTIVE
        });
        vm.prank(owner);
        registry2.addPaymentToken(address(paymentToken2));
        escrow2.initialize(client, owner, address(registry2));
        vm.startPrank(address(client));
        paymentToken2.mint(address(client), 1.08 ether);
        paymentToken2.approve(address(escrow2), 1.08 ether);
        vm.expectRevert(IEscrow.Escrow__NotSetFeeManager.selector);
        escrow2.deposit(deposit);
        vm.stopPrank();
        vm.prank(owner);
        registry2.updateFeeManager(address(feeManager2));
        vm.prank(client);
        escrow2.deposit(deposit);

        uint256 currentContractId = escrow2.getCurrentContractId();
        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));

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
        vm.startPrank(client);
        paymentToken.mint(client, 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        vm.expectEmit(true, true, true, true);
        emit Deposited(client, 1, 1.03 ether, contractor);
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
        assertEq(uint256(_status), 1); //Status.ACTIVE
    }

    // helpers
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
        assertEq(uint256(_status), 8); //Status.REFUND_APPROVED

        (uint256 totalDepositAmount, uint256 feeAmount) = _computeDepositAndFeeAmount(
            address(escrow), 1, client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ALL
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (, uint256 initialFeeAmount) =
            _computeDepositAndFeeAmount(address(escrow), 1, client, _amount, Enums.FeeConfig.CLIENT_COVERS_ALL);
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(client, currentContractId, _amountToWithdraw + feeAmount, platformFee);
        escrow.withdraw(currentContractId);
        (,, uint256 _amountAfter,, uint256 _amountToWithdrawAfter,,, Enums.Status _statusAfter) =
            escrow.deposits(currentContractId);
        assertEq(_amountAfter, 0 ether);
        assertEq(_amountToWithdrawAfter, 0 ether);
        assertEq(uint256(_statusAfter), 9); //Status.CANCELED
        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether); //totalDepositAmount - (_amountToWithdraw +
            // feeAmount)
        assertEq(paymentToken.balanceOf(address(client)), _amountToWithdraw + feeAmount); //==totalDepositAmount =
            // _amountToWithdraw + feeAmount
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
        assertEq(uint256(_status), 8); //Status.REFUND_APPROVED

        (uint256 totalDepositAmount, uint256 feeAmount) = _computeDepositAndFeeAmount(
            address(escrow), 1, client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ALL
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (, uint256 initialFeeAmount) =
            _computeDepositAndFeeAmount(address(escrow), 1, client, _amount, Enums.FeeConfig.CLIENT_COVERS_ALL);
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(client, currentContractId, totalDepositAmount, platformFee);
        escrow.withdraw(currentContractId);
        (,, uint256 _amountAfter,, uint256 _amountToWithdrawAfter,,, Enums.Status _statusAfter) =
            escrow.deposits(currentContractId);
        assertEq(_amountAfter, 0 ether);
        assertEq(_amountToWithdrawAfter, 0 ether);
        assertEq(uint256(_statusAfter), 9); //Status.CANCELED
        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether); //totalDepositAmount - (_amountToWithdraw +
            // feeAmount)
        assertEq(paymentToken.balanceOf(address(client)), totalDepositAmount); //==totalDepositAmount =
            // _amountToWithdraw + feeAmount
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee);
    }

    function test_withdraw_whenDisputeResolved() public {
        test_resolveDispute_winnerClient();
        uint256 currentContractId = escrow.getCurrentContractId();
        (,, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, _amount);
        assertEq(uint256(_status), 7); //Status.RESOLVED

        (uint256 totalDepositAmount, uint256 feeAmount) = _computeDepositAndFeeAmount(
            address(escrow), 1, client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ALL
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (, uint256 initialFeeAmount) =
            _computeDepositAndFeeAmount(address(escrow), 1, client, _amount, Enums.FeeConfig.CLIENT_COVERS_ALL);
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(client, currentContractId, totalDepositAmount, platformFee);
        escrow.withdraw(currentContractId);
        (,, uint256 _amountAfter,, uint256 _amountToWithdrawAfter,,, Enums.Status _statusAfter) =
            escrow.deposits(currentContractId);
        assertEq(_amountAfter, 0 ether);
        assertEq(_amountToWithdrawAfter, 0 ether);
        assertEq(uint256(_statusAfter), 9); //Status.CANCELED
        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee);
    }

    function test_withdraw_whenDisputeResolvedSplit() public {
        test_resolveDispute_winnerSplit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (,, uint256 _amount, uint256 _amountToClaim, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.deposits(currentContractId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0.5 ether);
        assertEq(_amountToWithdraw, 0.5 ether);
        assertEq(uint256(_status), 7); //Status.RESOLVED

        (uint256 totalDepositAmount, uint256 feeAmount) = _computeDepositAndFeeAmount(
            address(escrow), 1, client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ALL
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + feeAmount + _amountToClaim);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (, uint256 initialFeeAmount) =
            _computeDepositAndFeeAmount(address(escrow), 1, client, _amount, Enums.FeeConfig.CLIENT_COVERS_ALL);
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(client, currentContractId, totalDepositAmount, platformFee);
        escrow.withdraw(currentContractId);
        (,, uint256 _amountAfter,, uint256 _amountToWithdrawAfter,,, Enums.Status _statusAfter) =
            escrow.deposits(currentContractId);
        assertEq(_amountAfter, 0.5 ether);
        assertEq(_amountToWithdrawAfter, 0 ether);
        assertEq(uint256(_statusAfter), 9); //Status.CANCELED
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
        test_requestReturn_whenActive();
        assertEq(paymentToken.balanceOf(address(client)), 0);
        uint256 currentContractId = escrow.getCurrentContractId();
        (,,,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(client);
        escrow.createDispute(currentContractId);
        (,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 6); //Status.DISPUTED
        vm.prank(owner);
        escrow.resolveDispute(currentContractId, Enums.Winner.SPLIT, 0, 0.5 ether);
        (,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 7); //Status.RESOLVED
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__NoFundsAvailableForWithdraw.selector);
        escrow.withdraw(currentContractId);
        (,,,,,,, _status) = escrow.deposits(currentContractId);
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
        assertEq(uint256(_status), 1); //Status.ACTIVE

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
        assertEq(uint256(_status), 2); //Status.SUBMITTED
    }

    function test_submit_reverts() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,,,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 1); //Status.ACTIVE

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
        assertEq(uint256(_status), 1); //Status.ACTIVE

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
        assertEq(uint256(_status), 2); //Status.SUBMITTED
    }

    function test_submit_reverts_UnauthorizedAccount() public {
        test_deposit_withContractorAddress();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,,,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        vm.prank(address(this));
        vm.expectRevert(); //IEscrow.Escrow__UnauthorizedAccount.selector
        escrow.submit(currentContractId, contractData, salt);
        (_contractor,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 1); //Status.ACTIVE
    }

    function test_submit_reverts_InvalidStatusForSubmit() public {
        test_submit_withContractorAddress();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,,,,, bytes32 _contractorData,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);
        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusForSubmit.selector);
        escrow.submit(currentContractId, contractData, salt);
        (_contractor,,,,, _contractorData,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_contractorData, contractorDataHash);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
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
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        uint256 amountApprove = 1 ether;

        vm.startPrank(client);
        vm.expectEmit(true, true, true, true);
        emit Approved(client, currentContractId, amountApprove, contractor);
        escrow.approve(currentContractId, amountApprove, contractor);
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove);
        assertEq(uint256(_status), 3); //Status.APPROVED
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
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        uint256 amountApprove = 1 ether;

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit Approved(owner, currentContractId, amountApprove, contractor);
        escrow.approve(currentContractId, amountApprove, contractor);
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove);
        assertEq(uint256(_status), 3); //Status.APPROVED
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
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        uint256 amountApprove = 1 ether;
        vm.startPrank(address(this));
        vm.expectRevert(); //IEscrow.Escrow__UnauthorizedAccount.selector
        escrow.approve(currentContractId, amountApprove, contractor);
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
        vm.stopPrank();
    }

    function test_approve_reverts_InvalidStatusForApprove() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 1); //Status.ACTIVE

        uint256 amountApprove = 1 ether;
        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusForApprove.selector);
        escrow.approve(currentContractId, amountApprove, contractor);
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.stopPrank();
    }

    function test_approve_reverts_UnauthorizedReceiver() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        uint256 amountApprove = 1 ether;

        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__UnauthorizedReceiver.selector);
        escrow.approve(currentContractId, amountApprove, address(0));
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        vm.expectRevert(IEscrow.Escrow__UnauthorizedReceiver.selector);
        escrow.approve(currentContractId, amountApprove, address(123));
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
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
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidAmount.selector);
        escrow.approve(currentContractId, 0, contractor);
        (,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
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
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        uint256 amountApprove = 1.01 ether;
        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__NotEnoughDeposit.selector);
        escrow.approve(currentContractId, amountApprove, contractor);
        (,,, _amountToClaim,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_amountToClaim, 0);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
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
        assertEq(uint256(_status), 1); //Status.ACTIVE
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.08 ether
        uint256 amountAdditional = 1 ether;
        vm.startPrank(client);
        paymentToken.mint(client, totalDepositAmount);
        paymentToken.approve(address(escrow), totalDepositAmount);
        vm.expectEmit(true, true, true, true);
        emit Refilled(client, currentContractId, amountAdditional);
        escrow.refill(currentContractId, amountAdditional);
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + totalDepositAmount);
        (_contractor,, _amount, _amountToClaim,,, _feeConfig, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 2 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_feeConfig), 0); //Enums.Enums.FeeConfig.CLIENT_COVERS_ALL
        assertEq(uint256(_status), 1); //Status.ACTIVE
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
        assertEq(uint256(_status), 1);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL
        );
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

        vm.prank(owner);
        registry.addToBlacklist(client);
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__BlacklistedAccount.selector);
        escrow.refill(currentContractId, amountAdditional);
        vm.prank(owner);
        registry.removeFromBlacklist(client);
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidAmount.selector);
        escrow.refill(currentContractId, 0 ether);
    }

    ////////////////////////////////////////////
    //              claim tests               //
    ////////////////////////////////////////////

    function test_claim_clientCoversAll() public {
        test_approve();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_status), 3); //Status.APPROVED

        (uint256 totalDepositAmount, uint256 feeApplied) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL
        );

        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(contractor)), 0 ether);

        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
            _computeClaimableAndFeeAmount(address(escrow), 1, contractor, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);
        assertEq(feeApplied, clientFee);

        vm.startPrank(contractor);
        vm.expectEmit(true, true, true, true);
        emit Claimed(contractor, currentContractId, _amountToClaim, feeAmount);
        escrow.claim(currentContractId);
        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), feeAmount + clientFee);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);

        (,, uint256 _amountAfter, uint256 _amountToClaimAfter,,,, Enums.Status _statusAfter) =
            escrow.deposits(currentContractId);
        assertEq(_amountAfter, _amount - _amountToClaim);
        assertEq(_amountToClaimAfter, 0 ether);
        assertEq(uint256(_statusAfter), 4); //Status.COMPLETED
        vm.stopPrank();
    }

    function test_claim_reverts() public {
        uint256 amountApprove = 0 ether;
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (,, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove); //0
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusToClaim.selector);
        escrow.claim(currentContractId);

        amountApprove = _amount;
        vm.prank(client);
        escrow.approve(currentContractId, amountApprove, contractor);

        bytes memory expectedRevertData =
            abi.encodeWithSelector(IEscrow.Escrow__UnauthorizedAccount.selector, address(this));

        vm.prank(address(this));
        vm.expectRevert(expectedRevertData);
        escrow.claim(currentContractId);
        (,, _amount, _amountToClaim,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove); //0
        assertEq(uint256(_status), 3); //Status.APPROVED

        vm.prank(owner);
        registry.addToBlacklist(contractor);
        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__BlacklistedAccount.selector);
        escrow.claim(currentContractId);

        MockRegistry mockRegistry = new MockRegistry(owner);
        vm.startPrank(owner);
        mockRegistry.addPaymentToken(address(paymentToken));
        // mockRegistry.setTreasury(treasury);
        mockRegistry.updateFeeManager(address(feeManager));
        escrow.updateRegistry(address(mockRegistry));
        vm.stopPrank();

        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector); //treasury()
            // 0x0000000000000000000000000000000000000000
        escrow.claim(currentContractId);
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
            _computeDepositAndFeeAmount(address(escrow), 1, contractor, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);

        vm.startPrank(client);
        paymentToken.mint(address(client), depositAmount); //1.03 ether
        paymentToken.approve(address(escrow), depositAmount);
        escrow.deposit(deposit);
        vm.stopPrank();

        uint256 currentContractId = escrow.getCurrentContractId();
        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));

        vm.prank(contractor);
        escrow.submit(currentContractId, contractData, salt);

        uint256 amountApprove = 1 ether;
        vm.prank(client);
        escrow.approve(currentContractId, amountApprove, contractor);

        (address _contractor,, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_status), 3); //Status.APPROVED

        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
            _computeClaimableAndFeeAmount(address(escrow), 1, contractor, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(feeApplied, clientFee);

        vm.prank(contractor);
        escrow.claim(currentContractId);
        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), feeAmount + clientFee);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);
    }

    function test_claim_withSeveralDeposits() public {
        test_approve();

        (uint256 totalDepositAmount,) =
            _computeDepositAndFeeAmount(address(escrow), 1, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);

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
            _computeDepositAndFeeAmount(address(escrow), 1, contractor, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
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

        vm.prank(contractor);
        escrow.submit(currentContractId_2, contractData, salt);

        uint256 amountApprove = 1 ether;
        vm.prank(client);
        escrow.approve(currentContractId_2, amountApprove, contractor);

        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
            _computeClaimableAndFeeAmount(address(escrow), 1, contractor, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(feeApplied1, clientFee);
        assertEq(claimAmount, amountApprove - feeAmount);

        vm.prank(contractor);
        escrow.claim(currentContractId_2);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), feeAmount + clientFee);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);

        (uint256 _claimAmount,, uint256 _clientFee) =
            _computeClaimableAndFeeAmount(address(escrow), 1, contractor, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);

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

        (uint256 depositAmount,) =
            _computeDepositAndFeeAmount(address(escrow), 1, contractor, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);

        vm.startPrank(client);
        paymentToken.mint(address(client), depositAmount); //1.03 ether
        paymentToken.approve(address(escrow), depositAmount);
        escrow.deposit(deposit);
        vm.stopPrank();

        uint256 currentContractId = escrow.getCurrentContractId();
        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));

        vm.prank(contractor);
        escrow.submit(currentContractId, contractData, salt);
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
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        vm.prank(client);
        escrow.requestReturn(currentContractId);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED

        vm.prank(contractor);
        escrow.createDispute(currentContractId);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED

        // uint256 clientAmount = _amount / 2;
        // uint256 contractorAmount = _amount / 2;
        vm.prank(owner);
        escrow.resolveDispute(currentContractId, Enums.Winner.SPLIT, _amount / 2, _amount / 2);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0.5 ether);
        assertEq(_amountToWithdraw, 0.5 ether);
        assertEq(uint256(_status), 7); //Status.RESOLVED

        (uint256 totalDepositAmount, uint256 feeAmount) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + feeAmount + _amountToClaim);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(contractor)), 0 ether);

        (, uint256 initialFeeAmount) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId, client, _amount, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        // uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        escrow.withdraw(currentContractId);
        (,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_amount, 0.5 ether);
        assertEq(_amountToClaim, 0.5 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 9); //Status.CANCELED
        assertEq(paymentToken.balanceOf(address(escrow)), 0.5 ether);
        assertEq(paymentToken.balanceOf(address(client)), totalDepositAmount); //=0.5 ether
        assertEq(paymentToken.balanceOf(address(treasury)), initialFeeAmount - feeAmount);
        assertEq(paymentToken.balanceOf(address(contractor)), 0 ether);

        vm.startPrank(contractor);
        (uint256 claimAmount, uint256 claimFeeAmount,) = IEscrowFeeManager(feeManager).computeClaimableAmountAndFee(
            address(escrow), currentContractId, contractor, _amountToClaim, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        escrow.claim(currentContractId);
        (,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 4); //Status.COMPLETED
        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), initialFeeAmount - feeAmount + claimFeeAmount);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);
        vm.stopPrank();
    }

    function test_claim_whenResolveDispute_winnerSplit_reverts_NotApproved() public {
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

        (uint256 depositAmount,) =
            _computeDepositAndFeeAmount(address(escrow), 1, contractor, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);

        vm.startPrank(client);
        paymentToken.mint(address(client), depositAmount); //1.03 ether
        paymentToken.approve(address(escrow), depositAmount);
        escrow.deposit(deposit);
        vm.stopPrank();

        uint256 currentContractId = escrow.getCurrentContractId();
        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));

        vm.prank(contractor);
        escrow.submit(currentContractId, contractData, salt);
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
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        vm.prank(client);
        escrow.requestReturn(currentContractId);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED

        vm.prank(contractor);
        escrow.createDispute(currentContractId);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED

        vm.prank(owner);
        escrow.resolveDispute(currentContractId, Enums.Winner.SPLIT, _amount / 2, 0);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0.5 ether);
        assertEq(uint256(_status), 7); //Status.RESOLVED

        vm.startPrank(contractor);
        vm.expectRevert(IEscrow.Escrow__NotApproved.selector);
        escrow.claim(currentContractId);
    }

    MockDAI dai;
    MockUSDT usdt;

    function test_claim_several_contractIds_with_diff_tokens() public {
        dai = new MockDAI();
        usdt = new MockUSDT();
        vm.startPrank(owner);
        registry.addPaymentToken(address(dai));
        registry.addPaymentToken(address(usdt));
        vm.stopPrank();

        // 1. deposit dai
        deposit = IEscrowFixedPrice.Deposit({
            contractor: address(0),
            paymentToken: address(dai),
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.ACTIVE
        });

        uint256 initialTotalDepositAmount = 1.03 ether;
        uint256 depositAmount = 1 ether;
        test_initialize();
        vm.startPrank(client);
        dai.mint(client, initialTotalDepositAmount);
        dai.approve(address(escrow), initialTotalDepositAmount);
        vm.expectEmit(true, true, true, true);
        emit Deposited(client, 1, initialTotalDepositAmount, address(0));
        escrow.deposit(deposit);
        vm.stopPrank();

        uint256 currentContractId_1 = escrow.getCurrentContractId();
        assertEq(currentContractId_1, 1);
        (uint256 totalDepositAmount_dai,) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId_1, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(dai.balanceOf(address(escrow)), totalDepositAmount_dai); //1.03 ether
        assertEq(totalDepositAmount_dai, initialTotalDepositAmount);
        (,, uint256 _amount, uint256 _amountToClaim, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.deposits(currentContractId_1);
        assertEq(uint256(_status), 1); //Status.ACTIVE

        vm.prank(contractor);
        escrow.submit(currentContractId_1, contractData, salt);
        (,,,,,,, _status) = escrow.deposits(currentContractId_1);
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        vm.startPrank(client);
        escrow.approve(currentContractId_1, depositAmount, contractor);
        (,, _amount, _amountToClaim,,,, _status) = escrow.deposits(currentContractId_1);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, depositAmount);
        assertEq(uint256(_status), 3); //Status.APPROVED
        vm.stopPrank();

        // 2. deposit usdt
        deposit = IEscrowFixedPrice.Deposit({
            contractor: address(0),
            paymentToken: address(usdt),
            amount: 1e6,
            amountToClaim: 0,
            amountToWithdraw: 0,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.ACTIVE
        });

        uint256 initialTotalDepositAmount_usdt = 1.03e6;
        uint256 depositAmount_usdt = 1e6;

        vm.startPrank(client);
        usdt.mint(client, initialTotalDepositAmount_usdt);
        usdt.approve(address(escrow), initialTotalDepositAmount_usdt);
        vm.expectEmit(true, true, true, true);
        emit Deposited(client, 2, initialTotalDepositAmount_usdt, address(0));
        escrow.deposit(deposit);
        vm.stopPrank();

        uint256 currentContractId_2 = escrow.getCurrentContractId();
        assertEq(currentContractId_2, 2);
        (uint256 totalDepositAmount_usdt,) = _computeDepositAndFeeAmount(
            address(escrow), 1, client, depositAmount_usdt, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(usdt.balanceOf(address(escrow)), initialTotalDepositAmount_usdt); //1.03e6
        assertEq(totalDepositAmount_usdt, initialTotalDepositAmount_usdt);
        (,,,,,,, _status) = escrow.deposits(currentContractId_2);
        assertEq(uint256(_status), 1); //Status.ACTIVE

        // 3. deposit usdt again
        deposit = IEscrowFixedPrice.Deposit({
            contractor: address(0),
            paymentToken: address(usdt),
            amount: 1e6,
            amountToClaim: 0,
            amountToWithdraw: 0,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.ACTIVE
        });

        vm.startPrank(client);
        usdt.mint(client, initialTotalDepositAmount_usdt);
        usdt.approve(address(escrow), initialTotalDepositAmount_usdt);
        vm.expectEmit(true, true, true, true);
        emit Deposited(client, 3, initialTotalDepositAmount_usdt, address(0));
        escrow.deposit(deposit);
        vm.stopPrank();

        uint256 currentContractId_3 = escrow.getCurrentContractId();
        assertEq(currentContractId_3, 3);
        (,,,,,,, _status) = escrow.deposits(currentContractId_3);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        (totalDepositAmount_usdt,) = _computeDepositAndFeeAmount(
            address(escrow), 1, client, depositAmount_usdt, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        assertEq(totalDepositAmount_usdt, initialTotalDepositAmount_usdt);

        assertEq(usdt.balanceOf(address(escrow)), initialTotalDepositAmount_usdt + totalDepositAmount_usdt); //2.06e6
        assertEq(dai.balanceOf(address(escrow)), totalDepositAmount_dai); //1.03 ether

        vm.prank(client);
        escrow.requestReturn(currentContractId_3);
        vm.prank(owner);
        escrow.approveReturn(currentContractId_3);

        (,, _amount,, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId_3);
        assertEq(_amount, depositAmount_usdt);
        assertEq(_amountToWithdraw, depositAmount_usdt);
        assertEq(uint256(_status), 8); //Status.REFUND_APPROVED

        (uint256 totalDeposited_usdt, uint256 feeAmount_usdt) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId_3, client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        (totalDeposited_usdt);

        (, uint256 initialFeeAmount_usdt) = _computeDepositAndFeeAmount(
            address(escrow), currentContractId_3, client, depositAmount_usdt, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        uint256 platformFee_usdt = initialFeeAmount_usdt - feeAmount_usdt;

        vm.prank(client);
        escrow.withdraw(currentContractId_3);
        (,, _amount,, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId_3);
        assertEq(_amount, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 9); //Status.CANCELED

        assertEq(
            usdt.balanceOf(address(escrow)),
            initialTotalDepositAmount_usdt * 2 - (depositAmount_usdt + initialFeeAmount_usdt)
        ); //2.06e6-1e6
        assertEq(usdt.balanceOf(address(client)), depositAmount_usdt + initialFeeAmount_usdt);
        assertEq(usdt.balanceOf(address(treasury)), platformFee_usdt);
        assertEq(usdt.balanceOf(address(contractor)), 0);
        assertEq(platformFee_usdt, 0);
        assertEq(dai.balanceOf(address(escrow)), 1.03 ether); //1.03 ether - totalDepositAmount_dai
        assertEq(dai.balanceOf(address(contractor)), 0 ether);

        address new_contractor = makeAddr("new_contractor");
        vm.prank(new_contractor);
        escrow.submit(currentContractId_2, contractData, salt);
        vm.prank(client);
        escrow.approve(currentContractId_2, depositAmount_usdt, new_contractor);

        (uint256 claimAmount, uint256 contractorFee, uint256 clientFee) =
            _computeClaimableAndFeeAmount(address(escrow), 1, contractor, 1e6, Enums.FeeConfig.CLIENT_COVERS_ONLY);

        vm.prank(new_contractor);
        escrow.claim(currentContractId_2);

        assertEq(usdt.balanceOf(address(client)), 1e6 + initialFeeAmount_usdt);
        assertEq(usdt.balanceOf(address(treasury)), contractorFee + clientFee);
        assertEq(
            usdt.balanceOf(address(escrow)),
            2.06e6 - (1e6 + initialFeeAmount_usdt) - claimAmount - (contractorFee + clientFee)
        );
        assertEq(usdt.balanceOf(address(escrow)), 0);

        (claimAmount, contractorFee, clientFee) =
            _computeClaimableAndFeeAmount(address(escrow), 1, contractor, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);

        vm.prank(contractor);
        escrow.claim(1); //currentContractId_1
        assertEq(dai.balanceOf(address(escrow)), 0);
        assertEq(dai.balanceOf(address(client)), 0);
        assertEq(dai.balanceOf(address(contractor)), claimAmount);
        assertEq(dai.balanceOf(address(treasury)), contractorFee + clientFee);
    }

    ////////////////////////////////////////////
    //          return request tests          //
    ////////////////////////////////////////////

    function test_requestReturn_whenActive() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnRequested(client, currentContractId);
        escrow.requestReturn(currentContractId);
        (_contractor,, _amount,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_whenSubmitted() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnRequested(client, currentContractId);
        escrow.requestReturn(currentContractId);
        (_contractor,, _amount,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_whenApproved() public {
        test_approve();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 3); //Status.APPROVED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnRequested(client, currentContractId);
        escrow.requestReturn(currentContractId);
        (_contractor,, _amount,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_whenCompleted() public {
        test_claim_clientCoversOnly();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 0 ether);
        assertEq(uint256(_status), 4); //Status.COMPLETED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnRequested(client, currentContractId);
        escrow.requestReturn(currentContractId);
        (_contractor,, _amount,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 0 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_reverts_UnauthorizedAccount() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.prank(contractor);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender);
        escrow.requestReturn(currentContractId);
        (_contractor,, _amount,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
    }

    function test_requestReturn_reverts_ReturnNotAllowed() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__ReturnNotAllowed.selector);
        escrow.requestReturn(currentContractId);
        (_contractor,, _amount,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_reverts_submitted_UnauthorizedAccount() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
        vm.prank(address(this));
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender);
        escrow.requestReturn(currentContractId);
        (_contractor,, _amount,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
    }

    function test_approveReturn_by_owner() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit ReturnApproved(owner, currentContractId);
        escrow.approveReturn(currentContractId);
        (_contractor,, _amount,, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 1 ether);
        assertEq(uint256(_status), 8); //Status.REFUND_APPROVED
    }

    function test_approveReturn_by_contractor() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(contractor);
        vm.expectEmit(true, true, true, true);
        emit ReturnApproved(contractor, currentContractId);
        escrow.approveReturn(currentContractId);
        (_contractor,, _amount,, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 1 ether);
        assertEq(uint256(_status), 8); //Status.REFUND_APPROVED
    }

    function test_approveReturn_reverts_UnauthorizedToApproveReturn() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__UnauthorizedToApproveReturn.selector);
        escrow.approveReturn(currentContractId);
        (_contractor,, _amount,, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
    }

    function test_approveReturn_reverts_NoReturnRequested() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,,,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__NoReturnRequested.selector);
        escrow.approveReturn(currentContractId);
        (_contractor,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 1); //Status.ACTIVE
    }

    function test_approveReturn_reverts_submitted_NoReturnRequested() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,,,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__NoReturnRequested.selector);
        escrow.approveReturn(currentContractId);
        (_contractor,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
    }

    function test_cancelReturn() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        (,,,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        status = Enums.Status.ACTIVE;
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnCanceled(client, currentContractId);
        escrow.cancelReturn(currentContractId, status);
        (,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 1); //Status.ACTIVE
    }

    function test_cancelReturn_submitted() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,,,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        status = Enums.Status.SUBMITTED;
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnCanceled(client, currentContractId);
        escrow.cancelReturn(currentContractId, status);
        (_contractor,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
    }

    function test_cancelReturn_reverts() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        (,,,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        status = Enums.Status.ACTIVE;
        vm.prank(owner);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.cancelReturn(currentContractId, status);
        (,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        status = Enums.Status.CANCELED;
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusProvided.selector);
        escrow.cancelReturn(currentContractId, status);
        (,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
    }

    function test_cancelReturn_reverts_submitted() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        status = Enums.Status.RESOLVED;
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusProvided.selector);
        escrow.cancelReturn(currentContractId, status);
        (,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
    }

    function test_cancelReturn_reverts_submitted_NoReturnRequested() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,,,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
        status = Enums.Status.ACTIVE;
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__NoReturnRequested.selector);
        escrow.cancelReturn(currentContractId, status);
        (_contractor,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
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
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit DisputeCreated(client, currentContractId);
        escrow.createDispute(currentContractId);
        (_contractor,, _amount,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED
    }

    // if contractor doesn’t want to approve “Escrow Return Request”
    // or if a client doesn’t Approve Submitted work and sends Change Requests
    function test_createDispute_by_contractor() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(contractor);
        vm.expectEmit(true, true, true, true);
        emit DisputeCreated(contractor, currentContractId);
        escrow.createDispute(currentContractId);
        (_contractor,, _amount,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED
    }

    function test_createDispute_reverts_CreateDisputeNotAllowed() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__CreateDisputeNotAllowed.selector);
        escrow.createDispute(currentContractId);
        (_contractor,, _amount,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
    }

    function test_createDispute_reverts_UnauthorizedToApproveDispute() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(address(this));
        vm.expectRevert(IEscrow.Escrow__UnauthorizedToApproveDispute.selector);
        escrow.createDispute(currentContractId);
        (_contractor,, _amount,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
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
        assertEq(uint256(_status), 6); //Status.DISPUTED
        Enums.Winner _winner = Enums.Winner.CLIENT;
        uint256 clientAmount = _amount;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(owner, currentContractId, _winner, clientAmount, 0);
        escrow.resolveDispute(currentContractId, _winner, clientAmount, 0);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, clientAmount);
        assertEq(uint256(_status), 7); //Status.RESOLVED
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
        assertEq(uint256(_status), 6); //Status.DISPUTED
        Enums.Winner _winner = Enums.Winner.CONTRACTOR;
        uint256 contractorAmount = _amount;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(owner, currentContractId, _winner, 0, contractorAmount);
        escrow.resolveDispute(currentContractId, _winner, 0, contractorAmount);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, contractorAmount);
        assertEq(_amountToWithdraw, 0);
        assertEq(uint256(_status), 3); //Status.APPROVED
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
        assertEq(uint256(_status), 6); //Status.DISPUTED
        Enums.Winner _winner = Enums.Winner.SPLIT;
        uint256 clientAmount = _amount / 2;
        uint256 contractorAmount = _amount / 2;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(owner, currentContractId, _winner, clientAmount, contractorAmount);
        escrow.resolveDispute(currentContractId, _winner, clientAmount, contractorAmount);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0.5 ether);
        assertEq(_amountToWithdraw, 0.5 ether);
        assertEq(uint256(_status), 7); //Status.RESOLVED
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
        assertEq(uint256(_status), 6); //Status.DISPUTED
        Enums.Winner _winner = Enums.Winner.SPLIT;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(owner, currentContractId, _winner, 0, 0);
        escrow.resolveDispute(currentContractId, _winner, 0, 0);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 7); //Status.RESOLVED
    }

    function test_resolveDispute_reverts_DisputeNotActiveForThisDeposit() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (,,,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__DisputeNotActiveForThisDeposit.selector);
        escrow.resolveDispute(currentContractId, Enums.Winner.CLIENT, 0, 0);
        (,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 1); //Status.ACTIVE
    }

    function test_resolveDispute_reverts_UnauthorizedToApproveDispute() public {
        test_createDispute_by_client();
        uint256 currentContractId = escrow.getCurrentContractId();
        (,,,,,,, Enums.Status _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 6); //Status.DISPUTED
        vm.prank(address(this));
        vm.expectRevert(); //Unauthorized()
        escrow.resolveDispute(currentContractId, Enums.Winner.CONTRACTOR, 0, 0);
        (,,,,,,, _status) = escrow.deposits(currentContractId);
        assertEq(uint256(_status), 6); //Status.DISPUTED
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
        assertEq(uint256(_status), 6); //Status.DISPUTED
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__ResolutionExceedsDepositedAmount.selector);
        escrow.resolveDispute(currentContractId, Enums.Winner.CLIENT, 1.1 ether, 0 ether);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED
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
        assertEq(uint256(_status), 6); //Status.DISPUTED
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__ResolutionExceedsDepositedAmount.selector);
        escrow.resolveDispute(currentContractId, Enums.Winner.CONTRACTOR, 0 ether, 1.1 ether);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED
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
        assertEq(uint256(_status), 6); //Status.DISPUTED
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__ResolutionExceedsDepositedAmount.selector);
        escrow.resolveDispute(currentContractId, Enums.Winner.SPLIT, 1 ether, 1 wei);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED
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
        assertEq(uint256(_status), 6); //Status.DISPUTED
        vm.prank(owner);
        // vm.expectRevert(IEscrow.Escrow__InvalidWinnerSpecified.selector);
        vm.expectRevert(); // panic: failed to convert value into enum type (0x21)
        escrow.resolveDispute(currentContractId, Enums.Winner(uint256(4)), _amount, 0); // Invalid enum value for Winner
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.deposits(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
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
