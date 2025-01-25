// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Enums } from "../common/Enums.sol";

/// @title Interface for Escrow Fee Manager
/// @notice Defines the standard functions and events for an escrow fee management system.
interface IEscrowFeeManager {
    /// @notice Represents fee rates for coverage and claim fees, applicable at multiple levels.
    /// @dev This structure is used to define fee rates at various priority levels:
    /// contract-specific, instance-specific, user-specific, or as a default.
    /// @param coverage The coverage fee percentage.
    /// @param claim The claim fee percentage.
    struct FeeRates {
        uint16 coverage; // Coverage fee percentage.
        uint16 claim; // Claim fee percentage.
    }

    /// @dev Thrown when the specified fee exceeds the maximum allowed basis points.
    error FeeTooHigh();

    /// @dev Thrown when an unsupported fee configuration is used.
    error UnsupportedFeeConfiguration();

    /// @dev Thrown when an operation includes or results in a zero address where it is not allowed.
    error ZeroAddressProvided();

    /// @notice Thrown when an unauthorized account attempts an action.
    error UnauthorizedAccount();

    /// @notice Emitted when the default fees are updated.
    /// @param coverage The new default coverage fee as a percentage in basis points.
    /// @param claim The new default claim fee as a percentage in basis points.
    event DefaultFeesSet(uint16 coverage, uint16 claim);

    /// @notice Emitted when specific fees are set for a user.
    /// @param user The address of the user for whom specific fees are set.
    /// @param coverage The specific coverage fee as a percentage in basis points.
    /// @param claim The specific claim fee as a percentage in basis points.
    event UserSpecificFeesSet(address indexed user, uint16 coverage, uint16 claim);

    /// @notice Emitted when specific fees are set for an instance (proxy).
    /// @param instance The address of the instance for which to set specific fees.
    /// @param coverage The specific coverage fee as a percentage in basis points.
    /// @param claim The special claim fee as a percentage in basis points.
    event InstanceFeesSet(address indexed instance, uint16 coverage, uint16 claim);

    /// @notice Emitted when specific fees are set for a particular contract ID within an instance.
    /// @param instance The address of the instance for which to set specific fees.
    /// @param contractId The ID of the contract within the instance.
    /// @param coverage The specific coverage fee as a percentage in basis points.
    /// @param claim The specific claim fee as a percentage in basis points.
    event ContractSpecificFeesSet(address indexed instance, uint256 indexed contractId, uint16 coverage, uint16 claim);

    /// @notice Emitted when the contract-specific fees are reset to the default configuration.
    /// @param instance The address of the instance under which the contract falls.
    /// @param contractId The unique identifier for the contract whose fees were reset.
    event ContractSpecificFeesReset(address indexed instance, uint256 indexed contractId);

    /// @notice Emitted when the instance-specific fees are reset to the default configuration.
    /// @param instance The address of the instance whose fees were reset.
    event InstanceSpecificFeesReset(address indexed instance);

    /// @notice Emitted when the user-specific fees are reset to the default configuration.
    /// @param user The address of the user whose fees were reset.
    event UserSpecificFeesReset(address indexed user);

    /// @notice Computes the total deposit amount including any applicable fees.
    /// @param instance The address of the deployed proxy instance (e.g., EscrowHourly or EscrowMilestone).
    /// @param contractId The specific contract ID within the proxy instance.
    /// @param client The address of the client making the deposit.
    /// @param depositAmount The amount of the deposit before fees are applied.
    /// @param feeConfig The fee configuration to determine which fees to apply.
    /// @return totalDepositAmount The total amount after fees are added.
    /// @return feeApplied The amount of fees applied based on the configuration.
    function computeDepositAmountAndFee(
        address instance,
        uint256 contractId,
        address client,
        uint256 depositAmount,
        Enums.FeeConfig feeConfig
    ) external view returns (uint256 totalDepositAmount, uint256 feeApplied);

    /// @notice Calculates the amount a contractor can claim, accounting for any applicable fees.
    /// @param instance The address of the deployed proxy instance (e.g., EscrowHourly or EscrowMilestone).
    /// @param contractId The specific contract ID within the proxy instance.
    /// @param contractor The address of the contractor claiming the funds.
    /// @param claimedAmount The amount being claimed before fees.
    /// @param feeConfig The fee configuration to determine which fees to deduct.
    /// @return claimableAmount The amount the contractor can claim after fee deductions.
    /// @return feeDeducted The amount of fees deducted based on the configuration.
    /// @return clientFee The additional fee amount covered by the client if applicable.
    function computeClaimableAmountAndFee(
        address instance,
        uint256 contractId,
        address contractor,
        uint256 claimedAmount,
        Enums.FeeConfig feeConfig
    ) external view returns (uint256 claimableAmount, uint256 feeDeducted, uint256 clientFee);

    /// @notice Retrieves the default fee rates for coverage and claim.
    /// @return coverage The default fee percentage for coverage charges.
    /// @return claim The default fee percentage for claim charges.
    /// @dev This function returns two uint16 values representing the default percentages for coverage and claim fees
    ///     respectively.
    function defaultFees() external view returns (uint16, uint16);

    /// @notice Retrieves the applicable fee rates based on priority for a given contract, instance, and user.
    /// @param instance The address of the instance under which the contract falls.
    /// @param contractId The unique identifier for the contract to which the fees apply.
    /// @param user The address of the user involved in the transaction.
    /// @return The applicable `FeeRates` structure containing the coverage and claim fee rates.
    function getApplicableFees(address instance, uint256 contractId, address user)
        external
        view
        returns (FeeRates memory);
}
