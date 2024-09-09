// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Script.sol";

import {EscrowFixedPrice} from "src/EscrowFixedPrice.sol";
import {EscrowRegistry, IEscrowRegistry} from "src/modules/EscrowRegistry.sol";
import {EscrowAdminManager} from "src/modules/EscrowAdminManager.sol";
import {EthSepoliaConfig} from "config/EthSepoliaConfig.sol";
import {PolAmoyConfig} from "config/PolAmoyConfig.sol";

contract DeployEscrowFixedPriceScript is Script {
    EscrowFixedPrice escrow;
    address registry;
    address adminManager;
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
        adminManager = PolAmoyConfig.ADMIN_MANAGER;
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        escrow = new EscrowFixedPrice();
        escrow.initialize(address(deployerPublicKey), address(adminManager), address(registry));
        console.log("==escrow addr=%s", address(escrow));
        assert(address(escrow) != address(0));
        vm.stopBroadcast();

        vm.startBroadcast(ownerPrivateKey);
        EscrowRegistry(registry).updateEscrowFixedPrice(address(escrow));
        assert(EscrowRegistry(registry).escrowFixedPrice() == address(escrow));
        vm.stopBroadcast();
    }
}
