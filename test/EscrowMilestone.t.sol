// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test, console2 } from "forge-std/Test.sol";

import { EscrowMilestone, IEscrowMilestone } from "src/EscrowMilestone.sol";
import { EscrowAccountRecovery } from "src/modules/EscrowAccountRecovery.sol";
import { EscrowAdminManager, OwnedRoles } from "src/modules/EscrowAdminManager.sol";
import { EscrowFeeManager, IEscrowFeeManager } from "src/modules/EscrowFeeManager.sol";
import { EscrowRegistry, IEscrowRegistry } from "src/modules/EscrowRegistry.sol";
import { Enums } from "src/libs/Enums.sol";
import { IEscrow } from "src/interfaces/IEscrow.sol";
import { MockRegistry } from "test/mocks/MockRegistry.sol";
import { MockUSDT } from "test/mocks/MockUSDT.sol";
import { ERC20Mock } from "@openzeppelin/mocks/token/ERC20Mock.sol";

contract EscrowMilestoneUnitTest is Test {
    EscrowMilestone escrow;
    EscrowRegistry registry;
    ERC20Mock paymentToken;
    ERC20Mock newPaymentToken;
    EscrowFeeManager feeManager;
    EscrowAccountRecovery recovery;
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

    IEscrowMilestone.Milestone[] milestones;

    struct Milestone {
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
    event Approved(
        address indexed approver,
        uint256 indexed contractId,
        uint256 indexed milestoneId,
        uint256 amountApprove,
        address receiver
    );
    event Refilled(
        address indexed sender, uint256 indexed contractId, uint256 indexed milestoneId, uint256 amountAdditional
    );
    event Claimed(address indexed contractor, uint256 indexed contractId, uint256 indexed milestoneId, uint256 amount);
    event BulkClaimed(
        address indexed contractor,
        uint256 indexed contractId,
        uint256 startMilestoneId,
        uint256 endMilestoneId,
        uint256 totalClaimedAmount,
        uint256 totalFeeAmount,
        uint256 totalClientFee
    );
    event Withdrawn(
        address indexed withdrawer, uint256 indexed contractId, uint256 indexed milestoneId, uint256 amount
    );
    event RegistryUpdated(address registry);
    event AdminManagerUpdated(address adminManager);
    event MaxMilestonesSet(uint256 maxMilestones);
    event ReturnRequested(address indexed sender, uint256 indexed contractId, uint256 indexed milestoneId);
    event ReturnApproved(address indexed approver, uint256 indexed contractId, uint256 indexed milestoneId);
    event ReturnCanceled(address indexed sender, uint256 indexed contractId, uint256 indexed milestoneId);
    event DisputeCreated(address indexed sender, uint256 indexed contractId, uint256 indexed milestoneId);
    event DisputeResolved(
        address indexed approver,
        uint256 indexed contractId,
        uint256 indexed milestoneId,
        Enums.Winner winner,
        uint256 clientAmount,
        uint256 contractorAmount
    );

    function setUp() public {
        owner = makeAddr("owner");
        treasury = makeAddr("treasury");
        client = makeAddr("client");
        contractor = makeAddr("contractor");

        escrow = new EscrowMilestone();
        registry = new EscrowRegistry(owner);
        paymentToken = new ERC20Mock();
        feeManager = new EscrowFeeManager(300, 500, owner);
        adminManager = new EscrowAdminManager(owner);
        recovery = new EscrowAccountRecovery(address(adminManager));

        vm.startPrank(owner);
        registry.addPaymentToken(address(paymentToken));
        registry.setTreasury(treasury);
        registry.updateFeeManager(address(feeManager));
        registry.setAccountRecovery(address(recovery));
        vm.stopPrank();

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        contractorData = keccak256(abi.encodePacked(contractData, salt));

        // Initialize the milestones array within setUp
        milestones.push(
            IEscrowMilestone.Milestone({
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

    function test_deposit() public {
        test_initialize();
        vm.startPrank(client);
        paymentToken.mint(client, 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        vm.expectEmit(true, true, true, true);
        emit Deposited(client, 1, 0, address(paymentToken), 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        escrow.deposit(0, address(paymentToken), milestones);
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
        assertEq(uint256(_status), 1); //Status.ACTIVE
        assertEq(escrow.getMilestoneCount(currentContractId), 1);
        (address _paymentToken, uint256 _depositAmount, Enums.Winner _winner) =
            escrow.milestoneDetails(currentContractId, 0);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_depositAmount, _amount);
        assertEq(uint256(_winner), 0); //Status.NONE
    }

    function test_deposit_existingContract() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(currentContractId, 1);
        vm.startPrank(client);
        paymentToken.mint(client, 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        vm.expectEmit(true, true, true, true);
        emit Deposited(client, 1, 1, address(paymentToken), 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        escrow.deposit(currentContractId, address(paymentToken), milestones);
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
        assertEq(uint256(_status), 1); //Status.ACTIVE
        (address _paymentToken, uint256 _depositAmount, Enums.Winner _winner) =
            escrow.milestoneDetails(currentContractId, 0);
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
        escrow.deposit(0, address(paymentToken), milestones);
        test_initialize();
        address notClient = makeAddr("notClient");
        vm.prank(notClient);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.deposit(0, address(paymentToken), milestones);

        ERC20Mock notPaymentToken = new ERC20Mock();
        IEscrowMilestone.Milestone[] memory _milestones = new IEscrowMilestone.Milestone[](1);
        _milestones[0] = IEscrowMilestone.Milestone({
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
        escrow.deposit(0, address(notPaymentToken), _milestones);

        _milestones[0] = IEscrowMilestone.Milestone({
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
        escrow.deposit(0, address(paymentToken), _milestones);

        _milestones = new IEscrowMilestone.Milestone[](0);
        vm.prank(client);
        vm.expectRevert(IEscrowMilestone.Escrow__NoDepositsProvided.selector);
        escrow.deposit(0, address(paymentToken), _milestones);

        vm.startPrank(address(client));
        paymentToken.mint(address(client), 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        _milestones = new IEscrowMilestone.Milestone[](1);
        _milestones[0] = IEscrowMilestone.Milestone({
            contractor: address(0),
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.ACTIVE
        });
        vm.expectRevert(IEscrowMilestone.Escrow__InvalidContractId.selector);
        escrow.deposit(1, address(paymentToken), _milestones);
        vm.stopPrank();

        vm.prank(owner);
        registry.addToBlacklist(client);
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__BlacklistedAccount.selector);
        escrow.deposit(0, address(paymentToken), _milestones);
    }

    function test_deposit_reverts_NotSetFeeManager() public {
        // this test needs it's own setup
        IEscrowMilestone.Milestone[] memory _milestones = new IEscrowMilestone.Milestone[](1);
        _milestones[0] = IEscrowMilestone.Milestone({
            contractor: contractor,
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.ACTIVE
        });

        EscrowMilestone escrow2 = new EscrowMilestone();
        MockRegistry registry2 = new MockRegistry(owner);
        ERC20Mock paymentToken2 = new ERC20Mock();
        EscrowFeeManager feeManager2 = new EscrowFeeManager(300, 500, owner);
        vm.prank(owner);
        registry2.addPaymentToken(address(paymentToken2));
        escrow2.initialize(client, owner, address(registry2));
        vm.startPrank(address(client));
        paymentToken2.mint(address(client), 1.08 ether);
        paymentToken2.approve(address(escrow2), 1.08 ether);
        vm.expectRevert(IEscrow.Escrow__NotSetFeeManager.selector);
        escrow2.deposit(0, address(paymentToken2), _milestones);
        vm.stopPrank();
        vm.prank(owner);
        registry2.updateFeeManager(address(feeManager2));
        vm.prank(client);
        escrow2.deposit(0, address(paymentToken2), _milestones);

        uint256 currentContractId = escrow2.getCurrentContractId();
        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        vm.prank(contractor);
        escrow2.submit(currentContractId, 0, contractData, salt);
        vm.prank(client);
        escrow2.approve(currentContractId, 0, 1 ether, contractor);

        vm.prank(owner);
        registry2.updateFeeManager(address(0));
        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__NotSetFeeManager.selector);
        escrow2.claim(currentContractId, 0);
    }

    function test_deposit_severalMilestones() public {
        test_initialize();
        IEscrowMilestone.Milestone[] memory _milestones = new IEscrowMilestone.Milestone[](3);
        _milestones[0] = IEscrowMilestone.Milestone({
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
        _milestones[1] = IEscrowMilestone.Milestone({
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
        _milestones[2] = IEscrowMilestone.Milestone({
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
        escrow.deposit(0, address(paymentToken), _milestones);
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
        assertEq(uint256(_status), 1); //Status.ACTIVE
        (address _paymentToken, uint256 _depositAmount, Enums.Winner _winner) =
            escrow.milestoneDetails(currentContractId, 0);
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
        assertEq(uint256(_status), 1); //Status.ACTIVE
        (_paymentToken, _depositAmount, _winner) = escrow.milestoneDetails(currentContractId, 1);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_depositAmount, _amount);
        assertEq(uint256(_winner), 0); //Status.NONE

        (, _amount, _amountToClaim, _amountToWithdraw,, _feeConfig, _status) =
            escrow.contractMilestones(currentContractId, 2);
        assertEq(_amount, 3 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 1); //Status.ACTIVE
        (_paymentToken, _depositAmount, _winner) = escrow.milestoneDetails(currentContractId, 2);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_depositAmount, _amount);
        assertEq(uint256(_winner), 0); //Status.NONE

        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(escrow.getMilestoneCount(currentContractId), 3);
        vm.stopPrank();
    }

    function test_deposit_limit_number() public {
        test_initialize();
        uint256 depositAmount = 1 ether;
        IEscrowMilestone.Milestone[] memory _milestones = new IEscrowMilestone.Milestone[](10);
        for (uint256 i; i < _milestones.length; i++) {
            _milestones[i] = IEscrowMilestone.Milestone({
                contractor: address(0),
                amount: depositAmount,
                amountToClaim: 0,
                amountToWithdraw: 0,
                contractorData: contractorData,
                feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                status: Enums.Status.ACTIVE
            });
        }
        uint256 totalDepositAmount = depositAmount * _milestones.length;
        (uint256 totalDepositAmountWithFee,) =
            _computeDepositAndFeeAmount(client, totalDepositAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY);

        vm.startPrank(address(client));
        paymentToken.mint(address(client), totalDepositAmountWithFee);
        paymentToken.approve(address(escrow), totalDepositAmountWithFee);
        escrow.deposit(0, address(paymentToken), _milestones);
        uint256 currentContractId = escrow.getCurrentContractId();
        (
            address _contractor,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            bytes32 _contractorData,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractMilestones(currentContractId, 9);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 1); //Status.ACTIVE
        (address _paymentToken, uint256 _depositAmount, Enums.Winner _winner) =
            escrow.milestoneDetails(currentContractId, 0);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_depositAmount, _amount);
        assertEq(uint256(_winner), 0); //Status.NONE
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmountWithFee);
        assertEq(escrow.getMilestoneCount(currentContractId), 10);
        vm.stopPrank();
    }

    function test_deposit_limit_number_reverts_TooManyMilestones() public {
        test_initialize();
        uint256 depositAmount = 1 ether;
        IEscrowMilestone.Milestone[] memory _milestones = new IEscrowMilestone.Milestone[](11);
        for (uint256 i; i < _milestones.length; i++) {
            _milestones[i] = IEscrowMilestone.Milestone({
                contractor: address(0),
                amount: depositAmount,
                amountToClaim: 0,
                amountToWithdraw: 0,
                contractorData: contractorData,
                feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                status: Enums.Status.ACTIVE
            });
        }
        uint256 totalDepositAmount = depositAmount * _milestones.length;
        (uint256 totalDepositAmountWithFee,) =
            _computeDepositAndFeeAmount(client, totalDepositAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY);

        vm.startPrank(address(client));
        paymentToken.mint(address(client), totalDepositAmountWithFee);
        paymentToken.approve(address(escrow), totalDepositAmountWithFee);
        vm.expectRevert(IEscrowMilestone.Escrow__TooManyMilestones.selector);
        escrow.deposit(0, address(paymentToken), _milestones);
        assertEq(paymentToken.balanceOf(address(escrow)), 0);
        vm.stopPrank();
    }

    function test_deposit_withContractorAddress() public {
        test_initialize();
        IEscrowMilestone.Milestone[] memory _milestones = new IEscrowMilestone.Milestone[](1);
        _milestones[0] = IEscrowMilestone.Milestone({
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
        escrow.deposit(0, address(paymentToken), _milestones);
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
        assertEq(uint256(_status), 1); //Status.ACTIVE
        assertEq(paymentToken.balanceOf(address(escrow)), depositAmountMilestone1);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (address _paymentToken, uint256 _depositAmount, Enums.Winner _winner) =
            escrow.milestoneDetails(currentContractId, 0);
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
        assertEq(uint256(_status), 1); //Status.ACTIVE

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
        assertEq(uint256(_status), 2); //Status.SUBMITTED
    }

    function test_submit_withContractorAddress() public {
        test_deposit_withContractorAddress();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor, uint256 _amount,,, bytes32 _contractorData,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_status), 1); //Status.ACTIVE

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
        assertEq(uint256(_status), 2); //Status.SUBMITTED
    }

    function test_submit_reverts_InvalidStatusForSubmit() public {
        test_submit_withContractorAddress();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,,,, bytes32 _contractorData,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        vm.startPrank(contractor);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusForSubmit.selector);
        escrow.submit(currentContractId, 0, contractData, salt);
        (_contractor,,,,,, _status) = escrow.contractMilestones(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
    }

    function test_submit_reverts_InvalidContractorDataHash() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor, uint256 _amount,,, bytes32 _contractorData,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, 0);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_status), 1); //Status.ACTIVE

        contractData = bytes("contract_data_");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);
        vm.startPrank(contractor);
        vm.expectRevert(IEscrow.Escrow__InvalidContractorDataHash.selector);
        escrow.submit(currentContractId, 0, contractData, salt);
        (_contractor,,,,,, _status) = escrow.contractMilestones(currentContractId, 0);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 1); //Status.ACTIVE

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(43)));
        contractorDataHash = escrow.getContractorDataHash(contractData, salt);
        vm.startPrank(contractor);
        vm.expectRevert(IEscrow.Escrow__InvalidContractorDataHash.selector);
        escrow.submit(currentContractId, 0, contractData, salt);
        (_contractor,,,,,, _status) = escrow.contractMilestones(currentContractId, 0);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 1); //Status.ACTIVE
    }

    function test_submit_reverts_UnauthorizedAccount() public {
        test_deposit_withContractorAddress();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,,,, bytes32 _contractorData,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_status), 1); //Status.ACTIVE

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = escrow.getContractorDataHash(contractData, salt);
        vm.prank(address(this));
        vm.expectRevert(); //IEscrow.Escrow__UnauthorizedAccount.selector
        escrow.submit(currentContractId, 0, contractData, salt);
        (_contractor,,,,,, _status) = escrow.contractMilestones(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_contractorData, contractorDataHash);
        assertEq(uint256(_status), 1); //Status.ACTIVE
    }

    function test_submit_reverts_InvalidMilestoneId() public {
        test_deposit_withContractorAddress();
        uint256 currentContractId = escrow.getCurrentContractId();
        (address _contractor,,,, bytes32 _contractorData,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_status), 1); //Status.ACTIVE

        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        assertEq(milestoneId, 1);

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        vm.prank(contractor);
        vm.expectRevert(IEscrowMilestone.Escrow__InvalidMilestoneId.selector);
        escrow.submit(currentContractId, ++milestoneId, contractData, salt);
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
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        uint256 amountApprove = 1 ether;
        vm.startPrank(client);
        vm.expectEmit(true, true, true, true);
        emit Approved(client, currentContractId, milestoneId, amountApprove, contractor);
        escrow.approve(currentContractId, milestoneId, amountApprove, contractor);
        (_contractor, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove);
        assertEq(uint256(_status), 3); //Status.APPROVED
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
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        uint256 amountApprove = 1 ether;
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit Approved(owner, currentContractId, milestoneId, amountApprove, contractor);
        escrow.approve(currentContractId, milestoneId, amountApprove, contractor);
        (_contractor, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove);
        assertEq(uint256(_status), 3); //Status.APPROVED
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
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        address newAdmin = makeAddr("newAdmin");
        vm.prank(owner);
        adminManager.addAdmin(newAdmin);

        uint256 amountApprove = 1 ether;
        vm.startPrank(newAdmin);
        vm.expectEmit(true, true, true, true);
        emit Approved(newAdmin, currentContractId, milestoneId, amountApprove, contractor);
        escrow.approve(currentContractId, milestoneId, amountApprove, contractor);
        (_contractor, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove);
        assertEq(uint256(_status), 3); //Status.APPROVED
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
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        uint256 amountApprove = 1 ether;
        vm.startPrank(address(this));
        vm.expectRevert(); //IEscrow.Escrow__UnauthorizedAccount.selector
        escrow.approve(currentContractId, milestoneId, amountApprove, contractor);
        (_contractor, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
        vm.stopPrank();
    }

    function test_approve_reverts_InvalidStatusForApprove() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 1); //Status.ACTIVE

        uint256 amountApprove = 1 ether;
        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusForApprove.selector);
        escrow.approve(currentContractId, milestoneId, amountApprove, contractor);
        (_contractor, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
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
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        uint256 amountApprove = 1 ether;
        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__UnauthorizedReceiver.selector);
        escrow.approve(currentContractId, milestoneId, amountApprove, address(0));
        (_contractor, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        vm.expectRevert(IEscrow.Escrow__UnauthorizedReceiver.selector);
        escrow.approve(currentContractId, milestoneId, amountApprove, address(this));
        (_contractor, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
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
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        uint256 amountApprove = 0 ether;
        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidAmount.selector);
        escrow.approve(currentContractId, milestoneId, amountApprove, address(0));
        (_contractor, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
    }

    function test_approve_reverts_NotEnoughDeposit() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        uint256 amountApprove = 1.1 ether;
        vm.startPrank(client);
        vm.expectRevert(IEscrow.Escrow__NotEnoughDeposit.selector);
        escrow.approve(currentContractId, milestoneId, amountApprove, contractor);
        (_contractor, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
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
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount); //1.03 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);

        uint256 amountAdditional = 1 ether;
        vm.startPrank(client);
        paymentToken.mint(client, totalDepositAmount);
        paymentToken.approve(address(escrow), totalDepositAmount);
        vm.expectEmit(true, true, true, true);
        emit Refilled(client, currentContractId, milestoneId, amountAdditional);
        escrow.refill(currentContractId, milestoneId, amountAdditional);
        vm.stopPrank();
        (_contractor, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 2 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + totalDepositAmount); //2.06 ether
    }

    function test_refill_reverts() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (, uint256 _amount,,,,, Enums.Status _status) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE

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
        assertEq(uint256(_status), 3); //Status.APPROVED

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
        emit Claimed(contractor, currentContractId, milestoneId, claimAmount);
        escrow.claim(currentContractId, milestoneId);

        assertEq(paymentToken.balanceOf(address(escrow)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), feeAmount + clientFee);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 4); //Status.COMPLETED
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
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusToClaim.selector);
        escrow.claim(currentContractId, milestoneId);

        amountApprove = _amount;
        vm.prank(client);
        escrow.approve(currentContractId, milestoneId, amountApprove, contractor);

        bytes memory expectedRevertData =
            abi.encodeWithSelector(IEscrow.Escrow__UnauthorizedAccount.selector, address(this));

        vm.prank(address(this));
        vm.expectRevert(expectedRevertData);
        escrow.claim(currentContractId, milestoneId);
        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, amountApprove); //0
        assertEq(uint256(_status), 3); //Status.APPROVED

        vm.prank(owner);
        registry.addToBlacklist(contractor);
        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__BlacklistedAccount.selector);
        escrow.claim(currentContractId, milestoneId);

        MockRegistry mockRegistry = new MockRegistry(owner);
        vm.startPrank(owner);
        mockRegistry.addPaymentToken(address(paymentToken));
        // mockRegistry.setTreasury(treasury);
        mockRegistry.updateFeeManager(address(feeManager));
        escrow.updateRegistry(address(mockRegistry));
        vm.stopPrank();

        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__ZeroAddressProvided.selector);
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
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        vm.prank(client);
        escrow.requestReturn(currentContractId, milestoneId);
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED

        vm.prank(contractor);
        escrow.createDispute(currentContractId, milestoneId);
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED

        vm.prank(owner);
        escrow.resolveDispute(currentContractId, milestoneId, Enums.Winner.SPLIT, _amount / 2, _amount / 2);
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0.5 ether);
        assertEq(_amountToWithdraw, 0.5 ether);
        assertEq(uint256(_status), 7); //Status.RESOLVED

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
        assertEq(uint256(_status), 9); //Status.CANCELED
        assertEq(paymentToken.balanceOf(address(escrow)), 0.5 ether);
        assertEq(paymentToken.balanceOf(address(client)), totalDepositAmount); //=0.5 ether
        assertEq(paymentToken.balanceOf(address(treasury)), initialFeeAmount - feeAmount);
        assertEq(paymentToken.balanceOf(address(contractor)), 0 ether);

        vm.startPrank(contractor);
        (uint256 claimAmount, uint256 claimFeeAmount,) = IEscrowFeeManager(feeManager).computeClaimableAmountAndFee(
            contractor, _amountToClaim, Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        escrow.claim(currentContractId, milestoneId);
        (, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
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
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        vm.prank(client);
        escrow.requestReturn(currentContractId, milestoneId);
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED

        vm.prank(contractor);
        escrow.createDispute(currentContractId, milestoneId);
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED

        vm.prank(owner);
        escrow.resolveDispute(currentContractId, milestoneId, Enums.Winner.SPLIT, _amount / 2, 0);
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0.5 ether);
        assertEq(uint256(_status), 7); //Status.RESOLVED

        vm.startPrank(contractor);
        vm.expectRevert(IEscrow.Escrow__NotApproved.selector);
        escrow.claim(currentContractId, milestoneId);
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
        assertEq(uint256(_status), 1); //Status.ACTIVE

        uint256 milestoneId2 = milestoneId - 2;
        (_contractor, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId2);
        assertEq(_contractor, address(0));
        assertEq(_amount, 2 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
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
        assertEq(uint256(_status), 4); //Status.COMPLETED

        // check milestoneId1 is not changed
        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId1);
        assertEq(_amount, 3 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE

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

        uint256 startMilestoneId = 0;
        uint256 endMilestoneId = 2;
        vm.prank(contractor);
        vm.expectEmit(true, true, true, true);
        emit BulkClaimed(
            contractor,
            currentContractId,
            startMilestoneId,
            endMilestoneId,
            totalClaimAmount,
            totalFeeAmount,
            totalClientFee
        );
        escrow.claimAll(currentContractId, startMilestoneId, endMilestoneId);

        (, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, 0);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 4); //Status.COMPLETED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, 1);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 4); //Status.COMPLETED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, 2);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 4); //Status.COMPLETED

        assertEq(
            paymentToken.balanceOf(address(escrow)), 6.23 ether - totalClaimAmount - (totalFeeAmount + totalClientFee)
        );
        assertEq(paymentToken.balanceOf(address(escrow)), 0);
        assertEq(paymentToken.balanceOf(address(treasury)), totalFeeAmount + totalClientFee);
        assertEq(paymentToken.balanceOf(address(contractor)), totalClaimAmount);
    }

    function test_claimAll_oneOfThree() public {
        test_deposit_severalMilestones();
        assertEq(paymentToken.balanceOf(address(escrow)), 6.23 ether);
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(escrow.getMilestoneCount(currentContractId), 3);

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));

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
        escrow.claimAll(currentContractId, 0, 2);

        (, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, 0);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, 1);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 4); //Status.COMPLETED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, 2);
        assertEq(_amount, 3 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        assertTrue(paymentToken.balanceOf(address(escrow)) > 0);
        assertEq(paymentToken.balanceOf(address(escrow)), 6.23 ether - claimAmount - (feeAmount + clientFee));
        assertEq(paymentToken.balanceOf(address(treasury)), feeAmount + clientFee);
        assertEq(paymentToken.balanceOf(address(contractor)), claimAmount);
    }

    function test_claimAll_twoOfThree() public {
        test_deposit_severalMilestones();
        assertEq(paymentToken.balanceOf(address(escrow)), 6.23 ether);
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(escrow.getMilestoneCount(currentContractId), 3);

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));

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
        escrow.claimAll(currentContractId, 0, 2);

        (, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, 0);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 4); //Status.COMPLETED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, 1);
        assertEq(_amount, 2 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 2); //Status.SUBMITTED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, 2);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 4); //Status.COMPLETED

        assertTrue(paymentToken.balanceOf(address(escrow)) > 0);
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
        escrow.claimAll(currentContractId, 0, 2);

        (, uint256 _amount, uint256 _amountToClaim,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, 0);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_status), 3); //Status.APPROVED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, 1);
        assertEq(_amount, 2 ether);
        assertEq(_amountToClaim, 2 ether);
        assertEq(uint256(_status), 3); //Status.APPROVED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(currentContractId, 2);
        assertEq(_amount, 3 ether);
        assertEq(_amountToClaim, 3 ether);
        assertEq(uint256(_status), 3); //Status.APPROVED

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

        (, uint256 initialFeeAmount) = _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);
        uint256 platformFee = initialFeeAmount - clientFeeAmount;

        vm.startPrank(client);
        escrow.withdraw(1, 0);

        (, uint256 _amount, uint256 _amountToClaim, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.contractMilestones(1, 0);
        assertEq(_amount, 0.5 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 9); //Status.CANCELED

        assertEq(paymentToken.balanceOf(address(escrow)), 6.23 ether - withdrawableAmount - platformFee);
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee);
        assertEq(paymentToken.balanceOf(address(client)), withdrawableAmount);

        escrow.approve(1, 2, 3 ether, contractor);
        vm.stopPrank();

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(1, 1);
        assertEq(_amount, 2 ether);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_status), 7); //Status.RESOLVED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(1, 2);
        assertEq(_amount, 3 ether);
        assertEq(_amountToClaim, 3 ether);
        assertEq(uint256(_status), 3); //Status.APPROVED

        vm.prank(client);
        escrow.withdraw(1, 1);

        vm.prank(contractor);
        escrow.claimAll(1, 0, 2);

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(1, 0);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 4); //Status.COMPLETED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(1, 1);
        assertEq(_amount, 0 ether); // withdrawn & claimed
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 4); //Status.COMPLETED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(1, 2);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 4); //Status.COMPLETED

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

        (, uint256 initialFeeAmount) = _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);
        uint256 platformFee = initialFeeAmount - clientFeeAmount;

        vm.startPrank(client);
        escrow.withdraw(1, 0);

        (, uint256 _amount, uint256 _amountToClaim, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.contractMilestones(1, 0);
        assertEq(_amount, 0.5 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 9); //Status.CANCELED

        assertEq(paymentToken.balanceOf(address(escrow)), 6.23 ether - withdrawableAmount - platformFee);
        assertEq(paymentToken.balanceOf(address(treasury)), platformFee);
        assertEq(paymentToken.balanceOf(address(client)), withdrawableAmount);

        escrow.approve(1, 2, 3 ether, contractor);
        vm.stopPrank();

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(1, 1);
        assertEq(_amount, 2 ether);
        assertEq(_amountToClaim, 1 ether);
        assertEq(uint256(_status), 7); //Status.RESOLVED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(1, 2);
        assertEq(_amount, 3 ether);
        assertEq(_amountToClaim, 3 ether);
        assertEq(uint256(_status), 3); //Status.APPROVED

        vm.prank(contractor);
        escrow.claimAll(1, 0, 2);

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(1, 0);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 4); //Status.COMPLETED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(1, 1);
        // assertEq(_amount, 1 ether); //Claimed own split, not withdrawn yet
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 7); //Status.RESOLVED

        (, _amount, _amountToClaim,,,, _status) = escrow.contractMilestones(1, 2);
        assertEq(_amount, 0 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_status), 4); //Status.COMPLETED

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

    function test_claimAll_when_diff_contractors() public {
        MockUSDT usdt = new MockUSDT();
        vm.prank(owner);
        registry.addPaymentToken(address(usdt));
        uint256 depositAmount = 1e6;
        uint256 depositAmountAndFee = 1.03e6;
        test_initialize();
        IEscrowMilestone.Milestone[] memory _milestones = new IEscrowMilestone.Milestone[](3);
        _milestones[0] = IEscrowMilestone.Milestone({
            contractor: contractor,
            amount: depositAmount,
            amountToClaim: 0,
            amountToWithdraw: 0,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.NONE
        });
        address new_contractor = makeAddr("new_contractor");
        _milestones[1] = IEscrowMilestone.Milestone({
            contractor: new_contractor,
            amount: depositAmount,
            amountToClaim: 0,
            amountToWithdraw: 0,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.ACTIVE
        });
        _milestones[2] = IEscrowMilestone.Milestone({
            contractor: contractor,
            amount: depositAmount,
            amountToClaim: 0,
            amountToWithdraw: 0,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.ACTIVE
        });
        uint256 totalDepositAmount = depositAmountAndFee * 3;
        vm.startPrank(address(client));
        usdt.mint(address(client), totalDepositAmount);
        usdt.approve(address(escrow), totalDepositAmount);
        escrow.deposit(0, address(usdt), _milestones);
        vm.stopPrank();
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(usdt.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(usdt.balanceOf(address(treasury)), 0 ether);
        assertEq(usdt.balanceOf(address(client)), 0 ether);
        assertEq(escrow.getMilestoneCount(currentContractId), 3);

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        vm.startPrank(contractor);
        escrow.submit(currentContractId, 0, contractData, salt);
        escrow.submit(currentContractId, 2, contractData, salt);
        vm.stopPrank();
        vm.prank(new_contractor);
        escrow.submit(currentContractId, 1, contractData, salt);
        vm.startPrank(client);
        escrow.approve(currentContractId, 0, depositAmount, contractor);
        escrow.approve(currentContractId, 2, depositAmount, contractor);
        escrow.approve(currentContractId, 1, depositAmount, new_contractor);
        vm.stopPrank();

        (uint256 claimAmount, uint256 contractorFee, uint256 clientFee) =
            _computeClaimableAndFeeAmount(contractor, depositAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY);

        vm.prank(contractor);
        escrow.claimAll(currentContractId, 0, 2); // claim 2 of 3
        assertEq(usdt.balanceOf(address(escrow)), totalDepositAmount - (claimAmount + (contractorFee + clientFee)) * 2);
        assertEq(usdt.balanceOf(address(treasury)), (contractorFee + clientFee) * 2);
        assertEq(usdt.balanceOf(address(contractor)), claimAmount * 2);
        assertEq(usdt.balanceOf(address(new_contractor)), 0);
        assertEq(usdt.balanceOf(address(client)), 0);

        vm.prank(new_contractor);
        escrow.claimAll(currentContractId, 0, 2); // claim 1 of 3
        assertEq(usdt.balanceOf(address(escrow)), totalDepositAmount - (claimAmount + (contractorFee + clientFee)) * 3);
        assertEq(usdt.balanceOf(address(treasury)), (contractorFee + clientFee) * 3);
        assertEq(usdt.balanceOf(address(contractor)), claimAmount * 2);
        assertEq(usdt.balanceOf(address(new_contractor)), claimAmount);
        assertEq(usdt.balanceOf(address(client)), 0);
    }

    function test_claimAll_reverts_BlacklistedAccount() public {
        test_deposit_severalMilestones();
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(escrow.getMilestoneCount(currentContractId), 3);
        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));

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
        escrow.claimAll(currentContractId, 0, 2);
    }

    function test_claimAll_reverts_InvalidRange() public {
        test_deposit_severalMilestones();
        uint256 currentContractId = escrow.getCurrentContractId();
        assertEq(escrow.getMilestoneCount(currentContractId), 3);
        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));

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

        uint256 startMilestoneId = 1;
        uint256 endMilestoneId = 0;
        vm.startPrank(contractor);
        vm.expectRevert(IEscrow.Escrow__InvalidRange.selector);
        escrow.claimAll(currentContractId, startMilestoneId, endMilestoneId);
        startMilestoneId = 0;
        endMilestoneId = 4;
        vm.expectRevert(IEscrow.Escrow__OutOfRange.selector);
        escrow.claimAll(currentContractId, startMilestoneId, endMilestoneId);
        vm.stopPrank();
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
        assertEq(uint256(_status), 8); //Status.REFUND_APPROVED

        (uint256 totalDepositAmount, uint256 feeAmount) =
            _computeDepositAndFeeAmount(client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (, uint256 initialFeeAmount) = _computeDepositAndFeeAmount(client, _amount, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(client, currentContractId, milestoneId, _amountToWithdraw + feeAmount);
        escrow.withdraw(currentContractId, milestoneId);
        (, uint256 _amountAfter, uint256 _amountToWithdrawAfter,,,, Enums.Status _statusAfter) =
            escrow.contractMilestones(currentContractId, milestoneId);
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
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 1 ether);
        assertEq(uint256(_status), 8); //Status.REFUND_APPROVED

        (uint256 totalDepositAmount, uint256 feeAmount) =
            _computeDepositAndFeeAmount(client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (, uint256 initialFeeAmount) = _computeDepositAndFeeAmount(client, _amount, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(client, currentContractId, milestoneId, totalDepositAmount);
        escrow.withdraw(currentContractId, milestoneId);
        (, uint256 _amountAfter, uint256 _amountToWithdrawAfter,,,, Enums.Status _statusAfter) =
            escrow.contractMilestones(currentContractId, milestoneId);
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
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (, uint256 _amount,, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, _amount);
        assertEq(uint256(_status), 7); //Status.RESOLVED

        (uint256 totalDepositAmount, uint256 feeAmount) =
            _computeDepositAndFeeAmount(client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (, uint256 initialFeeAmount) = _computeDepositAndFeeAmount(client, _amount, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(client, currentContractId, milestoneId, totalDepositAmount);
        escrow.withdraw(currentContractId, milestoneId);
        (, uint256 _amountAfter, uint256 _amountToWithdrawAfter,,,, Enums.Status _statusAfter) =
            escrow.contractMilestones(currentContractId, milestoneId);
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
        (, uint256 _amount, uint256 _amountToClaim, uint256 _amountToWithdraw,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, 0);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0.5 ether);
        assertEq(_amountToWithdraw, 0.5 ether);
        assertEq(uint256(_status), 7); //Status.RESOLVED

        (uint256 totalDepositAmount, uint256 feeAmount) =
            _computeDepositAndFeeAmount(client, _amountToWithdraw, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + feeAmount + _amountToClaim);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);

        (, uint256 initialFeeAmount) = _computeDepositAndFeeAmount(client, _amount, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        uint256 platformFee = initialFeeAmount - feeAmount;

        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(client, currentContractId, 0, totalDepositAmount);
        escrow.withdraw(currentContractId, 0);
        (, uint256 _amountAfter,, uint256 _amountToWithdrawAfter,,, Enums.Status _statusAfter) =
            escrow.contractMilestones(currentContractId, 0);
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
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(client);
        escrow.createDispute(currentContractId, 0);
        (,,,,,, _status) = escrow.contractMilestones(currentContractId, 0);
        assertEq(uint256(_status), 6); //Status.DISPUTED
        vm.prank(owner);
        escrow.resolveDispute(currentContractId, 0, Enums.Winner.SPLIT, 0, 0.5 ether);
        (,,,,,, _status) = escrow.contractMilestones(currentContractId, 0);
        assertEq(uint256(_status), 7); //Status.RESOLVED
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__NoFundsAvailableForWithdraw.selector);
        escrow.withdraw(currentContractId, 0);
        (,,,,,, _status) = escrow.contractMilestones(currentContractId, 0);
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
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnRequested(client, currentContractId, milestoneId);
        escrow.requestReturn(currentContractId, milestoneId);
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_whenSubmitted() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnRequested(client, currentContractId, milestoneId);
        escrow.requestReturn(currentContractId, milestoneId);
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_whenApproved() public {
        test_approve();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 3); //Status.APPROVED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnRequested(client, currentContractId, milestoneId);
        escrow.requestReturn(currentContractId, milestoneId);
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_whenCompleted() public {
        test_claim_clientCoversOnly();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 0 ether);
        assertEq(uint256(_status), 4); //Status.COMPLETED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnRequested(client, currentContractId, milestoneId);
        escrow.requestReturn(currentContractId, milestoneId);
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 0 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_reverts_UnauthorizedAccount() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.prank(contractor);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender);
        escrow.requestReturn(currentContractId, milestoneId);
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
    }

    function test_requestReturn_reverts_ReturnNotAllowed() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__ReturnNotAllowed.selector);
        escrow.requestReturn(currentContractId, milestoneId);
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
    }

    function test_requestReturn_reverts_submitted_UnauthorizedAccount() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
        vm.prank(address(this));
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender);
        escrow.requestReturn(currentContractId, milestoneId);
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
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
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit ReturnApproved(owner, currentContractId, milestoneId);
        escrow.approveReturn(currentContractId, milestoneId);
        (_contractor, _amount,, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 1 ether);
        assertEq(uint256(_status), 8); //Status.REFUND_APPROVED
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
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(contractor);
        vm.expectEmit(true, true, true, true);
        emit ReturnApproved(contractor, currentContractId, milestoneId);
        escrow.approveReturn(currentContractId, milestoneId);
        (_contractor, _amount,, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 1 ether);
        assertEq(uint256(_status), 8); //Status.REFUND_APPROVED
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
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(contractor);
        vm.expectRevert(IEscrow.Escrow__UnauthorizedToApproveReturn.selector);
        escrow.approveReturn(currentContractId, milestoneId);
        (_contractor, _amount,, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
    }

    function test_approveReturn_reverts_NoReturnRequested() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor,,,,,, Enums.Status _status) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__NoReturnRequested.selector);
        escrow.approveReturn(currentContractId, milestoneId);
        (_contractor,,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, address(0));
        assertEq(uint256(_status), 1); //Status.ACTIVE
    }

    function test_approveReturn_reverts_submitted_NoReturnRequested() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor,,,,,, Enums.Status _status) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__NoReturnRequested.selector);
        escrow.approveReturn(currentContractId, milestoneId);
        (_contractor,,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
    }

    function test_cancelReturn() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (,,,,,, Enums.Status _status) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        status = Enums.Status.ACTIVE;
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnCanceled(client, currentContractId, milestoneId);
        escrow.cancelReturn(currentContractId, milestoneId, status);
        (,,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(uint256(_status), 1); //Status.ACTIVE
    }

    function test_cancelReturn_submitted() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor,,,,,, Enums.Status _status) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        status = Enums.Status.SUBMITTED;
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit ReturnCanceled(client, currentContractId, milestoneId);
        escrow.cancelReturn(currentContractId, milestoneId, status);
        (_contractor,,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
    }

    function test_cancelReturn_reverts() public {
        test_requestReturn_whenActive();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (,,,,,, Enums.Status _status) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        status = Enums.Status.ACTIVE;
        vm.prank(owner);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrow.cancelReturn(currentContractId, milestoneId, status);
        (,,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        status = Enums.Status.CANCELED;
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusProvided.selector);
        escrow.cancelReturn(currentContractId, milestoneId, status);
        (,,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
    }

    function test_cancelReturn_reverts_submitted() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        status = Enums.Status.RESOLVED;
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__InvalidStatusProvided.selector);
        escrow.cancelReturn(currentContractId, milestoneId, status);
        (,,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
    }

    function test_cancelReturn_reverts_submitted_NoReturnRequested() public {
        test_submit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor,,,,,, Enums.Status _status) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
        status = Enums.Status.ACTIVE;
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__NoReturnRequested.selector);
        escrow.cancelReturn(currentContractId, milestoneId, status);
        (_contractor,,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(uint256(_status), 2); //Status.SUBMITTED
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
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(client);
        vm.expectEmit(true, true, true, true);
        emit DisputeCreated(client, currentContractId, milestoneId);
        escrow.createDispute(currentContractId, milestoneId);
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED
    }

    function test_createDispute_by_contractor() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(contractor);
        vm.expectEmit(true, true, true, true);
        emit DisputeCreated(contractor, currentContractId, milestoneId);
        escrow.createDispute(currentContractId, milestoneId);
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED
    }

    function test_createDispute_reverts_CreateDisputeNotAllowed() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.prank(client);
        vm.expectRevert(IEscrow.Escrow__CreateDisputeNotAllowed.selector);
        escrow.createDispute(currentContractId, milestoneId);
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, address(0));
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 1); //Status.ACTIVE
    }

    function test_createDispute_reverts_UnauthorizedToApproveDispute() public {
        test_requestReturn_whenSubmitted();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (address _contractor, uint256 _amount,,,,, Enums.Status _status) =
            escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
        vm.prank(address(this));
        vm.expectRevert(IEscrow.Escrow__UnauthorizedToApproveDispute.selector);
        escrow.createDispute(currentContractId, milestoneId);
        (_contractor, _amount,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(uint256(_status), 5); //Status.RETURN_REQUESTED
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
        assertEq(uint256(_status), 6); //Status.DISPUTED
        Enums.Winner _winner = Enums.Winner.CLIENT;
        uint256 clientAmount = _amount;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(owner, currentContractId, milestoneId, _winner, clientAmount, 0);
        escrow.resolveDispute(currentContractId, milestoneId, _winner, clientAmount, 0);
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, clientAmount);
        assertEq(uint256(_status), 7); //Status.RESOLVED
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
        assertEq(uint256(_status), 6); //Status.DISPUTED
        Enums.Winner _winner = Enums.Winner.CONTRACTOR;
        uint256 contractorAmount = _amount;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(owner, currentContractId, milestoneId, _winner, 0, contractorAmount);
        escrow.resolveDispute(currentContractId, milestoneId, _winner, 0, contractorAmount);
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, contractorAmount);
        assertEq(_amountToWithdraw, 0);
        assertEq(uint256(_status), 3); //Status.APPROVED
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
        assertEq(uint256(_status), 6); //Status.DISPUTED
        Enums.Winner _winner = Enums.Winner.SPLIT;
        uint256 clientAmount = _amount / 2;
        uint256 contractorAmount = _amount / 2;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(owner, currentContractId, milestoneId, _winner, clientAmount, contractorAmount);
        escrow.resolveDispute(currentContractId, milestoneId, _winner, clientAmount, contractorAmount);
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0.5 ether);
        assertEq(_amountToWithdraw, 0.5 ether);
        assertEq(uint256(_status), 7); //Status.RESOLVED
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
        assertEq(uint256(_status), 6); //Status.DISPUTED
        Enums.Winner _winner = Enums.Winner.SPLIT;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(owner, currentContractId, milestoneId, _winner, 0, 0);
        escrow.resolveDispute(currentContractId, milestoneId, _winner, 0, 0);
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 7); //Status.RESOLVED
    }

    function test_resolveDispute_reverts_DisputeNotActiveForThisDeposit() public {
        test_deposit();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (,,,,,, Enums.Status _status) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__DisputeNotActiveForThisDeposit.selector);
        escrow.resolveDispute(currentContractId, milestoneId, Enums.Winner.CLIENT, 0, 0);
        (,,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(uint256(_status), 1); //Status.ACTIVE
    }

    function test_resolveDispute_reverts_UnauthorizedToApproveDispute() public {
        test_createDispute_by_client();
        uint256 currentContractId = escrow.getCurrentContractId();
        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);
        (,,,,,, Enums.Status _status) = escrow.contractMilestones(currentContractId, --milestoneId);
        assertEq(uint256(_status), 6); //Status.DISPUTED
        vm.prank(address(this));
        vm.expectRevert(); //Unauthorized()
        escrow.resolveDispute(currentContractId, milestoneId, Enums.Winner.CONTRACTOR, 0, 0);
        (,,,,,, _status) = escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(uint256(_status), 6); //Status.DISPUTED
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
        assertEq(uint256(_status), 6); //Status.DISPUTED
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__ResolutionExceedsDepositedAmount.selector);
        escrow.resolveDispute(currentContractId, milestoneId, Enums.Winner.CLIENT, 1.1 ether, 0 ether);
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED
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
        assertEq(uint256(_status), 6); //Status.DISPUTED
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__ResolutionExceedsDepositedAmount.selector);
        escrow.resolveDispute(currentContractId, milestoneId, Enums.Winner.CONTRACTOR, 0 ether, 1.1 ether);
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED
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
        assertEq(uint256(_status), 6); //Status.DISPUTED
        vm.prank(owner);
        vm.expectRevert(IEscrow.Escrow__ResolutionExceedsDepositedAmount.selector);
        escrow.resolveDispute(currentContractId, milestoneId, Enums.Winner.SPLIT, 1 ether, 1 wei);
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_status), 6); //Status.DISPUTED
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
        assertEq(uint256(_status), 6); //Status.DISPUTED
        vm.prank(owner);
        // vm.expectRevert(IEscrow.Escrow__InvalidWinnerSpecified.selector);
        vm.expectRevert(); // panic: failed to convert value into enum type (0x21)
        escrow.resolveDispute(currentContractId, milestoneId, Enums.Winner(uint256(4)), _amount, 0); // Invalid enum
            // value for Winner
        (_contractor, _amount, _amountToClaim, _amountToWithdraw,,, _status) =
            escrow.contractMilestones(currentContractId, milestoneId);
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

    function test_setMaxMilestones() public {
        test_initialize();
        assertEq(escrow.maxMilestones(), 10);
        address notOwner = makeAddr("notOwner");
        bytes memory expectedRevertData =
            abi.encodeWithSelector(IEscrow.Escrow__UnauthorizedAccount.selector, address(notOwner));
        vm.prank(notOwner);
        vm.expectRevert(expectedRevertData);
        escrow.setMaxMilestones(100);
        vm.startPrank(address(owner));
        vm.expectRevert(IEscrowMilestone.Escrow__InvalidMilestoneLimit.selector);
        escrow.setMaxMilestones(0);
        assertEq(escrow.maxMilestones(), 10);
        vm.expectRevert(IEscrowMilestone.Escrow__InvalidMilestoneLimit.selector);
        escrow.setMaxMilestones(21);
        assertEq(escrow.maxMilestones(), 10);
        vm.expectEmit(true, false, false, true);
        emit MaxMilestonesSet(15);
        escrow.setMaxMilestones(15);
        assertEq(escrow.maxMilestones(), 15);
        vm.stopPrank();
    }
}
