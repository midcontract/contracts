// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Script, console } from "forge-std/Script.sol";

import { EscrowFixedPrice, IEscrowFixedPrice } from "src/EscrowFixedPrice.sol";
import { EscrowFactory, IEscrowFactory } from "src/EscrowFactory.sol";
import { EscrowFeeManager } from "src/modules/EscrowFeeManager.sol";
import { EscrowRegistry, IEscrowRegistry } from "src/modules/EscrowRegistry.sol";
import { EthSepoliaConfig } from "config/EthSepoliaConfig.sol";
import { PolAmoyConfig } from "config/PolAmoyConfig.sol";
import { Enums } from "src/libs/Enums.sol";
import { MockDAI } from "test/mocks/MockDAI.sol";
import { MockUSDT } from "test/mocks/MockUSDT.sol";

contract ExecuteEscrowScript is Script {
    address escrow;
    address factory;
    address registry;
    address feeManager;
    address usdtToken;
    address owner;
    address newOwner;

    IEscrowFixedPrice.Deposit deposit;
    Enums.FeeConfig feeConfig;
    Enums.Status status;
    Enums.EscrowType escrowType;
    bytes32 contractorData;
    bytes32 salt;
    bytes contractData;

    struct Deposit {
        address contractor;
        address paymentToken;
        uint256 amount;
        uint256 amountToClaim;
        uint256 amountToWithdraw;
        bytes32 contractorData;
        Enums.FeeConfig feeConfig;
        Enums.Status status;
    }

    address deployerPublicKey;
    uint256 deployerPrivateKey;

    function setUp() public {
        deployerPublicKey = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        owner = vm.envAddress("OWNER_PUBLIC_KEY");

        escrow = PolAmoyConfig.ESCROW_FIXED_PRICE;
        registry = PolAmoyConfig.REGISTRY;
        factory = PolAmoyConfig.FACTORY;
        feeManager = PolAmoyConfig.FEE_MANAGER;
        newOwner = PolAmoyConfig.OWNER;
        usdtToken = PolAmoyConfig.MOCK_USDT;

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        contractorData = keccak256(abi.encodePacked(contractData, salt));

        deposit = IEscrowFixedPrice.Deposit({
            contractor: address(0),
            paymentToken: address(usdtToken),
            amount: 1000e6,
            amountToClaim: 0,
            amountToWithdraw: 0,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.ACTIVE
        });
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        // EscrowRegistry(registry).transferOwnership(newOwner);
        // assert(address(EscrowFixedPrice(escrow).owner()) == deployerPublicKey);
        // EscrowFixedPrice(escrow).transferOwnership(newOwner);
        // assert(address(EscrowFixedPrice(escrow).owner()) == newOwner);

        assert(address(EscrowFactory(factory).owner()) == deployerPublicKey);
        EscrowFactory(factory).transferOwnership(newOwner);
        assert(address(EscrowFactory(factory).owner()) == newOwner);

        EscrowFeeManager(feeManager).transferOwnership(newOwner);

        (bool sent,) = newOwner.call{value: 0.055 ether}("");
        require(sent, "Failed to send Ether");

        // // set treasury
        EscrowRegistry(registry).setTreasury(owner);

        // // deploy new escrow
        address deployedEscrowProxy = EscrowFactory(factory).deployEscrow(
            escrowType, address(deployerPublicKey), address(deployerPublicKey), address(registry)
        );
        EscrowFixedPrice escrowProxy = EscrowFixedPrice(address(deployedEscrowProxy));

        // // mint, approve payment token
        MockUSDT(usdtToken).mint(address(deployerPublicKey), 1800e6);
        MockUSDT(usdtToken).approve(address(escrowProxy), 1800e6);

        // // deposit
        EscrowFixedPrice(escrowProxy).deposit(deposit);

        // // submit
        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        // bytes32 contractorDataHash = Escrow(escrowProxy).getContractorDataHash(contractData, salt);
        uint256 currentContractId = EscrowFixedPrice(escrowProxy).getCurrentContractId();

        // // submit
        EscrowFixedPrice(escrowProxy).submit(currentContractId, contractData, salt);

        // // approve
        EscrowFixedPrice(escrowProxy).approve(currentContractId, 1000e6, address(deployerPublicKey));

        // // claim
        EscrowFixedPrice(escrowProxy).claim(currentContractId);

        vm.stopBroadcast();
    }
}
