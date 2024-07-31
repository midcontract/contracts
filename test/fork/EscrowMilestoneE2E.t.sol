// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {EscrowMilestone, IEscrowMilestone} from "src/EscrowMilestone.sol";
import {EscrowFactory, IEscrowFactory} from "src/EscrowFactory.sol";
import {EscrowRegistry, IEscrowRegistry} from "src/modules/EscrowRegistry.sol";
import {Enums} from "src/libs/Enums.sol";
import {EthSepoliaConfig} from "config/EthSepoliaConfig.sol";
import {PolAmoyConfig} from "config/PolAmoyConfig.sol";
import {MockDAI} from "test/mocks/MockDAI.sol";
import {MockUSDT} from "test/mocks/MockUSDT.sol";

contract ExecuteEscrowMilestoneEndToEndTest is Test {
    EscrowMilestone escrow = EscrowMilestone(PolAmoyConfig.ESCROW_MILESTONE);
    EscrowRegistry registry = EscrowRegistry(PolAmoyConfig.REGISTRY);
    EscrowFactory factory = EscrowFactory(PolAmoyConfig.FACTORY);
    MockDAI daiToken = MockDAI(PolAmoyConfig.MOCK_DAI);
    MockUSDT usdtToken = MockUSDT(PolAmoyConfig.MOCK_USDT);

    address client;
    address contractor;
    address owner;

    // IEscrowMilestone.Deposit deposit;
    Enums.FeeConfig feeConfig;
    Enums.Status status;
    Enums.EscrowType escrowType;
    bytes32 contractorData;
    bytes32 salt;
    bytes contractData;

    struct Deposit {
        address contractor;
        uint256 amount;
        uint256 amountToClaim;
        uint256 amountToWithdraw;
        bytes32 contractorData;
        Enums.FeeConfig feeConfig;
        Enums.Status status;
    }

    IEscrowMilestone.Deposit[] deposits;

    function setUp() public {
        client = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        // clientPrK = vm.envUint("DEPLOYER_PUBLIC_KEY");
        contractor = vm.envAddress("CONTRACTOR_PUBLIC_KEY");
        // contractorPrK = vm.envUint("CONTRACTOR_PRIVATE_KEY");
        owner = vm.envAddress("OWNER_PUBLIC_KEY");
        // adminPrK = vm.envUint("ADMIN_PRIVATE_KEY");

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        contractorData = keccak256(abi.encodePacked(contractData, salt));

        deposits.push(
            IEscrowMilestone.Deposit({
                contractor: address(0),
                amount: 1000e6,
                amountToClaim: 0,
                amountToWithdraw: 0 ether,
                contractorData: contractorData,
                feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
                status: Enums.Status.ACTIVE
            })
        );

        escrowType = Enums.EscrowType.MILESTONE;

        vm.startPrank(client);
        MockUSDT(usdtToken).mint(client, 1030e6);
        vm.stopPrank();
    }

    /// @dev This test verifies the complete flow of creating a deposit in an escrow system using a mocked ERC20 token.
    /// The steps include deploying an escrow proxy, approving a token, and creating a deposit.
    function test_createDeposit() public {
        // Start impersonating the client to perform actions as if they are initiated by the client.
        vm.startPrank(client);

        // Step 1: Deploy their own contract instance to interact with the factory.
        // The client deploys an Escrow contract via the factory specifying fee configurations.
        address deployedEscrowProxy =
            EscrowFactory(factory).deployEscrow(escrowType, address(client), address(owner), address(registry));
        EscrowMilestone escrowProxy = EscrowMilestone(address(deployedEscrowProxy));

        // Step 2: Client approves the payment token with the respective deposit token amount.
        // This approval enables the escrow contract to withdraw tokens from the client's account.
        MockUSDT(usdtToken).approve(address(escrowProxy), 1030e6);

        uint256 contractId = 0; // for newly created contract

        // Step 3: Client creates the first deposit on the deployed instance with contractId == 1.
        // The deposit function call involves transferring funds from the client to the escrow based on the approved amount.
        EscrowMilestone(escrowProxy).deposit(contractId, address(usdtToken), deposits);

        // Stop impersonating the client after completing the test actions.
        vm.stopPrank();

        // Verify the parameters of the deposit created in the escrow contract.
        // Ensure the current contract ID is as expected, indicating that the deposit has been properly logged under the correct ID.
        uint256 currentContractId = EscrowMilestone(escrowProxy).getCurrentContractId();
        assertEq(currentContractId, 1);

        uint256 milestoneId = escrow.getMilestoneCount(currentContractId);

        // Retrieve the details of the created deposit using the currentContractId.
        (
            address _contractor,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _amountToWithdraw,
            bytes32 _contractorData,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = EscrowMilestone(escrowProxy).contractMilestones(currentContractId, milestoneId);

        // Assertions to verify that the deposit parameters are correctly set according to the inputs provided during creation.
        assertEq(MockUSDT(usdtToken).balanceOf(address(escrowProxy)), 1030e6); // Confirms that the escrow proxy has received appropriate amount of tokens.
        assertEq(_contractor, address(0)); // // Verifies that the contractor address is initially set to zero, indicating no contractor is assigned yet.
        // assertEq(address(_paymentToken), address(usdtToken)); // Confirms that the correct payment token is associated with the deposit.
        assertEq(_amount, 1000e6); // Ensures that the deposited amount is correctly recorded as 1 ether.
        assertEq(_amountToClaim, 0 ether); // Checks that no amount is set to be claimable initially.
        assertEq(_amountToWithdraw, 0 ether); // Checks that no amount is set to be withdrawable initially.
        assertEq(_contractorData, contractorData); // Checks that the contractor data matches the expected initial value.
        assertEq(uint256(_feeConfig), 1); // Ensures the fee configuration is set to CLIENT_COVERS_ONLY (assuming 1 is CLIENT_COVERS_ONLY in the enum).
        assertEq(uint256(_status), 0); // Confirms that the initial status of the deposit is ACTIVE (assuming 0 is ACTIVE in the enum).
    }
}
