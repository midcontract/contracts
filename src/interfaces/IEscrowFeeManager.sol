// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Enums} from "src/libs/Enums.sol";

/// @title Interface for Escrow Fee Manager
/// @notice Defines the standard functions and events for an escrow fee management system.
interface IEscrowFeeManager {
    /// @dev Thrown when the specified fee exceeds the maximum allowed basis points.
    error EscrowFeeManager__FeeTooHigh();

    /// @dev Thrown when an unsupported fee configuration is used.
    error EscrowFeeManager__UnsupportedFeeConfiguration();

    /// @dev Thrown when an operation includes or results in a zero address where it is not allowed.
    error EscrowFeeManager__ZeroAddressProvided();

    /// @notice Emitted when the default fees are updated.
    /// @param coverage The new default coverage fee as a percentage in basis points.
    /// @param claim The new default claim fee as a percentage in basis points.
    event DefaultFeesSet(uint256 coverage, uint256 claim);

    /// @notice Emitted when special fees are set for a specific user.
    /// @param user The address of the user for whom special fees are set.
    /// @param coverage The special coverage fee as a percentage in basis points.
    /// @param claim The special claim fee as a percentage in basis points.
    event SpecialFeesSet(address user, uint256 coverage, uint256 claim);

    /// @notice Computes the total deposit amount including any applicable fees.
    /// @param client The address of the client making the deposit.
    /// @param depositAmount The amount of the deposit before fees are applied.
    /// @param feeConfig The fee configuration to determine which fees to apply.
    /// @return totalDepositAmount The total amount after fees are added.
    /// @return feeApplied The amount of fees applied based on the configuration.
    function computeDepositAmountAndFee(address client, uint256 depositAmount, Enums.FeeConfig feeConfig)
        external
        view
        returns (uint256 totalDepositAmount, uint256 feeApplied);

    /// @notice Calculates the amount a contractor can claim, accounting for any applicable fees.
    /// @param contractor The address of the contractor claiming the funds.
    /// @param claimedAmount The amount being claimed before fees.
    /// @param feeConfig The fee configuration to determine which fees to deduct.
    /// @return claimableAmount The amount the contractor can claim after fee deductions.
    /// @return feeDeducted The amount of fees deducted based on the configuration.
    /// @return clientFee The additional fee amount covered by the client if applicable.
    function computeClaimableAmountAndFee(address contractor, uint256 claimedAmount, Enums.FeeConfig feeConfig)
        external
        view
        returns (uint256 claimableAmount, uint256 feeDeducted, uint256 clientFee);

    /// @notice Retrieves the coverage fee percentage for a specific user.
    /// @param user The user's address whose fee rate is being queried.
    /// @return The coverage fee percentage for the specified user.
    function getCoverageFee(address user) external view returns (uint16);

    /// @notice Retrieves the claim fee percentage for a specific user.
    /// @param user The user's address whose fee rate is being queried.
    /// @return The claim fee percentage for the specified user.
    function getClaimFee(address user) external view returns (uint16);

    /// @notice Retrieves the default fee rates for coverage and claim.
    /// @return coverage The default fee percentage for coverage charges.
    /// @return claim The default fee percentage for claim charges.
    /// @dev This function returns two uint16 values representing the default percentages for coverage and claim fees respectively.
    function defaultFees() external view returns (uint16, uint16);
}
