// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {EscrowFeeManager} from "src/modules/EscrowFeeManager.sol";
import {EscrowRegistry, IEscrowRegistry} from "src/modules/EscrowRegistry.sol";
import {EthSepoliaConfig} from "config/EthSepoliaConfig.sol";

contract DeployEscrowFeeManagerScript is Script {
    EscrowFeeManager feeManager;
    address registry;
    address deployerPublicKey;
    uint256 deployerPrivateKey;

    function setUp() public {
        deployerPublicKey = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        registry = EthSepoliaConfig.REGISTRY;
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        feeManager = new EscrowFeeManager(3_00, 5_00, deployerPublicKey);
        EscrowRegistry(registry).updateFeeManager(address(feeManager));
        console.log("==feeManager addr=%s", address(feeManager));
        assert(address(feeManager) != address(0));
        assert(EscrowRegistry(registry).feeManager() == address(feeManager));
        vm.stopBroadcast();
    }
}
