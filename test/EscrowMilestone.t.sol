// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {EscrowMilestone, IEscrowMilestone, Ownable} from "src/EscrowMilestone.sol";
import {EscrowFeeManager, IEscrowFeeManager} from "src/modules/EscrowFeeManager.sol";
import {Registry, IRegistry} from "src/modules/Registry.sol";
import {Enums} from "src/libs/Enums.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {MockRegistry} from "test/mocks/MockRegistry.sol";

contract EscrowMilestoneUnitTest is Test {
    EscrowMilestone escrow;
    Registry registry;
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

    IEscrowMilestone.Deposit[] deposits;

    struct Deposit {
        address contractor;
        address paymentToken;
        uint256 amount;
        uint256 amountToClaim;
        uint256 amountToWithdraw;
        uint256 timeLock;
        bytes32 contractorData;
        Enums.FeeConfig feeConfig;
        Enums.Status status;
    }

    event Deposited(
        address indexed sender,
        uint256 indexed contractId,
        uint256 milestoneId,
        address paymentToken,
        uint256 amount,
        Enums.FeeConfig feeConfig
    );

    function setUp() public {
        owner = makeAddr("owner");
        treasury = makeAddr("treasury");
        client = makeAddr("client");
        contractor = makeAddr("contractor");

        escrow = new EscrowMilestone();
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

        // Initialize the deposits array within setUp
        deposits.push(
            IEscrowMilestone.Deposit({
                contractor: address(0),
                paymentToken: address(paymentToken),
                amount: 1 ether,
                amountToClaim: 0,
                amountToWithdraw: 0,
                timeLock: 0,
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
        vm.expectRevert(IEscrowMilestone.Escrow__ZeroAddressProvided.selector);
        escrow.initialize(address(0), owner, address(registry));
        vm.expectRevert(IEscrowMilestone.Escrow__ZeroAddressProvided.selector);
        escrow.initialize(client, address(0), address(registry));
        vm.expectRevert(IEscrowMilestone.Escrow__ZeroAddressProvided.selector);
        escrow.initialize(client, owner, address(0));
        vm.expectRevert(IEscrowMilestone.Escrow__ZeroAddressProvided.selector);
        escrow.initialize(address(0), address(0), address(0));
        escrow.initialize(client, owner, address(registry));
        assertTrue(escrow.initialized());
        vm.expectRevert(IEscrowMilestone.Escrow__AlreadyInitialized.selector);
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
            uint256 _timeLock,
            bytes32 _contractorData,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractMilestones(currentContractId, 0);
        assertEq(_contractor, address(0));
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(_timeLock, 0);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 0); //Status.ACTIVE
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
            uint256 _timeLock,
            bytes32 _contractorData,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractMilestones(currentContractId, 1);
        assertEq(_contractor, address(0));
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(_timeLock, 0);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 0); //Status.ACTIVE
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, _amount, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount + totalDepositAmount); //2.06 ether
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
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
        IEscrowMilestone.Deposit[] memory _deposits = new IEscrowMilestone.Deposit[](1);
        _deposits[0] = IEscrowMilestone.Deposit({
            contractor: address(0),
            paymentToken: address(notPaymentToken),
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            timeLock: 0,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.ACTIVE
        });
        vm.prank(client);
        vm.expectRevert(IEscrowMilestone.Escrow__NotSupportedPaymentToken.selector);
        escrow.deposit(0, _deposits);

        _deposits[0] = IEscrowMilestone.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 0 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            timeLock: 0,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.ACTIVE
        });
        vm.prank(client);
        vm.expectRevert(IEscrowMilestone.Escrow__ZeroDepositAmount.selector);
        escrow.deposit(0, _deposits);

        _deposits = new IEscrowMilestone.Deposit[](0);
        vm.prank(client);
        vm.expectRevert(IEscrowMilestone.Escrow__NoDepositsProvided.selector);
        escrow.deposit(0, _deposits);

        vm.startPrank(address(client));
        paymentToken.mint(address(client), 1.03 ether);
        paymentToken.approve(address(escrow), 1.03 ether);
        _deposits = new IEscrowMilestone.Deposit[](1);
        _deposits[0] = IEscrowMilestone.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            timeLock: 0,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.ACTIVE
        });
        vm.expectRevert(IEscrowMilestone.Escrow__InvalidContractId.selector);
        escrow.deposit(1, _deposits);
    }

    function test_deposit_severalMilestones() public {
        test_initialize();
        IEscrowMilestone.Deposit[] memory _deposits = new IEscrowMilestone.Deposit[](3);
        _deposits[0] = IEscrowMilestone.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            timeLock: 0,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.ACTIVE
        });
        (uint256 depositAmountMilestone1,) =
            _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);
        _deposits[1] = IEscrowMilestone.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 2 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            timeLock: 0,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.ACTIVE
        });
        (uint256 depositAmountMilestone2,) =
            _computeDepositAndFeeAmount(client, 2 ether, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        _deposits[2] = IEscrowMilestone.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 3 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            timeLock: 0,
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
            uint256 _timeLock,
            bytes32 _contractorData,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractMilestones(currentContractId, 0);
        assertEq(_contractor, address(0));
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(_timeLock, 0);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 0); //Enums.Enums.FeeConfig.CLIENT_COVERS_ALL
        assertEq(uint256(_status), 0); //Status.ACTIVE
        (_contractor,, _amount, _amountToClaim, _amountToWithdraw,,, _feeConfig, _status) =
            escrow.contractMilestones(currentContractId, 1);
        assertEq(_contractor, address(0));
        assertEq(_amount, 2 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 0); //Status.ACTIVE
        (,, _amount, _amountToClaim, _amountToWithdraw,,, _feeConfig, _status) =
            escrow.contractMilestones(currentContractId, 2);
        assertEq(_amount, 3 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 0); //Status.ACTIVE
        assertEq(paymentToken.balanceOf(address(escrow)), totalDepositAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
    }

    function test_deposit_withContractorAddress() public {
        test_initialize();
        IEscrowMilestone.Deposit[] memory _deposits = new IEscrowMilestone.Deposit[](1);
        _deposits[0] = IEscrowMilestone.Deposit({
            contractor: contractor,
            paymentToken: address(paymentToken),
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            timeLock: 0,
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
            uint256 _timeLock,
            bytes32 _contractorData,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrow.contractMilestones(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(_timeLock, 0);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 0); //Status.ACTIVE
        assertEq(paymentToken.balanceOf(address(escrow)), depositAmountMilestone1);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
    }

}