// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {Escrow} from "src/Escrow.sol";
import {EscrowFactory, IEscrowFactory} from "src/EscrowFactory.sol";
import {Registry, IRegistry} from "src/Registry.sol";

contract DeployEscrowFactoryScript is Script {
    EscrowFactory public factory;
    address public escrow;
    address public registry;
    address public deployerPublicKey;
    uint256 public deployerPrivateKey;

    function setUp() public {
        deployerPublicKey = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        factory = new EscrowFactory(registry);
        IRegistry(registry).updateFactory(address(factory));
        console.log("==factory addr=%s", address(factory));
        assert(address(factory) != address(0));
        assert(registry.factory() == address(factory));
        vm.stopBroadcast();
    }
}
