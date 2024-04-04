// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {Escrow} from "src/Escrow.sol";

contract EscrowScript is Script {
    Escrow public escrow;
    address public deployerPublicKey;
    uint256 public deployerPrivateKey;

    function setUp() public {
        deployerPublicKey = vm.envAddress("DEPLOYER_EOA_PUBLIC_KEY");
        deployerPrivateKey = vm.envUint("DEPLOYER_EOA_PRIVATE_KEY");
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        escrow = new Escrow();
        vm.stopBroadcast();
    }
}