// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {Escrow, IEscrow} from "src/Escrow.sol";
import {EscrowFactory, IEscrowFactory} from "src/EscrowFactory.sol";
import {Registry, IRegistry} from "src/Registry.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {EthSepoliaConfig} from "config/EthSepoliaConfig.sol";

contract ExecuteEscrowScript is Script {
    address public escrow;
    address public factory;
    address public registry;
    address public paymentToken;

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

    address public deployerPublicKey;
    uint256 public deployerPrivateKey;

    function setUp() public {
        deployerPublicKey = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        escrow = EthSepoliaConfig.ESCROW;
        registry = EthSepoliaConfig.REGISTRY;
        factory = EthSepoliaConfig.FACTORY;
        paymentToken = EthSepoliaConfig.MOCK_PAYMENT_TOKEN;

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
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        // deploy new escrow
        address deployedEscrowProxy = EscrowFactory(factory).deployEscrow(address(deployerPublicKey), address(deployerPublicKey), address(registry), 3_00, 8_00);
        Escrow escrowProxy = Escrow(address(deployedEscrowProxy));

        // mint, approve payment token
        ERC20Mock(paymentToken).mint(address(deployerPublicKey), 2 ether);
        ERC20Mock(paymentToken).approve(address(escrowProxy), 2 ether);

        // deposit
        Escrow(escrowProxy).deposit(deposit);

        // submit
        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        bytes32 contractorDataHash = Escrow(escrowProxy).getContractorDataHash(contractData, salt);
        uint256 currentContractId = Escrow(escrowProxy).getCurrentContractId();
        
        // submit
        Escrow(escrowProxy).submit(currentContractId, contractData, salt);

        // approve
        Escrow(escrowProxy).approve(currentContractId, 1 ether, 0 ether, address(deployerPublicKey));

        // claim
        Escrow(escrowProxy).claim(currentContractId);

        vm.stopBroadcast();
    }
}