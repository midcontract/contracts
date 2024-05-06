// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {Escrow} from "src/Escrow.sol";
import {EscrowFactory, IEscrowFactory} from "src/EscrowFactory.sol";
import {Registry, IRegistry} from "src/modules/Registry.sol";
import {EthSepoliaConfig} from "config/EthSepoliaConfig.sol";

contract DeployEscrowFactoryScript is Script {
    EscrowFactory public factory;
    address public escrow;
    address public registry;
    address public deployerPublicKey;
    uint256 public deployerPrivateKey;

    function setUp() public {
        deployerPublicKey = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        registry = EthSepoliaConfig.REGISTRY;
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        factory = new EscrowFactory(registry, deployerPublicKey);
        IRegistry(registry).updateFactory(address(factory));
        console.log("==factory addr=%s", address(factory));
        assert(address(factory) != address(0));
        assert(IRegistry(registry).factory() == address(factory));
        vm.stopBroadcast();
    }
}
