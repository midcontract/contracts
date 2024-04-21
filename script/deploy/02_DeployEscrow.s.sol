// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {Escrow} from "src/Escrow.sol";
import {Registry, IRegistry} from "src/Registry.sol";

contract DeployEscrowScript is Script {
    Escrow public escrow;
    address public registry;
    address public deployerPublicKey;
    uint256 public deployerPrivateKey;

    function setUp() public {
        deployerPublicKey = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        escrow = new Escrow();
        // IRegistry(registry).updateEscrow(address(escrow));
        console.log("==escrow addr=%s", address(escrow));
        assert(address(escrow) != address(0));
        // assert(registry.escrow() == address(paymentToken));
        vm.stopBroadcast();
    }
}
