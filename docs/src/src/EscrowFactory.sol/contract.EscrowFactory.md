# EscrowFactory
[Git Source](https://github.com/midcontract/contracts/blob/c3bacfc361af14f108b5e0e6edb2b6ddbd5e9ee6/src/EscrowFactory.sol)

**Inherits:**
[IEscrowFactory](/src/interfaces/IEscrowFactory.sol/interface.IEscrowFactory.md), OwnedThreeStep, Pausable

*This contract is used for creating new escrow contract instances using the clone factory pattern.*


## State Variables
### adminManager
Address of the adminManager contract managing platform administrators.


```solidity
IEscrowAdminManager public adminManager;
```


### registry
Address of the registry contract storing escrow templates and configurations.


```solidity
IEscrowRegistry public registry;
```


### factoryNonce
Tracks the number of escrows deployed per deployer to generate unique salts for clones.


```solidity
mapping(address deployer => uint256 nonce) public factoryNonce;
```


### existingEscrow
Tracks the addresses of deployed escrow contracts.


```solidity
mapping(address escrow => bool deployed) public existingEscrow;
```


## Functions
### constructor

Initializes the factory contract with the adminManager, registry and owner.


```solidity
constructor(address _adminManager, address _registry, address _owner) OwnedThreeStep(_owner);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_adminManager`|`address`|Address of the adminManager contract of the escrow platform.|
|`_registry`|`address`|Address of the registry contract.|
|`_owner`|`address`||


### deployEscrow

Deploys a new escrow contract clone with unique settings for each project.

*This function clones the specified escrow template and initializes it with specific parameters for the
project. It uses the clone factory pattern for deployment to minimize gas costs and manage multiple escrow
contract versions.*


```solidity
function deployEscrow(Enums.EscrowType _escrowType) external whenNotPaused returns (address deployedProxy);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_escrowType`|`Enums.EscrowType`|The type of escrow to deploy, which determines the template used for cloning.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`deployedProxy`|`address`|The address of the newly deployed escrow proxy.|


### _getEscrowImplementation

*Internal function to determine the implementation address for a given type of escrow.*

*This internal helper function queries the registry to obtain the correct implementation address for
cloning.*


```solidity
function _getEscrowImplementation(Enums.EscrowType _escrowType) internal view returns (address escrowImpl);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_escrowType`|`Enums.EscrowType`|The type of escrow contract (FixedPrice, Milestone, or Hourly).|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`escrowImpl`|`address`|The address of the escrow implementation.|


### getEscrowImplementation

Fetches the escrow contract implementation address based on the escrow type.


```solidity
function getEscrowImplementation(Enums.EscrowType _escrowType) external view returns (address escrowImpl);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_escrowType`|`Enums.EscrowType`|The type of escrow contract (FixedPrice, Milestone, or Hourly).|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`escrowImpl`|`address`|The address of the escrow implementation.|


### updateAdminManager

Updates the address of the admin manager contract.


```solidity
function updateAdminManager(address _adminManager) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_adminManager`|`address`|The new address of the AdminManager contract to be used.|


### updateRegistry

Updates the registry address used for fetching escrow implementations.


```solidity
function updateRegistry(address _registry) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_registry`|`address`|New registry address.|


### pause

Pauses the contract, preventing new escrows from being deployed.


```solidity
function pause() external onlyOwner;
```

### unpause

Unpauses the contract, allowing new escrows to be deployed.


```solidity
function unpause() external onlyOwner;
```

### withdrawETH

Withdraws any ETH accidentally sent to the contract.


```solidity
function withdrawETH(address _receiver) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_receiver`|`address`|The address that will receive the withdrawn ETH.|


