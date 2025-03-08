// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Script, console2 } from "forge-std/Script.sol";

import { ECDSA } from "@solbase/utils/ECDSA.sol";
import { SignatureChecker } from "@openzeppelin/utils/cryptography/SignatureChecker.sol";

import { EscrowFixedPrice, IEscrowFixedPrice } from "src/EscrowFixedPrice.sol";
import { EscrowHourly, IEscrowHourly } from "src/EscrowHourly.sol";
import { EscrowMilestone, IEscrowMilestone } from "src/EscrowMilestone.sol";
import { EscrowFactory, IEscrowFactory } from "src/EscrowFactory.sol";
import { EscrowAdminManager, OwnedRoles } from "src/modules/EscrowAdminManager.sol";
import { EscrowFeeManager } from "src/modules/EscrowFeeManager.sol";
import { EscrowRegistry, IEscrowRegistry } from "src/modules/EscrowRegistry.sol";
import { EthSepoliaConfig } from "config/EthSepoliaConfig.sol";
import { PolAmoyConfig } from "config/PolAmoyConfig.sol";
import { Enums } from "src/common/Enums.sol";
import { MockDAI } from "test/mocks/MockDAI.sol";
import { MockUSDT } from "test/mocks/MockUSDT.sol";
import { MockUSDC } from "test/mocks/MockUSDC.sol";
import { TestUtils } from "test/utils/TestUtils.sol";

contract ExecuteEscrowScript is Script, TestUtils {
    address escrow;
    address escrowHourly;
    address factory;
    address registry;
    address adminManager;
    address feeManager;
    address usdtToken;
    address usdcToken;
    address daiToken;
    address owner;
    address newOwner;
    address client;

    IEscrowFixedPrice.DepositRequest deposit;
    EscrowFixedPrice.SubmitRequest submitRequest;
    IEscrowHourly.DepositRequest depositHourly;
    Enums.FeeConfig feeConfig;
    Enums.Status status;
    Enums.EscrowType escrowType;
    bytes32 contractorDataHash;
    bytes32 contractorData;
    bytes32 salt;
    bytes contractData;
    bytes signature;

    address deployerPublicKey;
    uint256 deployerPrivateKey;
    uint256 ownerPrKey;

    uint256 contractId;
    address contractor;
    uint256 contractorPrKey;
    uint256 expiration;

    function setUp() public {
        deployerPublicKey = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        owner = vm.envAddress("OWNER_PUBLIC_KEY");
        ownerPrKey = vm.envUint("OWNER_PRIVATE_KEY");

        escrow = PolAmoyConfig.ESCROW_FIXED_PRICE;
        registry = PolAmoyConfig.REGISTRY_1;
        factory = PolAmoyConfig.FACTORY_1;
        feeManager = PolAmoyConfig.FEE_MANAGER;
        newOwner = PolAmoyConfig.OWNER;
        usdtToken = PolAmoyConfig.MOCK_USDT;
        usdcToken = PolAmoyConfig.MOCK_USDC;
        daiToken = PolAmoyConfig.MOCK_DAI;
        escrowHourly = PolAmoyConfig.ESCROW_HOURLY_1;
        adminManager = PolAmoyConfig.ADMIN_MANAGER;
        client = deployerPublicKey;

        contractId = 1;
        contractor = deployerPublicKey;
        contractorPrKey = deployerPrivateKey;
        expiration = block.timestamp + 3 hours;

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        contractorData = keccak256(abi.encodePacked(contractor, contractData, salt));
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        deploy_and_deposit_escrow_fixed_price();

        deploy_and_deposit_escrow_milestone();

        deploy_and_deposit_escrow_hourly();

        vm.stopBroadcast();
    }

    function deploy_and_deposit_escrow_fixed_price() public {
        // Deploy a new Fixed Price Escrow contract
        address deployedEscrowProxy = EscrowFactory(factory).deployEscrow(Enums.EscrowType.FIXED_PRICE);
        EscrowFixedPrice escrowProxy = EscrowFixedPrice(address(deployedEscrowProxy));

        // Generate the deposit hash from the smart contract
        bytes32 depositHash = EscrowFixedPrice(escrowProxy).getDepositHash(
            client,
            contractId,
            contractor,
            address(usdtToken),
            1000e6,
            Enums.FeeConfig.CLIENT_COVERS_ONLY,
            contractorData,
            expiration
        );

        // Sign the deposit hash with the owner's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrKey, depositHash);
        signature = abi.encodePacked(r, s, v);

        // Prepare the deposit request
        deposit = IEscrowFixedPrice.DepositRequest({
            contractId: contractId,
            contractor: contractor,
            paymentToken: address(usdtToken),
            amount: 1000e6,
            amountToClaim: 0 ether,
            amountToWithdraw: 0 ether,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.ACTIVE,
            escrow: address(escrowProxy),
            expiration: expiration,
            signature: signature
        });

        // Mint and approve payment token
        MockUSDT(usdtToken).mint(address(deployerPublicKey), 1300e6);
        MockUSDT(usdtToken).approve(address(escrowProxy), 1300e6);

        // Execute the deposit transaction
        EscrowFixedPrice(escrowProxy).deposit(deposit);

        // Prepare submit request
        submitRequest = IEscrowFixedPrice.SubmitRequest({
            contractId: contractId,
            data: contractData,
            salt: salt,
            expiration: expiration,
            signature: getFixedPriceSubmitSignature(
                FixedPriceSubmitSignatureParams({
                    contractId: contractId,
                    contractor: contractor,
                    data: contractData,
                    salt: salt,
                    expiration: expiration,
                    proxy: address(escrowProxy),
                    ownerPrKey: ownerPrKey
                })
            )
        });

        // Submit
        EscrowFixedPrice(escrowProxy).submit(submitRequest);

        // Approve
        EscrowFixedPrice(escrowProxy).approve(contractId, 1000e6, address(deployerPublicKey));

        // Claim
        EscrowFixedPrice(escrowProxy).claim(contractId);
    }

    function deploy_and_deposit_escrow_milestone() public {
        address deployedEscrowProxy = EscrowFactory(factory).deployEscrow(Enums.EscrowType.MILESTONE);
        EscrowMilestone escrowProxy = EscrowMilestone(address(deployedEscrowProxy));

        // Compute the hash for milestones
        IEscrowMilestone.Milestone[] memory milestones = new IEscrowMilestone.Milestone[](1);
        milestones[0] = IEscrowMilestone.Milestone({
            contractor: contractor,
            amount: 1 ether,
            amountToClaim: 0,
            amountToWithdraw: 0,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            status: Enums.Status.ACTIVE
        });
        bytes32 milestonesHash = EscrowMilestone(escrowProxy).hashMilestones(milestones);

        // Generate deposit hash
        bytes32 depositHash = EscrowMilestone(escrowProxy).getDepositHash(
            client, contractId, address(daiToken), milestonesHash, block.timestamp + 3 hours
        );

        // Sign the deposit hash off-chain (simulated in test)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrKey, depositHash);
        signature = abi.encodePacked(r, s, v);

        // Construct deposit request with signed hash
        IEscrowMilestone.DepositRequest memory depositMilestone = IEscrowMilestone.DepositRequest({
            contractId: contractId,
            paymentToken: address(daiToken),
            milestonesHash: milestonesHash,
            escrow: address(escrowProxy),
            expiration: block.timestamp + 3 hours,
            signature: signature
        });

        // Mint, approve payment token
        MockDAI(daiToken).mint(address(deployerPublicKey), 1.03 ether);
        MockDAI(daiToken).approve(address(escrowProxy), 1.03 ether);

        // Perform the deposit
        EscrowMilestone(escrowProxy).deposit(depositMilestone, milestones);

        uint256 milestoneId = EscrowMilestone(escrowProxy).getMilestoneCount(1); //contractId
        milestoneId--;

        // Generate the contractor's off-chain signature
        contractorDataHash = keccak256(abi.encodePacked(contractor, contractData, salt));
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(contractorDataHash);
        (v, r, s) = vm.sign(contractorPrKey, ethSignedHash); // Simulate contractor's signature
        bytes memory contractorSignature = abi.encodePacked(r, s, v);

        // Submit
        EscrowMilestone(escrowProxy).submit(contractId, milestoneId, contractData, salt, contractorSignature);

        // Approve
        EscrowMilestone(escrowProxy).approve(contractId, milestoneId, 1 ether, address(deployerPublicKey));

        // Claim
        EscrowMilestone(escrowProxy).claim(contractId, milestoneId);
    }

    function deploy_and_deposit_escrow_hourly() public {
        address deployedEscrowProxy = EscrowFactory(factory).deployEscrow(Enums.EscrowType.HOURLY);
        EscrowHourly escrowProxyHourly = EscrowHourly(address(deployedEscrowProxy));

        // Generate hash using contract function
        bytes32 depositHash = EscrowHourly(escrowProxyHourly).getDepositHash(
            client,
            contractId,
            contractor,
            address(usdcToken),
            0, // prepaymentAmount
            1000e6, // amountToClaim
            Enums.FeeConfig.CLIENT_COVERS_ONLY,
            uint256(block.timestamp + 3 hours)
        );

        // Sign the deposit hash with the owner's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrKey, depositHash);
        signature = abi.encodePacked(r, s, v);

        // Create the deposit request struct using the generated hash and signature
        uint256 amountToClaim = 1000e6;
        depositHourly = IEscrowHourly.DepositRequest({
            contractId: contractId,
            contractor: deployerPublicKey,
            paymentToken: address(usdcToken),
            prepaymentAmount: 0,
            amountToClaim: amountToClaim,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrowProxyHourly),
            expiration: uint256(block.timestamp + 3 hours),
            signature: signature
        });

        // Mint and approve payment token
        MockUSDT(usdcToken).mint(address(deployerPublicKey), 1300e6);
        MockUSDT(usdcToken).approve(address(escrowProxyHourly), 1300e6);

        // Perform the deposit
        EscrowHourly(escrowProxyHourly).deposit(depositHourly);

        uint256 weekId = EscrowHourly(escrowProxyHourly).getWeeksCount(contractId);
        weekId--;

        // Claim
        EscrowHourly(escrowProxyHourly).claim(contractId, weekId);
    }
}
