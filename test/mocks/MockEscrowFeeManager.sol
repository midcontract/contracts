// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEscrowFeeManager} from "src/interfaces/IEscrowFeeManager.sol";
import {Ownable} from "src/libs/Ownable.sol";
import {Enums} from "src/libs/Enums.sol";

/// @title Escrow Fee Manager
/// @notice Manages fee rates and calculations for escrow transactions.
contract MockEscrowFeeManager is Ownable {
    /// @dev Custom errors
    error EscrowFeeManager__FeeTooHigh();
    error EscrowFeeManager__UnsupportedFeeConfiguration();
    error EscrowFeeManager__ZeroAddressProvided();

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

    /// @dev Events
    event DefaultFeesSet(uint256 coverage, uint256 claim);
    event SpecialFeesSet(address user, uint256 coverage, uint256 claim);

    /// @dev Sets initial default fees on contract deployment.
    /// @param _coverage Initial default coverage fee percentage.
    /// @param _claim Initial default claim fee percentage.
    /// @param _owner Address of the initial owner of the fee manager contract.
    constructor(uint16 _coverage, uint16 _claim, address _owner) {
        _updateDefaultFees(_coverage, _claim);
        _initializeOwner(_owner);
    }

    /// @notice Updates the default coverage and claim fees.
    /// @param _coverage New default coverage fee percentage.
    /// @param _claim New default claim fee percentage.
    function updateDefaultFees(uint16 _coverage, uint16 _claim) external onlyOwner {
        _updateDefaultFees(_coverage, _claim);
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
    function computeDepositAmountAndFee(address _client, uint256 _depositAmount, uint256 _feeConfig)
        external
        view
        returns (uint256 totalDepositAmount, uint256 feeApplied)
    {
        FeeRates memory rates =
            (specialFees[_client].coverage != 0 || specialFees[_client].claim != 0) ? specialFees[_client] : defaultFees;

        if (uint256(_feeConfig) == uint256(Enums.FeeConfig.CLIENT_COVERS_ALL)) {
            // If the client covers both the coverage and claim fees
            feeApplied = _depositAmount * (rates.coverage + rates.claim) / MAX_BPS;
            totalDepositAmount = _depositAmount + feeApplied;
        } else if (uint256(_feeConfig) == uint256(Enums.FeeConfig.CLIENT_COVERS_ONLY)) {
            // If the client only covers the coverage fee
            feeApplied = _depositAmount * rates.coverage / MAX_BPS;
            totalDepositAmount = _depositAmount + feeApplied;
        } else if (uint256(_feeConfig) == uint256(Enums.FeeConfig.NO_FEES)) {
            // No fees applied
            totalDepositAmount = _depositAmount;
            feeApplied = 0;
        } else {
            revert EscrowFeeManager__UnsupportedFeeConfiguration();
        }

        return (totalDepositAmount, feeApplied);
    }

    /// @notice Calculates the claimable amount after any applicable fees based on the fee configuration.
    /// @param _contractor The address of the contractor claiming the amount.
    /// @param _claimedAmount The initial claimed amount before fees.
    /// @param _feeConfig The fee configuration to determine which fees to deduct.
    /// @return claimableAmount The amount claimable after fees are deducted.
    /// @return feeDeducted The amount of fees deducted from the claim.
    /// @return clientFee The additional fee amount covered by the client if applicable.
    function computeClaimableAmountAndFee(address _contractor, uint256 _claimedAmount, uint256 _feeConfig)
        external
        view
        returns (uint256 claimableAmount, uint256 feeDeducted, uint256 clientFee)
    {
        FeeRates memory rates = (specialFees[_contractor].claim != 0) ? specialFees[_contractor] : defaultFees;

        if (uint256(_feeConfig) == uint256(Enums.FeeConfig.CLIENT_COVERS_ALL)) {
            // The client covers both coverage and claim fees.
            feeDeducted = 0; // No fee is deducted from the contractor's claim.
            clientFee = _claimedAmount * (rates.coverage + rates.claim) / MAX_BPS;
            claimableAmount = _claimedAmount;
        } else if (uint256(_feeConfig) == uint256(Enums.FeeConfig.CONTRACTOR_COVERS_CLAIM)) {
            // The contractor covers the claim fee.
            feeDeducted = _claimedAmount * rates.claim / MAX_BPS;
            clientFee = 0; // No additional fee covered by the client in this configuration.
            claimableAmount = _claimedAmount - feeDeducted;
        } else if (uint256(_feeConfig) == uint256(Enums.FeeConfig.CLIENT_COVERS_ONLY)) {
            // The client covers the coverage fee, the claim fee is handled by the contractor.
            feeDeducted = _claimedAmount * rates.claim / MAX_BPS;
            clientFee = _claimedAmount * rates.coverage / MAX_BPS; // Client additionally covers this amount.
            claimableAmount = _claimedAmount - feeDeducted;
        } else if (uint256(_feeConfig) == uint256(Enums.FeeConfig.NO_FEES)) {
            // No fees are applicable.
            feeDeducted = 0;
            clientFee = 0;
            claimableAmount = _claimedAmount;
        } else {
            revert EscrowFeeManager__UnsupportedFeeConfiguration();
        }

        return (claimableAmount, feeDeducted, clientFee);
    }

    /// @notice Retrieves the coverage fee percentage for a specific user.
    /// @param _user The user's address.
    /// @return The coverage fee percentage.
    function getCoverageFee(address _user) external view returns (uint16) {
        return specialFees[_user].coverage > 0 ? specialFees[_user].coverage : defaultFees.coverage;
    }

    /// @notice Retrieves the claim fee percentage for a specific user.
    /// @param _user The user's address.
    /// @return The claim fee percentage.
    function getClaimFee(address _user) external view returns (uint16) {
        return specialFees[_user].claim > 0 ? specialFees[_user].claim : defaultFees.claim;
    }

    /// @dev Updates the default coverage and claim fees.
    /// @param _coverage New default coverage fee percentage.
    /// @param _claim New default claim fee percentage.
    function _updateDefaultFees(uint16 _coverage, uint16 _claim) internal {
        if (_coverage > MAX_BPS || _claim > MAX_BPS) revert EscrowFeeManager__FeeTooHigh();
        defaultFees = FeeRates({coverage: _coverage, claim: _claim});
        emit DefaultFeesSet(_coverage, _claim);
    }
}
