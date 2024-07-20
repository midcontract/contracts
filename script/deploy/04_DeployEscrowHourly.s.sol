// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {EscrowHourly} from "src/EscrowHourly.sol";
import {EscrowRegistry, IEscrowRegistry} from "src/modules/EscrowRegistry.sol";
import {PolAmoyConfig} from "config/PolAmoyConfig.sol";

contract DeployEscrowHourlyScript is Script {
    EscrowHourly escrow;
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
        escrow = new EscrowHourly();
        escrow.initialize(address(deployerPublicKey), address(ownerPublicKey), address(registry));
        vm.stopBroadcast();

        vm.startBroadcast(ownerPrivateKey);
        EscrowRegistry(registry).updateEscrowHourly(address(escrow));
        console.log("==escrow addr=%s", address(escrow));
        assert(address(escrow) != address(0));
        assert(EscrowRegistry(registry).escrowHourly() == address(escrow));
        vm.stopBroadcast();
    }
}
