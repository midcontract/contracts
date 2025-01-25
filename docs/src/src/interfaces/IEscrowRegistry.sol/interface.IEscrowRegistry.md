# IEscrowRegistry
[Git Source](https://github.com/midcontract/contracts/blob/c3bacfc361af14f108b5e0e6edb2b6ddbd5e9ee6/src/interfaces/IEscrowRegistry.sol)

*Interface for the registry that manages configuration settings such as payment tokens and contract addresses
for an escrow system.*


## Functions
### paymentTokens

Checks if a token is enabled as a payment token in the registry.


```solidity
function paymentTokens(address token) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The address of the token to check.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the token is enabled, false otherwise.|


### escrowFixedPrice

Retrieves the current fixed price escrow contract address stored in the registry.


```solidity
function escrowFixedPrice() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the fixed price escrow contract.|


### escrowMilestone

Retrieves the current milestone escrow contract address stored in the registry.


```solidity
function escrowMilestone() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the milestone escrow contract.|


### escrowHourly

Retrieves the current hourly escrow contract address stored in the registry.


```solidity
function escrowHourly() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the hourly escrow contract.|


### factory

Retrieves the current factory contract address stored in the registry.


```solidity
function factory() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the factory contract.|


### feeManager

Retrieves the current feeManager contract address stored in the registry.


```solidity
function feeManager() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the feeManager contract.|


### fixedTreasury

Retrieves the treasury address used for fixed-price escrow contracts.

*Used to isolate funds collected from fixed-price contracts.*


```solidity
function fixedTreasury() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the fixed-price escrow treasury.|


### hourlyTreasury

Retrieves the treasury address used for hourly escrow contracts.

*Used to isolate funds collected from hourly-based contracts.*


```solidity
function hourlyTreasury() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the hourly escrow treasury.|


### milestoneTreasury

Retrieves the treasury address used for milestone escrow contracts.

*Used to isolate funds collected from milestone-based contracts.*


```solidity
function milestoneTreasury() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the milestone escrow treasury.|


### accountRecovery

Retrieves the current account recovery address stored in the registry.


```solidity
function accountRecovery() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the account recovery contract.|


### adminManager

Retrieves the current admin manager address stored in the registry.


```solidity
function adminManager() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the admin manager contract.|


### blacklist

Checks if an address is blacklisted.


```solidity
function blacklist(address user) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|The address to check against the blacklist.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool True if the address is blacklisted, false otherwise.|


### updateEscrowFixedPrice

Updates the address of the fixed price escrow contract used in the system.


```solidity
function updateEscrowFixedPrice(address newEscrowFixedPrice) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newEscrowFixedPrice`|`address`|The new address of the fixed price escrow contract to be used across the platform.|


### updateEscrowMilestone

Updates the address of the milestone escrow contract used in the system.


```solidity
function updateEscrowMilestone(address newEscrowMilestone) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newEscrowMilestone`|`address`|The new address of the milestone escrow contract to be used.|


### updateEscrowHourly

Updates the address of the hourly escrow contract used in the system.


```solidity
function updateEscrowHourly(address newEscrowHourly) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newEscrowHourly`|`address`|The new address of the hourly escrow contract to be used.|


### updateFactory

Updates the address of the Factory contract used in the system.

*This function allows the system administrator to set a new factory contract address.*


```solidity
function updateFactory(address newFactory) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newFactory`|`address`|The new address of the Factory contract to be used across the platform.|


## Events
### PaymentTokenAdded
Emitted when a new payment token is added to the registry.


```solidity
event PaymentTokenAdded(address token);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The address of the token that was added.|

### PaymentTokenRemoved
Emitted when a payment token is removed from the registry.


```solidity
event PaymentTokenRemoved(address token);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The address of the token that was removed.|

### EscrowUpdated
Emitted when the escrow contract address is updated in the registry.


```solidity
event EscrowUpdated(address escrow);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`escrow`|`address`|The new escrow contract address.|

### FactoryUpdated
Emitted when the factory contract address is updated in the registry.


```solidity
event FactoryUpdated(address factory);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`factory`|`address`|The new factory contract address.|

### FeeManagerUpdated
Emitted when the feeManager contract address is updated in the registry.


```solidity
event FeeManagerUpdated(address feeManager);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`feeManager`|`address`|The new feeManager contract address.|

### TreasurySet
Emitted when the treasury account address is set in the registry.


```solidity
event TreasurySet(address treasury);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`treasury`|`address`|The new treasury contract address.|

### AccountRecoverySet
Emitted when the account recovery address is updated in the registry.


```solidity
event AccountRecoverySet(address accountRecovery);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`accountRecovery`|`address`|The new account recovery contract address.|

### AdminManagerSet
Emitted when the admin manager address is updated in the registry.


```solidity
event AdminManagerSet(address adminManager);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`adminManager`|`address`|The new admin manager contract address.|

### Blacklisted
Emitted when an address is added to the blacklist.


```solidity
event Blacklisted(address indexed user);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|The address that has been blacklisted.|

### Whitelisted
Emitted when an address is removed from the blacklist.


```solidity
event Whitelisted(address indexed user);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|The address that has been removed from the blacklist.|

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
Thrown when a zero address is provided where a valid address is required.


```solidity
error ZeroAddressProvided();
```

### TokenAlreadyAdded
Thrown when attempting to add a token that has already been added to the registry.


```solidity
error TokenAlreadyAdded();
```

### PaymentTokenNotRegistered
Thrown when attempting to remove or access a token that is not registered.


```solidity
error PaymentTokenNotRegistered();
```

### ETHTransferFailed
Thrown when an ETH transfer failed.


```solidity
error ETHTransferFailed();
```

