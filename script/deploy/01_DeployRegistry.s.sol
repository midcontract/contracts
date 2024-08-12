// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Script.sol";

import {EscrowRegistry} from "src/modules/EscrowRegistry.sol";
import {MockDAI} from "test/mocks/MockDAI.sol";
import {MockUSDT} from "test/mocks/MockUSDT.sol";
import {EthSepoliaConfig} from "config/EthSepoliaConfig.sol";
import {PolAmoyConfig} from "config/PolAmoyConfig.sol";

contract DeployRegistryScript is Script {
    // EscrowRegistry registry;
    MockDAI daiToken;
    MockUSDT usdtToken;
    address ownerPublicKey;
    uint256 ownerPrivateKey;
    address deployerPublicKey;
    uint256 deployerPrivateKey;
    address paymentToken;
    address registry;

    function setUp() public {
        ownerPublicKey = vm.envAddress("OWNER_PUBLIC_KEY");
        ownerPrivateKey = vm.envUint("OWNER_PRIVATE_KEY");
        deployerPublicKey = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        paymentToken = EthSepoliaConfig.MOCK_USDT;
        registry = PolAmoyConfig.REGISTRY;
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        // registry = new EscrowRegistry(ownerPublicKey);
        daiToken = new MockDAI();
        // registry.addPaymentToken(address(daiToken));
        // usdtToken = new MockUSDT();
        // console.log("==registry addr=%s", address(registry));
        // // console.log("==daiToken addr=%s", address(daiToken));
        // console.log("==usdtToken addr=%s", address(usdtToken));
        // assert(address(registry) != address(0));
        // // assert(registry.paymentTokens(address(paymentToken)) == true);
        vm.stopBroadcast();

        vm.startBroadcast(ownerPrivateKey);
        EscrowRegistry(registry).addPaymentToken(address(daiToken));
        // registry.addPaymentToken(address(usdtToken));
        // registry.setTreasury(ownerPublicKey);
        // assert(registry.paymentTokens(address(usdtToken)) == true);
        // assert(registry.treasury() == address(ownerPublicKey));
        vm.stopBroadcast();
    }
}
