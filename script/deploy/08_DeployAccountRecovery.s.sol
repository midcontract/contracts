// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Script.sol";

import {EscrowAccountRecovery} from "src/modules/EscrowAccountRecovery.sol";
import {EscrowAdminManager} from "src/modules/EscrowAdminManager.sol";
import {EscrowRegistry, IEscrowRegistry} from "src/modules/EscrowRegistry.sol";
import {EthSepoliaConfig} from "config/EthSepoliaConfig.sol";
import {PolAmoyConfig} from "config/PolAmoyConfig.sol";

contract DeployAccountRecoveryScript is Script {
    EscrowAccountRecovery accountRecovery;
    address adminManager;
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
        adminManager = PolAmoyConfig.ADMIN_MANAGER;
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        accountRecovery = new EscrowAccountRecovery(adminManager);
        console.log("==accountRecovery addr=%s", address(accountRecovery));
        vm.stopBroadcast();

        vm.startBroadcast(ownerPrivateKey);
        EscrowRegistry(registry).setAccountRecovery(address(accountRecovery));
        assert(EscrowRegistry(registry).accountRecovery() == address(accountRecovery));
        vm.stopBroadcast();
    }
}
