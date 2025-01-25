# IEscrowFeeManager
[Git Source](https://github.com/midcontract/contracts/blob/c3bacfc361af14f108b5e0e6edb2b6ddbd5e9ee6/src/interfaces/IEscrowFeeManager.sol)

Defines the standard functions and events for an escrow fee management system.


## Functions
### computeDepositAmountAndFee

Computes the total deposit amount including any applicable fees.


```solidity
function computeDepositAmountAndFee(
    address instance,
    uint256 contractId,
    address client,
    uint256 depositAmount,
    Enums.FeeConfig feeConfig
) external view returns (uint256 totalDepositAmount, uint256 feeApplied);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`instance`|`address`|The address of the deployed proxy instance (e.g., EscrowHourly or EscrowMilestone).|
|`contractId`|`uint256`|The specific contract ID within the proxy instance.|
|`client`|`address`|The address of the client making the deposit.|
|`depositAmount`|`uint256`|The amount of the deposit before fees are applied.|
|`feeConfig`|`Enums.FeeConfig`|The fee configuration to determine which fees to apply.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`totalDepositAmount`|`uint256`|The total amount after fees are added.|
|`feeApplied`|`uint256`|The amount of fees applied based on the configuration.|


### computeClaimableAmountAndFee

Calculates the amount a contractor can claim, accounting for any applicable fees.


```solidity
function computeClaimableAmountAndFee(
    address instance,
    uint256 contractId,
    address contractor,
    uint256 claimedAmount,
    Enums.FeeConfig feeConfig
) external view returns (uint256 claimableAmount, uint256 feeDeducted, uint256 clientFee);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`instance`|`address`|The address of the deployed proxy instance (e.g., EscrowHourly or EscrowMilestone).|
|`contractId`|`uint256`|The specific contract ID within the proxy instance.|
|`contractor`|`address`|The address of the contractor claiming the funds.|
|`claimedAmount`|`uint256`|The amount being claimed before fees.|
|`feeConfig`|`Enums.FeeConfig`|The fee configuration to determine which fees to deduct.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`claimableAmount`|`uint256`|The amount the contractor can claim after fee deductions.|
|`feeDeducted`|`uint256`|The amount of fees deducted based on the configuration.|
|`clientFee`|`uint256`|The additional fee amount covered by the client if applicable.|


### defaultFees

Retrieves the default fee rates for coverage and claim.

*This function returns two uint16 values representing the default percentages for coverage and claim fees
respectively.*


```solidity
function defaultFees() external view returns (uint16, uint16);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint16`|coverage The default fee percentage for coverage charges.|
|`<none>`|`uint16`|claim The default fee percentage for claim charges.|


### getApplicableFees

Retrieves the applicable fee rates based on priority for a given contract, instance, and user.


```solidity
function getApplicableFees(address instance, uint256 contractId, address user)
    external
    view
    returns (FeeRates memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`instance`|`address`|The address of the instance under which the contract falls.|
|`contractId`|`uint256`|The unique identifier for the contract to which the fees apply.|
|`user`|`address`|The address of the user involved in the transaction.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`FeeRates`|The applicable `FeeRates` structure containing the coverage and claim fee rates.|


## Events
### DefaultFeesSet
Emitted when the default fees are updated.


```solidity
event DefaultFeesSet(uint16 coverage, uint16 claim);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`coverage`|`uint16`|The new default coverage fee as a percentage in basis points.|
|`claim`|`uint16`|The new default claim fee as a percentage in basis points.|

### UserSpecificFeesSet
Emitted when specific fees are set for a user.


```solidity
event UserSpecificFeesSet(address indexed user, uint16 coverage, uint16 claim);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|The address of the user for whom specific fees are set.|
|`coverage`|`uint16`|The specific coverage fee as a percentage in basis points.|
|`claim`|`uint16`|The specific claim fee as a percentage in basis points.|

### InstanceFeesSet
Emitted when specific fees are set for an instance (proxy).


```solidity
event InstanceFeesSet(address indexed instance, uint16 coverage, uint16 claim);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`instance`|`address`|The address of the instance for which to set specific fees.|
|`coverage`|`uint16`|The specific coverage fee as a percentage in basis points.|
|`claim`|`uint16`|The special claim fee as a percentage in basis points.|

### ContractSpecificFeesSet
Emitted when specific fees are set for a particular contract ID within an instance.


```solidity
event ContractSpecificFeesSet(address indexed instance, uint256 indexed contractId, uint16 coverage, uint16 claim);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`instance`|`address`|The address of the instance for which to set specific fees.|
|`contractId`|`uint256`|The ID of the contract within the instance.|
|`coverage`|`uint16`|The specific coverage fee as a percentage in basis points.|
|`claim`|`uint16`|The specific claim fee as a percentage in basis points.|

### ContractSpecificFeesReset
Emitted when the contract-specific fees are reset to the default configuration.


```solidity
event ContractSpecificFeesReset(address indexed instance, uint256 indexed contractId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`instance`|`address`|The address of the instance under which the contract falls.|
|`contractId`|`uint256`|The unique identifier for the contract whose fees were reset.|

### InstanceSpecificFeesReset
Emitted when the instance-specific fees are reset to the default configuration.


```solidity
event InstanceSpecificFeesReset(address indexed instance);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`instance`|`address`|The address of the instance whose fees were reset.|

### UserSpecificFeesReset
Emitted when the user-specific fees are reset to the default configuration.


```solidity
event UserSpecificFeesReset(address indexed user);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|The address of the user whose fees were reset.|

## Errors
### FeeTooHigh
*Thrown when the specified fee exceeds the maximum allowed basis points.*


```solidity
error FeeTooHigh();
```

### UnsupportedFeeConfiguration
*Thrown when an unsupported fee configuration is used.*


```solidity
error UnsupportedFeeConfiguration();
```

### ZeroAddressProvided
*Thrown when an operation includes or results in a zero address where it is not allowed.*


```solidity
error ZeroAddressProvided();
```

### UnauthorizedAccount
Thrown when an unauthorized account attempts an action.


```solidity
error UnauthorizedAccount();
```

## Structs
### FeeRates
Represents fee rates for coverage and claim fees, applicable at multiple levels.

*This structure is used to define fee rates at various priority levels:
contract-specific, instance-specific, user-specific, or as a default.*


```solidity
struct FeeRates {
    uint16 coverage;
    uint16 claim;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`coverage`|`uint16`|The coverage fee percentage.|
|`claim`|`uint16`|The claim fee percentage.|

