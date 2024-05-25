// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {Escrow, IEscrow} from "src/Escrow.sol";
import {EscrowFactory, IEscrowFactory} from "src/EscrowFactory.sol";
import {Registry, IRegistry} from "src/modules/Registry.sol";
import {EthSepoliaConfig} from "config/EthSepoliaConfig.sol";
import {Enums} from "src/libs/Enums.sol";
import {MockDAI} from "test/mocks/MockDAI.sol";
import {MockUSDT} from "test/mocks/MockUSDT.sol";

contract ExecuteEscrowScript is Script {
    address public escrow;
    address public factory;
    address public registry;
    address public usdtToken;
    address public owner;

    IEscrow.Deposit public deposit;
    Enums.FeeConfig public feeConfig;
    Enums.Status public status;
    bytes32 public contractorData;
    bytes32 public salt;
    bytes public contractData;

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

    address public deployerPublicKey;
    uint256 public deployerPrivateKey;

    function setUp() public {
        deployerPublicKey = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        owner = vm.envAddress("OWNER_PUBLIC_KEY");

        escrow = EthSepoliaConfig.ESCROW;
        registry = EthSepoliaConfig.REGISTRY;
        factory = EthSepoliaConfig.FACTORY;
        usdtToken = EthSepoliaConfig.MOCK_USDT;

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        contractorData = keccak256(abi.encodePacked(contractData, salt));

        deposit = IEscrow.Deposit({
            contractor: address(0),
            paymentToken: address(usdtToken),
            amount: 1000e6,
            amountToClaim: 0,
            amountToWithdraw: 0,
            timeLock: 0,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.PENDING
        });
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        
        // set treasury
        Registry(registry).setTreasury(owner);

        // deploy new escrow
        address deployedEscrowProxy = EscrowFactory(factory).deployEscrow(
            address(deployerPublicKey), address(deployerPublicKey), address(registry)
        );
        Escrow escrowProxy = Escrow(address(deployedEscrowProxy));

        // mint, approve payment token
        MockUSDT(usdtToken).mint(address(deployerPublicKey), 1800e6);
        MockUSDT(usdtToken).approve(address(escrowProxy), 1800e6);

        // deposit
        Escrow(escrowProxy).deposit(deposit);

        // submit
        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        // bytes32 contractorDataHash = Escrow(escrowProxy).getContractorDataHash(contractData, salt);
        uint256 currentContractId = Escrow(escrowProxy).getCurrentContractId();

        // submit
        Escrow(escrowProxy).submit(currentContractId, contractData, salt);

        // approve
        Escrow(escrowProxy).approve(currentContractId, 1000e6, address(deployerPublicKey));

        // claim
        Escrow(escrowProxy).claim(currentContractId);

        vm.stopBroadcast();
    }
}
