// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test, console2 } from "forge-std/Test.sol";
import { ECDSA } from "@solbase/utils/ECDSA.sol";

import { Enums } from "src/common/Enums.sol";
import { EscrowRegistry, IEscrowRegistry } from "src/modules/EscrowRegistry.sol";
import { IEscrowFeeManager } from "src/interfaces/IEscrowFeeManager.sol";
import { IEscrowMilestone } from "src/interfaces/IEscrowMilestone.sol";

/// @title TestUtils
/// @dev Abstract contract providing utility functions for testing escrow-related contracts.
abstract contract TestUtils is Test {
    /// @dev Struct for fixed price escrow signature inputs.
    struct FixedPriceSignatureParams {
        uint256 contractId;
        address contractor;
        address proxy;
        address token;
        uint256 amount;
        Enums.FeeConfig feeConfig;
        bytes32 contractorData;
        address client;
        uint256 ownerPrKey;
    }

    /// @notice Generate a signature for fixed-price escrow.
    /// @param params The `FixedPriceSignatureParams` struct containing all necessary data.
    /// @return The generated signature as bytes.
    function getSignatureFixed(FixedPriceSignatureParams memory params) internal view returns (bytes memory) {
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    params.client,
                    params.contractId,
                    params.contractor,
                    params.token,
                    params.amount,
                    params.feeConfig,
                    params.contractorData,
                    uint256(block.timestamp + 3 hours),
                    params.proxy
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(params.ownerPrKey, ethSignedHash);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Struct for hourly escrow signature inputs.
    struct HourlySignatureParams {
        uint256 contractId;
        address contractor;
        address proxy;
        address token;
        uint256 prepaymentAmount;
        uint256 amountToClaim;
        Enums.FeeConfig feeConfig;
        address client;
        uint256 ownerPrKey;
    }

    /// @notice Generate a signature for hourly escrow.
    /// @param params The `HourlySignatureParams` struct containing all necessary data.
    /// @return The generated signature as bytes.
    function getSignatureHourly(HourlySignatureParams memory params) internal view returns (bytes memory) {
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    params.client,
                    params.contractId,
                    params.contractor,
                    params.token,
                    params.prepaymentAmount,
                    params.amountToClaim,
                    params.feeConfig,
                    uint256(block.timestamp + 3 hours),
                    params.proxy
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(params.ownerPrKey, ethSignedHash);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Struct for milestone escrow signature inputs.
    struct MilestoneSignatureParams {
        uint256 contractId;
        address proxy;
        address token;
        bytes32 milestonesHash;
        address client;
        uint256 ownerPrKey;
    }

    /// @notice Generate a signature for milestone escrow.
    /// @param params The `MilestoneSignatureParams` struct containing all necessary data.
    /// @return The generated signature as bytes.
    function getSignatureMilestone(MilestoneSignatureParams memory params) internal view returns (bytes memory) {
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    params.client,
                    params.contractId,
                    params.token,
                    params.milestonesHash,
                    uint256(block.timestamp + 3 hours),
                    params.proxy
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(params.ownerPrKey, ethSignedHash);
        return abi.encodePacked(r, s, v);
    }

    /// @notice Hash an array of milestones.
    function hashMilestones(IEscrowMilestone.Milestone[] memory milestones) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](milestones.length);
        for (uint256 i = 0; i < milestones.length; i++) {
            hashes[i] = keccak256(
                abi.encode(
                    milestones[i].contractor,
                    milestones[i].amount,
                    milestones[i].contractorData,
                    milestones[i].feeConfig
                )
            );
        }
        return keccak256(abi.encodePacked(hashes));
    }

    /// @dev Struct for fixed price submit authorization inputs.
    struct FixedPriceSubmitSignatureParams {
        uint256 contractId;
        address contractor;
        bytes data;
        bytes32 salt;
        uint256 expiration;
        uint256 nonce;
        address proxy;
        uint256 ownerPrKey;
    }

    /// @notice Generate a signature for fixed-price submit authorization.
    /// @param params The `FixedPriceSubmitSignatureParams` struct containing all necessary data.
    /// @return The generated signature as bytes.
    function getFixedPriceSubmitSignature(FixedPriceSubmitSignatureParams memory params)
        internal
        pure
        returns (bytes memory)
    {
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    params.contractId,
                    params.contractor,
                    params.data,
                    params.salt,
                    params.expiration,
                    params.nonce,
                    params.proxy
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(params.ownerPrKey, ethSignedHash); // Admin signs the submission
        return abi.encodePacked(r, s, v);
    }

    /// @notice Generate a signature for submit functionality.
    function getSubmitSignature(address contractor, uint256 contractorPrKey, bytes memory data, bytes32 salt)
        internal
        pure
        returns (bytes32 contractorDataHash, bytes memory contractorSignature)
    {
        // Generate the contractor's off-chain signature
        contractorDataHash = keccak256(abi.encodePacked(contractor, data, salt));
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(contractorDataHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(contractorPrKey, ethSignedHash); // Simulate contractor's signature
        contractorSignature = abi.encodePacked(r, s, v);
        return (contractorDataHash, contractorSignature);
    }

    /// @notice Compute the total deposit amount and fee.
    function computeDepositAndFeeAmount(
        address registry,
        address escrow,
        uint256 contractId,
        address client,
        uint256 depositAmount,
        Enums.FeeConfig feeConfig
    ) internal view returns (uint256 totalDepositAmount, uint256 feeApplied) {
        address feeManagerAddress = IEscrowRegistry(address(registry)).feeManager();
        IEscrowFeeManager feeManager = IEscrowFeeManager(feeManagerAddress);
        return feeManager.computeDepositAmountAndFee(escrow, contractId, client, depositAmount, feeConfig);
    }

    /// @notice Compute claimable amount and fee.
    function computeClaimableAndFeeAmount(
        address registry,
        address escrow,
        uint256 contractId,
        address contractor,
        uint256 claimAmount,
        Enums.FeeConfig feeConfig
    ) internal view returns (uint256 claimableAmount, uint256 feeAmount, uint256 clientFee) {
        address feeManagerAddress = IEscrowRegistry(address(registry)).feeManager();
        IEscrowFeeManager feeManager = IEscrowFeeManager(feeManagerAddress);
        return feeManager.computeClaimableAmountAndFee(escrow, contractId, contractor, claimAmount, feeConfig);
    }
}
