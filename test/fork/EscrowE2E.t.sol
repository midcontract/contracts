// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {Escrow, IEscrow} from "src/Escrow.sol";
import {EscrowFactory, IEscrowFactory} from "src/EscrowFactory.sol";
import {Registry, IRegistry} from "src/modules/Registry.sol";
import {Enums} from "src/libs/Enums.sol";
import {EthSepoliaConfig} from "config/EthSepoliaConfig.sol";
import {MockDAI} from "test/mocks/MockDAI.sol";
import {MockUSDT} from "test/mocks/MockUSDT.sol";

contract ExecuteEscrowEndToEndTest is Test {
    Escrow escrow = Escrow(EthSepoliaConfig.ESCROW);
    Registry registry = Registry(EthSepoliaConfig.REGISTRY);
    EscrowFactory factory = EscrowFactory(EthSepoliaConfig.FACTORY);
    MockDAI daiToken = MockDAI(EthSepoliaConfig.MOCK_DAI);
    MockUSDT usdtToken = MockUSDT(EthSepoliaConfig.MOCK_USDT);

    address client;
    address contractor;
    address owner;

    IEscrow.Deposit deposit;
    Enums.FeeConfig feeConfig;
    Enums.Status status;
    Enums.EscrowType escrowType;
    bytes32 contractorData;
    bytes32 salt;
    bytes contractData;

    struct Deposit {
        address contractor;
        address usdtToken;
        uint256 amount;
        uint256 amountToClaim;
        uint256 amountToWithdraw;
        bytes32 contractorData;
        Enums.FeeConfig feeConfig;
        Enums.Status status;
    }

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

        deposit = IEscrow.Deposit({
            contractor: address(0),
            paymentToken: address(usdtToken),
            amount: 1000e6,
            amountToClaim: 0,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.ACTIVE
        });

        vm.startPrank(client);
        MockUSDT(usdtToken).claim();
        // assertEq(MockUSDT(usdtToken).balanceOf(client), 1000e6);
        MockUSDT(usdtToken).mint(client, 80e6);
        // assertEq(MockUSDT(usdtToken).balanceOf(client), 1080e6);
        // MockDAI(daiToken).claim();
        // assertEq(MockDAI(daiToken).balanceOf(client), 1000 ether);
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
        Escrow escrowProxy = Escrow(address(deployedEscrowProxy));

        // Step 2: Client approves the payment token with the respective deposit token amount.
        // This approval enables the escrow contract to withdraw tokens from the client's account.
        MockUSDT(usdtToken).approve(address(escrowProxy), 1080e6);

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
            uint256 _amountToWithdraw,
            bytes32 _contractorData,
            Enums.FeeConfig _feeConfig,
            Enums.Status _status
        ) = Escrow(escrowProxy).deposits(currentContractId);

        // Assertions to verify that the deposit parameters are correctly set according to the inputs provided during creation.
        assertEq(MockUSDT(usdtToken).balanceOf(address(escrowProxy)), 1080e6); // Confirms that the escrow proxy has received appropriate amount of tokens.
        assertEq(_contractor, address(0)); // // Verifies that the contractor address is initially set to zero, indicating no contractor is assigned yet.
        assertEq(address(_paymentToken), address(usdtToken)); // Confirms that the correct payment token is associated with the deposit.
        assertEq(_amount, 1000e6); // Ensures that the deposited amount is correctly recorded as 1 ether.
        assertEq(_amountToClaim, 0 ether); // Checks that no amount is set to be claimable initially.
        assertEq(_amountToWithdraw, 0 ether); // Checks that no amount is set to be withdrawable initially.
        assertEq(_contractorData, contractorData); // Checks that the contractor data matches the expected initial value.
        assertEq(uint256(_feeConfig), 0); // Ensures the fee configuration is set to CLIENT_COVERS_ALL (assuming 0 is CLIENT_COVERS_ALL in the enum).
        assertEq(uint256(_status), 0); // Confirms that the initial status of the deposit is ACTIVE (assuming 0 is ACTIVE in the enum).
    }
}
