// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";

import {EscrowHourly, IEscrowHourly} from "src/EscrowHourly.sol";
import {EscrowAdminManager, OwnedRoles} from "src/modules/EscrowAdminManager.sol";
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
    IEscrowHourly.ContractDetails contractDetails;

    struct ContractDetails {
        address paymentToken;
        uint256 prepaymentAmount;
        Enums.Status status;
    }

    struct Deposit {
        address contractor;
        uint256 amountToClaim;
        uint256 amountToWithdraw;
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
    event RegistryUpdated(address registry);
    event AdminManagerUpdated(address adminManager);
    event ReturnRequested(uint256 contractId, uint256 weekId);
    event ReturnApproved(uint256 contractId, uint256 weekId, address sender);
    event ReturnCanceled(uint256 contractId, uint256 weekId);
    event DisputeCreated(uint256 contractId, uint256 weekId, address sender);
    event DisputeResolved(
        uint256 contractId, uint256 weekId, Enums.Winner winner, uint256 clientAmount, uint256 contractorAmount
    );
    event BulkClaimed(
        address indexed contractor,
        uint256 contractId,
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

        contractDetails = IEscrowHourly.ContractDetails({
            paymentToken: address(paymentToken),
            prepaymentAmount: 1 ether,
            status: Enums.Status.ACTIVE
        });

        deposit = IEscrowHourly.Deposit({
            contractor: contractor,
            amountToClaim: 0,
            amountToWithdraw: 0,
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
        IEscrowFeeManager _feeManager = IEscrowFeeManager(feeManagerAddress);
        (totalDepositAmount, feeApplied) = _feeManager.computeDepositAmountAndFee(_client, _depositAmount, _feeConfig);

        return (totalDepositAmount, feeApplied);
    }

    function _computeClaimableAndFeeAmount(address _contractor, uint256 _claimAmount, Enums.FeeConfig _feeConfig)
        internal
        view
        returns (uint256 claimAmount, uint256 feeAmount, uint256 clientFee)
    {
        address feeManagerAddress = registry.feeManager();
        IEscrowFeeManager _feeManager = IEscrowFeeManager(feeManagerAddress);
        (claimAmount, feeAmount, clientFee) =
            _feeManager.computeClaimableAmountAndFee(_contractor, _claimAmount, _feeConfig);

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
        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
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
        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, 1);
        assertEq(_contractor, contractor);
        assertEq(_amountToWithdraw, 0 ether);
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
            amountToClaim: 0,
            amountToWithdraw: 0,
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
            amountToClaim: 0,
            amountToWithdraw: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY
        });
        vm.expectRevert(IEscrowHourly.Escrow__InvalidContractId.selector);
        escrow.deposit(1, address(paymentToken), 1 ether, deposit);
        vm.stopPrank();

        vm.prank(owner);
        registry.addToBlacklist(client);
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__BlacklistedAccount.selector);
        escrow.deposit(0, address(paymentToken), 1 ether, deposit);
    }

    function test_deposit_amountToClaim() public {
        test_initialize();
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 0);
        deposit = IEscrowHourly.Deposit({
            contractor: contractor,
            amountToClaim: 1 ether,
            amountToWithdraw: 0,
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
        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY

        (uint256 totalDepositAmount,) =
            _computeDepositAndFeeAmount(client, _amountToClaim, Enums.FeeConfig.CLIENT_COVERS_ONLY);
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
        (address _contractor, uint256 _amountToClaim,, Enums.FeeConfig _feeConfig) =
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
        (_contractor, _amountToClaim,,) = escrow.contractWeeks(currentContractId, weekId);
        // assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + totalDepositAmount); //amountApprove+fee
    }

    function test_adminApprove_prepayment_equal_amount_to_approve() public {
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
        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        uint256 amountApprove = 1 ether;
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit Approved(currentContractId, weekId, amountApprove, contractor);
        escrow.adminApprove(currentContractId, weekId, amountApprove, contractor, false);
        (_contractor, _amountToClaim,,) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amountToClaim, amountApprove);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether - amountApprove); //0
        assertEq(uint256(_status), 2); //Status.APPROVED
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //prepaymentAmount+fee
    }

    function test_adminApprove_prepayment_bigger_amount_to_approve() public {
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
        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        uint256 amountApprove = 0.5 ether;
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit Approved(currentContractId, weekId, amountApprove, contractor);
        escrow.adminApprove(currentContractId, weekId, amountApprove, contractor, false);
        (_contractor, _amountToClaim,,) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amountToClaim, amountApprove);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0.5 ether); //_prepaymentAmount - amountApprove
        assertEq(uint256(_status), 2); //Status.APPROVED
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //prepaymentAmount+fee
    }

    function test_adminApprove_prepayment_less_than_amount_to_approve() public {
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
        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        uint256 amountApprove = 1.5 ether;
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit Approved(currentContractId, weekId, amountApprove, contractor);
        escrow.adminApprove(currentContractId, weekId, amountApprove, contractor, false);
        (_contractor, _amountToClaim,,) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amountToClaim, _prepaymentAmount);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0 ether); //0
        assertEq(uint256(_status), 2); //Status.APPROVED
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //prepaymentAmount+fee
    }

    function test_adminApprove_prepayment_bigger_amount_to_approve_initializeNewWeek_zero_weekId() public {
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
        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        uint256 amountApprove = 0.5 ether;
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit Approved(currentContractId, weekId, amountApprove, contractor);
        escrow.adminApprove(currentContractId, weekId, amountApprove, contractor, true);
        (_contractor, _amountToClaim, _amountToWithdraw, _feeConfig) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amountToClaim, amountApprove);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1);
        assertEq(escrow.getWeeksCount(currentContractId), 1);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0.5 ether); //_prepaymentAmount - amountApprove
        assertEq(uint256(_status), 2); //Status.APPROVED
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //prepaymentAmount+fee
    }

    function test_adminApprove_prepayment_bigger_amount_to_approve_initializeNewWeek() public {
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
        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(escrow.getWeeksCount(currentContractId), 1);

        uint256 amountApprove = 0.5 ether;
        weekId = escrow.getWeeksCount(currentContractId);
        vm.startPrank(owner);
        vm.expectRevert(IEscrowHourly.Escrow__InvalidWeekId.selector);
        escrow.adminApprove(currentContractId, weekId, amountApprove, contractor, false);
        vm.expectRevert(IEscrow.Escrow__InvalidAmount.selector);
        escrow.adminApprove(currentContractId, weekId, 0, contractor, true);
        vm.expectEmit(true, true, true, true);
        emit Approved(currentContractId, weekId, amountApprove, contractor);
        escrow.adminApprove(currentContractId, weekId, amountApprove, contractor, true);
        (_contractor, _amountToClaim, _amountToWithdraw, _feeConfig) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amountToClaim, amountApprove);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1);
        assertEq(escrow.getWeeksCount(currentContractId), 2);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0.5 ether); //_prepaymentAmount - amountApprove
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
        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw, Enums.FeeConfig _feeConfig) =
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
        (_contractor, _amountToClaim, _amountToWithdraw,) = escrow.contractWeeks(currentContractId, weekId);
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
        (address _contractor, uint256 _amountToClaim,,) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 1 ether);

        uint256 amountApprove = 1.03 ether;
        vm.startPrank(client);
        paymentToken.mint(address(client), amountApprove);
        paymentToken.approve(address(escrow), amountApprove);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusForApprove.selector);
        escrow.approve(currentContractId, weekId, amountApprove, contractor);
        (, _amountToClaim,,) = escrow.contractWeeks(currentContractId, weekId);
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
        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToWithdraw, 0 ether);
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

        (, _amountToClaim,,) = escrow.contractWeeks(currentContractId, weekId);
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
        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToWithdraw, 0 ether);
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

        (, _amountToClaim,,) = escrow.contractWeeks(currentContractId, weekId);
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
        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw, Enums.FeeConfig _feeConfig) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToWithdraw, 0 ether);
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

        (, _amountToClaim,,) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amountToClaim, 1 ether);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);

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
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED

        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor, uint256 _amountToClaim,, Enums.FeeConfig _feeConfig) =
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
        assertEq(uint256(_status), 2); //Status.APPROVED //3); //Status.COMPLETED

        (, _amountToClaim,,) = escrow.contractWeeks(currentContractId, weekId);
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
        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw, Enums.FeeConfig _feeConfig) =
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
        (_contractor, _amountToClaim, _amountToWithdraw,) = escrow.contractWeeks(currentContractId, weekId);
        // assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED
        vm.stopPrank();

        vm.prank(address(this));
        vm.expectRevert(); //IEscrow.Escrow__UnauthorizedAccount.selector
        escrow.claim(currentContractId, weekId);
        (_contractor, _amountToClaim, _amountToWithdraw,) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_amountToClaim, amountApprove);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED

        vm.prank(owner);
        registry.addToBlacklist(contractor);
        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__BlacklistedAccount.selector);
        escrow.claim(currentContractId, weekId);
    }

    function test_claimAll() public {
        test_approve();
        // uint256 prepaymentAmount = 1.03 ether;
        uint256 amountToMint = 1.03 ether;
        uint256 amountApprove = 1 ether;

        assertEq(paymentToken.balanceOf(address(escrow)), amountToMint + amountToMint); //prepaymentAmount+amountToMint=2.06 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);

        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        assertEq(weekId, 1);

        vm.startPrank(address(client));
        paymentToken.mint(address(client), amountToMint);
        paymentToken.approve(address(escrow), amountToMint);
        escrow.deposit(currentContractId, address(paymentToken), amountApprove, deposit);

        currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        weekId = escrow.getWeeksCount(currentContractId);
        assertEq(weekId, 2);
        vm.stopPrank();

        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusToClaim.selector);
        escrow.claimAll(currentContractId, 1, 1);

        vm.startPrank(address(client));
        paymentToken.mint(address(client), amountToMint);
        paymentToken.approve(address(escrow), amountToMint);
        escrow.approve(currentContractId, 1, amountApprove, contractor);
        (, uint256 _prepaymentAmount, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, amountApprove);
        assertEq(uint256(_status), 2); //Status.APPROVED
        vm.stopPrank();

        assertEq(paymentToken.balanceOf(address(escrow)), amountToMint * 4);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(contractor)), 0 ether);

        (uint256 claimAmount, uint256 feeAmount, uint256 clientFee) =
            _computeClaimableAndFeeAmount(contractor, amountApprove, Enums.FeeConfig.CLIENT_COVERS_ONLY);

        uint256 startWeekId = 0;
        uint256 endWeekId = 1;
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

        assertEq(
            paymentToken.balanceOf(address(escrow)),
            (amountToMint * 4) - claimAmount * 2 - feeAmount * 2 - clientFee * 2
        );
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount * 2);
        assertEq(paymentToken.balanceOf(address(treasury)), feeAmount * 2 + clientFee * 2);
    }

    ///////////////////////////////////////////
    //           withdraw tests              //
    ///////////////////////////////////////////

    function test_withdraw_whenRefundApprovedByOwner() public {
        test_approveReturn_by_owner();
        uint256 currentContractId = escrow.getCurrentContractId();
        // uint256 weekId = escrow.getWeeksCount(currentContractId);
        // weekId--;
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 7); //Status.REFUND_APPROVED
        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw,) =
            escrow.contractWeeks(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 1 ether);

        (uint256 totalDepositAmount, uint256 feeAmount) =
            _computeDepositAndFeeAmount(client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (uint256 initialDepositAmount, uint256 initialFeeAmount) =
            _computeDepositAndFeeAmount(client, _prepaymentAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(currentContractId, 0, _amountToWithdraw + feeAmount);
        escrow.withdraw(currentContractId, 0);

        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_status), 8); //Status.CANCELED

        (, uint256 _amountAfter, uint256 _amountToWithdrawAfter,) = escrow.contractWeeks(currentContractId, 0);
        assertEq(_amountAfter, 0 ether);
        assertEq(_amountToWithdrawAfter, 0 ether);

        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether); //totalDepositAmount - (_amountToWithdraw + feeAmount)
        assertEq(paymentToken.balanceOf(address(client)), _amountToWithdraw + feeAmount); //==totalDepositAmount = _amountToWithdraw + feeAmount
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee);
    }

    function test_withdraw_whenRefundApprovedByContractor() public {
        test_approveReturn_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        // uint256 weekId = escrow.getWeeksCount(currentContractId);
        // weekId--;
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 7); //Status.REFUND_APPROVED
        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw,) =
            escrow.contractWeeks(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 1 ether);

        (uint256 totalDepositAmount, uint256 feeAmount) =
            _computeDepositAndFeeAmount(client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (uint256 initialDepositAmount, uint256 initialFeeAmount) =
            _computeDepositAndFeeAmount(client, _prepaymentAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(currentContractId, 0, _amountToWithdraw + feeAmount);
        escrow.withdraw(currentContractId, 0);

        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_status), 8); //Status.CANCELED

        (, uint256 _amountAfter, uint256 _amountToWithdrawAfter,) = escrow.contractWeeks(currentContractId, 0);
        assertEq(_amountAfter, 0 ether);
        assertEq(_amountToWithdrawAfter, 0 ether);

        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether); //totalDepositAmount - (_amountToWithdraw + feeAmount)
        assertEq(paymentToken.balanceOf(address(client)), totalDepositAmount); //==totalDepositAmount = _amountToWithdraw + feeAmount
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee);
    }

    function test_withdraw_whenDisputeResolved() public {
        test_resolveDispute_winnerClient();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 6); //Status.RESOLVED

        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw,) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, _prepaymentAmount);

        (uint256 totalDepositAmount, uint256 feeAmount) =
            _computeDepositAndFeeAmount(client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (uint256 initialDepositAmount, uint256 initialFeeAmount) =
            _computeDepositAndFeeAmount(client, _prepaymentAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(currentContractId, weekId, totalDepositAmount);
        escrow.withdraw(currentContractId, weekId);

        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0 ether);
        assertEq(uint256(_status), 8); //Status.CANCELED

        (, _amountToClaim, _amountToWithdraw,) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);

        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee);
    }

    function test_withdraw_whenDisputeResolvedSplit() public {
        test_resolveDispute_winnerSplit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 6); //Status.RESOLVED

        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw,) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, _prepaymentAmount / 2);
        assertEq(_amountToWithdraw, _prepaymentAmount / 2);

        (uint256 totalDepositAmount, uint256 feeAmount) =
            _computeDepositAndFeeAmount(client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + feeAmount + _amountToClaim);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (uint256 initialDepositAmount, uint256 initialFeeAmount) =
            _computeDepositAndFeeAmount(client, _prepaymentAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(currentContractId, 0, totalDepositAmount);
        escrow.withdraw(currentContractId, 0);

        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 0.5 ether);
        assertEq(uint256(_status), 8); //Status.CANCELED

        (, _amountToClaim, _amountToWithdraw,) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0.5 ether);
        assertEq(_amountToWithdraw, 0 ether);

        assertEq(paymentToken.balanceOf(address(escrow)), 0.5 ether);
        assertEq(paymentToken.balanceOf(address(client)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee);
    }

    function test_withdraw_reverts_UnauthorizedAccount() public {
        test_deposit_prepayment();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        address notClient = makeAddr("notClient");
        vm.prank(notClient);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.withdraw(currentContractId, --weekId);
    }

    function test_withdraw_reverts_InvalidStatusForWithdraw() public {
        test_deposit_amountToClaim();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusToWithdraw.selector);
        escrow.withdraw(currentContractId, --weekId);
    }

    function test_withdraw_reverts_NoFundsAvailableForWithdraw() public {
        test_requestReturn_whenActive();
        assertEq(paymentToken.balanceOf(address(client)), 0);
        uint256 currentContractId = escrow.getCurrentContractId();
        (,, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(client);
        escrow.createDispute(currentContractId, 0);
        (,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        vm.prank(owner);
        escrow.resolveDispute(currentContractId, 0, Enums.Winner.SPLIT, 0, 0.5 ether);
        (,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 6); //Status.RESOLVED
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__NoFundsAvailableForWithdraw.selector);
        escrow.withdraw(currentContractId, 0);
        (,, _status) = escrow.contractDetails(currentContractId);
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
        test_deposit_prepayment();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnRequested(currentContractId, weekId);
        escrow.requestReturn(currentContractId, weekId);
        (_paymentToken, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_whenApproved() public {
        test_approve();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnRequested(currentContractId, weekId);
        escrow.requestReturn(currentContractId, weekId);
        (_paymentToken, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    // claim::if (C.prepaymentAmount == 0) C.status = Enums.Status.COMPLETED; // TODO TBC conditions to change the Status
    function test_requestReturn_whenCompleted() public {
        test_claim_clientCoversOnly();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnRequested(currentContractId, weekId);
        escrow.requestReturn(currentContractId, weekId);
        (_paymentToken, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_reverts_UnauthorizedAccount() public {
        test_deposit_prepayment();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,,,) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        (, uint256 _prepaymentAmount, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.prank(contractor);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender);
        escrow.requestReturn(currentContractId, weekId);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_requestReturn_reverts_ReturnNotAllowed() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,,,) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        (, uint256 _prepaymentAmount, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__ReturnNotAllowed.selector);
        escrow.requestReturn(currentContractId, weekId);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_approveReturn_by_owner() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        weekId--;
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit ReturnApproved(currentContractId, weekId, owner);
        escrow.approveReturn(currentContractId, weekId);
        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw,) =
            escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 1 ether);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 7); //Status.REFUND_APPROVED
    }

    function test_approveReturn_by_contractor() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        weekId--;
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(contractor);
        vm.expectEmit(true, true, true, true);
        emit ReturnApproved(currentContractId, weekId, contractor);
        escrow.approveReturn(currentContractId, weekId);
        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw,) =
            escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 1 ether);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 7); //Status.REFUND_APPROVED
    }

    function test_approveReturn_reverts_UnauthorizedToApproveReturn() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        weekId--;
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(address(this));
        vm.expectRevert(IEscrow.Escrow__UnauthorizedToApproveReturn.selector);
        escrow.approveReturn(currentContractId, weekId);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_approveReturn_reverts_NoReturnRequested() public {
        test_deposit_prepayment();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _contractor,,,) = escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        (, uint256 _prepaymentAmount, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__NoReturnRequested.selector);
        escrow.approveReturn(currentContractId, weekId);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_cancelReturn() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        weekId--;
        (, uint256 _prepaymentAmount, Enums.Status _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnCanceled(currentContractId, weekId);
        escrow.cancelReturn(currentContractId, weekId, status);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_cancelReturn_reverts() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        weekId--;
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(owner);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.cancelReturn(currentContractId, weekId, status);
        (,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        status = Enums.Status.CANCELED;
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusProvided.selector);
        escrow.cancelReturn(currentContractId, weekId, status);
        (,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    ////////////////////////////////////////////
    //              dispute tests             //
    ////////////////////////////////////////////

    function test_createDispute_by_client() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit DisputeCreated(currentContractId, --weekId, client);
        escrow.createDispute(currentContractId, weekId);
        (_paymentToken, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    function test_createDispute_by_contractor() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(contractor);
        vm.expectEmit(true, true, true, true);
        emit DisputeCreated(currentContractId, --weekId, contractor);
        escrow.createDispute(currentContractId, weekId);
        (address _contractor,,,) = escrow.contractWeeks(currentContractId, 0);
        assertEq(_contractor, contractor);
        (_paymentToken, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    function test_createDispute_reverts_CreateDisputeNotAllowed() public {
        test_deposit_prepayment();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__CreateDisputeNotAllowed.selector);
        escrow.createDispute(currentContractId, 0);
        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_createDispute_reverts_UnauthorizedToApproveDispute() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
        vm.prank(address(this));
        vm.expectRevert(IEscrow.Escrow__UnauthorizedToApproveDispute.selector);
        escrow.createDispute(currentContractId, --weekId);
        (_paymentToken, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 4); //Status.RETURN_REQUESTED
    }

    function test_resolveDispute_winnerClient() public {
        test_createDispute_by_client();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED

        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw,) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);

        Enums.Winner _winner = Enums.Winner.CLIENT;
        uint256 clientAmount = _prepaymentAmount;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(currentContractId, weekId, _winner, clientAmount, 0);
        escrow.resolveDispute(currentContractId, weekId, _winner, clientAmount, 0);
        (_contractor, _amountToClaim, _amountToWithdraw,) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, clientAmount);

        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 6); //Status.RESOLVED
    }

    function test_resolveDispute_winnerContractor() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED

        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw,) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);

        Enums.Winner _winner = Enums.Winner.CONTRACTOR;
        uint256 contractorAmount = _prepaymentAmount;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(currentContractId, weekId, _winner, 0, contractorAmount);
        escrow.resolveDispute(currentContractId, weekId, _winner, 0, contractorAmount);
        (_contractor, _amountToClaim, _amountToWithdraw,) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, _prepaymentAmount);
        assertEq(_amountToWithdraw, 0 ether);

        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 2); //Status.APPROVED
    }

    function test_resolveDispute_winnerSplit() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED

        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw,) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);

        Enums.Winner _winner = Enums.Winner.SPLIT;
        uint256 clientAmount = _prepaymentAmount / 2;
        uint256 contractorAmount = _prepaymentAmount / 2;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(currentContractId, weekId, _winner, clientAmount, contractorAmount);
        escrow.resolveDispute(currentContractId, weekId, _winner, clientAmount, contractorAmount);
        (_contractor, _amountToClaim, _amountToWithdraw,) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, clientAmount);
        assertEq(_amountToWithdraw, contractorAmount);

        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 6); //Status.RESOLVED
    }
    /// TODO TBC the below test

    function test_resolveDispute_winnerSplit_ZeroAllocationToEachParty() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED

        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw,) =
            escrow.contractWeeks(currentContractId, --weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);

        Enums.Winner _winner = Enums.Winner.SPLIT;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(currentContractId, weekId, _winner, 0, 0);
        escrow.resolveDispute(currentContractId, weekId, _winner, 0, 0);
        (_contractor, _amountToClaim, _amountToWithdraw,) = escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);

        (, _prepaymentAmount, _status) = escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 6); //Status.RESOLVED
    }

    function test_resolveDispute_reverts_DisputeNotActiveForThisDeposit() public {
        test_deposit_prepayment();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__DisputeNotActiveForThisDeposit.selector);
        escrow.resolveDispute(currentContractId, --weekId, Enums.Winner.CLIENT, 0, 0);
        (,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_resolveDispute_reverts_UnauthorizedToApproveDispute() public {
        test_createDispute_by_client();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED
        vm.prank(address(this));
        vm.expectRevert(); //Unauthorized()
        escrow.resolveDispute(currentContractId, weekId, Enums.Winner.CONTRACTOR, 0, 0);
        (,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    function test_resolveDispute_reverts_winnerClient_ResolutionExceedsDepositedAmount() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED

        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__ResolutionExceedsDepositedAmount.selector);
        escrow.resolveDispute(currentContractId, --weekId, Enums.Winner.CLIENT, 1.1 ether, 0 ether);
        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw,) =
            escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        (,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    function test_resolveDispute_reverts_winnerContractor_ResolutionExceedsDepositedAmount() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED

        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__ResolutionExceedsDepositedAmount.selector);
        escrow.resolveDispute(currentContractId, --weekId, Enums.Winner.CONTRACTOR, 0 ether, 1.1 ether);
        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw,) =
            escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        (,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    function test_resolveDispute_reverts_winnerSplit_ResolutionExceedsDepositedAmount() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED

        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__ResolutionExceedsDepositedAmount.selector);
        escrow.resolveDispute(currentContractId, --weekId, Enums.Winner.SPLIT, 1 ether, 1 wei);
        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw,) =
            escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        (,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 5); //Status.DISPUTED
    }

    function test_resolveDispute_reverts_InvalidWinnerSpecified() public {
        test_createDispute_by_contractor();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 weekId = escrow.getWeeksCount(currentContractId);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrow.contractDetails(currentContractId);
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 5); //Status.DISPUTED

        vm.prank(owner);
        // vm.expectRevert(IEscrow.Escrow__InvalidWinnerSpecified.selector);
        vm.expectRevert(); // panic: failed to convert value into enum type (0x21)
        escrow.resolveDispute(currentContractId, --weekId, Enums.Winner(uint256(4)), 1 ether, 0); // Invalid enum value for Winner
        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw,) =
            escrow.contractWeeks(currentContractId, weekId);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        (,, _status) = escrow.contractDetails(currentContractId);
        assertEq(uint256(_status), 5); //Status.DISPUTED
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
