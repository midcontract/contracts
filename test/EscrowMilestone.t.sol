// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";

import {EscrowMilestone, IEscrowMilestone} from "src/EscrowMilestone.sol";
import {EscrowAdminManager, OwnedRoles} from "src/modules/EscrowAdminManager.sol";
import {EscrowFeeManager, IEscrowFeeManager} from "src/modules/EscrowFeeManager.sol";
import {EscrowRegistry, IEscrowRegistry} from "src/modules/EscrowRegistry.sol";
import {Enums} from "src/libs/Enums.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {IEscrow} from "src/interfaces/IEscrow.sol";
import {MockRegistry} from "test/mocks/MockRegistry.sol";

contract EscrowMilestoneUnitTest is Test {
    EscrowMilestone escrow;
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

    IEscrowMilestone.Deposit[] deposits;

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

    IEscrowMilestone.MilestoneDetails milestoneDetails;

    struct MilestoneDetails {
        address paymentToken;
        uint256 depositAmount;
        Enums.Winner winner;
    }

    event Deposited(
        address indexed sender,
        uint256 indexed contractId,
        uint256 indexed milestoneId,
        address paymentToken,
        uint256 amount,
        Enums.FeeConfig feeConfig
    );
    event Submitted(address indexed sender, uint256 indexed contractId, uint256 indexed milestoneId);
    event Approved(uint256 indexed contractId, uint256 indexed milestoneId, uint256 amountApprove, address receiver);
    event Refilled(uint256 indexed contractId, uint256 indexed milestoneId, uint256 indexed amountAdditional);
    event Claimed(uint256 indexed contractId, uint256 indexed milestoneId, uint256 indexed amount);
    event Withdrawn(uint256 indexed contractId, uint256 indexed milestoneId, uint256 amount);
    event ReturnRequested(uint256 contractId, uint256 milestoneId);
    event ReturnApproved(uint256 contractId, uint256 milestoneId, address sender);
    event ReturnCanceled(uint256 contractId, uint256 milestoneId);
    event DisputeCreated(uint256 contractId, uint256 milestoneId, address sender);
    event DisputeResolved(
        uint256 contractId, uint256 milestoneId, Enums.Winner winner, uint256 clientAmount, uint256 contractorAmount
    );

    function setUp() public {
        owner = makeAddr("owner");
        treasury = makeAddr("treasury");
        client = makeAddr("client");
        contractor = makeAddr("contractor");

        escrow = new EscrowMilestone();
        registry = new EscrowRegistry(owner);
        paymentToken = new ERC20Mock();
        feeManager = new EscrowFeeManager(3_00, 5_00, owner);
        adminManager = new EscrowAdminManager(owner);

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
            IEscrowMilestone.Deposit({
                contractor: address(0),
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
        escrow.deposit(0, address(paymentToken), deposits);
        vm.stopPrank();
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (
            address _contractor,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            bytes32 _contractorData,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractMilestones(currentContractId, 0);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 0); //Status.ACTIVE
        assertEq(escrow.getMilestoneCount(currentContractId), 1);
        (address _paymentToken, uint256 _depositAmount, Enums.Winner _winner) =
            escrow.milestoneData(currentContractId, 0);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_depositAmount, _amount);
        assertEq(uint256(_winner), 0); //Status.NONE
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
        escrow.deposit(currentContractId, address(paymentToken), deposits);
        vm.stopPrank();
        (
            address _contractor,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            bytes32 _contractorData,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractMilestones(currentContractId, 1);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 0); //Status.ACTIVE
        (address _paymentToken, uint256 _depositAmount, Enums.Winner _winner) =
            escrow.milestoneData(currentContractId, 0);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_depositAmount, _amount);
        assertEq(uint256(_winner), 0); //Status.NONE
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, _amount, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + totalDepositAmount); //2.06 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(escrow.getMilestoneCount(currentContractId), 2);
    }

    function test_deposit_reverts() public {
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        vm.prank(client);
        escrow.deposit(0, address(paymentToken), deposits);
        test_initialize();
        address notClient = makeAddr("notClient");
        vm.prank(notClient);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.deposit(0, address(paymentToken), deposits);

        ERC20Mock notPaymentToken = new ERC20Mock();
        IEscrowMilestone.Deposit[] memory _deposits = new IEscrowMilestone.Deposit[](1);
        _deposits[0] = IEscrowMilestone.Deposit({
            contractor: address(0),
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.ACTIVE
        });
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__NotSupportedPaymentToken.selector);
        escrow.deposit(0, address(notPaymentToken), _deposits);

        _deposits[0] = IEscrowMilestone.Deposit({
            contractor: address(0),
            amount: 0 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.ACTIVE
        });
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__ZeroDepositAmount.selector);
        escrow.deposit(0, address(paymentToken), _deposits);

        _deposits = new IEscrowMilestone.Deposit[](0);
        vm.prank(client);
        vm.expectRevert(IEscrowMilestone.Escrow__NoDepositsProvided.selector);
        escrow.deposit(0, address(paymentToken), _deposits);

        vm.startPrank(address(client));
        paymentToken.mint(address(client), 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        _deposits = new IEscrowMilestone.Deposit[](1);
        _deposits[0] = IEscrowMilestone.Deposit({
            contractor: address(0),
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.ACTIVE
        });
        vm.expectRevert(IEscrowMilestone.Escrow__InvalidContractId.selector);
        escrow.deposit(1, address(paymentToken), _deposits);
        vm.stopPrank();

        vm.prank(owner);
        registry.addToBlacklist(client);
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__BlacklistedAccount.selector);
        escrow.deposit(0, address(paymentToken), _deposits);
    }

    function test_deposit_severalMilestones() public {
        test_initialize();
        IEscrowMilestone.Deposit[] memory _deposits = new IEscrowMilestone.Deposit[](3);
        _deposits[0] = IEscrowMilestone.Deposit({
            contractor: address(0),
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.ACTIVE
        });
        (uint256 depositAmountMilestone1,) =
            _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);
        _deposits[1] = IEscrowMilestone.Deposit({
            contractor: address(0),
            amount: 2 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.ACTIVE
        });
        (uint256 depositAmountMilestone2,) =
            _computeDepositAndFeeAmount(client, 2 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        _deposits[2] = IEscrowMilestone.Deposit({
            contractor: address(0),
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
        escrow.deposit(0, address(paymentToken), _deposits);
        uint256 currentContractId = escrow.getCurrentContractId();
        (
            address _contractor,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            bytes32 _contractorData,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractMilestones(currentContractId, 0);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 0); //Enums.Enums.FeeConfig.CLIENT_COVERS_ALL
        assertEq(uint256(_status), 0); //Status.ACTIVE
        (address _paymentToken, uint256 _depositAmount, Enums.Winner _winner) =
            escrow.milestoneData(currentContractId, 0);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_depositAmount, _amount);
        assertEq(uint256(_winner), 0); //Status.NONE

        (_contractor, _amount, _amountToClaim, _amountToWithdraw,, _feeConfig, _status) =
            escrow.contractMilestones(currentContractId, 1);
        assertEq(_contractor, address(0));
        assertEq(_amount, 2 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 0); //Status.ACTIVE
        (_paymentToken, _depositAmount, _winner) = escrow.milestoneData(currentContractId, 1);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_depositAmount, _amount);
        assertEq(uint256(_winner), 0); //Status.NONE

        (, _amount, _amountToClaim, _amountToWithdraw,, _feeConfig, _status) =
            escrow.contractMilestones(currentContractId, 2);
        assertEq(_amount, 3 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 0); //Status.ACTIVE
        (_paymentToken, _depositAmount, _winner) = escrow.milestoneData(currentContractId, 2);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_depositAmount, _amount);
        assertEq(uint256(_winner), 0); //Status.NONE

        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(escrow.getMilestoneCount(currentContractId), 3);
        vm.stopPrank();
    }

    function test_deposit_withContractorAddress() public {
        test_initialize();
        IEscrowMilestone.Deposit[] memory _deposits = new IEscrowMilestone.Deposit[](1);
        _deposits[0] = IEscrowMilestone.Deposit({
            contractor: contractor,
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
        escrow.deposit(0, address(paymentToken), _deposits);
        uint256 currentContractId = escrow.getCurrentContractId();
        (
            address _contractor,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            bytes32 _contractorData,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractMilestones(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 0); //Status.ACTIVE
        assertEq(paymentToken.balanceOf(address(escrow)), depositAmountMilestone1);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (address _paymentToken, uint256 _depositAmount, Enums.Winner _winner) =
            escrow.milestoneData(currentContractId, 0);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_depositAmount, _amount);
        assertEq(uint256(_winner), 0); //Status.NONE
        vm.stopPrank();
    }

    ///////////////////////////////////////////
    //             submit tests              //
    ///////////////////////////////////////////

    function test_submit() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor, uint256 _amount,,, bytes32 _contractorData,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, 0);
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
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_contractorData, contractorDataHash);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    function test_submit_withContractorAddress() public {
        test_deposit_withContractorAddress();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor, uint256 _amount,,, bytes32 _contractorData,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, 0);
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
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_contractorData, contractorDataHash);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    function test_submit_reverts_InvalidStatusForSubmit() public {
        test_submit_withContractorAddress();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,,,, bytes32 _contractorData,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);
        vm.startPrank(contractor);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusForSubmit.selector);
        escrow.submit(currentContractId, 0, contractData, salt);
        (_contractor,,,,,, _status) = escrow.contractMilestones(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    function test_submit_reverts_InvalidContractorDataHash() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor, uint256 _amount,,, bytes32 _contractorData,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, 0);
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
        (_contractor,,,,,, _status) = escrow.contractMilestones(currentContractId, 0);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 0); //Status.ACTIVE

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(43)));
        contractorDataHash = escrow.getContractorDataHash(contractData, salt);
        vm.startPrank(contractor);
        vm.expectRevert(IEscrow.Escrow__InvalidContractorDataHash.selector);
        escrow.submit(currentContractId, 0, contractData, salt);
        (_contractor,,,,,, _status) = escrow.contractMilestones(currentContractId, 0);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_submit_reverts_UnauthorizedAccount() public {
        test_deposit_withContractorAddress();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,,,, bytes32 _contractorData,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_status), 0); //Status.ACTIVE

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);
        vm.prank(address(this));
        vm.expectRevert(); //IEscrow.Escrow__UnauthorizedAccount.selector
        escrow.submit(currentContractId, 0, contractData, salt);
        (_contractor,,,,,, _status) = escrow.contractMilestones(currentContractId, 0);
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
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        milestoneId--;
        (address _contractor, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        uint256 amountApprove = 1 ether;
        vm.startPrank(client);
        vm.expectEmit(true, true, true, true);
        emit Approved(currentContractId, milestoneId, amountApprove, contractor);
        escrow.approve(currentContractId, milestoneId, amountApprove, contractor);
        (_contractor, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove);
        assertEq(uint256(_status), 2); //Status.APPROVED
        vm.stopPrank();
    }

    function test_approve_by_admin() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        milestoneId--;
        (address _contractor, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        uint256 amountApprove = 1 ether;
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit Approved(currentContractId, milestoneId, amountApprove, contractor);
        escrow.approve(currentContractId, milestoneId, amountApprove, contractor);
        (_contractor, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove);
        assertEq(uint256(_status), 2); //Status.APPROVED
        vm.stopPrank();
    }

    function test_approve_by_new_admin() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        milestoneId--;
        (address _contractor, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        address newAdmin = makeAddr("newAdmin");
        vm.prank(owner);
        adminManager.addAdmin(newAdmin);

        uint256 amountApprove = 1 ether;
        vm.startPrank(newAdmin);
        vm.expectEmit(true, true, true, true);
        emit Approved(currentContractId, milestoneId, amountApprove, contractor);
        escrow.approve(currentContractId, milestoneId, amountApprove, contractor);
        (_contractor, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove);
        assertEq(uint256(_status), 2); //Status.APPROVED
        vm.stopPrank();
    }

    function test_approve_reverts_UnauthorizedAccount() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        milestoneId--;
        (address _contractor, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        uint256 amountApprove = 1 ether;
        vm.startPrank(address(this));
        vm.expectRevert(); //IEscrow.Escrow__UnauthorizedAccount.selector
        escrow.approve(currentContractId, milestoneId, amountApprove, contractor);
        (_contractor, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        vm.stopPrank();
    }

    function test_approve_reverts_InvalidStatusForApprove() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 0); //Status.ACTIVE

        uint256 amountApprove = 1 ether;
        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusForApprove.selector);
        escrow.approve(currentContractId, milestoneId, amountApprove, contractor);
        (_contractor, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.stopPrank();
    }

    function test_approve_reverts_UnauthorizedReceiver() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        uint256 amountApprove = 1 ether;
        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__UnauthorizedReceiver.selector);
        escrow.approve(currentContractId, milestoneId, amountApprove, address(0));
        (_contractor, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        vm.expectRevert(IEscrow.Escrow__UnauthorizedReceiver.selector);
        escrow.approve(currentContractId, milestoneId, amountApprove, address(this));
        (_contractor, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        vm.stopPrank();
    }

    function test_approve_reverts_InvalidAmount() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        uint256 amountApprove = 0 ether;
        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidAmount.selector);
        escrow.approve(currentContractId, milestoneId, amountApprove, address(0));
        (_contractor, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    function test_approve_reverts_NotEnoughDeposit() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        uint256 amountApprove = 1.1 ether;
        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__NotEnoughDeposit.selector);
        escrow.approve(currentContractId, milestoneId, amountApprove, contractor);
        (_contractor, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
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
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
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
        emit Refilled(currentContractId, milestoneId, amountAdditional);
        escrow.refill(currentContractId, milestoneId, amountAdditional);
        vm.stopPrank();
        (_contractor, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 2 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + totalDepositAmount); //2.06 ether
    }

    function test_refill_reverts() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (, uint256 _amount,,,,, Enums.Status _status) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE

        uint256 amountAdditional = 1 ether;
        vm.startPrank(address(this));
        paymentToken.mint(address(client), amountAdditional);
        paymentToken.approve(address(escrow), amountAdditional);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender);
        escrow.refill(currentContractId, milestoneId, amountAdditional);
        vm.stopPrank();

        amountAdditional = 0 ether;
        vm.startPrank(client);
        paymentToken.mint(address(client), amountAdditional);
        paymentToken.approve(address(escrow), amountAdditional);
        vm.expectRevert(IEscrow.Escrow__InvalidAmount.selector);
        escrow.refill(currentContractId, milestoneId, amountAdditional);
        vm.stopPrank();

        (, _amount,,,,,) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_amount, 1 ether);

        vm.prank(owner);
        registry.addToBlacklist(client);
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__BlacklistedAccount.selector);
        escrow.refill(currentContractId, milestoneId, amountAdditional);
        vm.prank(owner);
        registry.removeFromBlacklist(client);
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidAmount.selector);
        escrow.refill(currentContractId, milestoneId, amountAdditional);
    }

    ////////////////////////////////////////////
    //              claim tests               //
    ////////////////////////////////////////////

    function test_claim_clientCoversOnly() public {
        test_approve();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (
            address _contractor,
            uint256 _amount,
            uint256 _amountToClaim,
            ,
            ,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractMilestones(currentContractId, --milestoneId);
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
        emit Claimed(currentContractId, milestoneId, claimAmount);
        escrow.claim(currentContractId, milestoneId);

        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), feeAmount + clientFee);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 3); //Status.COMPLETED
        vm.stopPrank();
    }

    function test_claim_reverts() public {
        uint256 amountApprove = 0 ether;
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove); //0
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusToClaim.selector);
        // vm.expectRevert(IEscrow.Escrow__NotApproved.selector); //TODO test
        escrow.claim(currentContractId, milestoneId);
        vm.prank(address(this));
        vm.expectRevert(); //IEscrow.Escrow__UnauthorizedAccount.selector
        escrow.claim(currentContractId, milestoneId);
        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove); //0
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        vm.prank(owner);
        registry.addToBlacklist(contractor);
        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__BlacklistedAccount.selector);
        escrow.claim(currentContractId, milestoneId);
    }

    function test_claim_whenResolveDispute_winnerSplit() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (
            address _contractor,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            ,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        vm.prank(client);
        escrow.requestReturn(currentContractId, milestoneId);
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED

        vm.prank(contractor);
        escrow.createDispute(currentContractId, milestoneId);
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED

        vm.prank(owner);
        escrow.resolveDispute(currentContractId, milestoneId, Enums.Winner.SPLIT, _amount / 2, _amount / 2);
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
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
        escrow.withdraw(currentContractId, milestoneId);
        (, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
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
        escrow.claim(currentContractId, milestoneId);
        (, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
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
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        assertEq(escrow.getMilestoneCount(currentContractId), 3);
        uint256 milestoneId1 = milestoneId - 1;

        (address _contractor, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, milestoneId1);
        assertEq(_contractor, address(0));
        assertEq(_amount, 3 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE

        uint256 milestoneId2 = milestoneId - 2;
        (_contractor, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId2);
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
        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId2);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 3); //Status.COMPLETED

        // check milestoneId1 is not changed
        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId1);
        assertEq(_amount, 3 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE

        // check updated balances
        assertEq(paymentToken.balanceOf(address(escrow)), 6.23 ether - claimAmount - (feeAmount + clientFee));
        assertEq(paymentToken.balanceOf(address(treasury)), feeAmount + clientFee);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);
    }

    function test_claimAll() public {
        test_deposit_severalMilestones();
        assertEq(paymentToken.balanceOf(address(escrow)), 6.23 ether);

        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(escrow.getMilestoneCount(currentContractId), 3);

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);

        vm.startPrank(contractor);
        escrow.submit(currentContractId, 0, contractData, salt);
        escrow.submit(currentContractId, 1, contractData, salt);
        escrow.submit(currentContractId, 2, contractData, salt);
        vm.stopPrank();

        vm.startPrank(client);
        escrow.approve(currentContractId, 0, 1 ether, contractor);
        escrow.approve(currentContractId, 1, 2 ether, contractor);
        escrow.approve(currentContractId, 2, 3 ether, contractor);
        vm.stopPrank();

        uint256 totalClaimAmount;
        uint256 totalFeeAmount;
        uint256 totalClientFee;

        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
            _computeClaimableAndFeeAmount(contractor, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);

        totalClaimAmount += claimAmount;
        totalFeeAmount += feeAmount;
        totalClientFee += clientFee;

        (claimAmount, feeAmount, clientFee) =
            _computeClaimableAndFeeAmount(contractor, 2 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);

        totalClaimAmount += claimAmount;
        totalFeeAmount += feeAmount;
        totalClientFee += clientFee;

        (claimAmount, feeAmount, clientFee) =
            _computeClaimableAndFeeAmount(contractor, 3 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);

        totalClaimAmount += claimAmount;
        totalFeeAmount += feeAmount;
        totalClientFee += clientFee;

        vm.prank(contractor);
        escrow.claimAll(currentContractId);

        (, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, 0);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 3); //Status.COMPLETED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, 1);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 3); //Status.COMPLETED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, 2);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 3); //Status.COMPLETED

        assertEq(
            paymentToken.balanceOf(address(escrow)), 6.23 ether - totalClaimAmount - (totalFeeAmount + totalClientFee)
        );
        assertEq(paymentToken.balanceOf(address(treasury)), totalFeeAmount + totalClientFee);
        assertEq(paymentToken.balanceOf(address(contractor)), totalClaimAmount);
    }

    function test_claimAll_oneOfthree() public {
        test_deposit_severalMilestones();
        assertEq(paymentToken.balanceOf(address(escrow)), 6.23 ether);
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(escrow.getMilestoneCount(currentContractId), 3);

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);

        vm.startPrank(contractor);
        escrow.submit(currentContractId, 0, contractData, salt);
        escrow.submit(currentContractId, 1, contractData, salt);
        escrow.submit(currentContractId, 2, contractData, salt);
        vm.stopPrank();

        vm.startPrank(client);
        // escrow.approve(currentContractId, 0, 1 ether, contractor);
        escrow.approve(currentContractId, 1, 2 ether, contractor);
        // escrow.approve(currentContractId, 2, 3 ether, contractor);
        vm.stopPrank();

        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
            _computeClaimableAndFeeAmount(contractor, 2 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);

        vm.prank(contractor);
        escrow.claimAll(currentContractId);

        (, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, 0);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, 1);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 3); //Status.COMPLETED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, 2);
        assertEq(_amount, 3 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        assertEq(paymentToken.balanceOf(address(escrow)), 6.23 ether - claimAmount - (feeAmount + clientFee));
        assertEq(paymentToken.balanceOf(address(treasury)), feeAmount + clientFee);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);
    }

    function test_claimAll_twoOfthree() public {
        test_deposit_severalMilestones();
        assertEq(paymentToken.balanceOf(address(escrow)), 6.23 ether);
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(escrow.getMilestoneCount(currentContractId), 3);

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);

        vm.startPrank(contractor);
        escrow.submit(currentContractId, 0, contractData, salt);
        escrow.submit(currentContractId, 1, contractData, salt);
        escrow.submit(currentContractId, 2, contractData, salt);
        vm.stopPrank();

        vm.startPrank(client);
        escrow.approve(currentContractId, 0, 1 ether, contractor);
        // escrow.approve(currentContractId, 1, 2 ether, contractor);
        escrow.approve(currentContractId, 2, 3 ether, contractor);
        vm.stopPrank();

        uint256 totalClaimAmount;
        uint256 totalFeeAmount;
        uint256 totalClientFee;

        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
            _computeClaimableAndFeeAmount(contractor, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);

        totalClaimAmount += claimAmount;
        totalFeeAmount += feeAmount;
        totalClientFee += clientFee;

        (claimAmount, feeAmount, clientFee) =
            _computeClaimableAndFeeAmount(contractor, 3 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);

        totalClaimAmount += claimAmount;
        totalFeeAmount += feeAmount;
        totalClientFee += clientFee;

        vm.prank(contractor);
        escrow.claimAll(currentContractId);

        (, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, 0);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 3); //Status.COMPLETED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, 1);
        assertEq(_amount, 2 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, 2);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 3); //Status.COMPLETED

        assertEq(
            paymentToken.balanceOf(address(escrow)), 6.23 ether - totalClaimAmount - (totalFeeAmount + totalClientFee)
        );
        assertEq(paymentToken.balanceOf(address(treasury)), totalFeeAmount + totalClientFee);
        assertEq(paymentToken.balanceOf(address(contractor)), totalClaimAmount);
    }

    function test_claimAll_invalidContractor() public {
        test_deposit_severalMilestones();
        assertEq(paymentToken.balanceOf(address(escrow)), 6.23 ether);
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(escrow.getMilestoneCount(currentContractId), 3);

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);

        vm.startPrank(contractor);
        escrow.submit(currentContractId, 0, contractData, salt);
        escrow.submit(currentContractId, 1, contractData, salt);
        escrow.submit(currentContractId, 2, contractData, salt);
        vm.stopPrank();

        vm.startPrank(client);
        escrow.approve(currentContractId, 0, 1 ether, contractor);
        escrow.approve(currentContractId, 1, 2 ether, contractor);
        escrow.approve(currentContractId, 2, 3 ether, contractor);
        vm.stopPrank();

        address invalidContractor = makeAddr("invalidContractor");

        vm.prank(invalidContractor);
        escrow.claimAll(currentContractId);

        (, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, 0);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, 1);
        assertEq(_amount, 2 ether);
        assertEq(_amountToClaim, 2 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, 2);
        assertEq(_amount, 3 ether);
        assertEq(_amountToClaim, 3 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED

        assertEq(paymentToken.balanceOf(address(escrow)), 6.23 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0);
        assertEq(paymentToken.balanceOf(address(contractor)), 0);
        assertEq(paymentToken.balanceOf(address(invalidContractor)), 0);
    }

    function test_claimAll_whenResolvedAndCanceled_afterWithdraw() public {
        test_deposit_severalMilestones();
        assertEq(paymentToken.balanceOf(address(escrow)), 6.23 ether);
        // uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(escrow.getMilestoneCount(1), 3);

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);

        vm.startPrank(contractor);
        escrow.submit(1, 0, contractData, salt);
        escrow.submit(1, 1, contractData, salt);
        escrow.submit(1, 2, contractData, salt);
        vm.stopPrank();

        vm.startPrank(client);
        escrow.createDispute(1, 0);
        escrow.createDispute(1, 1);
        vm.stopPrank();

        vm.startPrank(owner);
        escrow.resolveDispute(1, 0, Enums.Winner.SPLIT, 0.5 ether, 0.5 ether);
        escrow.resolveDispute(1, 1, Enums.Winner.SPLIT, 1 ether, 1 ether);
        vm.stopPrank();

        (uint256 withdrawableAmount, uint256 clientFeeAmount) =
            _computeDepositAndFeeAmount(client, 0.5 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);

        (uint256 initialDepositAmount, uint256 initialFeeAmount) =
            _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);
        uint256 platformFee = initialFeeAmount - clientFeeAmount;

        vm.startPrank(client);
        escrow.withdraw(1, 0);

        (, uint256 _amount, uint256 _amountToClaim, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.contractMilestones(1, 0);
        assertEq(_amount, 0.5 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 8); //Status.CANCELED

        assertEq(paymentToken.balanceOf(address(escrow)), 6.23 ether - withdrawableAmount - platformFee);
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee);
        assertEq(paymentToken.balanceOf(address(client)), withdrawableAmount);

        escrow.approve(1, 2, 3 ether, contractor);
        vm.stopPrank();

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(1, 1);
        assertEq(_amount, 2 ether);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_status), 6); //Status.RESOLVED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(1, 2);
        assertEq(_amount, 3 ether);
        assertEq(_amountToClaim, 3 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED

        vm.prank(client);
        escrow.withdraw(1, 1);

        vm.prank(contractor);
        escrow.claimAll(1);

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(1, 0);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 3); //Status.COMPLETED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(1, 1);
        assertEq(_amount, 0 ether); // withdrawn & claimed
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 3); //Status.COMPLETED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(1, 2);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 3); //Status.COMPLETED

        //
        uint256 totalClaimAmount;
        uint256 totalFeeAmount;
        uint256 totalClientFee;

        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
            _computeClaimableAndFeeAmount(contractor, 0.5 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);

        totalClaimAmount += claimAmount;
        totalFeeAmount += feeAmount;
        totalClientFee += clientFee;

        (claimAmount, feeAmount, clientFee) =
            _computeClaimableAndFeeAmount(contractor, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);

        totalClaimAmount += claimAmount;
        totalFeeAmount += feeAmount;
        // totalClientFee += clientFee;

        (claimAmount, feeAmount, clientFee) =
            _computeClaimableAndFeeAmount(contractor, 3 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);

        totalClaimAmount += claimAmount;
        totalFeeAmount += feeAmount;
        totalClientFee += clientFee;

        assertEq(paymentToken.balanceOf(address(escrow)), 0);
        assertEq(paymentToken.balanceOf(address(contractor)), totalClaimAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0.54 ether + 1.03 ether); //amountToWithdrawSplit+fee
    }

    function test_claimAll_whenResolvedAndCanceled_beforeWithdraw() public {
        test_deposit_severalMilestones();
        assertEq(paymentToken.balanceOf(address(escrow)), 6.23 ether);
        // uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(escrow.getMilestoneCount(1), 3);

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);

        vm.startPrank(contractor);
        escrow.submit(1, 0, contractData, salt);
        escrow.submit(1, 1, contractData, salt);
        escrow.submit(1, 2, contractData, salt);
        vm.stopPrank();

        vm.startPrank(client);
        escrow.createDispute(1, 0);
        escrow.createDispute(1, 1);
        vm.stopPrank();

        vm.startPrank(owner);
        escrow.resolveDispute(1, 0, Enums.Winner.SPLIT, 0.5 ether, 0.5 ether);
        escrow.resolveDispute(1, 1, Enums.Winner.SPLIT, 1 ether, 1 ether);
        vm.stopPrank();

        (uint256 withdrawableAmount, uint256 clientFeeAmount) =
            _computeDepositAndFeeAmount(client, 0.5 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);

        (uint256 initialDepositAmount, uint256 initialFeeAmount) =
            _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);
        uint256 platformFee = initialFeeAmount - clientFeeAmount;

        vm.startPrank(client);
        escrow.withdraw(1, 0);

        (, uint256 _amount, uint256 _amountToClaim, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.contractMilestones(1, 0);
        assertEq(_amount, 0.5 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 8); //Status.CANCELED

        assertEq(paymentToken.balanceOf(address(escrow)), 6.23 ether - withdrawableAmount - platformFee);
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee);
        assertEq(paymentToken.balanceOf(address(client)), withdrawableAmount);

        escrow.approve(1, 2, 3 ether, contractor);
        vm.stopPrank();

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(1, 1);
        assertEq(_amount, 2 ether);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_status), 6); //Status.RESOLVED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(1, 2);
        assertEq(_amount, 3 ether);
        assertEq(_amountToClaim, 3 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED

        vm.prank(contractor);
        escrow.claimAll(1);

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(1, 0);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 3); //Status.COMPLETED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(1, 1);
        // assertEq(_amount, 1 ether); //Claimed own split, not withdrawn yet
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 6); //Status.RESOLVED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(1, 2);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 3); //Status.COMPLETED

        //
        uint256 totalClaimAmount;
        uint256 totalFeeAmount;
        uint256 totalClientFee;

        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
            _computeClaimableAndFeeAmount(contractor, 0.5 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);

        totalClaimAmount += claimAmount;
        totalFeeAmount += feeAmount;
        // totalClientFee += clientFee; //because CANCELED

        (claimAmount, feeAmount, clientFee) =
            _computeClaimableAndFeeAmount(contractor, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);

        totalClaimAmount += claimAmount;
        totalFeeAmount += feeAmount;
        // totalClientFee += clientFee; // because RESOLVED

        (claimAmount, feeAmount, clientFee) =
            _computeClaimableAndFeeAmount(contractor, 3 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);

        totalClaimAmount += claimAmount;
        totalFeeAmount += feeAmount;
        totalClientFee += clientFee;

        assertEq(
            paymentToken.balanceOf(address(escrow)),
            6.23 ether - (0.54 ether + 0.04 ether) - totalClaimAmount - (totalFeeAmount + totalClientFee)
        );
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee + totalFeeAmount + totalClientFee);
        assertEq(paymentToken.balanceOf(address(contractor)), totalClaimAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0.54 ether); //withdrawableAmount

        vm.prank(client);
        escrow.withdraw(1, 1);

        (, feeAmount) = _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);

        assertEq(paymentToken.balanceOf(address(escrow)), 0);
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee + totalFeeAmount + totalClientFee + feeAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0.54 ether + 1.03 ether); //amountToWithdrawSplit+fee
    }

    function test_claimAll_reverts_BlacklistedAccount() public {
        test_deposit_severalMilestones();
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(escrow.getMilestoneCount(currentContractId), 3);
        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);

        vm.startPrank(contractor);
        escrow.submit(currentContractId, 0, contractData, salt);
        escrow.submit(currentContractId, 1, contractData, salt);
        escrow.submit(currentContractId, 2, contractData, salt);
        vm.stopPrank();

        vm.startPrank(client);
        escrow.approve(currentContractId, 0, 1 ether, contractor);
        escrow.approve(currentContractId, 1, 2 ether, contractor);
        escrow.approve(currentContractId, 2, 3 ether, contractor);
        vm.stopPrank();

        vm.prank(owner);
        registry.addToBlacklist(contractor);
        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__BlacklistedAccount.selector);
        escrow.claimAll(currentContractId);
    }

    ///////////////////////////////////////////
    //           withdraw tests              //
    ///////////////////////////////////////////

    function test_withdraw_whenRefundApprovedByOwner() public {
        test_approveReturn_by_owner();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
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
        emit Withdrawn(currentContractId, milestoneId, _amountToWithdraw + feeAmount);
        escrow.withdraw(currentContractId, milestoneId);
        (, uint256 _amountAfter, uint256 _amountToWithdrawAfter,,,, Enums.Status _statusAfter) =
            escrow.contractMilestones(currentContractId, milestoneId);
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
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
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
        emit Withdrawn(currentContractId, milestoneId, totalDepositAmount);
        escrow.withdraw(currentContractId, milestoneId);
        (, uint256 _amountAfter, uint256 _amountToWithdrawAfter,,,, Enums.Status _statusAfter) =
            escrow.contractMilestones(currentContractId, milestoneId);
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
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
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
        emit Withdrawn(currentContractId, milestoneId, totalDepositAmount);
        escrow.withdraw(currentContractId, milestoneId);
        (, uint256 _amountAfter, uint256 _amountToWithdrawAfter,,,, Enums.Status _statusAfter) =
            escrow.contractMilestones(currentContractId, milestoneId);
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
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            ,
            ,
            Enums.Status _status
        ) = escrow.contractMilestones(currentContractId, 0);
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
        (, uint256 _amountAfter,, uint256 _amountToWithdrawAfter,,, Enums.Status _statusAfter) =
            escrow.contractMilestones(currentContractId, 0);
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
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        address notClient = makeAddr("notClient");
        vm.prank(notClient);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.withdraw(currentContractId, --milestoneId);
    }

    function test_withdraw_reverts_InvalidStatusForWithdraw() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusToWithdraw.selector);
        escrow.withdraw(currentContractId, --milestoneId);
    }

    function test_withdraw_reverts_NoFundsAvailableForWithdraw() public {
        test_requestReturn_whenActive();
        assertEq(paymentToken.balanceOf(address(client)), 0);
        uint256 currentContractId = escrow.getCurrentContractId();
        (,,,,,, Enums.Status _status) = escrow.contractMilestones(currentContractId, 0);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(client);
        escrow.createDispute(currentContractId, 0);
        (,,,,,, _status) = escrow.contractMilestones(currentContractId, 0);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        vm.prank(owner);
        escrow.resolveDispute(currentContractId, 0, Enums.Winner.SPLIT, 0, 0.5 ether);
        (,,,,,, _status) = escrow.contractMilestones(currentContractId, 0);
        assertEq(uint256(_status), 6); //Status.RESOLVED
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__NoFundsAvailableForWithdraw.selector);
        escrow.withdraw(currentContractId, 0);
        (,,,,,, _status) = escrow.contractMilestones(currentContractId, 0);
        assertEq(uint256(_status), 6); //Status.RESOLVED
        assertEq(paymentToken.balanceOf(address(client)), 0);
    }

    function test_withdraw_reverts_BlacklistedAccount() public {
        test_resolveDispute_winnerClient();
        uint256 currentContractId = escrow.getCurrentContractId();
        vm.prank(owner);
        registry.addToBlacklist(client);
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__BlacklistedAccount.selector);
        escrow.withdraw(currentContractId, 0);
    }

    ////////////////////////////////////////////
    //          return request tests          //
    ////////////////////////////////////////////

    function test_requestReturn_whenActive() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnRequested(currentContractId, milestoneId);
        escrow.requestReturn(currentContractId, milestoneId);
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_whenSubmitted() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnRequested(currentContractId, milestoneId);
        escrow.requestReturn(currentContractId, milestoneId);
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_whenApproved() public {
        test_approve();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnRequested(currentContractId, milestoneId);
        escrow.requestReturn(currentContractId, milestoneId);
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_whenCompleted() public {
        test_claim_clientCoversOnly();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 0 ether);
        assertEq(uint256(_status), 3); //Status.COMPLETED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnRequested(currentContractId, milestoneId);
        escrow.requestReturn(currentContractId, milestoneId);
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 0 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_reverts_UnauthorizedAccount() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.prank(contractor);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender);
        escrow.requestReturn(currentContractId, milestoneId);
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_requestReturn_reverts_ReturnNotAllowed() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__ReturnNotAllowed.selector);
        escrow.requestReturn(currentContractId, milestoneId);
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_reverts_submitted_UnauthorizedAccount() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        vm.prank(address(this));
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender);
        escrow.requestReturn(currentContractId, milestoneId);
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    function test_approveReturn_by_owner() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit ReturnApproved(currentContractId, milestoneId, owner);
        escrow.approveReturn(currentContractId, milestoneId);
        (_contractor, _amount,, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 1 ether);
        assertEq(uint256(_status), 7); //Status.REFUND_APPROVED
    }

    function test_approveReturn_by_contractor() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(contractor);
        vm.expectEmit(true, true, true, true);
        emit ReturnApproved(currentContractId, milestoneId, contractor);
        escrow.approveReturn(currentContractId, milestoneId);
        (_contractor, _amount,, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 1 ether);
        assertEq(uint256(_status), 7); //Status.REFUND_APPROVED
    }

    function test_approveReturn_reverts_UnauthorizedToApproveReturn() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__UnauthorizedToApproveReturn.selector);
        escrow.approveReturn(currentContractId, milestoneId);
        (_contractor, _amount,, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 4); //Status.REFUND_APPROVED
    }

    function test_approveReturn_reverts_NoReturnRequested() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor,,,,,, Enums.Status _status) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__NoReturnRequested.selector);
        escrow.approveReturn(currentContractId, milestoneId);
        (_contractor,,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_approveReturn_reverts_submitted_NoReturnRequested() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor,,,,,, Enums.Status _status) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__NoReturnRequested.selector);
        escrow.approveReturn(currentContractId, milestoneId);
        (_contractor,,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    function test_cancelReturn() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (,,,,,, Enums.Status _status) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        Enums.Status status = Enums.Status.ACTIVE;
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnCanceled(currentContractId, milestoneId);
        escrow.cancelReturn(currentContractId, milestoneId, status);
        (,,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_cancelReturn_submitted() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor,,,,,, Enums.Status _status) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        Enums.Status status = Enums.Status.SUBMITTED;
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnCanceled(currentContractId, milestoneId);
        escrow.cancelReturn(currentContractId, milestoneId, status);
        (_contractor,,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    function test_cancelReturn_reverts() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (,,,,,, Enums.Status _status) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        Enums.Status status = Enums.Status.ACTIVE;
        vm.prank(owner);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.cancelReturn(currentContractId, milestoneId, status);
        (,,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        status = Enums.Status.CANCELED;
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusProvided.selector);
        escrow.cancelReturn(currentContractId, milestoneId, status);
        (,,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_cancelReturn_reverts_submitted() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        Enums.Status status = Enums.Status.RESOLVED;
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusProvided.selector);
        escrow.cancelReturn(currentContractId, milestoneId, status);
        (,,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_cancelReturn_reverts_submitted_NoReturnRequested() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor,,,,,, Enums.Status _status) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
        Enums.Status status = Enums.Status.ACTIVE;
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__NoReturnRequested.selector);
        escrow.cancelReturn(currentContractId, milestoneId, status);
        (_contractor,,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 1); //Status.SUBMITTED
    }

    ////////////////////////////////////////////
    //              dispute tests             //
    ////////////////////////////////////////////

    function test_createDispute_by_client() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit DisputeCreated(currentContractId, milestoneId, client);
        escrow.createDispute(currentContractId, milestoneId);
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    function test_createDispute_by_contractor() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(contractor);
        vm.expectEmit(true, true, true, true);
        emit DisputeCreated(currentContractId, milestoneId, contractor);
        escrow.createDispute(currentContractId, milestoneId);
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    function test_createDispute_reverts_CreateDisputeNotAllowed() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__CreateDisputeNotAllowed.selector);
        escrow.createDispute(currentContractId, milestoneId);
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_createDispute_reverts_UnauthorizedToApproveDispute() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(address(this));
        vm.expectRevert(IEscrow.Escrow__UnauthorizedToApproveDispute.selector);
        escrow.createDispute(currentContractId, milestoneId);
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_resolveDispute_winnerClient() public {
        test_createDispute_by_client();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (
            address _contractor,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            ,
            ,
            Enums.Status _status
        ) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        Enums.Winner _winner = Enums.Winner.CLIENT;
        uint256 clientAmount = _amount;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(currentContractId, milestoneId, _winner, clientAmount, 0);
        escrow.resolveDispute(currentContractId, milestoneId, _winner, clientAmount, 0);
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, clientAmount);
        assertEq(uint256(_status), 6); //Status.RESOLVED
    }

    function test_resolveDispute_winnerContractor() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (
            address _contractor,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            ,
            ,
            Enums.Status _status
        ) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        Enums.Winner _winner = Enums.Winner.CONTRACTOR;
        uint256 contractorAmount = _amount;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(currentContractId, milestoneId, _winner, 0, contractorAmount);
        escrow.resolveDispute(currentContractId, milestoneId, _winner, 0, contractorAmount);
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, contractorAmount);
        assertEq(_amountToWithdraw, 0);
        assertEq(uint256(_status), 2); //Status.APPROVED
    }

    function test_resolveDispute_winnerSplit() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (
            address _contractor,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            ,
            ,
            Enums.Status _status
        ) = escrow.contractMilestones(currentContractId, --milestoneId);
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
        emit DisputeResolved(currentContractId, milestoneId, _winner, clientAmount, contractorAmount);
        escrow.resolveDispute(currentContractId, milestoneId, _winner, clientAmount, contractorAmount);
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0.5 ether);
        assertEq(_amountToWithdraw, 0.5 ether);
        assertEq(uint256(_status), 6); //Status.RESOLVED
    }

    function test_resolveDispute_winnerSplit_ZeroAllocationToEachParty() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (
            address _contractor,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            ,
            ,
            Enums.Status _status
        ) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        Enums.Winner _winner = Enums.Winner.SPLIT;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(currentContractId, milestoneId, _winner, 0, 0);
        escrow.resolveDispute(currentContractId, milestoneId, _winner, 0, 0);
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 6); //Status.RESOLVED
    }

    function test_resolveDispute_reverts_DisputeNotActiveForThisDeposit() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (,,,,,, Enums.Status _status) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__DisputeNotActiveForThisDeposit.selector);
        escrow.resolveDispute(currentContractId, milestoneId, Enums.Winner.CLIENT, 0, 0);
        (,,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_resolveDispute_reverts_UnauthorizedToApproveDispute() public {
        test_createDispute_by_client();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (,,,,,, Enums.Status _status) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        vm.prank(address(this));
        vm.expectRevert(); //Unauthorized()
        escrow.resolveDispute(currentContractId, milestoneId, Enums.Winner.CONTRACTOR, 0, 0);
        (,,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    function test_resolveDispute_reverts_winnerClient_ResolutionExceedsDepositedAmount() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (
            address _contractor,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            ,
            ,
            Enums.Status _status
        ) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__ResolutionExceedsDepositedAmount.selector);
        escrow.resolveDispute(currentContractId, milestoneId, Enums.Winner.CLIENT, 1.1 ether, 0 ether);
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    function test_resolveDispute_reverts_winnerContractor_ResolutionExceedsDepositedAmount() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (
            address _contractor,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            ,
            ,
            Enums.Status _status
        ) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__ResolutionExceedsDepositedAmount.selector);
        escrow.resolveDispute(currentContractId, milestoneId, Enums.Winner.CONTRACTOR, 0 ether, 1.1 ether);
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    function test_resolveDispute_reverts_winnerSplit_ResolutionExceedsDepositedAmount() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (
            address _contractor,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            ,
            ,
            Enums.Status _status
        ) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__ResolutionExceedsDepositedAmount.selector);
        escrow.resolveDispute(currentContractId, milestoneId, Enums.Winner.SPLIT, 1 ether, 1 wei);
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    function test_resolveDispute_reverts_InvalidWinnerSpecified() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (
            address _contractor,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            ,
            ,
            Enums.Status _status
        ) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        vm.prank(owner);
        // vm.expectRevert(IEscrow.Escrow__InvalidWinnerSpecified.selector);
        vm.expectRevert(); // panic: failed to convert value into enum type (0x21)
        escrow.resolveDispute(currentContractId, milestoneId, Enums.Winner(uint256(4)), _amount, 0); // Invalid enum value for Winner
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }
}
