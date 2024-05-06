// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {Registry} from "src/modules/Registry.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract DeployRegistryScript is Script {
    Registry public registry;
    ERC20Mock public paymentToken;
    address public deployerPublicKey;
    uint256 public deployerPrivateKey;

    function setUp() public {
        deployerPublicKey = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        registry = new Registry(deployerPublicKey);
        paymentToken = new ERC20Mock();
        registry.addPaymentToken(address(paymentToken));
        console.log("==registry addr=%s", address(registry));
        console.log("==paymentToken addr=%s", address(paymentToken));
        assert(address(registry) != address(0));
        assert(registry.paymentTokens(address(paymentToken)) == true);
        vm.stopBroadcast();
    }
}
