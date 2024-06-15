// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {Registry} from "src/modules/Registry.sol";
import {MockDAI} from "test/mocks/MockDAI.sol";
import {MockUSDT} from "test/mocks/MockUSDT.sol";
import {EthSepoliaConfig} from "config/EthSepoliaConfig.sol";

contract DeployRegistryScript is Script {
    Registry registry;
    MockDAI daiToken;
    MockUSDT usdtToken;
    address ownerPublicKey;
    uint256 ownerPrivateKey;
    address deployerPublicKey;
    uint256 deployerPrivateKey;
    address paymentToken;

    function setUp() public {
        ownerPublicKey = vm.envAddress("OWNER_PUBLIC_KEY");
        ownerPrivateKey = vm.envUint("OWNER_PRIVATE_KEY");
        deployerPublicKey = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        paymentToken = EthSepoliaConfig.MOCK_USDT;
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        registry = new Registry(deployerPublicKey);
        // daiToken = new MockDAI();
        // registry.addPaymentToken(address(daiToken));
        // usdtToken = new MockUSDT();
        console.log("==registry addr=%s", address(registry));
        // console.log("==daiToken addr=%s", address(daiToken));
        // console.log("==usdtToken addr=%s", address(usdtToken));
        assert(address(registry) != address(0));
        assert(registry.paymentTokens(address(paymentToken)) == true);
        vm.stopBroadcast();

        vm.startBroadcast(ownerPrivateKey);
        registry.addPaymentToken(paymentToken);
        registry.setTreasury(ownerPublicKey);
        assert(registry.paymentTokens(address(paymentToken)) == true);
        vm.stopBroadcast();
    }
}
