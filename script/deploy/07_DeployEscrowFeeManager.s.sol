// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Script, console } from "forge-std/Script.sol";

import { EscrowFeeManager } from "src/modules/EscrowFeeManager.sol";
import { EscrowRegistry } from "src/modules/EscrowRegistry.sol";
import { EthSepoliaConfig } from "config/EthSepoliaConfig.sol";
import { PolAmoyConfig } from "config/PolAmoyConfig.sol";

contract DeployEscrowFeeManagerScript is Script {
    EscrowFeeManager feeManager;
    address registry;
    address ownerPublicKey;
    uint256 ownerPrivateKey;
    address deployerPublicKey;
    uint256 deployerPrivateKey;

    function setUp() public {
        ownerPublicKey = vm.envAddress("OWNER_PUBLIC_KEY");
        ownerPrivateKey = vm.envUint("OWNER_PRIVATE_KEY");
        deployerPublicKey = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        registry = PolAmoyConfig.REGISTRY;
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        feeManager = new EscrowFeeManager(3_00, 5_00, ownerPublicKey);
        console.log("==feeManager addr=%s", address(feeManager));
        assert(address(feeManager) != address(0));
        vm.stopBroadcast();

        vm.startBroadcast(ownerPrivateKey);
        EscrowRegistry(registry).updateFeeManager(address(feeManager));
        assert(EscrowRegistry(registry).feeManager() == address(feeManager));
        vm.stopBroadcast();
    }
}
