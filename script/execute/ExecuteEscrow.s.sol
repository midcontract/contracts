// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Script, console } from "forge-std/Script.sol";

import { ECDSA } from "@solbase/utils/ECDSA.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import { EscrowFixedPrice, IEscrowFixedPrice } from "src/EscrowFixedPrice.sol";
import { EscrowHourly, IEscrowHourly } from "src/EscrowHourly.sol";
import { EscrowFactory, IEscrowFactory } from "src/EscrowFactory.sol";
import { EscrowAdminManager, OwnedRoles } from "src/modules/EscrowAdminManager.sol";
import { EscrowFeeManager } from "src/modules/EscrowFeeManager.sol";
import { EscrowRegistry, IEscrowRegistry } from "src/modules/EscrowRegistry.sol";
import { EthSepoliaConfig } from "config/EthSepoliaConfig.sol";
import { PolAmoyConfig } from "config/PolAmoyConfig.sol";
import { Enums } from "src/common/Enums.sol";
import { MockDAI } from "test/mocks/MockDAI.sol";
import { MockUSDT } from "test/mocks/MockUSDT.sol";

contract ExecuteEscrowScript is Script {
    address escrow;
    address escrowHourly;
    address factory;
    address registry;
    address adminManager;
    address feeManager;
    address usdtToken;
    address owner;
    address newOwner;
    address client;

    IEscrowFixedPrice.DepositRequest deposit;
    IEscrowHourly.DepositRequest depositHourly;
    Enums.FeeConfig feeConfig;
    Enums.Status status;
    Enums.EscrowType escrowType;
    bytes32 contractorDataHash;
    bytes32 contractorData;
    bytes32 salt;
    bytes contractData;
    bytes contractorSignature;
    bytes signature;

    address deployerPublicKey;
    uint256 deployerPrivateKey;
    uint256 ownerPrKey;

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
        escrowHourly = PolAmoyConfig.ESCROW_HOURLY_1;
        adminManager = PolAmoyConfig.ADMIN_MANAGER;
        client = deployerPublicKey;

        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        contractorData = keccak256(abi.encodePacked(contractData, salt));

        // Generate the contractor's off-chain signature
        contractorDataHash = keccak256(abi.encodePacked(deployerPublicKey, contractData, salt));
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(contractorDataHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPrivateKey, ethSignedHash); // Simulate contractor's signature
        contractorSignature = abi.encodePacked(r, s, v);

        uint256 expiration = block.timestamp + 1 days;

        // Sign deposit authorization
        bytes32 hash = keccak256(
            abi.encodePacked(
                address(this), address(0), address(usdtToken), uint256(1000e6), feeConfig, expiration, address(escrow)
            )
        );
        ethSignedHash = ECDSA.toEthSignedMessageHash(hash);
        (v, r, s) = vm.sign(ownerPrKey, ethSignedHash); // Admin signs
        signature = abi.encodePacked(r, s, v);

        deposit = IEscrowFixedPrice.DepositRequest({
            contractId: 1,
            contractor: address(0),
            paymentToken: address(usdtToken),
            amount: 1000e6,
            amountToClaim: 0,
            amountToWithdraw: 0,
            contractorData: contractorData,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ALL,
            status: Enums.Status.ACTIVE,
            escrow: address(escrow),
            expiration: expiration,
            signature: signature
        });
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        deploy_and_deposit_escrow_hourly();

        vm.stopBroadcast();
    }

    function deploy_and_deposit_escrow_fixed_price() public {
        // EscrowRegistry(registry).transferOwnership(newOwner);
        // assert(address(EscrowFixedPrice(escrow).owner()) == deployerPublicKey);
        // EscrowFixedPrice(escrow).transferOwnership(newOwner);
        // assert(address(EscrowFixedPrice(escrow).owner()) == newOwner);

        // assert(address(EscrowFactory(factory).owner()) == deployerPublicKey);
        // EscrowFactory(factory).transferOwnership(newOwner);
        // assert(address(EscrowFactory(factory).owner()) == newOwner);

        // EscrowFeeManager(feeManager).transferOwnership(newOwner);

        (bool sent,) = newOwner.call{ value: 0.055 ether }("");
        require(sent, "Failed to send Ether");

        // // set treasury
        EscrowRegistry(registry).setFixedTreasury(owner);

        // // deploy new escrow
        address deployedEscrowProxy = EscrowFactory(factory).deployEscrow(escrowType);
        EscrowFixedPrice escrowProxy = EscrowFixedPrice(address(deployedEscrowProxy));

        // // mint, approve payment token
        MockUSDT(usdtToken).mint(address(deployerPublicKey), 1800e6);
        MockUSDT(usdtToken).approve(address(escrowProxy), 1800e6);

        // // deposit
        EscrowFixedPrice(escrowProxy).deposit(deposit);

        // // submit
        contractData = bytes("contract_data");
        salt = keccak256(abi.encodePacked(uint256(42)));
        // bytes32 contractorDataHash = Escrow(escrowProxy).getContractorDataHash(contractData, salt);
        uint256 currentContractId = 1;

        // // submit
        EscrowFixedPrice(escrowProxy).submit(currentContractId, contractData, salt, contractorSignature);

        // // approve
        EscrowFixedPrice(escrowProxy).approve(currentContractId, 1000e6, address(deployerPublicKey));

        // // claim
        EscrowFixedPrice(escrowProxy).claim(currentContractId);
    }

    function deploy_and_deposit_escrow_hourly() public {
        address deployedEscrowProxy;
        escrowType = Enums.EscrowType.HOURLY;
        deployedEscrowProxy = EscrowFactory(factory).deployEscrow(escrowType);
        EscrowHourly escrowProxyHourly = EscrowHourly(address(deployedEscrowProxy));
        // mint, approve payment token
        MockUSDT(usdtToken).mint(address(deployerPublicKey), 1300e6);
        MockUSDT(usdtToken).approve(address(escrowProxyHourly), 1300e6);
        // deposit
        uint256 currentContractId = 1;
        uint256 depositHourlyAmount = 1000e6;
        depositHourly = IEscrowHourly.DepositRequest({
            contractId: currentContractId,
            contractor: deployerPublicKey,
            paymentToken: address(usdtToken),
            prepaymentAmount: depositHourlyAmount,
            amountToClaim: 0,
            feeConfig: Enums.FeeConfig.CLIENT_COVERS_ONLY,
            escrow: address(escrowProxyHourly),
            expiration: uint256(block.timestamp + 3 hours),
            signature: _getSignatureHourly(
                currentContractId,
                deployerPublicKey,
                address(escrowProxyHourly),
                address(usdtToken),
                depositHourlyAmount,
                0,
                Enums.FeeConfig.CLIENT_COVERS_ONLY
            )
        });
        (uint256 totalDepositAmount, uint256 feeApplied) = EscrowFeeManager(feeManager).computeDepositAmountAndFee(
            address(escrowProxyHourly),
            currentContractId,
            deployerPublicKey,
            depositHourlyAmount,
            Enums.FeeConfig.CLIENT_COVERS_ONLY
        );
        (feeApplied);
        assert(totalDepositAmount > depositHourlyAmount);
        escrowProxyHourly.deposit(depositHourly);
    }

    function _getSignatureHourly(
        uint256 _contractId,
        address _contractor,
        address _proxy,
        address _token,
        uint256 _prepaymentAmount,
        uint256 _amountToClaim,
        Enums.FeeConfig _feeConfig
    ) internal returns (bytes memory) {
        // Sign deposit authorization
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    client,
                    _contractId,
                    address(_contractor),
                    address(_token),
                    uint256(_prepaymentAmount),
                    uint256(_amountToClaim),
                    _feeConfig,
                    uint256(block.timestamp + 3 hours),
                    address(_proxy)
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrKey, ethSignedHash); // Admin signs
        return signature = abi.encodePacked(r, s, v);
    }
}
