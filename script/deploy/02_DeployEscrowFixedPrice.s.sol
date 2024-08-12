// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Script.sol";

import {EscrowFixedPrice} from "src/EscrowFixedPrice.sol";
import {EscrowRegistry, IEscrowRegistry} from "src/modules/EscrowRegistry.sol";
import {EthSepoliaConfig} from "config/EthSepoliaConfig.sol";
import {PolAmoyConfig} from "config/PolAmoyConfig.sol";

contract DeployEscrowFixedPriceScript is Script {
    EscrowFixedPrice escrow;
    address registry;
    address ownerPublicKey;
    uint256 ownerPrivateKey;
    address deployerPublicKey;
    uint256 deployerPrivateKey;

    function setUp() public {
        ownerPublicKey = vm.envAddress("OWNER_PUBLIC_KEY");
        ownerPrivateKey = vm.envUint("OWNER_PRIVATE_KEY");
        deployerPublicKey = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        registry = PolAmoyConfig.REGISTRY;
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        escrow = new EscrowFixedPrice();
        escrow.initialize(address(deployerPublicKey), address(deployerPublicKey), address(registry));
        console.log("==escrow addr=%s", address(escrow));
        assert(address(escrow) != address(0));
        vm.stopBroadcast();

        vm.startBroadcast(ownerPrivateKey);
        EscrowRegistry(registry).updateEscrowFixedPrice(0xA925686d8DA646854BF47b493C0f053ce62308C5);
        assert(EscrowRegistry(registry).escrowFixedPrice() == address(0xA925686d8DA646854BF47b493C0f053ce62308C5));
        vm.stopBroadcast();
    }
}
