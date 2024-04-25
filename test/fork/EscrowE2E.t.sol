// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {Escrow, IEscrow} from "src/Escrow.sol";
import {EscrowFactory, IEscrowFactory} from "src/EscrowFactory.sol";
import {Registry, IRegistry} from "src/Registry.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {EthSepoliaConfig} from "config/EthSepoliaConfig.sol";

contract ExecuteEscrowEndToEndTest is Test {
    Escrow escrow = Escrow(EthSepoliaConfig.ESCROW);
    Registry registry = Registry(EthSepoliaConfig.REGISTRY);
    EscrowFactory factory = EscrowFactory(EthSepoliaConfig.FACTORY);
    ERC20Mock paymentToken = ERC20Mock(EthSepoliaConfig.MOCK_PAYMENT_TOKEN);

    address client;
    address contractor;
    address admin;

    IEscrow.Deposit deposit;
    IEscrow.FeeConfig feeConfig;
    IEscrow.Status status;
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
        IEscrow.FeeConfig feeConfig;
        IEscrow.Status status;
    }

    function setUp() public {
        client = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        // clientPrK = vm.envUint("DEPLOYER_PUBLIC_KEY");
        contractor = vm.envAddress("CONTRACTOR_PUBLIC_KEY");
        // contractorPrK = vm.envUint("CONTRACTOR_PRIVATE_KEY");
        admin = vm.envAddress("ADMIN_PUBLIC_KEY");
        // adminPrK = vm.envUint("ADMIN_PRIVATE_KEY");
        
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

        vm.prank(contractor);
        ERC20Mock(paymentToken).mint(address(contractor), 1.11 ether);
    }

    /// @dev This test verifies the complete flow of creating a deposit in an escrow system using a mocked ERC20 token.
    /// The steps include deploying an escrow proxy, approving a token, and creating a deposit.
    function test_createDeposit() public {
        // Start impersonating the client to perform actions as if they are initiated by the client.
        vm.startPrank(client);
        
        // Step 1: Deploy their own contract instance to interact with the factory.
        // The client deploys an Escrow contract via the factory specifying fee configurations.
        address deployedEscrowProxy = EscrowFactory(factory).deployEscrow(address(client), address(admin), address(registry), 3_00, 8_00);
        Escrow escrowProxy = Escrow(address(deployedEscrowProxy));

        // Step 2: Client approves the payment token with the respective deposit token amount.
        // This approval enables the escrow contract to withdraw tokens from the client's account.
        ERC20Mock(paymentToken).approve(address(escrowProxy), 1.11 ether);

        // Step 3: Client creates the first deposit on the deployed instance with contractId == 1.
        // The deposit function call involves transferring funds from the client to the escrow based on the approved amount.
        Escrow(escrowProxy).deposit(deposit);

        // Stop impersonating the client after completing the test actions.
        vm.stopPrank();

        // Verify the parameters of the deposit created in the escrow contract.
        // Ensure the current contract ID is as expected, indicating that the deposit has been properly logged under the correct ID.
        uint256 currentContractId = Escrow(escrowProxy).getCurrentContractId();
        assertEq(currentContractId, 1);

        // Retrieve the details of the created deposit using the currentContractId.
        (
            address _contractor,
            address _paymentToken,
            uint256 _amount,
            uint256 _amountToClaim,
            uint256 _timeLock,
            bytes32 _contractorData,
            IEscrow.FeeConfig _feeConfig,
            IEscrow.Status _status
        ) = Escrow(escrowProxy).deposits(currentContractId);

        // Assertions to verify that the deposit parameters are correctly set according to the inputs provided during creation.
        assertGt(ERC20Mock(paymentToken).balanceOf(address(escrowProxy)), 0); // Confirms that the escrow proxy has received the tokens.
        assertEq(_contractor, address(0)); // // Verifies that the contractor address is initially set to zero, indicating no contractor is assigned yet.
        assertEq(address(_paymentToken), address(paymentToken)); // Confirms that the correct payment token is associated with the deposit.
        assertEq(_amount, 1 ether); // Ensures that the deposited amount is correctly recorded as 1 ether.
        assertEq(_amountToClaim, 0 ether); // Checks that no amount is set to be claimable initially.
        assertEq(_timeLock, 0); // Verifies that the time lock for the deposit is set to 0 (no delay).
        assertEq(_contractorData, contractorData); // Checks that the contractor data matches the expected initial value.
        assertEq(uint256(_feeConfig), 0); // Ensures the fee configuration is set to FULL (assuming 0 is FULL in the enum).
        assertEq(uint256(_status), 0); // Confirms that the initial status of the deposit is PENDING (assuming 0 is PENDING in the enum).
    }
}
