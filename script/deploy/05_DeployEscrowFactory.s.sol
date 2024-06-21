// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {EscrowFactory} from "src/EscrowFactory.sol";
import {EscrowRegistry, IEscrowRegistry} from "src/modules/EscrowRegistry.sol";
import {EthSepoliaConfig} from "config/EthSepoliaConfig.sol";

contract DeployEscrowFactoryScript is Script {
    EscrowFactory factory;
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
        registry = EthSepoliaConfig.REGISTRY;
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        factory = new EscrowFactory(registry, ownerPublicKey);
        console.log("==factory addr=%s", address(factory));
        assert(address(factory) != address(0));
        vm.stopBroadcast();

        vm.startBroadcast(ownerPrivateKey);
        IEscrowRegistry(registry).updateFactory(address(factory));
        assert(IEscrowRegistry(registry).factory() == address(factory));
        vm.stopBroadcast();
    }
}
