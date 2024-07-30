// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {EscrowFixedPrice, IEscrowFixedPrice} from "src/EscrowFixedPrice.sol";
import {EscrowAccountRecovery} from "src/modules/EscrowAccountRecovery.sol";
import {EscrowFeeManager, IEscrowFeeManager} from "src/modules/EscrowFeeManager.sol";
import {EscrowRegistry, IEscrowRegistry} from "src/modules/EscrowRegistry.sol";
import {Enums} from "src/libs/Enums.sol";

contract EscrowAccountRecoveryUnitTest is Test {
    EscrowAccountRecovery recovery;
    EscrowFixedPrice escrow;
    EscrowRegistry registry;
    ERC20Mock paymentToken;
    EscrowFeeManager feeManager;

    address owner;
    address guardian;
    address treasury;
    address client;
    address contractor;
    address new_client;

    bytes contractData;
    bytes32 contractorData;
    bytes32 salt;

    EscrowFixedPrice.Deposit deposit;
    EscrowAccountRecovery.RecoveryData recoveryInfo;

    event RecoveryInitiated(address indexed sender, bytes32 indexed recoveryHash);

    function setUp() public {
        owner = makeAddr("owner");
        guardian = makeAddr("guardian");
        treasury = makeAddr("treasury");
        client = makeAddr("client");
        contractor = makeAddr("contractor");
        new_client = makeAddr("new_client");

        recovery = new EscrowAccountRecovery(owner, guardian);
        escrow = new EscrowFixedPrice();
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

        deposit = IEscrowFixedPrice.Deposit({
            contractor: contractor,
            paymentToken: address(paymentToken),
            amount: 1 ether,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.ACTIVE
        });
    }

    function test_setUpState() public view {
        assertTrue(address(recovery).code.length > 0);
        assertEq(recovery.owner(), address(owner));
        assertEq(recovery.guardian(), address(guardian));
        assertEq(recovery.MIN_RECOVERY_PERIOD(), 3 days);
    }

    // helpers
    function initializeEscrowFixedPrice() public {
        assertFalse(escrow.initialized());
        escrow.initialize(client, owner, address(registry));
        assertTrue(escrow.initialized());
        uint256 depositAmount = 1.03 ether;
        vm.startPrank(address(client));
        paymentToken.mint(address(client), depositAmount);
        paymentToken.approve(address(escrow), depositAmount);
        escrow.deposit(deposit);
        vm.stopPrank();
    }

    function getRecoveryHash(address escrow, address oldAccount, address newAccount) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(escrow, oldAccount, newAccount));
    }

    function test_initiateRecovery() public {
        initializeEscrowFixedPrice();
        uint256 contractId = escrow.getCurrentContractId();
        Enums.EscrowType escrowType = Enums.EscrowType.FIXED_PRICE;
        bytes32 recoveryHash = getRecoveryHash(address(escrow), client, new_client);

        vm.prank(guardian);
        vm.expectEmit(true, false, false, true);
        emit RecoveryInitiated(guardian, recoveryHash);
        recovery.initiateRecovery(address(escrow), contractId, 0, client, new_client, escrowType);
        (
            address _escrow,
            address _oldAccount,
            uint256 _contractId,
            uint256 _milestoneId,
            uint256 _executeAfter,
            bool _executed,
            bool _confirmed,
            Enums.EscrowType _escrowType
        ) = recovery.recoveryData(recoveryHash);
        assertEq(_escrow, address(escrow));
        assertEq(_oldAccount, client);
        assertEq(_contractId, contractId);
        assertEq(_milestoneId, 0);
        assertEq(_executeAfter, block.timestamp + 3 days);
        assertFalse(_executed);
        assertTrue(_confirmed);
        assertEq(uint256(_escrowType), 0);
    }
}
