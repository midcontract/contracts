// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEscrowFeeManager} from "../interfaces/IEscrowFeeManager.sol";
import {Owned} from "../libs/Owned.sol";

/// @title Escrow Fee Manager
/// @notice Manages fee rates and calculations for escrow transactions.
contract EscrowFeeManager is IEscrowFeeManager, Owned {
    /// @notice The maximum allowable percentage in basis points (100%).
    uint256 public constant MAX_BPS = 100_00; // 100%

    /// @notice Stores default fee rates for coverage and claim.
    struct FeeRates {
        uint16 coverage; // Coverage fee percentage
        uint16 claim; // Claim fee percentage
    }

    /// @notice The default fees applied if no special fees are set for a user.
    FeeRates public defaultFees;

    /// @notice Mapping from user addresses to their specific fee rates.
    mapping(address user => FeeRates feeType) public specialFees;

    /// @notice Enumerates the different configurations of fee responsibilities.
    enum FeeConfig {
        CLIENT_COVERS_ALL, // Client pays both coverage and claim fees (total 8%)
        CLIENT_COVERS_ONLY, // Client pays only the coverage fee (3%), contractor responsible for the claim fee (5%)
        CONTRACTOR_COVERS_CLAIM, // Contractor pays the claim fee (5%), no coverage fee applied
        NO_FEES // No fees applied (0%)
    }

    /// @dev Sets initial default fees on contract deployment.
    /// @param _coverage Initial default coverage fee percentage.
    /// @param _claim Initial default claim fee percentage.
    constructor(uint16 _coverage, uint16 _claim) Owned(msg.sender) {
        updateDefaultFees(_coverage, _claim);
    }

    /// @notice Updates the default coverage and claim fees.
    /// @param _coverage New default coverage fee percentage.
    /// @param _claim New default claim fee percentage.
    function updateDefaultFees(uint16 _coverage, uint16 _claim) public onlyOwner {
        if (_coverage > MAX_BPS || _claim > MAX_BPS) revert EscrowFeeManager__FeeTooHigh();
        defaultFees = FeeRates({coverage: _coverage, claim: _claim});
        emit DefaultFeesSet(_coverage, _claim);
    }

    /// @notice Sets special fee rates for a specific user.
    /// @param _user The address of the user for whom to set special fees.
    /// @param _coverage Special coverage fee percentage for the user.
    /// @param _claim Special claim fee percentage for the user.
    function setSpecialFees(address _user, uint16 _coverage, uint16 _claim) external onlyOwner {
        if (_coverage > MAX_BPS || _claim > MAX_BPS) revert EscrowFeeManager__FeeTooHigh();
        if (_user == address(0)) revert EscrowFeeManager__ZeroAddressProvided();
        specialFees[_user] = FeeRates({coverage: _coverage, claim: _claim});
        emit SpecialFeesSet(_user, _coverage, _claim);
    }

    /// @notice Calculates the total deposit amount including any applicable fees based on the fee configuration.
    /// @param _client The address of the client paying the deposit.
    /// @param _depositAmount The initial deposit amount before fees.
    /// @param _feeConfig The fee configuration to determine which fees to apply.
    /// @return totalDepositAmount The total amount after fees are added.
    /// @return feeApplied The amount of fees added to the deposit.
    function computeDepositAmount(address _client, uint256 _depositAmount, FeeConfig _feeConfig)
        external
        view
        returns (uint256 totalDepositAmount, uint256 feeApplied)
    {
        FeeRates memory rates =
            (specialFees[_client].coverage != 0 || specialFees[_client].claim != 0) ? specialFees[_client] : defaultFees;

        if (_feeConfig == FeeConfig.CLIENT_COVERS_ALL) {
            // If the client covers both the coverage and claim fees
            feeApplied = _depositAmount * (rates.coverage + rates.claim) / MAX_BPS;
            totalDepositAmount = _depositAmount + feeApplied;
        } else if (_feeConfig == FeeConfig.CLIENT_COVERS_ONLY) {
            // If the client only covers the coverage fee
            feeApplied = _depositAmount * rates.coverage / MAX_BPS;
            totalDepositAmount = _depositAmount + feeApplied;
        } else {
            // No fees applied
            totalDepositAmount = _depositAmount;
            feeApplied = 0;
        }

        return (totalDepositAmount, feeApplied);
    }

    /// @notice Calculates the claimable amount after any applicable fees based on the fee configuration.
    /// @param _contractor The address of the contractor claiming the amount.
    /// @param _claimedAmount The initial claimed amount before fees.
    /// @param _feeConfig The fee configuration to determine which fees to deduct.
    /// @return claimableAmount The amount claimable after fees are deducted.
    /// @return feeDeducted The amount of fees deducted from the claim.
    function computeClaimableAmount(address _contractor, uint256 _claimedAmount, FeeConfig _feeConfig)
        external
        view
        returns (uint256 claimableAmount, uint256 feeDeducted)
    {
        FeeRates memory rates = (specialFees[_contractor].claim != 0) ? specialFees[_contractor] : defaultFees;

        if (_feeConfig == FeeConfig.CLIENT_COVERS_ALL) {
            claimableAmount = _claimedAmount;
            feeDeducted = 0;
        } else if (_feeConfig == FeeConfig.CONTRACTOR_COVERS_CLAIM || _feeConfig == FeeConfig.CLIENT_COVERS_ONLY) {
            feeDeducted = _claimedAmount * rates.claim / MAX_BPS;
            claimableAmount = _claimedAmount - feeDeducted;
        } else {
            claimableAmount = _claimedAmount;
            feeDeducted = 0;
        }

        return (claimableAmount, feeDeducted);
    }

    /// @notice Retrieves the coverage fee percentage for a specific user.
    /// @param _user The user's address.
    /// @return The coverage fee percentage.
    function getCoverageFee(address _user) external view returns (uint256) {
        return specialFees[_user].coverage > 0 ? specialFees[_user].coverage : defaultFees.coverage;
    }

    /// @notice Retrieves the claim fee percentage for a specific user.
    /// @param _user The user's address.
    /// @return The claim fee percentage.
    function getClaimFee(address _user) external view returns (uint256) {
        return specialFees[_user].claim > 0 ? specialFees[_user].claim : defaultFees.claim;
    }
}
