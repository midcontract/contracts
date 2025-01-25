# IEscrowFactory
[Git Source](https://github.com/midcontract/contracts/blob/c3bacfc361af14f108b5e0e6edb2b6ddbd5e9ee6/src/interfaces/IEscrowFactory.sol)

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
function deployEscrow(Enums.EscrowType escrowType) external returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`escrowType`|`Enums.EscrowType`|The type of escrow to deploy, which determines the template used for cloning.|

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

### AdminManagerUpdated
Emitted when the admin manager address is updated in the registry.


```solidity
event AdminManagerUpdated(address adminManager);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`adminManager`|`address`|The new admin manager contract address.|

### RegistryUpdated
Emitted when the registry address is updated in the factory.


```solidity
event RegistryUpdated(address registry);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`registry`|`address`|The new registry address.|

### ETHWithdrawn
Emitted when ETH is successfully withdrawn from the contract.


```solidity
event ETHWithdrawn(address receiver, uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`receiver`|`address`|The address that received the withdrawn ETH.|
|`amount`|`uint256`|The amount of ETH withdrawn from the contract.|

## Errors
### ZeroAddressProvided
Thrown when an operation involves a zero address where a valid address is required.


```solidity
error ZeroAddressProvided();
```

### InvalidEscrowType
Thrown when an invalid escrow type is used in operations requiring a specific escrow type.


```solidity
error InvalidEscrowType();
```

### ETHTransferFailed
Thrown when an ETH transfer failed.


```solidity
error ETHTransferFailed();
```

