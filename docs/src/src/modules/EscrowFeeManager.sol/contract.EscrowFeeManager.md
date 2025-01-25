# EscrowFeeManager
[Git Source](https://github.com/midcontract/contracts/blob/c3bacfc361af14f108b5e0e6edb2b6ddbd5e9ee6/src/modules/EscrowFeeManager.sol)

**Inherits:**
[IEscrowFeeManager](/src/interfaces/IEscrowFeeManager.sol/interface.IEscrowFeeManager.md)

Manages fee rates and calculations for escrow transactions.


## State Variables
### adminManager
Address of the adminManager contract managing platform administrators.


```solidity
IEscrowAdminManager public adminManager;
```


### MAX_BPS
The maximum allowable percentage in basis points (100%).


```solidity
uint256 public constant MAX_BPS = 10_000;
```


### MAX_FEE_BPS
The maximum allowable fee percentage in basis points (e.g., 50%).


```solidity
uint256 public constant MAX_FEE_BPS = 5000;
```


### defaultFees
The default fees applied if no special fees are set (4th priority).


```solidity
FeeRates public defaultFees;
```


### userSpecificFees
Mapping from user addresses to their specific fee rates (3rd priority).


```solidity
mapping(address user => FeeRates feeType) public userSpecificFees;
```


### instanceFees
Mapping from instance addresses (proxies) to their specific fee rates (2nd priority).


```solidity
mapping(address instance => FeeRates feeType) public instanceFees;
```


### contractSpecificFees
Mapping from instance addresses to a mapping of contract IDs to their specific fee rates (1st priority).


```solidity
mapping(address instance => mapping(uint256 contractId => FeeRates)) public contractSpecificFees;
```


## Functions
### onlyAdmin

Restricts access to admin-only functions.


```solidity
modifier onlyAdmin();
```

### constructor

Initializes the fee manager contract with the adminManager and default fees.


```solidity
constructor(address _adminManager, uint16 _coverage, uint16 _claim);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_adminManager`|`address`|Address of the adminManager contract of the escrow platform.|
|`_coverage`|`uint16`|Initial default coverage fee percentage.|
|`_claim`|`uint16`|Initial default claim fee percentage.|


### setDefaultFees

Updates the default coverage and claim fees.


```solidity
function setDefaultFees(uint16 _coverage, uint16 _claim) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_coverage`|`uint16`|New default coverage fee percentage.|
|`_claim`|`uint16`|New default claim fee percentage.|


### setUserSpecificFees

Sets specific fee rates for a user.


```solidity
function setUserSpecificFees(address _user, uint16 _coverage, uint16 _claim) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|The address of the user for whom to set specific fees.|
|`_coverage`|`uint16`|Specific coverage fee percentage for the user.|
|`_claim`|`uint16`|Specific claim fee percentage for the user.|


### setInstanceFees

Sets specific fee rates for an instance (proxy).


```solidity
function setInstanceFees(address _instance, uint16 _coverage, uint16 _claim) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_instance`|`address`|The address of the instance for which to set specific fees.|
|`_coverage`|`uint16`|Specific coverage fee percentage for the instance.|
|`_claim`|`uint16`|Specific claim fee percentage for the instance.|


### setContractSpecificFees

Sets specific fee rates for a particular contract ID within an instance.


```solidity
function setContractSpecificFees(address _instance, uint256 _contractId, uint16 _coverage, uint16 _claim)
    external
    onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_instance`|`address`|The address of the instance containing the contract.|
|`_contractId`|`uint256`|The ID of the contract within the instance.|
|`_coverage`|`uint16`|Specific coverage fee percentage for the contract.|
|`_claim`|`uint16`|Specific claim fee percentage for the contract.|


### resetContractSpecificFees

Resets contract-specific fees to default by removing the fee entry for a given contract ID.


```solidity
function resetContractSpecificFees(address _instance, uint256 _contractId) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_instance`|`address`|The address of the instance under which the contract falls.|
|`_contractId`|`uint256`|The unique identifier for the contract whose fees are being reset.|


### resetInstanceSpecificFees

Resets instance-specific fees to default by removing the fee entry for the given instance.


```solidity
function resetInstanceSpecificFees(address _instance) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_instance`|`address`|The address of the instance for which fees are being reset.|


### resetUserSpecificFees

Resets user-specific fees to default by removing the fee entry for the specified user.


```solidity
function resetUserSpecificFees(address _user) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|The address of the user whose fees are being reset.|


### resetAllToDefault

Resets all higher-priority fees (contract, instance, and user-specific fees) to default in a single
call.


```solidity
function resetAllToDefault(address _instance, uint256 _contractId, address _user) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_instance`|`address`|The address of the instance containing the contract to be reset.|
|`_contractId`|`uint256`|The unique identifier for the contract whose fees are being reset.|
|`_user`|`address`|The address of the user whose fees are being reset.|


### computeDepositAmountAndFee

Calculates the total deposit amount including any applicable fees based on the fee configuration.

*This function calculates fees by prioritizing specific fee configurations in the following order:
contract-level fees (highest priority), instance-level fees, user-specific fees, and default fees (lowest
priority).*


```solidity
function computeDepositAmountAndFee(
    address _instance,
    uint256 _contractId,
    address _client,
    uint256 _depositAmount,
    Enums.FeeConfig _feeConfig
) external view returns (uint256 totalDepositAmount, uint256 feeApplied);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_instance`|`address`|The address of the deployed proxy instance (e.g., EscrowHourly or EscrowMilestone).|
|`_contractId`|`uint256`|The specific contract ID within the proxy instance, if applicable, for contract-level fee overrides.|
|`_client`|`address`|The address of the client paying the deposit.|
|`_depositAmount`|`uint256`|The initial deposit amount before fees.|
|`_feeConfig`|`Enums.FeeConfig`|The fee configuration to determine which fees to apply.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`totalDepositAmount`|`uint256`|The total amount after fees are added.|
|`feeApplied`|`uint256`|The amount of fees added to the deposit.|


### computeClaimableAmountAndFee

Calculates the claimable amount after any applicable fees based on the fee configuration.

*This function calculates fees by prioritizing specific fee configurations in the following order:
contract-level fees (highest priority), instance-level fees, user-specific fees, and default fees (lowest
priority).*


```solidity
function computeClaimableAmountAndFee(
    address _instance,
    uint256 _contractId,
    address _contractor,
    uint256 _claimedAmount,
    Enums.FeeConfig _feeConfig
) external view returns (uint256 claimableAmount, uint256 feeDeducted, uint256 clientFee);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_instance`|`address`|The address of the deployed proxy instance (e.g., EscrowFixedPrice or EscrowMilestone).|
|`_contractId`|`uint256`|The specific contract ID within the proxy instance.|
|`_contractor`|`address`|The address of the contractor claiming the amount.|
|`_claimedAmount`|`uint256`|The initial claimed amount before fees.|
|`_feeConfig`|`Enums.FeeConfig`|The fee configuration to determine which fees to deduct.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`claimableAmount`|`uint256`|The amount claimable after fees are deducted.|
|`feeDeducted`|`uint256`|The amount of fees deducted from the claim.|
|`clientFee`|`uint256`|The additional fee amount covered by the client if applicable.|


### getApplicableFees

Retrieves the applicable fee rates based on priority for a given contract, instance, and user.

*This function returns the highest-priority fee rates among contract-specific, instance-specific,
user-specific, or default fees based on the configured hierarchy.*


```solidity
function getApplicableFees(address _instance, uint256 _contractId, address _user)
    external
    view
    returns (FeeRates memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_instance`|`address`|The address of the instance under which the contract falls.|
|`_contractId`|`uint256`|The unique identifier for the contract to which the fees apply.|
|`_user`|`address`|The address of the user involved in the transaction.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`FeeRates`|The applicable `FeeRates` structure containing the coverage and claim fee rates.|


### _getApplicableFees

*Retrieves applicable fees with the following priority:
Contract-specific > Instance-specific > User-specific > Default.*


```solidity
function _getApplicableFees(address _instance, uint256 _contractId, address _user)
    internal
    view
    returns (FeeRates memory rates);
```

### _setDefaultFees

*Updates the default coverage and claim fees.
Fees may be set to zero initially, meaning no fees are applied for that type.*


```solidity
function _setDefaultFees(uint16 _coverage, uint16 _claim) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_coverage`|`uint16`|New default coverage fee percentage.|
|`_claim`|`uint16`|New default claim fee percentage.|


