// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {Escrow, IEscrow} from "src/Escrow.sol";
import {EscrowFactory, IEscrowFactory, Ownable, Pausable} from "src/EscrowFactory.sol";
import {EscrowFeeManager, IEscrowFeeManager} from "src/modules/EscrowFeeManager.sol";
import {Enums} from "src/libs/Enums.sol";
import {Registry, IRegistry} from "src/modules/Registry.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract EscrowFactoryUnitTest is Test {
    EscrowFactory factory;
    Escrow escrow;
    Registry registry;
    ERC20Mock paymentToken;
    EscrowFeeManager feeManager;

    address client;
    address contractor;
    address treasury;
    address owner;

    Escrow.Deposit deposit;
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
        uint256 timeLock;
        bytes32 contractorData;
        Enums.FeeConfig feeConfig;
        Enums.Status status;
    }

    event EscrowProxyDeployed(address sender, address deployedProxy);
    event RegistryUpdated(address registry);
    event Paused(address account);
    event Unpaused(address account);

    function setUp() public {
        owner = makeAddr("owner");
        treasury = makeAddr("treasury");
        client = makeAddr("client");
        contractor = makeAddr("contractor");
        
        escrow = new Escrow();
        registry = new Registry(owner);
        paymentToken = new ERC20Mock();
        feeManager = new EscrowFeeManager(3_00, 5_00, owner);
        vm.startPrank(owner);
        registry.addPaymentToken(address(paymentToken));
        registry.updateEscrow(address(escrow));
        registry.updateFeeManager(address(feeManager));
        vm.stopPrank();

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
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.PENDING
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
        vm.startPrank(client);
        vm.expectEmit(true, true, false, false);
        emit EscrowProxyDeployed(client, deployedEscrowProxy);
        deployedEscrowProxy = factory.deployEscrow(client, owner, address(registry));
        vm.stopPrank();
        Escrow escrowProxy = Escrow(address(deployedEscrowProxy));
        assertEq(escrowProxy.client(), client);
        assertEq(escrowProxy.owner(), owner);
        assertEq(address(escrowProxy.registry()), address(registry));
        assertEq(escrowProxy.getCurrentContractId(), 0);
        assertTrue(escrowProxy.initialized());
        assertEq(factory.factoryNonce(client), 1);
        assertTrue(factory.existingEscrow(address(escrowProxy)));
    }

    function test_deploy_and_deposit() public returns (Escrow escrowProxy) {
        vm.startPrank(client);
        // 1. deploy
        address deployedEscrowProxy = factory.deployEscrow(client, owner, address(registry));
        escrowProxy = Escrow(address(deployedEscrowProxy));
        assertEq(escrowProxy.client(), client);
        assertEq(escrowProxy.owner(), owner);
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
            uint256 _timeLock,
            bytes32 _contractorData,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrowProxy.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_amount, 1 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_timeLock, 0);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 0); //Enums.Enums.FeeConfig.CLIENT_COVERS_ALL
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
            feeConfig: Enums.FeeConfig.NO_FEES,
            status: Enums.Status.PENDING
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
            uint256 _timeLock,
            bytes32 _contractorData,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = escrowProxy.deposits(currentContractId);
        assertEq(_contractor, address(0));
        assertEq(address(_paymentToken), address(paymentToken));
        assertEq(_amount, 2 ether);
        assertEq(_amountToClaim, 0 ether);
        assertEq(_timeLock, 0);
        assertEq(_contractorData, contractorData);
        assertEq(uint256(_feeConfig), 3); //Enums.FeeConfig.NO_FEES
        assertEq(uint256(_status), 0); //Status.PENDING
        vm.stopPrank();
    }

    function test_deploy_next() public {
        address deployedEscrowProxy = test_deployEscrow();
        Escrow escrowProxy = Escrow(address(deployedEscrowProxy));
        assertEq(escrowProxy.client(), client);
        assertEq(escrowProxy.owner(), owner);
        assertEq(address(escrowProxy.registry()), address(registry));
        assertEq(escrowProxy.getCurrentContractId(), 0);
        assertTrue(escrowProxy.initialized());
        assertEq(factory.factoryNonce(client), 1);
        assertTrue(factory.existingEscrow(address(escrowProxy)));

        vm.startPrank(client);
        address deployedEscrowProxy2 = factory.deployEscrow(client, owner, address(registry));
        Escrow escrowProxy2 = Escrow(address(deployedEscrowProxy2));
        assertEq(escrowProxy2.client(), client);
        assertEq(escrowProxy2.owner(), owner);
        assertEq(address(escrowProxy2.registry()), address(registry));
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
        vm.expectRevert(Ownable.Unauthorized.selector);
        factory.updateRegistry(address(registry));
        vm.startPrank(address(owner));
        vm.expectRevert(IEscrowFactory.Factory__ZeroAddressProvided.selector);
        factory.updateRegistry(address(0));
        assertEq(address(factory.registry()), address(registry));
        Registry newRegistry = new Registry(owner);
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
        vm.expectRevert(Ownable.Unauthorized.selector);
        factory.pause();
        assertFalse(factory.paused());
        vm.startPrank(client);
        address deployedEscrowProxy = factory.deployEscrow(client, owner, address(registry));
        vm.stopPrank();
        assertTrue(address(deployedEscrowProxy).code.length > 0);
        vm.startPrank(owner);
        vm.expectEmit(true, false, false, true);
        emit Paused(address(owner));
        factory.pause();
        assertTrue(factory.paused());
        vm.expectRevert(Pausable.Pausable__Paused.selector);
        address deployedEscrowProxy2 = factory.deployEscrow(client, owner, address(registry));
        assertTrue(address(deployedEscrowProxy2).code.length == 0);
        vm.stopPrank();
        vm.prank(notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        factory.unpause();
        vm.prank(address(owner));
        vm.expectEmit(true, false, false, true);
        emit Unpaused(address(owner));
        factory.unpause();
        assertFalse(factory.paused());
        vm.prank(client);
        deployedEscrowProxy2 = factory.deployEscrow(client, owner, address(registry));
        assertTrue(address(deployedEscrowProxy2).code.length > 0);
    }
}
