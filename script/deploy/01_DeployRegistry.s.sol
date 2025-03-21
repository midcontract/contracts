// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Script, console } from "forge-std/Script.sol";

import { EscrowRegistry } from "src/modules/EscrowRegistry.sol";
import { MockDAI } from "test/mocks/MockDAI.sol";
import { MockUSDT } from "test/mocks/MockUSDT.sol";
import { EthSepoliaConfig } from "config/EthSepoliaConfig.sol";
import { PolAmoyConfig } from "config/PolAmoyConfig.sol";

contract DeployRegistryScript is Script {
    EscrowRegistry registry;
    MockDAI daiToken;
    MockUSDT usdtToken;
    address ownerPublicKey;
    uint256 ownerPrivateKey;
    address deployerPublicKey;
    uint256 deployerPrivateKey;
    address paymentToken1;
    address paymentToken2;
    address paymentToken3;
    // address registry;

    function setUp() public {
        ownerPublicKey = vm.envAddress("OWNER_PUBLIC_KEY");
        ownerPrivateKey = vm.envUint("OWNER_PRIVATE_KEY");
        deployerPublicKey = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        paymentToken1 = PolAmoyConfig.MOCK_USDT;
        paymentToken2 = PolAmoyConfig.MOCK_DAI;
        paymentToken3 = PolAmoyConfig.MOCK_USDC;
        // registry = PolAmoyConfig.REGISTRY;
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        registry = new EscrowRegistry(ownerPublicKey);
        // daiToken = new MockDAI();
        // registry.addPaymentToken(address(daiToken));
        // usdtToken = new MockUSDT();
        // console.log("==registry addr=%s", address(registry));
        // // console.log("==daiToken addr=%s", address(daiToken));
        // console.log("==usdtToken addr=%s", address(usdtToken));
        // assert(address(registry) != address(0));
        // // assert(registry.paymentTokens(address(paymentToken)) == true);
        vm.stopBroadcast();

        vm.startBroadcast(ownerPrivateKey);
        // EscrowRegistry(registry).setFixedTreasury(ownerPublicKey);
        // EscrowRegistry(registry).setHourlyTreasury(ownerPublicKey);
        // EscrowRegistry(registry).setMilestoneTreasury(ownerPublicKey);
        EscrowRegistry(registry).addPaymentToken(paymentToken1);
        EscrowRegistry(registry).addPaymentToken(paymentToken2);
        EscrowRegistry(registry).addPaymentToken(paymentToken3);

        // EscrowRegistry(registry).updateEscrowFixedPrice(0xD8038Fae596CDC13cC9b3681A6Eb44cC1984D670);
        // EscrowRegistry(registry).updateEscrowMilestone(0x2dc075B51ef3b4f0AD868b0cc342951682019E62);
        // EscrowRegistry(registry).updateEscrowHourly(0x2b8660f1c512dBc74967d35BC23A6186a5CDE90a);
        // EscrowRegistry(registry).updateFactory(0xeaD5265B6412103d316b6389c0c15EBA82a0cbDa);
        // EscrowRegistry(registry).updateFeeManager(0xA4857B1178425cfaaaeedBcFc220F242b4A518fA);

        // EscrowRegistry(registry).updateEscrowHourly(address(escrow));
        vm.stopBroadcast();
    }
}