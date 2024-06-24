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

    IEscrowHourly.Deposit[] deposits;

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
        uint256 indexed weekId,
        address paymentToken,
        uint256 amount,
        Enums.FeeConfig feeConfig
    );
    event Submitted(address indexed sender, uint256 indexed contractId, uint256 indexed weekId);
    event Approved(uint256 indexed contractId, uint256 indexed weekId, uint256 amountApprove, address receiver);
    event Refilled(uint256 indexed contractId, uint256 indexed weekId, uint256 indexed amountAdditional);
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

        // Initialize the deposits array within setUp
        deposits.push(
            IEscrowHourly.Deposit({
                contractor: address(0),
                paymentToken: address(paymentToken),
                amount: 1 ether,
                amountToClaim: 0,
                amountToWithdraw: 0,
                contractorData: contractorData,
                feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                status: Enums.Status.ACTIVE
            })
        );
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

    function test_deposit() public {
        test_initialize();
        vm.startPrank(address(client));
        paymentToken.mint(address(client), 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        vm.expectEmit(true, true, true, true);
        emit Deposited(address(client), 1, 0, address(paymentToken), 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        escrow.deposit(0, deposits);
        vm.stopPrank();
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
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
        ) = escrow.contractWeeks(currentContractId, 0);
        assertEq(_contractor, address(0));
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);

        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 0); //Status.ACTIVE
        assertEq(escrow.getWeeksCount(currentContractId), 1);
    }

    function test_deposit_existingContract() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        vm.startPrank(address(client));
        paymentToken.mint(address(client), 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        vm.expectEmit(true, true, true, true);
        emit Deposited(address(client), 1, 1, address(paymentToken), 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        escrow.deposit(currentContractId, deposits);
        vm.stopPrank();
        (
            address _contractor,
            address _paymentToken,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            bytes32 _contractorData,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractWeeks(currentContractId, 1);
        assertEq(_contractor, address(0));
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);

        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 0); //Status.ACTIVE
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, _amount, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + totalDepositAmount); //2.06 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(escrow.getWeeksCount(currentContractId), 2);
    }

    function test_deposit_reverts() public {
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        vm.prank(client);
        escrow.deposit(0, deposits);
        test_initialize();
        address notClient = makeAddr("notClient");
        vm.prank(notClient);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.deposit(0, deposits);

        ERC20Mock notPaymentToken = new ERC20Mock();
        IEscrowHourly.Deposit[] memory _deposits = new IEscrowHourly.Deposit[](1);
        _deposits[0] = IEscrowHourly.Deposit({
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
        escrow.deposit(0, _deposits);

        _deposits = new IEscrowHourly.Deposit[](0);
        vm.prank(client);
        vm.expectRevert(IEscrowHourly.Escrow__NoDepositsProvided.selector);
        escrow.deposit(0, _deposits);

        vm.startPrank(address(client));
        paymentToken.mint(address(client), 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        _deposits = new IEscrowHourly.Deposit[](1);
        _deposits[0] = IEscrowHourly.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.ACTIVE
        });
        vm.expectRevert(IEscrowHourly.Escrow__InvalidContractId.selector);
        escrow.deposit(1, _deposits);
        vm.stopPrank();
    }

    function test_deposit_withEmptyPrepayment() public {
        test_initialize();
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 0);
        IEscrowHourly.Deposit[] memory _deposits = new IEscrowHourly.Deposit[](1);
        _deposits[0] = IEscrowHourly.Deposit({
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
        vm.expectEmit(true, true, true, true);
        emit Deposited(address(client), 1, 0, address(paymentToken), 0 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);
        escrow.deposit(0, _deposits);
        vm.stopPrank();
        currentContractId = escrow.getCurrentContractId();
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
        ) = escrow.contractWeeks(currentContractId, 0);
        assertEq(_contractor, address(0));
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);

        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 0); //Enums.Enums.FeeConfig.CLIENT_COVERS_ALL
        assertEq(uint256(_status), 0); //Status.ACTIVE
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, _amount, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(escrow.getWeeksCount(currentContractId), 1);
    }

    function test_deposit_severalMilestones() public {
        test_initialize();
        IEscrowHourly.Deposit[] memory _deposits = new IEscrowHourly.Deposit[](3);
        _deposits[0] = IEscrowHourly.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.ACTIVE
        });
        (uint256 depositAmountMilestone1,) =
            _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);
        _deposits[1] = IEscrowHourly.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 2 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.ACTIVE
        });
        (uint256 depositAmountMilestone2,) =
            _computeDepositAndFeeAmount(client, 2 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        _deposits[2] = IEscrowHourly.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 3 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.ACTIVE
        });
        (uint256 depositAmountMilestone3,) =
            _computeDepositAndFeeAmount(client, 3 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        uint256 totalDepositAmount = depositAmountMilestone1 + depositAmountMilestone2 + depositAmountMilestone3;
        vm.startPrank(address(client));
        paymentToken.mint(address(client), totalDepositAmount);
        paymentToken.approve(address(escrow), totalDepositAmount);
        escrow.deposit(0, _deposits);
        uint256 currentContractId = escrow.getCurrentContractId();
        (
            address _contractor,
            address _paymentToken,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            bytes32 _contractorData,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractWeeks(currentContractId, 0);
        assertEq(_contractor, address(0));
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);

        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 0); //Enums.Enums.FeeConfig.CLIENT_COVERS_ALL
        assertEq(uint256(_status), 0); //Status.ACTIVE
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,, _feeConfig, _status) =
            escrow.contractWeeks(currentContractId, 1);
        assertEq(_contractor, address(0));
        assertEq(_amount, 2 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 0); //Status.ACTIVE
        (,, _amount, _amountToClaim, _amountToWithdraw,, _feeConfig, _status) =
            escrow.contractWeeks(currentContractId, 2);
        assertEq(_amount, 3 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 0); //Status.ACTIVE
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(escrow.getWeeksCount(currentContractId), 3);
        vm.stopPrank();
    }

    function test_deposit_withContractorAddress() public {
        test_initialize();
        IEscrowHourly.Deposit[] memory _deposits = new IEscrowHourly.Deposit[](1);
        _deposits[0] = IEscrowHourly.Deposit({
            contractor: contractor,
            paymentToken: address(paymentToken),
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.ACTIVE
        });
        (uint256 depositAmountMilestone1,) =
            _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        vm.startPrank(address(client));
        paymentToken.mint(address(client), depositAmountMilestone1);
        paymentToken.approve(address(escrow), depositAmountMilestone1);
        escrow.deposit(0, _deposits);
        uint256 currentContractId = escrow.getCurrentContractId();
        (
            address _contractor,
            address _paymentToken,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            bytes32 _contractorData,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractWeeks(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);

        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 0); //Status.ACTIVE
        assertEq(paymentToken.balanceOf(address(escrow)), depositAmountMilestone1);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        vm.stopPrank();
    }

    ///////////////////////////////////////////
    //             submit tests              //
    ///////////////////////////////////////////

    function test_submit() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,, bytes32 _contractorData,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, 0);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_status), 0); //Status.ACTIVE

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);
        vm.prank(contractor);
        vm.expectEmit(true, true, true, true);
        emit Submitted(contractor, currentContractId, 0);
        escrow.submit(currentContractId, 0, contractData, salt);
        (_contractor,, _amount,,,,, _status) = escrow.contractWeeks(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_contractorData, contractorDataHash);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    function test_submit_withContractorAddress() public {
        test_deposit_withContractorAddress();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,, bytes32 _contractorData,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_status), 0); //Status.ACTIVE

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);
        vm.prank(contractor);
        vm.expectEmit(true, true, true, true);
        emit Submitted(contractor, currentContractId, 0);
        escrow.submit(currentContractId, 0, contractData, salt);
        (_contractor,, _amount,,,,, _status) = escrow.contractWeeks(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_contractorData, contractorDataHash);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    function test_submit_reverts_InvalidStatusForSubmit() public {
        test_submit_withContractorAddress();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,,,,, bytes32 _contractorData,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);
        vm.startPrank(contractor);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusForSubmit.selector);
        escrow.submit(currentContractId, 0, contractData, salt);
        (_contractor,,,,,,, _status) = escrow.contractWeeks(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    function test_submit_reverts_InvalidContractorDataHash() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,, uint256 _amount,,, bytes32 _contractorData,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, 0);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_status), 0); //Status.ACTIVE

        contractData = bytes("contract_data_");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);
        vm.startPrank(contractor);
        vm.expectRevert(IEscrow.Escrow__InvalidContractorDataHash.selector);
        escrow.submit(currentContractId, 0, contractData, salt);
        (_contractor,,,,,,, _status) = escrow.contractWeeks(currentContractId, 0);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 0); //Status.ACTIVE

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(43)));
        contractorDataHash = escrow.getContractorDataHash(contractData, salt);
        vm.startPrank(contractor);
        vm.expectRevert(IEscrow.Escrow__InvalidContractorDataHash.selector);
        escrow.submit(currentContractId, 0, contractData, salt);
        (_contractor,,,,,,, _status) = escrow.contractWeeks(currentContractId, 0);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_submit_reverts_UnauthorizedAccount() public {
        test_deposit_withContractorAddress();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,,,,, bytes32 _contractorData,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_status), 0); //Status.ACTIVE

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);
        vm.prank(address(this));
        vm.expectRevert(); //IEscrow.Escrow__UnauthorizedAccount.selector
        escrow.submit(currentContractId, 0, contractData, salt);
        (_contractor,,,,,,, _status) = escrow.contractWeeks(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_contractorData, contractorDataHash);
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    ////////////////////////////////////////////
    //             approve tests              //
    ////////////////////////////////////////////

    function test_approve() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        weekId--;
        (address _contractor,, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        uint256 amountApprove = 1 ether;
        vm.startPrank(client);
        vm.expectEmit(true, true, true, true);
        emit Approved(currentContractId, weekId, amountApprove, contractor);
        escrow.approve(currentContractId, weekId, amountApprove, contractor);
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove);
        assertEq(uint256(_status), 2); //Status.APPROVED
        vm.stopPrank();
    }

    function test_approve_byOwner() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        weekId--;
        (address _contractor,, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        uint256 amountApprove = 1 ether;
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit Approved(currentContractId, weekId, amountApprove, contractor);
        escrow.approve(currentContractId, weekId, amountApprove, contractor);
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove);
        assertEq(uint256(_status), 2); //Status.APPROVED
        vm.stopPrank();
    }

    function test_approve_reverts_UnauthorizedAccount() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        weekId--;
        (address _contractor,, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        uint256 amountApprove = 1 ether;
        vm.startPrank(address(this));
        vm.expectRevert(); //IEscrow.Escrow__UnauthorizedAccount.selector
        escrow.approve(currentContractId, weekId, amountApprove, contractor);
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        vm.stopPrank();
    }

    function test_approve_reverts_InvalidStatusForApprove() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 0); //Status.ACTIVE

        uint256 amountApprove = 1 ether;
        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusForApprove.selector);
        escrow.approve(currentContractId, weekId, amountApprove, contractor);
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.stopPrank();
    }

    function test_approve_reverts_UnauthorizedReceiver() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        uint256 amountApprove = 1 ether;
        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__UnauthorizedReceiver.selector);
        escrow.approve(currentContractId, weekId, amountApprove, address(0));
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        vm.expectRevert(IEscrow.Escrow__UnauthorizedReceiver.selector);
        escrow.approve(currentContractId, weekId, amountApprove, address(this));
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        vm.stopPrank();
    }

    function test_approve_reverts_InvalidAmount() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        uint256 amountApprove = 0 ether;
        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidAmount.selector);
        escrow.approve(currentContractId, weekId, amountApprove, address(0));
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    function test_approve_reverts_NotEnoughDeposit() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        uint256 amountApprove = 1.1 ether;
        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__NotEnoughDeposit.selector);
        escrow.approve(currentContractId, weekId, amountApprove, contractor);
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    ////////////////////////////////////////////
    //              refill tests              //
    ////////////////////////////////////////////

    function test_refill() public {
        test_approve_reverts_NotEnoughDeposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);

        uint256 amountAdditional = 1 ether;
        vm.startPrank(address(client));
        paymentToken.mint(address(client), totalDepositAmount);
        paymentToken.approve(address(escrow), totalDepositAmount);
        vm.expectEmit(true, true, true, true);
        emit Refilled(currentContractId, weekId, amountAdditional);
        escrow.refill(currentContractId, weekId, amountAdditional);
        vm.stopPrank();
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 2 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + totalDepositAmount); //2.06 ether
    }

    function test_refill_reverts() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (,, uint256 _amount,,,,, Enums.Status _status) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE

        uint256 amountAdditional = 1 ether;
        vm.startPrank(address(this));
        paymentToken.mint(address(client), amountAdditional);
        paymentToken.approve(address(escrow), amountAdditional);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender);
        escrow.refill(currentContractId, weekId, amountAdditional);
        vm.stopPrank();

        amountAdditional = 0 ether;
        vm.startPrank(client);
        paymentToken.mint(address(client), amountAdditional);
        paymentToken.approve(address(escrow), amountAdditional);
        vm.expectRevert(IEscrow.Escrow__InvalidAmount.selector);
        escrow.refill(currentContractId, weekId, amountAdditional);
        vm.stopPrank();

        (,, _amount,,,,,) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amount, 1 ether);
    }

    ////////////////////////////////////////////
    //              claim tests               //
    ////////////////////////////////////////////

    function test_claim_clientCoversOnly() public {
        test_approve();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (
            address _contractor,
            ,
            uint256 _amount,
            uint256 _amountToClaim,
            ,
            ,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 2); //Status.APPROVED

        (uint256 totalDepositAmount, uint256 feeApplied) =
            _computeDepositAndFeeAmount(client, _amount, Enums.FeeConfig.CLIENT_COVERS_ONLY);

        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(contractor)), 0 ether);

        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
            _computeClaimableAndFeeAmount(contractor, _amountToClaim, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(feeApplied, clientFee);

        vm.startPrank(contractor);
        vm.expectEmit(true, true, true, true);
        emit Claimed(currentContractId, weekId, claimAmount);
        escrow.claim(currentContractId, weekId);

        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), feeAmount + clientFee);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);

        (,, _amount, _amountToClaim,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 3); //Status.COMPLETED
        vm.stopPrank();
    }

    function test_claim_reverts() public {
        uint256 amountApprove = 0 ether;
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (,, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove); //0
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusToClaim.selector);
        // vm.expectRevert(IEscrow.Escrow__NotApproved.selector); //TODO test
        escrow.claim(currentContractId, weekId);
        vm.prank(address(this));
        vm.expectRevert(); //IEscrow.Escrow__UnauthorizedAccount.selector
        escrow.claim(currentContractId, weekId);
        (,, _amount, _amountToClaim,,,, _status) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove); //0
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    function test_claim_whenResolveDispute_winnerSplit() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (
            address _contractor,
            ,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            ,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        vm.prank(client);
        escrow.requestReturn(currentContractId, weekId);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED

        vm.prank(contractor);
        escrow.createDispute(currentContractId, weekId);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED

        vm.prank(owner);
        escrow.resolveDispute(currentContractId, weekId, Enums.Winner.SPLIT, _amount / 2, _amount / 2);
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractWeeks(currentContractId, weekId);
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

        vm.prank(client);
        escrow.withdraw(currentContractId, weekId);
        (,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.contractWeeks(currentContractId, weekId);
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
        escrow.claim(currentContractId, weekId);
        (,, _amount, _amountToClaim, _amountToWithdraw,,, _status) = escrow.contractWeeks(currentContractId, weekId);
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

    function test_claim_severalMilestone() public {
        test_deposit_severalMilestones();
        assertEq(paymentToken.balanceOf(address(escrow)), 6.23 ether);

        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        assertEq(escrow.getWeeksCount(currentContractId), 3);
        uint256 milestoneId1 = weekId - 1;

        (address _contractor,, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractWeeks(currentContractId, milestoneId1);
        assertEq(_contractor, address(0));
        assertEq(_amount, 3 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE

        uint256 milestoneId2 = weekId - 2;
        (_contractor,, _amount, _amountToClaim,,,, _status) = escrow.contractWeeks(currentContractId, milestoneId2);
        assertEq(_contractor, address(0));
        assertEq(_amount, 2 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);
        vm.prank(contractor);
        escrow.submit(currentContractId, milestoneId2, contractData, salt);

        uint256 amountApprove = 2 ether;
        vm.prank(client);
        escrow.approve(currentContractId, milestoneId2, amountApprove, contractor);

        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
            _computeClaimableAndFeeAmount(contractor, 2 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(claimAmount, amountApprove - feeAmount);

        vm.prank(contractor);
        escrow.claim(currentContractId, milestoneId2);
        // check milestoneId2 is changed
        (,, _amount, _amountToClaim,,,, _status) = escrow.contractWeeks(currentContractId, milestoneId2);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 3); //Status.COMPLETED

        // check milestoneId1 is not changed
        (,, _amount, _amountToClaim,,,, _status) = escrow.contractWeeks(currentContractId, milestoneId1);
        assertEq(_amount, 3 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE

        // check updated balances
        assertEq(paymentToken.balanceOf(address(escrow)), 6.23 ether - claimAmount - (feeAmount + clientFee));
        assertEq(paymentToken.balanceOf(address(treasury)), feeAmount + clientFee);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);
    }

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
}
