# EscrowFactory
[Git Source](https://github.com/midcontract/contracts/blob/846255a5e3f946c40a5e526a441b2695f1307e48/src/EscrowFactory.sol)

**Inherits:**
[IEscrowFactory](/src/interfaces/IEscrowFactory.sol/interface.IEscrowFactory.md), OwnedThreeStep, Pausable

*This contract is used for creating new escrow contract instances using the clone factory pattern.*


## State Variables
### registry
EscrowRegistry contract address storing escrow templates and configurations.


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

*Sets the initial registry used for cloning escrow contracts.*


```solidity
constructor(address _registry, address _owner) OwnedThreeStep(_owner);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_registry`|`address`|Address of the registry contract.|
|`_owner`|`address`|Address of the initial owner of the factory contract.|


### deployEscrow

Deploys a new escrow contract clone with unique settings for each project.

*This function clones the specified escrow template and initializes it with specific parameters for the
project.
It uses the clone factory pattern for deployment to minimize gas costs and manage multiple escrow contract
versions.*


```solidity
function deployEscrow(Enums.EscrowType _escrowType, address _client, address _adminManager, address _registry)
    external
    whenNotPaused
    returns (address deployedProxy);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_escrowType`|`Enums.EscrowType`|The type of escrow to deploy, which determines the template used for cloning.|
|`_client`|`address`|The client's address who initiates the escrow, msg.sender.|
|`_adminManager`|`address`|Address of the adminManager contract of the escrow platform.|
|`_registry`|`address`|Address of the registry contract to fetch escrow implementation.|

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
function pause() public onlyOwner;
```

### unpause

Unpauses the contract, allowing new escrows to be deployed.


```solidity
function unpause() public onlyOwner;
```

