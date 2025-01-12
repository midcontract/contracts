// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IEscrowAdminManager } from "../interfaces/IEscrowAdminManager.sol";
import { IEscrowFeeManager } from "../interfaces/IEscrowFeeManager.sol";
import { Enums } from "../common/Enums.sol";

/// @title Escrow Fee Manager
/// @notice Manages fee rates and calculations for escrow transactions.
contract EscrowFeeManager is IEscrowFeeManager {
    /// @notice Address of the adminManager contract managing platform administrators.
    IEscrowAdminManager public adminManager;

    /// @notice The maximum allowable percentage in basis points (100%).
    uint256 public constant MAX_BPS = 10_000; // 100%

    /// @notice The maximum allowable fee percentage in basis points (e.g., 50%).
    uint256 public constant MAX_FEE_BPS = 5000; // 50%

    /// @notice The default fees applied if no special fees are set (4th priority).
    FeeRates public defaultFees;

    /// @notice Mapping from user addresses to their specific fee rates (3rd priority).
    mapping(address user => FeeRates feeType) public userSpecificFees;

    /// @notice Mapping from instance addresses (proxies) to their specific fee rates (2nd priority).
    mapping(address instance => FeeRates feeType) public instanceFees;

    /// @notice Mapping from instance addresses to a mapping of contract IDs to their specific fee rates (1st priority).
    mapping(address instance => mapping(uint256 contractId => FeeRates)) public contractSpecificFees;

    /// @notice Restricts access to admin-only functions.
    modifier onlyAdmin() {
        if (!adminManager.isAdmin(msg.sender)) revert EscrowFeeManager__UnauthorizedAccount();
        _;
    }

    /// @notice Initializes the fee manager contract with the adminManager and default fees.
    /// @param _adminManager Address of the adminManager contract of the escrow platform.
    /// @param _coverage Initial default coverage fee percentage.
    /// @param _claim Initial default claim fee percentage.
    constructor(address _adminManager, uint16 _coverage, uint16 _claim) {
        if (_adminManager == address(0)) revert EscrowFeeManager__ZeroAddressProvided();
        adminManager = IEscrowAdminManager(_adminManager);
        _setDefaultFees(_coverage, _claim);
    }

    /// @notice Updates the default coverage and claim fees.
    /// @param _coverage New default coverage fee percentage.
    /// @param _claim New default claim fee percentage.
    function setDefaultFees(uint16 _coverage, uint16 _claim) external onlyAdmin {
        _setDefaultFees(_coverage, _claim);
    }

    /// @notice Sets specific fee rates for a user.
    /// @param _user The address of the user for whom to set specific fees.
    /// @param _coverage Specific coverage fee percentage for the user.
    /// @param _claim Specific claim fee percentage for the user.
    function setUserSpecificFees(address _user, uint16 _coverage, uint16 _claim) external onlyAdmin {
        if (_coverage > MAX_FEE_BPS || _claim > MAX_FEE_BPS) revert EscrowFeeManager__FeeTooHigh();
        if (_user == address(0)) revert EscrowFeeManager__ZeroAddressProvided();
        userSpecificFees[_user] = FeeRates({ coverage: _coverage, claim: _claim });
        emit UserSpecificFeesSet(_user, _coverage, _claim);
    }

    /// @notice Sets specific fee rates for an instance (proxy).
    /// @param _instance The address of the instance for which to set specific fees.
    /// @param _coverage Specific coverage fee percentage for the instance.
    /// @param _claim Specific claim fee percentage for the instance.
    function setInstanceFees(address _instance, uint16 _coverage, uint16 _claim) external onlyAdmin {
        if (_coverage > MAX_FEE_BPS || _claim > MAX_FEE_BPS) revert EscrowFeeManager__FeeTooHigh();
        if (_instance == address(0)) revert EscrowFeeManager__ZeroAddressProvided();
        instanceFees[_instance] = FeeRates({ coverage: _coverage, claim: _claim });
        emit InstanceFeesSet(_instance, _coverage, _claim);
    }

    /// @notice Sets specific fee rates for a particular contract ID within an instance.
    /// @param _instance The address of the instance containing the contract.
    /// @param _contractId The ID of the contract within the instance.
    /// @param _coverage Specific coverage fee percentage for the contract.
    /// @param _claim Specific claim fee percentage for the contract.
    function setContractSpecificFees(address _instance, uint256 _contractId, uint16 _coverage, uint16 _claim)
        external
        onlyAdmin
    {
        if (_coverage > MAX_FEE_BPS || _claim > MAX_FEE_BPS) revert EscrowFeeManager__FeeTooHigh();
        if (_instance == address(0)) revert EscrowFeeManager__ZeroAddressProvided();
        contractSpecificFees[_instance][_contractId] = FeeRates({ coverage: _coverage, claim: _claim });
        emit ContractSpecificFeesSet(_instance, _contractId, _coverage, _claim);
    }

    /// @notice Resets contract-specific fees to default by removing the fee entry for a given contract ID.
    /// @param _instance The address of the instance under which the contract falls.
    /// @param _contractId The unique identifier for the contract whose fees are being reset.
    function resetContractSpecificFees(address _instance, uint256 _contractId) external onlyAdmin {
        delete contractSpecificFees[_instance][_contractId];
        emit ContractSpecificFeesReset(_instance, _contractId);
    }

    /// @notice Resets instance-specific fees to default by removing the fee entry for the given instance.
    /// @param _instance The address of the instance for which fees are being reset.
    function resetInstanceSpecificFees(address _instance) external onlyAdmin {
        delete instanceFees[_instance];
        emit InstanceSpecificFeesReset(_instance);
    }

    /// @notice Resets user-specific fees to default by removing the fee entry for the specified user.
    /// @param _user The address of the user whose fees are being reset.
    function resetUserSpecificFees(address _user) external onlyAdmin {
        delete userSpecificFees[_user];
        emit UserSpecificFeesReset(_user);
    }

    /// @notice Resets all higher-priority fees (contract, instance, and user-specific fees) to default in a single
    ///     call.
    /// @param _instance The address of the instance containing the contract to be reset.
    /// @param _contractId The unique identifier for the contract whose fees are being reset.
    /// @param _user The address of the user whose fees are being reset.
    function resetAllToDefault(address _instance, uint256 _contractId, address _user) external onlyAdmin {
        delete contractSpecificFees[_instance][_contractId];
        delete instanceFees[_instance];
        delete userSpecificFees[_user];

        emit ContractSpecificFeesReset(_instance, _contractId);
        emit InstanceSpecificFeesReset(_instance);
        emit UserSpecificFeesReset(_user);
    }

    /// @notice Calculates the total deposit amount including any applicable fees based on the fee configuration.
    /// @dev This function calculates fees by prioritizing specific fee configurations in the following order:
    ///      contract-level fees (highest priority), instance-level fees, user-specific fees, and default fees (lowest
    ///     priority).
    /// @param _instance The address of the deployed proxy instance (e.g., EscrowHourly or EscrowMilestone).
    /// @param _contractId The specific contract ID within the proxy instance, if applicable, for contract-level fee
    ///     overrides.
    /// @param _client The address of the client paying the deposit.
    /// @param _depositAmount The initial deposit amount before fees.
    /// @param _feeConfig The fee configuration to determine which fees to apply.
    /// @return totalDepositAmount The total amount after fees are added.
    /// @return feeApplied The amount of fees added to the deposit.
    function computeDepositAmountAndFee(
        address _instance,
        uint256 _contractId,
        address _client,
        uint256 _depositAmount,
        Enums.FeeConfig _feeConfig
    ) external view returns (uint256 totalDepositAmount, uint256 feeApplied) {
        FeeRates memory rates = _getApplicableFees(_instance, _contractId, _client);

        if (_feeConfig == Enums.FeeConfig.CLIENT_COVERS_ALL) {
            // If the client covers both the coverage and claim fees.
            feeApplied = _depositAmount * (rates.coverage + rates.claim) / MAX_BPS;
            totalDepositAmount = _depositAmount + feeApplied;
        } else if (_feeConfig == Enums.FeeConfig.CLIENT_COVERS_ONLY) {
            // If the client only covers the coverage fee.
            feeApplied = _depositAmount * rates.coverage / MAX_BPS;
            totalDepositAmount = _depositAmount + feeApplied;
        } else if (_feeConfig == Enums.FeeConfig.NO_FEES) {
            // No fees applied.
            totalDepositAmount = _depositAmount;
            feeApplied = 0;
        } else {
            revert EscrowFeeManager__UnsupportedFeeConfiguration();
        }

        return (totalDepositAmount, feeApplied);
    }

    /// @notice Calculates the claimable amount after any applicable fees based on the fee configuration.
    /// @dev This function calculates fees by prioritizing specific fee configurations in the following order:
    ///     contract-level fees (highest priority), instance-level fees, user-specific fees, and default fees (lowest
    ///     priority).
    /// @param _instance The address of the deployed proxy instance (e.g., EscrowFixedPrice or EscrowMilestone).
    /// @param _contractId The specific contract ID within the proxy instance.
    /// @param _contractor The address of the contractor claiming the amount.
    /// @param _claimedAmount The initial claimed amount before fees.
    /// @param _feeConfig The fee configuration to determine which fees to deduct.
    /// @return claimableAmount The amount claimable after fees are deducted.
    /// @return feeDeducted The amount of fees deducted from the claim.
    /// @return clientFee The additional fee amount covered by the client if applicable.
    function computeClaimableAmountAndFee(
        address _instance,
        uint256 _contractId,
        address _contractor,
        uint256 _claimedAmount,
        Enums.FeeConfig _feeConfig
    ) external view returns (uint256 claimableAmount, uint256 feeDeducted, uint256 clientFee) {
        FeeRates memory rates = _getApplicableFees(_instance, _contractId, _contractor);

        if (_feeConfig == Enums.FeeConfig.CLIENT_COVERS_ALL) {
            // The client covers both coverage and claim fees.
            feeDeducted = 0; // No fee is deducted from the contractor's claim.
            clientFee = _claimedAmount * (rates.coverage + rates.claim) / MAX_BPS;
            claimableAmount = _claimedAmount;
        } else if (_feeConfig == Enums.FeeConfig.CONTRACTOR_COVERS_CLAIM) {
            // The contractor covers the claim fee.
            feeDeducted = _claimedAmount * rates.claim / MAX_BPS;
            clientFee = 0; // No additional fee covered by the client in this configuration.
            claimableAmount = _claimedAmount - feeDeducted;
        } else if (_feeConfig == Enums.FeeConfig.CLIENT_COVERS_ONLY) {
            // The client covers the coverage fee, the claim fee is handled by the contractor.
            feeDeducted = _claimedAmount * rates.claim / MAX_BPS;
            clientFee = _claimedAmount * rates.coverage / MAX_BPS; // Client additionally covers this amount.
            claimableAmount = _claimedAmount - feeDeducted;
        } else if (_feeConfig == Enums.FeeConfig.NO_FEES) {
            // No fees are applicable.
            feeDeducted = 0;
            clientFee = 0;
            claimableAmount = _claimedAmount;
        } else {
            revert EscrowFeeManager__UnsupportedFeeConfiguration();
        }

        return (claimableAmount, feeDeducted, clientFee);
    }

    /// @notice Retrieves the applicable fee rates based on priority for a given contract, instance, and user.
    /// @dev This function returns the highest-priority fee rates among contract-specific, instance-specific,
    ///     user-specific, or default fees based on the configured hierarchy.
    /// @param _instance The address of the instance under which the contract falls.
    /// @param _contractId The unique identifier for the contract to which the fees apply.
    /// @param _user The address of the user involved in the transaction.
    /// @return The applicable `FeeRates` structure containing the coverage and claim fee rates.
    function getApplicableFees(address _instance, uint256 _contractId, address _user)
        external
        view
        returns (FeeRates memory)
    {
        return _getApplicableFees(_instance, _contractId, _user);
    }

    /// @dev Retrieves applicable fees with the following priority:
    /// Contract-specific > Instance-specific > User-specific > Default.
    function _getApplicableFees(address _instance, uint256 _contractId, address _user)
        internal
        view
        returns (FeeRates memory rates)
    {
        rates = contractSpecificFees[_instance][_contractId];
        if (rates.coverage != 0 || rates.claim != 0) return rates; // 1st priority

        rates = instanceFees[_instance];
        if (rates.coverage != 0 || rates.claim != 0) return rates; // 2nd priority

        rates = userSpecificFees[_user];
        if (rates.coverage != 0 || rates.claim != 0) return rates; // 3rd priority

        return defaultFees; // 4th priority
    }

    /// @dev Updates the default coverage and claim fees.
    ///     Fees may be set to zero initially, meaning no fees are applied for that type.
    /// @param _coverage New default coverage fee percentage.
    /// @param _claim New default claim fee percentage.
    function _setDefaultFees(uint16 _coverage, uint16 _claim) internal {
        if (_coverage > MAX_FEE_BPS || _claim > MAX_FEE_BPS) revert EscrowFeeManager__FeeTooHigh();
        defaultFees = FeeRates({ coverage: _coverage, claim: _claim });
        emit DefaultFeesSet(_coverage, _claim);
    }
}
