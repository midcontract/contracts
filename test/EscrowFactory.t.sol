// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";

import {EscrowAdminManager, OwnedRoles} from "src/modules/EscrowAdminManager.sol";
import {EscrowFactory, IEscrowFactory, OwnedThreeStep, Pausable} from "src/EscrowFactory.sol";
import {EscrowFeeManager, IEscrowFeeManager} from "src/modules/EscrowFeeManager.sol";
import {EscrowFixedPrice, IEscrowFixedPrice} from "src/EscrowFixedPrice.sol";
import {EscrowMilestone, IEscrowMilestone} from "src/EscrowMilestone.sol";
import {EscrowHourly, IEscrowHourly} from "src/EscrowHourly.sol";
import {EscrowRegistry, IEscrowRegistry} from "src/modules/EscrowRegistry.sol";
import {Enums} from "src/libs/Enums.sol";
import {ERC20Mock} from "@openzeppelin/mocks/token/ERC20Mock.sol";

contract EscrowFactoryUnitTest is Test {
    EscrowFactory factory;
    EscrowFixedPrice escrow;
    EscrowRegistry registry;
    ERC20Mock paymentToken;
    EscrowFeeManager feeManager;
    EscrowMilestone escrowMilestone;
    EscrowAdminManager adminManager;
    EscrowHourly escrowHourly;

    address client;
    address contractor;
    address treasury;
    address owner;

    EscrowFixedPrice.Deposit deposit;
    Enums.FeeConfig feeConfig;
    Enums.Status status;
    Enums.EscrowType escrowType;
    IEscrowHourly.Deposit depositHourly;
    IEscrowHourly.ContractDetails contractDetails;

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

    event EscrowProxyDeployed(address sender, address deployedProxy, Enums.EscrowType escrowType);
    event RegistryUpdated(address registry);
    event Paused(address account);
    event Unpaused(address account);

    function setUp() public {
        owner = makeAddr("owner");
        treasury = makeAddr("treasury");
        client = makeAddr("client");
        contractor = makeAddr("contractor");

        escrow = new EscrowFixedPrice();
        escrowMilestone = new EscrowMilestone();
        registry = new EscrowRegistry(owner);
        paymentToken = new ERC20Mock();
        feeManager = new EscrowFeeManager(3_00, 5_00, owner);
        adminManager = new EscrowAdminManager(owner);
        escrowHourly = new EscrowHourly();

        vm.startPrank(owner);
        registry.addPaymentToken(address(paymentToken));
        registry.updateEscrowFixedPrice(address(escrow));
        registry.updateEscrowMilestone(address(escrowMilestone));
        registry.updateEscrowHourly(address(escrowHourly));
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

        escrow.initialize(address(client), address(owner), address(registry));

        factory = new EscrowFactory(address(registry), owner);
    }

    function test_setUpState() public view {
        assertTrue(escrow.initialized());
        assertTrue(address(factory).code.length > 0);
        assertFalse(factory.paused());
        assertEq(factory.owner(), address(owner));
        assertEq(address(factory.registry()), address(registry));
    }

    function test_deployFactory_reverts() public {
        vm.expectRevert(IEscrowFactory.Factory__ZeroAddressProvided.selector);
        new EscrowFactory(address(0), owner);
        vm.expectRevert(IEscrowFactory.Factory__ZeroAddressProvided.selector);
        new EscrowFactory(address(0), address(0));
        vm.expectRevert(IEscrowFactory.Factory__ZeroAddressProvided.selector);
        new EscrowFactory(address(registry), address(0));
    }

    // helper
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

    function test_deployEscrow() public returns (address deployedEscrowProxy) {
        assertEq(factory.factoryNonce(client), 0);
        escrowType = Enums.EscrowType.FIXED_PRICE;
        vm.startPrank(client);
        vm.expectEmit(true, true, false, false);
        emit EscrowProxyDeployed(client, deployedEscrowProxy, escrowType);
        deployedEscrowProxy = factory.deployEscrow(escrowType, client, address(adminManager), address(registry));
        vm.stopPrank();
        EscrowFixedPrice escrowProxy = EscrowFixedPrice(address(deployedEscrowProxy));
        assertEq(escrowProxy.client(), client);
        assertEq(address(escrowProxy.adminManager()), address(adminManager));
        assertEq(address(escrowProxy.registry()), address(registry));
        assertEq(escrowProxy.getCurrentContractId(), 0);
        assertTrue(escrowProxy.initialized());
        assertEq(factory.factoryNonce(client), 1);
        assertTrue(factory.existingEscrow(address(escrowProxy)));
    }

    function test_deploy_and_deposit() public returns (EscrowFixedPrice escrowProxy) {
        vm.startPrank(client);
        // 1. deploy
        address deployedEscrowProxy = factory.deployEscrow(escrowType, client, address(adminManager), address(registry));
        escrowProxy = EscrowFixedPrice(address(deployedEscrowProxy));
        assertEq(escrowProxy.client(), client);
        assertEq(address(escrowProxy.adminManager()), address(adminManager));
        assertEq(address(escrowProxy.registry()), address(registry));
        assertEq(escrowProxy.getCurrentContractId(), 0);
        assertTrue(escrowProxy.initialized());
        assertEq(factory.factoryNonce(client), 1);
        assertTrue(factory.existingEscrow(address(escrowProxy)));
        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL);
        // 2. mint, approve payment token
        paymentToken.mint(address(client), totalDepositAmount);
        paymentToken.approve(address(escrowProxy), totalDepositAmount);
        // 3. deposit
        escrowProxy.deposit(deposit);
        uint256 currentContractId = escrowProxy.getCurrentContractId();
        assertEq(currentContractId, 1);
        assertEq(paymentToken.balanceOf(address(escrowProxy)), totalDepositAmount);
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
        ) = escrowProxy.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 0); //Enums.Enums.FeeConfig.CLIENT_COVERS_ALL
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.stopPrank();
    }

    function test_deposit_next() public {
        EscrowFixedPrice escrowProxy = test_deploy_and_deposit();

        EscrowFixedPrice.Deposit memory deposit2 = IEscrowFixedPrice.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 2 ether,
            amountToClaim: 0.5 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.NO_FEES,
            status: Enums.Status.ACTIVE
        });

        (uint256 totalDepositAmount,) = _computeDepositAndFeeAmount(client, 2 ether, Enums.FeeConfig.NO_FEES);

        vm.startPrank(address(this));
        paymentToken.mint(address(this), totalDepositAmount);
        paymentToken.approve(address(escrowProxy), totalDepositAmount);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrowProxy.deposit(deposit2);
        vm.stopPrank();

        uint256 escrowBalanceBefore = paymentToken.balanceOf(address(escrowProxy));

        vm.startPrank(client);
        paymentToken.mint(address(client), totalDepositAmount);
        paymentToken.approve(address(escrowProxy), totalDepositAmount);
        escrowProxy.deposit(deposit2);
        uint256 currentContractId = escrowProxy.getCurrentContractId();
        assertEq(currentContractId, 2);
        assertEq(paymentToken.balanceOf(address(escrowProxy)), escrowBalanceBefore + totalDepositAmount);
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
        ) = escrowProxy.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_amount, 2 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 3); //Enums.FeeConfig.NO_FEES
        assertEq(uint256(_status), 0); //Status.ACTIVE
        vm.stopPrank();
    }

    function test_deploy_next() public {
        address deployedEscrowProxy = test_deployEscrow();
        EscrowFixedPrice escrowProxy = EscrowFixedPrice(address(deployedEscrowProxy));
        assertEq(escrowProxy.client(), client);
        assertEq(address(escrowProxy.adminManager()), address(adminManager));
        assertEq(address(escrowProxy.registry()), address(registry));
        assertEq(escrowProxy.getCurrentContractId(), 0);
        assertTrue(escrowProxy.initialized());
        assertEq(factory.factoryNonce(client), 1);
        assertTrue(factory.existingEscrow(address(escrowProxy)));

        vm.startPrank(client);
        address deployedEscrowProxy2 =
            factory.deployEscrow(escrowType, client, address(adminManager), address(registry));
        EscrowFixedPrice escrowProxy2 = EscrowFixedPrice(address(deployedEscrowProxy2));
        assertEq(escrowProxy2.client(), client);
        assertEq(address(escrowProxy2.adminManager()), address(adminManager));
        assertEq(address(escrowProxy2.registry()), address(registry));
        assertEq(escrowProxy2.getCurrentContractId(), 0);
        assertTrue(escrowProxy2.initialized());
        assertEq(factory.factoryNonce(client), 2);
        assertTrue(factory.existingEscrow(address(escrowProxy2)));
        assertNotEq(address(deployedEscrowProxy2), address(deployedEscrowProxy));
        vm.stopPrank();
    }

    function test_deploy_and_deposit_milestone() public {
        address deployedEscrowProxy;
        escrowType = Enums.EscrowType.MILESTONE;
        // 1. deploy
        vm.startPrank(client);
        vm.expectEmit(true, true, false, false);
        emit EscrowProxyDeployed(client, deployedEscrowProxy, escrowType);
        deployedEscrowProxy = factory.deployEscrow(escrowType, client, address(adminManager), address(registry));

        EscrowMilestone escrowProxy = EscrowMilestone(address(deployedEscrowProxy));
        assertEq(escrowProxy.client(), client);
        assertEq(address(escrowProxy.adminManager()), address(adminManager));
        assertEq(address(escrowProxy.registry()), address(registry));
        assertEq(escrowProxy.getCurrentContractId(), 0);
        assertTrue(escrowProxy.initialized());
        assertEq(factory.factoryNonce(client), 1);
        assertTrue(factory.existingEscrow(address(escrowProxy)));

        // 2. mint, approve payment token
        uint256 depositMilestoneAmount = 1 ether;
        (uint256 totalDepositMilestoneAmount,) =
            _computeDepositAndFeeAmount(client, depositMilestoneAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        paymentToken.mint(address(client), totalDepositMilestoneAmount);
        paymentToken.approve(address(escrowProxy), totalDepositMilestoneAmount);

        // 3. deposit
        IEscrowMilestone.Deposit[] memory deposits = new IEscrowMilestone.Deposit[](1);
        deposits[0] = IEscrowMilestone.Deposit({
            contractor: contractor,
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.ACTIVE
        });

        uint256 currentContractId = escrowProxy.getCurrentContractId();
        assertEq(currentContractId, 0);
        escrowProxy.deposit(currentContractId, address(paymentToken), deposits);
        assertEq(paymentToken.balanceOf(address(escrowProxy)), totalDepositMilestoneAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        vm.stopPrank();
        currentContractId = escrowProxy.getCurrentContractId();
        assertEq(currentContractId, 1);
        uint256 milestoneId = escrowProxy.getMilestoneCount(currentContractId);

        (
            address _contractor,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            bytes32 _contractorData,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrowProxy.contractMilestones(currentContractId, --milestoneId);
        assertEq(_contractor, contractor);
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 0); //Status.ACTIVE
    }

    function test_deploy_and_deposit_hourly() public {
        address deployedEscrowProxy;
        escrowType = Enums.EscrowType.HOURLY;
        vm.startPrank(client);
        vm.expectRevert(IEscrowFactory.Factory__InvalidEscrowType.selector);
        deployedEscrowProxy =
            factory.deployEscrow(Enums.EscrowType.INVALID, client, address(adminManager), address(registry));
        vm.expectEmit(true, true, false, false);
        emit EscrowProxyDeployed(client, deployedEscrowProxy, escrowType);
        deployedEscrowProxy = factory.deployEscrow(escrowType, client, address(adminManager), address(registry));

        EscrowHourly escrowProxyHourly = EscrowHourly(address(deployedEscrowProxy));
        assertEq(escrowProxyHourly.client(), client);
        assertEq(address(escrowProxyHourly.adminManager()), address(adminManager));
        assertEq(address(escrowProxyHourly.registry()), address(registry));
        assertEq(escrowProxyHourly.getCurrentContractId(), 0);
        assertTrue(escrowProxyHourly.initialized());
        assertEq(factory.factoryNonce(client), 1);
        assertTrue(factory.existingEscrow(address(escrowProxyHourly)));

        // 2. mint, approve payment token
        uint256 depositHourlyAmount = 1 ether;
        (uint256 totalDepositHourlyAmount,) =
            _computeDepositAndFeeAmount(client, depositHourlyAmount, Enums.FeeConfig.CLIENT_COVERS_ONLY);
        paymentToken.mint(address(client), totalDepositHourlyAmount);
        paymentToken.approve(address(escrowProxyHourly), totalDepositHourlyAmount);

        // 3. deposit
        depositHourly = IEscrowHourly.Deposit({
            contractor: contractor,
            amountToClaim: 0,
            amountToWithdraw: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY
        });

        uint256 currentContractId = escrowProxyHourly.getCurrentContractId();
        assertEq(currentContractId, 0);

        escrowProxyHourly.deposit(currentContractId, address(paymentToken), depositHourlyAmount, depositHourly);
        assertEq(paymentToken.balanceOf(address(escrowProxyHourly)), totalDepositHourlyAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        vm.stopPrank();

        currentContractId = escrowProxyHourly.getCurrentContractId();
        assertEq(currentContractId, 1);
        (address _paymentToken, uint256 _prepaymentAmount, Enums.Status _status) =
            escrowProxyHourly.contractDetails(currentContractId); //currentContractId
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(uint256(_status), 0); //Status.ACTIVE
        (address _contractor, uint256 _amountToClaim, uint256 _amountToWithdraw, Enums.FeeConfig _feeConfig) =
            escrowProxyHourly.contractWeeks(currentContractId, 0);
        assertEq(_contractor, contractor);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(escrowProxyHourly.getWeeksCount(currentContractId), 1);
    }

    function test_getEscrowImplementation() public {
        assertEq(factory.getEscrowImplementation(Enums.EscrowType.FIXED_PRICE), registry.escrowFixedPrice());
        assertEq(factory.getEscrowImplementation(Enums.EscrowType.MILESTONE), registry.escrowMilestone());
        assertEq(factory.getEscrowImplementation(Enums.EscrowType.HOURLY), registry.escrowHourly());
        assertNotEq(factory.getEscrowImplementation(Enums.EscrowType.FIXED_PRICE), registry.escrowHourly());

        vm.expectRevert(IEscrowFactory.Factory__InvalidEscrowType.selector);
        factory.getEscrowImplementation(Enums.EscrowType.INVALID);
    }

    function test_updateRegistry() public {
        assertEq(address(factory.registry()), address(registry));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        factory.updateRegistry(address(registry));
        vm.startPrank(address(owner));
        vm.expectRevert(IEscrowFactory.Factory__ZeroAddressProvided.selector);
        factory.updateRegistry(address(0));
        assertEq(address(factory.registry()), address(registry));
        EscrowRegistry newRegistry = new EscrowRegistry(owner);
        vm.expectEmit(true, false, false, true);
        emit RegistryUpdated(address(newRegistry));
        factory.updateRegistry(address(newRegistry));
        assertEq(address(factory.registry()), address(newRegistry));
        vm.stopPrank();
    }

    function test_pause_unpause() public {
        assertFalse(factory.paused());
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        factory.pause();
        assertFalse(factory.paused());
        vm.startPrank(client);
        address deployedEscrowProxy = factory.deployEscrow(escrowType, client, owner, address(registry));
        vm.stopPrank();
        assertTrue(address(deployedEscrowProxy).code.length > 0);
        vm.startPrank(owner);
        vm.expectEmit(true, false, false, true);
        emit Paused(address(owner));
        factory.pause();
        assertTrue(factory.paused());
        vm.expectRevert(Pausable.EnforcedPause.selector);
        address deployedEscrowProxy2 = factory.deployEscrow(escrowType, client, owner, address(registry));
        assertTrue(address(deployedEscrowProxy2).code.length == 0);
        vm.stopPrank();
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        factory.unpause();
        vm.prank(address(owner));
        vm.expectEmit(true, false, false, true);
        emit Unpaused(address(owner));
        factory.unpause();
        assertFalse(factory.paused());
        vm.prank(client);
        deployedEscrowProxy2 = factory.deployEscrow(escrowType, client, owner, address(registry));
        assertTrue(address(deployedEscrowProxy2).code.length > 0);
    }
}
