// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {EscrowFactory, IEscrowFactory, Owned, Pausable} from "src/EscrowFactory.sol";
import {Escrow, IEscrow} from "src/Escrow.sol";
import {Registry, IRegistry} from "src/Registry.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract EscrowFactoryUnitTest is Test {
    EscrowFactory public factory;
    Escrow public escrow;
    Registry public registry;
    ERC20Mock public paymentToken;

    address public client;
    address public treasury;
    address public admin;
    address public contractor;

    Escrow.Deposit public deposit;
    FeeConfig public feeConfig;
    Status public status;

    bytes32 public contractorData;
    bytes32 public salt;
    bytes public contractData;

    struct Deposit {
        address contractor;
        address paymentToken;
        uint256 amount;
        uint256 amountToClaim;
        uint256 timeLock;
        bytes32 contractorData;
        FeeConfig feeConfig;
        Status status;
    }

    enum FeeConfig {
        FULL,
        ONLY_CLIENT,
        ONLY_CONTRACTOR,
        FREE
    }

    enum Status {
        PENDING,
        SUBMITTED,
        APPROVED
    }

    event EscrowProxyDeployed(address sender, address deployedProxy);

    event RegistryUpdated(address registry);

    event Paused(address account);

    event Unpaused(address account);

    function setUp() public {
        client = makeAddr("client");
        treasury = makeAddr("treasury");
        admin = makeAddr("admin");
        contractor = makeAddr("contractor");
        escrow = new Escrow();
        registry = new Registry();
        paymentToken = new ERC20Mock();
        registry.addPaymentToken(address(paymentToken));
        registry.updateEscrow(address(escrow));

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
            feeConfig: IEscrow.FeeConfig.FULL,
            status: IEscrow.Status.PENDING
        });

        escrow.initialize(address(this), treasury, address(this), address(registry), 5_00, 7_00);

        factory = new EscrowFactory(address(registry));
    }

    function test_setUpState() public view {
        assertTrue(escrow.initialized());
        assertTrue(address(factory).code.length > 0);
        assertFalse(factory.paused());
        assertEq(factory.owner(), address(this));
        assertEq(address(factory.registry()), address(registry));
    }

    function test_deployEscrow() public returns (address deployedEscrowProxy)  {
        vm.startPrank(client);
        vm.expectEmit(true, true, false, false);
        emit EscrowProxyDeployed(client, deployedEscrowProxy);
        deployedEscrowProxy = factory.deployEscrow(client, treasury, admin, address(registry), 3_00, 8_00);
        vm.stopPrank();
        Escrow escrowProxy = Escrow(address(deployedEscrowProxy));
        assertEq(escrowProxy.client(), client);
        assertEq(escrowProxy.treasury(), treasury);
        assertEq(escrowProxy.admin(), admin);
        assertEq(address(escrowProxy.registry()), address(registry));
        assertEq(escrowProxy.feeClient(), 3_00);
        assertEq(escrowProxy.feeContractor(), 8_00);
        assertEq(escrowProxy.getCurrentContractId(), 0);
        assertTrue(escrowProxy.initialized());
        assertEq(factory.factoryNonce(client), 1);
        assertTrue(factory.existingEscrow(address(escrowProxy)));
    }

    function test_deploy_and_deposit() public returns (Escrow escrowProxy) {
        vm.startPrank(client);
        // 1. deploy
        address deployedEscrowProxy = factory.deployEscrow(client, treasury, admin, address(registry), 3_00, 8_00);
        escrowProxy = Escrow(address(deployedEscrowProxy));
        assertEq(escrowProxy.client(), client);
        assertEq(escrowProxy.treasury(), treasury);
        assertEq(escrowProxy.admin(), admin);
        assertEq(address(escrowProxy.registry()), address(registry));
        assertEq(escrowProxy.feeClient(), 3_00);
        assertEq(escrowProxy.feeContractor(), 8_00);
        assertEq(escrowProxy.getCurrentContractId(), 0);
        assertTrue(escrowProxy.initialized());
        assertEq(factory.factoryNonce(client), 1);
        assertTrue(factory.existingEscrow(address(escrowProxy)));
        // 2. mint, approve payment token
        paymentToken.mint(address(client), 1.11 ether);
        paymentToken.approve(address(escrowProxy), 1.11 ether);
        // 3. deposit
        escrowProxy.deposit(deposit);
        uint256 currentContractId = escrowProxy.getCurrentContractId();
        assertEq(currentContractId, 1);
        assertEq(paymentToken.balanceOf(address(escrowProxy)), 1 ether);
        assertEq(paymentToken.balanceOf(address(treasury)), 0.11 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (
            address _contractor,
            address _paymentToken,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _timeLock,
            bytes32 _contractorData,
            IEscrow.FeeConfig _feeConfig,
            IEscrow.Status _status
        ) = escrowProxy.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_timeLock, 0);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 0); //IEscrow.FeeConfig.FULL
        assertEq(uint256(_status), 0); //Status.PENDING
        vm.stopPrank();
    }

    function test_deposit_next() public {
        Escrow escrowProxy = test_deploy_and_deposit();

        Escrow.Deposit memory deposit2 = IEscrow.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 2 ether,
            amountToClaim: 0.5 ether,
            timeLock: 0,
            contractorData: contractorData,
            feeConfig: IEscrow.FeeConfig.FREE,
            status: IEscrow.Status.PENDING
        });

        vm.startPrank(address(this));
        paymentToken.mint(address(this), 2 ether);
        paymentToken.approve(address(escrowProxy), 2 ether);
        vm.expectRevert(); //Escrow__UnauthorizedAccount(msg.sender)
        escrowProxy.deposit(deposit2);
        vm.stopPrank();

        vm.startPrank(client);
        paymentToken.mint(address(client), 2 ether);
        paymentToken.approve(address(escrowProxy), 2 ether);
        escrowProxy.deposit(deposit2);
        uint256 currentContractId = escrowProxy.getCurrentContractId();
        assertEq(currentContractId, 2);
        assertEq(paymentToken.balanceOf(address(escrowProxy)), 1 ether + 2 ether);
        assertEq(paymentToken.balanceOf(address(client)), 0 ether);
        (
            address _contractor,
            address _paymentToken,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _timeLock,
            bytes32 _contractorData,
            IEscrow.FeeConfig _feeConfig,
            IEscrow.Status _status
        ) = escrowProxy.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_amount, 2 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_timeLock, 0);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 3); //IEscrow.FeeConfig.FREE
        assertEq(uint256(_status), 0); //Status.PENDING
        vm.stopPrank();
    }

    function test_deploy_next() public {
        address deployedEscrowProxy = test_deployEscrow();
        Escrow escrowProxy = Escrow(address(deployedEscrowProxy));
        assertEq(escrowProxy.client(), client);
        assertEq(escrowProxy.treasury(), treasury);
        assertEq(escrowProxy.admin(), admin);
        assertEq(address(escrowProxy.registry()), address(registry));
        assertEq(escrowProxy.feeClient(), 3_00);
        assertEq(escrowProxy.feeContractor(), 8_00);
        assertEq(escrowProxy.getCurrentContractId(), 0);
        assertTrue(escrowProxy.initialized());
        assertEq(factory.factoryNonce(client), 1);
        assertTrue(factory.existingEscrow(address(escrowProxy)));

        vm.startPrank(client);
        address deployedEscrowProxy2 = factory.deployEscrow(client, treasury, admin, address(registry), 5_00, 10_00);
        Escrow escrowProxy2 = Escrow(address(deployedEscrowProxy2));
        assertEq(escrowProxy2.client(), client);
        assertEq(escrowProxy2.treasury(), treasury);
        assertEq(escrowProxy2.admin(), admin);
        assertEq(address(escrowProxy2.registry()), address(registry));
        assertEq(escrowProxy2.feeClient(), 5_00);
        assertEq(escrowProxy2.feeContractor(), 10_00);
        assertEq(escrowProxy2.getCurrentContractId(), 0);
        assertTrue(escrowProxy2.initialized());
        assertEq(factory.factoryNonce(client), 2);
        assertTrue(factory.existingEscrow(address(escrowProxy2)));
        assertNotEq(address(deployedEscrowProxy2), address(deployedEscrowProxy));
        vm.stopPrank();
    }

    function test_updateRegistry() public {
        assertEq(address(factory.registry()), address(registry));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(Owned.Owned__Unauthorized.selector);
        factory.updateRegistry(address(registry));
        vm.startPrank(address(this));
        vm.expectRevert(IEscrowFactory.Factory__ZeroAddressProvided.selector);
        factory.updateRegistry(address(0));
        assertEq(address(factory.registry()), address(registry));
        Registry newRegistry = new Registry();
        vm.expectEmit(true, false, false, true);
        emit RegistryUpdated(address(newRegistry));
        factory.updateRegistry(address(newRegistry));
        assertEq(address(factory.registry()), address(newRegistry));
        vm.stopPrank();
    }

    function test_pause() public {
        assertFalse(factory.paused());
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(Owned.Owned__Unauthorized.selector);
        factory.pause();
        assertFalse(factory.paused());
        vm.startPrank(client);
        address deployedEscrowProxy = factory.deployEscrow(client, treasury, admin, address(registry), 3_00, 8_00);
        vm.stopPrank();
        assertTrue(address(deployedEscrowProxy).code.length > 0);
        vm.expectEmit(true, false, false, true);
        emit Paused(address(this));
        factory.pause();
        assertTrue(factory.paused());
        vm.expectRevert(Pausable.Pausable__Paused.selector);
        address deployedEscrowProxy2 = factory.deployEscrow(client, treasury, admin, address(registry), 3_00, 8_00);
        assertTrue(address(deployedEscrowProxy2).code.length == 0);
        vm.stopPrank();
        vm.prank(notOwner);
        vm.expectRevert(Owned.Owned__Unauthorized.selector);
        factory.unpause();
        vm.prank(address(this));
        vm.expectEmit(true, false, false, true);
        emit Unpaused(address(this));
        factory.unpause();
        assertFalse(factory.paused());
        vm.prank(client);
        deployedEscrowProxy2 = factory.deployEscrow(client, treasury, admin, address(registry), 3_00, 8_00);
        assertTrue(address(deployedEscrowProxy2).code.length > 0);
    }
}