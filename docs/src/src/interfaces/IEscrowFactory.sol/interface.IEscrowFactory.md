# IEscrowFactory
[Git Source](https://github.com/midcontract/contracts/blob/846255a5e3f946c40a5e526a441b2695f1307e48/src/interfaces/IEscrowFactory.sol)

*Interface defining the functionality for an escrow factory, responsible for deploying new escrow contracts.*


## Functions
### existingEscrow

Checks if the given address is an escrow contract deployed by this factory.


```solidity
function existingEscrow(address escrow) external returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`escrow`|`address`|The address of the escrow contract to check.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the address is an existing deployed escrow contract, false otherwise.|


### deployEscrow

Deploys a new escrow contract with specified parameters.


```solidity
function deployEscrow(Enums.EscrowType escrowType, address client, address admin, address registry)
    external
    returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`escrowType`|`Enums.EscrowType`|The type of escrow to deploy, which determines the template used for cloning.|
|`client`|`address`|The address of the client for whom the escrow is being created.|
|`admin`|`address`|The address with administrative privileges over the new escrow.|
|`registry`|`address`|The address of the registry containing escrow configurations.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the newly deployed escrow contract.|


## Events
### EscrowProxyDeployed
Emitted when a new escrow proxy is successfully deployed.


```solidity
event EscrowProxyDeployed(address sender, address deployedProxy, Enums.EscrowType escrowType);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sender`|`address`|The address of the sender who initiated the escrow deployment.|
|`deployedProxy`|`address`|The address of the newly deployed escrow proxy.|
|`escrowType`|`Enums.EscrowType`|The type of escrow to deploy, which determines the template used for cloning.|

### RegistryUpdated
Emitted when the registry address is updated in the factory.


```solidity
event RegistryUpdated(address registry);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`registry`|`address`|The new registry address.|

## Errors
### Factory__ZeroAddressProvided
Thrown when an operation involves a zero address where a valid address is required.


```solidity
error Factory__ZeroAddressProvided();
```

### Factory__InvalidEscrowType
Thrown when an invalid escrow type is used in operations requiring a specific escrow type.


```solidity
error Factory__InvalidEscrowType();
```

