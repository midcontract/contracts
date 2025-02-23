// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test, console2 } from "forge-std/Test.sol";

import { ECDSA } from "@solbase/utils/ECDSA.sol";
import { ERC20Mock } from "@openzeppelin/mocks/token/ERC20Mock.sol";
import { SignatureChecker } from "@openzeppelin/utils/cryptography/SignatureChecker.sol";

import { EscrowAdminManager, OwnedRoles } from "src/modules/EscrowAdminManager.sol";
import { EscrowFactory, IEscrowFactory, OwnedThreeStep, Pausable } from "src/EscrowFactory.sol";
import { EscrowFeeManager, IEscrowFeeManager } from "src/modules/EscrowFeeManager.sol";
import { EscrowFixedPrice, IEscrowFixedPrice } from "src/EscrowFixedPrice.sol";
import { EscrowMilestone, IEscrowMilestone } from "src/EscrowMilestone.sol";
import { EscrowHourly, IEscrowHourly } from "src/EscrowHourly.sol";
import { EscrowRegistry, IEscrowRegistry } from "src/modules/EscrowRegistry.sol";
import { Enums } from "src/common/Enums.sol";
import { MockFailingReceiver } from "test/mocks/MockFailingReceiver.sol";
import { TestUtils } from "test/utils/TestUtils.sol";

contract EscrowFactoryUnitTest is Test, TestUtils {
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
    uint256 ownerPrKey;

    bytes32 contractorData;
    bytes32 salt;
    bytes contractData;
    bytes signature;

    Enums.FeeConfig feeConfig;
    Enums.Status status;
    Enums.EscrowType escrowType;
    IEscrowFixedPrice.DepositRequest deposit;
    IEscrowHourly.DepositRequest depositHourly;
    IEscrowHourly.ContractDetails contractDetails;
    IEscrowMilestone.DepositRequest depositMilestone;

    event EscrowProxyDeployed(address sender, address deployedProxy, Enums.EscrowType escrowType);
    event AdminManagerUpdated(address adminManager);
    event RegistryUpdated(address registry);
    event Paused(address account);
    event Unpaused(address account);
    event ETHWithdrawn(address receiver, uint256 amount);

    function setUp() public {
        (owner, ownerPrKey) = makeAddrAndKey("owner");
        treasury = makeAddr("treasury");
        client = makeAddr("client");
        contractor = makeAddr("contractor");

        escrow = new EscrowFixedPrice();
        escrowMilestone = new EscrowMilestone();
        registry = new EscrowRegistry(owner);
        paymentToken = new ERC20Mock();
        adminManager = new EscrowAdminManager(owner);
        feeManager = new EscrowFeeManager(address(adminManager), 300, 500);
        escrowHourly = new EscrowHourly();

        vm.startPrank(owner);
        registry.addPaymentToken(address(paymentToken));
        registry.updateEscrowFixedPrice(address(escrow));
        registry.updateEscrowMilestone(address(escrowMilestone));
        registry.updateEscrowHourly(address(escrowHourly));
        registry.updateFeeManager(address(feeManager));
        registry.setAdminManager(address(adminManager));
        vm.stopPrank();

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        contractorData = keccak256(abi.encodePacked(contractData, salt));

        escrow.initialize(address(client), address(owner), address(registry));

        factory = new EscrowFactory(address(adminManager), address(registry), owner);
    }

    ///////////////////////////////////////////
    //        setup & functional tests       //
    ///////////////////////////////////////////

    function test_setUpState() public view {
        assertTrue(escrow.initialized());
        assertTrue(address(factory).code.length > 0);
        assertFalse(factory.paused());
        assertEq(address(factory.owner()), owner);
        assertEq(address(factory.adminManager()), address(adminManager));
        assertEq(address(factory.registry()), address(registry));
    }

    function test_deployFactory_reverts() public {
        vm.expectRevert(IEscrowFactory.ZeroAddressProvided.selector);
        new EscrowFactory(address(0), address(registry), address(0));
        vm.expectRevert(IEscrowFactory.ZeroAddressProvided.selector);
        new EscrowFactory(address(0), address(0), address(0));
        vm.expectRevert(IEscrowFactory.ZeroAddressProvided.selector);
        new EscrowFactory(address(adminManager), address(0), address(0));
        vm.expectRevert(IEscrowFactory.ZeroAddressProvided.selector);
        new EscrowFactory(address(0), address(0), address(owner));
    }

    function test_deployEscrow() public returns (address deployedEscrowProxy) {
        assertEq(factory.factoryNonce(client), 0);
        escrowType = Enums.EscrowType.FIXED_PRICE;
        vm.startPrank(client);
        vm.expectEmit(true, true, false, false);
        emit EscrowProxyDeployed(client, deployedEscrowProxy, escrowType);
        deployedEscrowProxy = factory.deployEscrow(escrowType);
        vm.stopPrank();
        EscrowFixedPrice escrowProxy = EscrowFixedPrice(address(deployedEscrowProxy));
        assertEq(escrowProxy.client(), client);
        assertEq(address(escrowProxy.adminManager()), address(adminManager));
        assertEq(address(escrowProxy.registry()), address(registry));
        assertTrue(escrowProxy.initialized());
        assertEq(factory.factoryNonce(client), 1);
        assertTrue(factory.existingEscrow(address(escrowProxy)));
    }

    function test_deploy_and_deposit() public returns (EscrowFixedPrice escrowProxy) {
        vm.startPrank(client);
        // 1. deploy
        address deployedEscrowProxy = factory.deployEscrow(escrowType);
        escrowProxy = EscrowFixedPrice(address(deployedEscrowProxy));
        assertEq(escrowProxy.client(), client);
        assertEq(address(escrowProxy.adminManager()), address(adminManager));
        assertEq(address(escrowProxy.registry()), address(registry));
        assertTrue(escrowProxy.initialized());
        assertEq(factory.factoryNonce(client), 1);
        assertTrue(factory.existingEscrow(address(escrowProxy)));
        (uint256 totalDepositAmount,) = computeDepositAndFeeAmount(
            address(registry), address(escrowProxy), 0, client, 1 ether, Enums.FeeConfig.CLIENT_COVERS_ALL
        );
        // 2. mint, approve payment token
        paymentToken.mint(address(client), totalDepositAmount);
        paymentToken.approve(address(escrowProxy), totalDepositAmount);
        // 3. deposit
        TestUtils.FixedPriceSignatureParams memory params = FixedPriceSignatureParams({
            contractId: 1,
            contractor: address(0),
            proxy: address(escrowProxy),
            token: address(paymentToken),
            amount: 1 ether,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            contractorData: contractorData,
            client: client,
            ownerPrKey: ownerPrKey
        });
        deposit = IEscrowFixedPrice.DepositRequest({
            contractId: 1,
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.ACTIVE,
            escrow: address(escrowProxy),
            expiration: block.timestamp + 3 hours,
            signature: getSignatureFixed(params)
        });

        escrowProxy.deposit(deposit);
        uint256 currentContractId = 1;
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
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.stopPrank();
    }

    function test_deposit_next() public {
        EscrowFixedPrice escrowProxy = test_deploy_and_deposit();

        TestUtils.FixedPriceSignatureParams memory params = FixedPriceSignatureParams({
            contractId: 2,
            contractor: address(0),
            proxy: address(escrowProxy),
            token: address(paymentToken),
            amount: 2 ether,
            feeConfig: Enums.FeeConfig.NO_FEES,
            contractorData: contractorData,
            client: client,
            ownerPrKey: ownerPrKey
        });

        EscrowFixedPrice.DepositRequest memory deposit2 = IEscrowFixedPrice.DepositRequest({
            contractId: 2,
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 2 ether,
            amountToClaim: 0.5 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.NO_FEES,
            status: Enums.Status.ACTIVE,
            escrow: address(escrowProxy),
            expiration: block.timestamp + 3 hours,
            signature: getSignatureFixed(params)
        });

        (uint256 totalDepositAmount,) = computeDepositAndFeeAmount(
            address(registry), address(escrowProxy), 1, client, 2 ether, Enums.FeeConfig.NO_FEES
        );

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
        uint256 currentContractId = 2;
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
        assertEq(uint256(_status), 1); //Status.ACTIVE
        vm.stopPrank();
    }

    function test_deploy_next() public {
        address deployedEscrowProxy = test_deployEscrow();
        EscrowFixedPrice escrowProxy = EscrowFixedPrice(address(deployedEscrowProxy));
        assertEq(escrowProxy.client(), client);
        assertEq(address(escrowProxy.adminManager()), address(adminManager));
        assertEq(address(escrowProxy.registry()), address(registry));
        assertTrue(escrowProxy.initialized());
        assertEq(factory.factoryNonce(client), 1);
        assertTrue(factory.existingEscrow(address(escrowProxy)));

        vm.startPrank(client);
        address deployedEscrowProxy2 = factory.deployEscrow(escrowType);
        EscrowFixedPrice escrowProxy2 = EscrowFixedPrice(address(deployedEscrowProxy2));
        assertEq(escrowProxy2.client(), client);
        assertEq(address(escrowProxy2.adminManager()), address(adminManager));
        assertEq(address(escrowProxy2.registry()), address(registry));
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
        deployedEscrowProxy = factory.deployEscrow(escrowType);

        EscrowMilestone escrowProxy = EscrowMilestone(address(deployedEscrowProxy));
        assertEq(escrowProxy.client(), client);
        assertEq(address(escrowProxy.adminManager()), address(adminManager));
        assertEq(address(escrowProxy.registry()), address(registry));
        assertTrue(escrowProxy.initialized());
        assertEq(factory.factoryNonce(client), 1);
        assertTrue(factory.existingEscrow(address(escrowProxy)));

        // 2. mint, approve payment token
        uint256 depositMilestoneAmount = 1 ether;
        (uint256 totalDepositMilestoneAmount,) = computeDepositAndFeeAmount(
            address(registry),
            address(escrowProxy),
            1,
            client,
            depositMilestoneAmount,
            Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        paymentToken.mint(address(client), totalDepositMilestoneAmount);
        paymentToken.approve(address(escrowProxy), totalDepositMilestoneAmount);

        // 3. deposit
        IEscrowMilestone.Milestone[] memory milestones = new IEscrowMilestone.Milestone[](1);
        milestones[0] = IEscrowMilestone.Milestone({
            contractor: contractor,
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.ACTIVE
        });

        uint256 currentContractId = 1;
        bytes32 milestonesHash = hashMilestones(milestones);
        TestUtils.MilestoneSignatureParams memory milestoneInput = MilestoneSignatureParams({
            proxy: address(escrowProxy),
            client: client,
            contractId: currentContractId,
            token: address(paymentToken),
            milestonesHash: milestonesHash,
            ownerPrKey: ownerPrKey
        });
        depositMilestone = IEscrowMilestone.DepositRequest({
            contractId: currentContractId,
            paymentToken: address(paymentToken),
            milestonesHash: milestonesHash,
            escrow: address(escrowProxy),
            expiration: uint256(block.timestamp + 3 hours),
            signature: getSignatureMilestone(milestoneInput)
        });

        escrowProxy.deposit(depositMilestone, milestones);
        assertEq(paymentToken.balanceOf(address(escrowProxy)), totalDepositMilestoneAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        vm.stopPrank();
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
        assertEq(uint256(_status), 1); //Status.ACTIVE
    }

    function test_deploy_and_deposit_hourly() public {
        address deployedEscrowProxy;
        escrowType = Enums.EscrowType.HOURLY;
        vm.startPrank(client);
        vm.expectRevert(IEscrowFactory.InvalidEscrowType.selector);
        deployedEscrowProxy = factory.deployEscrow(Enums.EscrowType.INVALID);
        vm.expectEmit(true, true, false, false);
        emit EscrowProxyDeployed(client, deployedEscrowProxy, escrowType);
        deployedEscrowProxy = factory.deployEscrow(escrowType);

        EscrowHourly escrowProxyHourly = EscrowHourly(address(deployedEscrowProxy));
        assertEq(escrowProxyHourly.client(), client);
        assertEq(address(escrowProxyHourly.adminManager()), address(adminManager));
        assertEq(address(escrowProxyHourly.registry()), address(registry));
        assertTrue(escrowProxyHourly.initialized());
        assertEq(factory.factoryNonce(client), 1);
        assertTrue(factory.existingEscrow(address(escrowProxyHourly)));

        // 2. mint, approve payment token
        uint256 depositHourlyAmount = 1 ether;
        (uint256 totalDepositHourlyAmount,) = computeDepositAndFeeAmount(
            address(registry),
            address(escrowProxyHourly),
            1,
            client,
            depositHourlyAmount,
            Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        paymentToken.mint(address(client), totalDepositHourlyAmount);
        paymentToken.approve(address(escrowProxyHourly), totalDepositHourlyAmount);

        // 3. deposit
        uint256 currentContractId = 1;
        TestUtils.HourlySignatureParams memory hourlyInput = HourlySignatureParams({
            contractId: currentContractId,
            contractor: contractor,
            proxy: address(escrowProxyHourly),
            token: address(paymentToken),
            prepaymentAmount: depositHourlyAmount,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            client: client,
            ownerPrKey: ownerPrKey
        });
        depositHourly = IEscrowHourly.DepositRequest({
            contractId: currentContractId,
            contractor: contractor,
            paymentToken: address(paymentToken),
            prepaymentAmount: depositHourlyAmount,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrowProxyHourly),
            expiration: uint256(block.timestamp + 3 hours),
            signature: getSignatureHourly(hourlyInput)
        });

        assertFalse(escrowProxyHourly.contractExists(currentContractId));

        escrowProxyHourly.deposit(depositHourly);
        assertEq(paymentToken.balanceOf(address(escrowProxyHourly)), totalDepositHourlyAmount);
        assertEq(paymentToken.balanceOf(address(treasury)), 0 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        assertTrue(escrowProxyHourly.contractExists(currentContractId));
        vm.stopPrank();

        (
            address _contractor,
            address _paymentToken,
            uint256 _prepaymentAmount,
            uint256 _amountToWithdraw,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrowProxyHourly.contractDetails(currentContractId);
        assertEq(_contractor, contractor);
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_prepaymentAmount, 1 ether);
        assertEq(_amountToWithdraw, 0 ether);
        assertEq(uint256(_feeConfig), 1); //Enums.Enums.FeeConfig.CLIENT_COVERS_ONLY
        assertEq(uint256(_status), 1); //Status.ACTIVE
        (uint256 _amountToClaim, Enums.Status _weekStatus) = escrowProxyHourly.weeklyEntries(currentContractId, 0);
        assertEq(_amountToClaim, 0 ether);
        assertEq(uint256(_weekStatus), 1); //Status.ACTIVE
        assertEq(escrowProxyHourly.getWeeksCount(currentContractId), 1);
    }

    function test_getEscrowImplementation() public {
        assertEq(factory.getEscrowImplementation(Enums.EscrowType.FIXED_PRICE), registry.escrowFixedPrice());
        assertEq(factory.getEscrowImplementation(Enums.EscrowType.MILESTONE), registry.escrowMilestone());
        assertEq(factory.getEscrowImplementation(Enums.EscrowType.HOURLY), registry.escrowHourly());
        assertNotEq(factory.getEscrowImplementation(Enums.EscrowType.FIXED_PRICE), registry.escrowHourly());

        vm.expectRevert(IEscrowFactory.InvalidEscrowType.selector);
        factory.getEscrowImplementation(Enums.EscrowType.INVALID);
    }

    function test_setAdminManager() public {
        assertEq(address(factory.adminManager()), address(adminManager));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        factory.updateAdminManager(address(adminManager));
        vm.startPrank(address(owner));
        vm.expectRevert(IEscrowFactory.ZeroAddressProvided.selector);
        factory.updateAdminManager(address(0));
        assertEq(address(factory.adminManager()), address(adminManager));
        EscrowAdminManager newAdminManager = new EscrowAdminManager(owner);
        vm.expectEmit(true, false, false, true);
        emit AdminManagerUpdated(address(newAdminManager));
        factory.updateAdminManager(address(newAdminManager));
        assertEq(address(factory.adminManager()), address(newAdminManager));
        vm.stopPrank();
    }

    function test_updateRegistry() public {
        assertEq(address(factory.registry()), address(registry));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        factory.updateRegistry(address(registry));
        vm.startPrank(address(owner));
        vm.expectRevert(IEscrowFactory.ZeroAddressProvided.selector);
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
        address deployedEscrowProxy = factory.deployEscrow(escrowType);
        vm.stopPrank();
        assertTrue(address(deployedEscrowProxy).code.length > 0);
        vm.startPrank(owner);
        vm.expectEmit(true, false, false, true);
        emit Paused(address(owner));
        factory.pause();
        assertTrue(factory.paused());
        vm.expectRevert(Pausable.EnforcedPause.selector);
        address deployedEscrowProxy2 = factory.deployEscrow(escrowType);
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
        deployedEscrowProxy2 = factory.deployEscrow(escrowType);
        assertTrue(address(deployedEscrowProxy2).code.length > 0);
    }

    function test_withdraw_eth() public {
        vm.deal(address(factory), 10 ether);
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(OwnedThreeStep.Unauthorized.selector);
        factory.withdrawETH(notOwner);
        vm.startPrank(owner);
        vm.expectRevert(IEscrowFactory.ZeroAddressProvided.selector);
        factory.withdrawETH(address(0));
        vm.expectEmit(true, false, false, true);
        emit ETHWithdrawn(owner, 10 ether);
        factory.withdrawETH(owner);
        assertEq(owner.balance, 10 ether, "Receiver did not receive the correct amount of ETH");
        assertEq(address(factory).balance, 0, "Factory contract balance should be zero");
        vm.deal(address(factory), 10 ether);
        MockFailingReceiver failingReceiver = new MockFailingReceiver();
        vm.expectRevert(IEscrowFactory.ETHTransferFailed.selector);
        factory.withdrawETH(address(failingReceiver));
        vm.stopPrank();
    }
}
