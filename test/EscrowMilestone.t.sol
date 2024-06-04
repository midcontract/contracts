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
        deposits.push(IEscrowMilestone.Deposit({
            contractor: address(0),
            paymentToken: address(paymentToken),
            amount: 1 ether,
            amountToClaim: 0,
            amountToWithdraw: 0,
            timeLock: 0,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.ACTIVE
        }));
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

}