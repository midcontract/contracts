// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {Registry} from "src/modules/Registry.sol";
import {MockDAI} from "test/mocks/MockDAI.sol";
import {MockUSDT} from "test/mocks/MockUSDT.sol";

contract DeployRegistryScript is Script {
    Registry public registry;
    MockDAI public daiToken;
    MockUSDT public usdtToken;
    address public deployerPublicKey;
    uint256 public deployerPrivateKey;
    address public owner;

    function setUp() public {
        deployerPublicKey = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        owner = vm.envAddress("OWNER_PUBLIC_KEY");
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        // registry = new Registry(deployerPublicKey);
        // daiToken = new MockDAI();
        // registry.addPaymentToken(address(daiToken));
        // usdtToken = new MockUSDT();
        // registry.addPaymentToken(address(usdtToken));
        registry.setTreasury(owner);
        // console.log("==registry addr=%s", address(registry));
        // console.log("==daiToken addr=%s", address(daiToken));
        // console.log("==usdtToken addr=%s", address(usdtToken));
        // assert(address(registry) != address(0));
        // assert(registry.paymentTokens(address(daiToken)) == true);
        // assert(registry.paymentTokens(address(usdtToken)) == true);
        vm.stopBroadcast();
    }
}
