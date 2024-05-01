// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Interface for Escrow Fee Manager
/// @notice Defines the standard functions and events for an escrow fee management system.
interface IEscrowFeeManager {
    /// @dev Thrown when the specified fee exceeds the maximum allowed basis points.
    error EscrowFeeManager__FeeTooHigh();

    /// @dev Thrown when an invalid fee configuration is used.
    error EscrowFeeManager__InvalidFeeConfig();

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
    function computeDepositAmount(address client, uint256 depositAmount, FeeConfig feeConfig)
        external
        view
        returns (uint256 totalDepositAmount, uint256 feeApplied);

    /// @notice Calculates the amount a contractor can claim, accounting for any applicable fees.
    /// @param contractor The address of the contractor claiming the funds.
    /// @param claimedAmount The amount being claimed before fees.
    /// @param feeConfig The fee configuration to determine which fees to deduct.
    /// @return claimableAmount The amount the contractor can claim after fee deductions.
    /// @return feeDeducted The amount of fees deducted based on the configuration.
    function computeClaimableAmount(address contractor, uint256 claimedAmount, FeeConfig feeConfig)
        external
        view
        returns (uint256 claimableAmount, uint256 feeDeducted);

    /// @notice Retrieves the coverage fee percentage for a specific user.
    /// @param user The user's address whose fee rate is being queried.
    /// @return The coverage fee percentage for the specified user.
    function getCoverageFee(address user) external view returns (uint256);

    /// @notice Retrieves the claim fee percentage for a specific user.
    /// @param user The user's address whose fee rate is being queried.
    /// @return The claim fee percentage for the specified user.
    function getClaimFee(address user) external view returns (uint256);
}