// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Script, console } from "forge-std/Script.sol";

import { EscrowAdminManager } from "src/modules/EscrowAdminManager.sol";
import { EscrowRegistry } from "src/modules/EscrowRegistry.sol";
import { EthSepoliaConfig } from "config/EthSepoliaConfig.sol";
import { PolAmoyConfig } from "config/PolAmoyConfig.sol";

contract DeployAdminManagerScript is Script {
    EscrowAdminManager adminManager;
    address ownerPublicKey;
    uint256 ownerPrivateKey;
    address deployerPublicKey;
    uint256 deployerPrivateKey;
    address registry;

    function setUp() public {
        ownerPublicKey = vm.envAddress("OWNER_PUBLIC_KEY");
        ownerPrivateKey = vm.envUint("OWNER_PRIVATE_KEY");
        deployerPublicKey = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        registry = PolAmoyConfig.REGISTRY;
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        adminManager = new EscrowAdminManager(ownerPublicKey);
        console.log("==adminManager addr=%s", address(adminManager));
        vm.stopBroadcast();

        vm.startBroadcast(ownerPrivateKey);
        EscrowRegistry(registry).setAdminManager(address(adminManager));
        assert(EscrowRegistry(registry).adminManager() == address(adminManager));
        vm.stopBroadcast();
    }
}
