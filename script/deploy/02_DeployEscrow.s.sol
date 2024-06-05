// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {Escrow} from "src/Escrow.sol";
import {Registry, IRegistry} from "src/modules/Registry.sol";
import {EthSepoliaConfig} from "config/EthSepoliaConfig.sol";

contract DeployEscrowScript is Script {
    Escrow public escrow;
    address public registry;
    address public ownerPublicKey;
    uint256 public ownerPrivateKey;
    address public deployerPublicKey;
    uint256 public deployerPrivateKey;

    function setUp() public {
        ownerPublicKey = vm.envAddress("OWNER_PUBLIC_KEY");
        ownerPrivateKey = vm.envUint("OWNER_PRIVATE_KEY");
        deployerPublicKey = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        registry = EthSepoliaConfig.REGISTRY;
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        escrow = new Escrow();
        escrow.initialize(address(deployerPublicKey), address(deployerPublicKey), address(registry));
        vm.stopBroadcast();

        vm.startBroadcast(ownerPrivateKey);
        Registry(registry).updateEscrow(address(escrow));
        console.log("==escrow addr=%s", address(escrow));
        assert(address(escrow) != address(0));
        assert(Registry(registry).escrow() == address(escrow));
        vm.stopBroadcast();
    }
}
