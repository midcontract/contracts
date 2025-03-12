# EscrowAccountRecovery
[Git Source](https://github.com/midcontract/contracts/blob/71e459a676c50fe05291a09ea107d28263f8dabb/src/modules/EscrowAccountRecovery.sol)

Provides mechanisms for recovering access to the client or contractor accounts
in an escrow contract in case of lost credentials, using a guardian-based recovery process.


## State Variables
### adminManager
*Address of the adminManager contract.*


```solidity
IEscrowAdminManager public adminManager;
```


### registry
*Address of the registry contract.*


```solidity
IEscrowRegistry public registry;
```


### MIN_RECOVERY_PERIOD
*Recovery period after which recovery can be executed.*


```solidity
uint256 public constant MIN_RECOVERY_PERIOD = 3 days;
```


### MAX_RECOVERY_PERIOD
*Maximum allowed recovery period to prevent indefinite blocking of recovery actions.*


```solidity
uint256 public constant MAX_RECOVERY_PERIOD = 30 days;
```


### recoveryPeriod
*Configurable recovery period initialized to the minimum allowed.*


```solidity
uint256 public recoveryPeriod;
```


### recoveryData
*Mapping of recovery hashes to their corresponding data.*


```solidity
mapping(bytes32 recoveryHash => RecoveryData) public recoveryData;
```


## Functions
### constructor

*Initializes the contract with the owner and guardian addresses.*


```solidity
constructor(address _adminManager, address _registry);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_adminManager`|`address`|Address of the adminManager contract of the escrow platform.|
|`_registry`|`address`|Address of the registry contract.|


### initiateRecovery

Initiates the recovery process for an account.


```solidity
function initiateRecovery(
    address _escrow,
    uint256 _contractId,
    uint256 _milestoneId,
    address _oldAccount,
    address _newAccount,
    Enums.EscrowType _escrowType,
    Enums.AccountTypeRecovery _accountType
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_escrow`|`address`|Address of the escrow contract related to the recovery.|
|`_contractId`|`uint256`|Contract identifier within the escrow.|
|`_milestoneId`|`uint256`|Milestone identifier within the contract.|
|`_oldAccount`|`address`|Current account address that needs recovery.|
|`_newAccount`|`address`|New account address to replace the old one.|
|`_escrowType`|`Enums.EscrowType`|Type of the escrow contract involved.|
|`_accountType`|`Enums.AccountTypeRecovery`|Type of the account for recovery.|


### executeRecovery

Executes a previously confirmed recovery.

*This function checks that the recovery period has elapsed and that the recovery is confirmed before
executing it.*


```solidity
function executeRecovery(
    Enums.AccountTypeRecovery _accountType,
    address _escrow,
    uint256 _contractId,
    uint256 _milestoneId,
    address _oldAccount
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_accountType`|`Enums.AccountTypeRecovery`|Type of the account being recovered, either CLIENT or CONTRACTOR.|
|`_escrow`|`address`|Address of the escrow involved in the recovery.|
|`_contractId`|`uint256`|Contract identifier within the escrow.|
|`_milestoneId`|`uint256`|Milestone identifier within the contract.|
|`_oldAccount`|`address`|Old account address being replaced in the recovery.|


### cancelRecovery

Cancels an ongoing recovery process.


```solidity
function cancelRecovery(bytes32 _recoveryHash) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_recoveryHash`|`bytes32`|Hash of the recovery request to be canceled.|


### _transferContractOwnership

*Transfers the ownership of the escrow contract based on the specified account type and escrow type.*


```solidity
function _transferContractOwnership(
    Enums.EscrowType _escrowType,
    address _escrow,
    uint256 _contractId,
    uint256 _milestoneId,
    Enums.AccountTypeRecovery _accountType
) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_escrowType`|`Enums.EscrowType`|The type of escrow contract involved in the transfer.|
|`_escrow`|`address`|The address of the escrow contract.|
|`_contractId`|`uint256`|The identifier of the contract within the escrow, relevant for contractor transfers.|
|`_milestoneId`|`uint256`|The identifier of the milestone within the contract, relevant for milestone-specific contractor transfers.|
|`_accountType`|`Enums.AccountTypeRecovery`|The type of account to be transferred, can be either CLIENT or CONTRACTOR.|


### _encodeRecoveryHash

*Encodes recovery details into a hash (used internally).*


```solidity
function _encodeRecoveryHash(
    address _escrow,
    uint256 _contractId,
    uint256 _milestoneId,
    address _oldAccount,
    address _newAccount,
    Enums.AccountTypeRecovery _accountType
) internal pure returns (bytes32);
```

### getRecoveryHash

*Generates the recovery hash that should be signed by the guardian to initiate a recovery.*


```solidity
function getRecoveryHash(
    address _escrow,
    uint256 _contractId,
    uint256 _milestoneId,
    address _oldAccount,
    address _newAccount,
    Enums.AccountTypeRecovery _accountType
) external pure returns (bytes32);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_escrow`|`address`|Address of the escrow contract related to the recovery.|
|`_contractId`|`uint256`|Contract identifier within the escrow.|
|`_milestoneId`|`uint256`|Milestone identifier within the contract.|
|`_oldAccount`|`address`|Address of the user being replaced.|
|`_newAccount`|`address`|Address of the new user.|
|`_accountType`|`Enums.AccountTypeRecovery`|Type of the account being recovered, either CLIENT or CONTRACTOR.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|Hash of the recovery details.|


### updateRecoveryPeriod

Updates the recovery period to a new value, ensuring it meets minimum requirements.

*Can only be called by the owner of the contract.*


```solidity
function updateRecoveryPeriod(uint256 _recoveryPeriod) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_recoveryPeriod`|`uint256`|The new recovery period in seconds.|


### updateAdminManager

Updates the address of the admin manager contract.

*Restricts the function to be callable only by the current owner of the admin manager.*


```solidity
function updateAdminManager(address _adminManager) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_adminManager`|`address`|The new address of the admin manager contract.|


## Events
### RecoveryInitiated
*Emitted when a recovery is initiated by the guardian.*


```solidity
event RecoveryInitiated(address indexed sender, bytes32 indexed recoveryHash);
```

### RecoveryExecuted
*Emitted when a recovery is executed successfully.*


```solidity
event RecoveryExecuted(address indexed sender, bytes32 indexed recoveryHash);
```

### RecoveryCanceled
*Emitted when a recovery is canceled.*


```solidity
event RecoveryCanceled(address indexed sender, bytes32 indexed recoveryHash);
```

### RecoveryPeriodUpdated
*Emitted when the recovery period is updated to a new value.*


```solidity
event RecoveryPeriodUpdated(uint256 recoveryPeriod);
```

### AdminManagerUpdated
*Emitted when the admin manager address is updated in the contract.*


```solidity
event AdminManagerUpdated(address adminManager);
```

## Errors
### ZeroAddressProvided
*Thrown when zero address usage where prohibited.*


```solidity
error ZeroAddressProvided();
```

### RecoveryAlreadyExecuted
*Thrown when trying to execute an already executed recovery.*


```solidity
error RecoveryAlreadyExecuted();
```

### RecoveryPeriodStillPending
*Thrown when trying to execute recovery before the period has elapsed.*


```solidity
error RecoveryPeriodStillPending();
```

### RecoveryNotInitiated
*Thrown when trying to execute a recovery that has not been initiated.*


```solidity
error RecoveryNotInitiated();
```

### UnauthorizedAccount
*Thrown when an unauthorized account attempts a restricted action.*


```solidity
error UnauthorizedAccount();
```

### RecoveryPeriodNotValid
*Thrown indicates an attempt to set the recovery period below the minimum required or to zero.*


```solidity
error RecoveryPeriodNotValid();
```

### InvalidContractId
*Thrown if the provided contract ID is invalid or uninitialized.*


```solidity
error InvalidContractId();
```

### InvalidMilestoneId
*Thrown if the provided milestone ID does not exist for the specified contract.*


```solidity
error InvalidMilestoneId();
```

### MilestoneNotSupported
*Thrown if a milestone ID is provided for non-milestone escrows.*


```solidity
error MilestoneNotSupported();
```

### SameAccountProvided
*Thrown if the old and new account addresses provided for recovery are identical.*


```solidity
error SameAccountProvided();
```

## Structs
### RecoveryData
Data structure to store recovery-related information.


```solidity
struct RecoveryData {
    address escrow;
    address account;
    uint256 contractId;
    uint256 milestoneId;
    uint64 executeAfter;
    bool executed;
    Enums.EscrowType escrowType;
    Enums.AccountTypeRecovery accountType;
}
```

