# IEscrowMilestone
[Git Source](https://github.com/midcontract/contracts/blob/846255a5e3f946c40a5e526a441b2695f1307e48/src/interfaces/IEscrowMilestone.sol)

**Inherits:**
[IEscrow](/src/interfaces/IEscrow.sol/interface.IEscrow.md)

Defines the contract interface necessary for managing milestone-based escrow agreements.
Focuses on the declaration of structs, events, errors, and essential function signatures to support milestone
operations within the escrow system.


## Functions
### transferContractorOwnership

Interface declaration for transferring contractor ownership.


```solidity
function transferContractorOwnership(uint256 contractId, uint256 milestoneId, address newOwner) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`contractId`|`uint256`|The identifier of the contract for which contractor ownership is being transferred.|
|`milestoneId`|`uint256`|The identifier of the milestone for which contractor ownership is being transferred.|
|`newOwner`|`address`|The address to which the contractor ownership will be transferred.|


## Events
### Deposited
Emitted when a deposit is made.


```solidity
event Deposited(
    address indexed depositor,
    uint256 indexed contractId,
    uint256 milestoneId,
    uint256 amount,
    address indexed contractor
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`depositor`|`address`|The address of the depositor.|
|`contractId`|`uint256`|The ID of the contract.|
|`milestoneId`|`uint256`|The ID of the milestone.|
|`amount`|`uint256`|The amount deposited.|
|`contractor`|`address`|The address of the contractor.|

### Submitted
Emitted when a submission is made.


```solidity
event Submitted(address indexed sender, uint256 indexed contractId, uint256 indexed milestoneId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sender`|`address`|The address of the sender.|
|`contractId`|`uint256`|The ID of the contract.|
|`milestoneId`|`uint256`|The ID of the milestone.|

### Approved
Emitted when an approval is made.


```solidity
event Approved(
    address indexed approver,
    uint256 indexed contractId,
    uint256 indexed milestoneId,
    uint256 amountApprove,
    address receiver
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`approver`|`address`|The address of the approver.|
|`contractId`|`uint256`|The ID of the contract.|
|`milestoneId`|`uint256`|The ID of the milestone.|
|`amountApprove`|`uint256`|The approved amount.|
|`receiver`|`address`|The address of the receiver.|

### Refilled
Emitted when a contract is refilled.


```solidity
event Refilled(
    address indexed sender, uint256 indexed contractId, uint256 indexed milestoneId, uint256 amountAdditional
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sender`|`address`|The address of the sender.|
|`contractId`|`uint256`|The ID of the contract.|
|`milestoneId`|`uint256`|The ID of the milestone.|
|`amountAdditional`|`uint256`|The additional amount added.|

### Claimed
Emitted when a claim is made.


```solidity
event Claimed(
    address indexed contractor,
    uint256 indexed contractId,
    uint256 indexed milestoneId,
    uint256 amount,
    uint256 feeAmount
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`contractor`|`address`|The address of the contractor.|
|`contractId`|`uint256`|The ID of the contract.|
|`milestoneId`|`uint256`|The ID of the milestone.|
|`amount`|`uint256`|The net amount claimed by the contractor, after deducting fees.|
|`feeAmount`|`uint256`|The fee amount paid by the contractor for the claim.|

### BulkClaimed
Emitted when a contractor claims amounts from multiple milestones in one transaction.


```solidity
event BulkClaimed(
    address indexed contractor,
    uint256 indexed contractId,
    uint256 startMilestoneId,
    uint256 endMilestoneId,
    uint256 totalClaimedAmount,
    uint256 totalFeeAmount,
    uint256 totalClientFee
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`contractor`|`address`|The address of the contractor who performed the bulk claim.|
|`contractId`|`uint256`|The identifier of the contract within which the bulk claim was made.|
|`startMilestoneId`|`uint256`|The starting milestone ID of the range within which the claims were made.|
|`endMilestoneId`|`uint256`|The ending milestone ID of the range within which the claims were made.|
|`totalClaimedAmount`|`uint256`|The total amount claimed across all milestones in the specified range.|
|`totalFeeAmount`|`uint256`|The total fee amount deducted during the bulk claim process.|
|`totalClientFee`|`uint256`|The total client fee amount deducted, if applicable, during the bulk claim process.|

### Withdrawn
Emitted when a withdrawal is made.


```solidity
event Withdrawn(
    address indexed withdrawer,
    uint256 indexed contractId,
    uint256 indexed milestoneId,
    uint256 amount,
    uint256 feeAmount
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`withdrawer`|`address`|The address of the withdrawer.|
|`contractId`|`uint256`|The ID of the contract.|
|`milestoneId`|`uint256`|The ID of the milestone.|
|`amount`|`uint256`|The net amount withdrawn, after deducting fees.|
|`feeAmount`|`uint256`|The fee amount paid by the withdrawer for the withdrawal, if applicable.|

### ReturnRequested
Emitted when a return is requested.


```solidity
event ReturnRequested(address indexed sender, uint256 indexed contractId, uint256 indexed milestoneId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sender`|`address`|The address of the sender.|
|`contractId`|`uint256`|The ID of the contract.|
|`milestoneId`|`uint256`|The ID of the milestone.|

### ReturnApproved
Emitted when a return is approved.


```solidity
event ReturnApproved(address indexed approver, uint256 indexed contractId, uint256 indexed milestoneId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`approver`|`address`|The address of the approver.|
|`contractId`|`uint256`|The ID of the contract.|
|`milestoneId`|`uint256`|The ID of the milestone.|

### ReturnCanceled
Emitted when a return is canceled.


```solidity
event ReturnCanceled(address indexed sender, uint256 indexed contractId, uint256 indexed milestoneId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sender`|`address`|The address of the sender.|
|`contractId`|`uint256`|The ID of the contract.|
|`milestoneId`|`uint256`|The ID of the milestone.|

### DisputeCreated
Emitted when a dispute is created.


```solidity
event DisputeCreated(address indexed sender, uint256 indexed contractId, uint256 indexed milestoneId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sender`|`address`|The address of the sender.|
|`contractId`|`uint256`|The ID of the contract.|
|`milestoneId`|`uint256`|The ID of the milestone.|

### DisputeResolved
Emitted when a dispute is resolved.


```solidity
event DisputeResolved(
    address indexed approver,
    uint256 indexed contractId,
    uint256 indexed milestoneId,
    Enums.Winner winner,
    uint256 clientAmount,
    uint256 contractorAmount
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`approver`|`address`|The address of the approver.|
|`contractId`|`uint256`|The ID of the contract.|
|`milestoneId`|`uint256`|The ID of the milestone.|
|`winner`|`Enums.Winner`|The winner of the dispute.|
|`clientAmount`|`uint256`|The amount awarded to the client.|
|`contractorAmount`|`uint256`|The amount awarded to the contractor.|

### ContractorOwnershipTransferred
Emitted when the ownership of a contractor account is transferred to a new owner.


```solidity
event ContractorOwnershipTransferred(
    uint256 indexed contractId, uint256 indexed milestoneId, address previousOwner, address indexed newOwner
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`contractId`|`uint256`|The identifier of the contract for which contractor ownership is being transferred.|
|`milestoneId`|`uint256`|The identifier of the milestone for which contractor ownership is being transferred.|
|`previousOwner`|`address`|The previous owner of the contractor account.|
|`newOwner`|`address`|The new owner of the contractor account.|

### MaxMilestonesSet
Emitted when the maximum number of milestones per transaction is updated.


```solidity
event MaxMilestonesSet(uint256 maxMilestones);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`maxMilestones`|`uint256`|The new maximum number of milestones that can be processed in a single transaction.|

## Errors
### Escrow__NoDepositsProvided
Error for when no deposits are provided in a function call that expects at least one.


```solidity
error Escrow__NoDepositsProvided();
```

### Escrow__TooManyMilestones
Error for when too many deposit entries are provided, exceeding the allowed limit for a single
transaction.


```solidity
error Escrow__TooManyMilestones();
```

### Escrow__InvalidContractId
Error for when an invalid contract ID is provided to a function expecting a valid existing contract ID.


```solidity
error Escrow__InvalidContractId();
```

### Escrow__InvalidMilestoneId
Error for when an invalid milestone ID is provided to a function expecting a valid existing milestone
ID.


```solidity
error Escrow__InvalidMilestoneId();
```

### Escrow__InvalidMilestoneLimit
Error for when the provided milestone limit is zero or exceeds the maximum allowed.


```solidity
error Escrow__InvalidMilestoneLimit();
```

## Structs
### MilestoneDetails
This struct stores details about individual milestones within an escrow contract.


```solidity
struct MilestoneDetails {
    address paymentToken;
    uint256 depositAmount;
    Enums.Winner winner;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`paymentToken`|`address`|The address of the token to be used for payments.|
|`depositAmount`|`uint256`|The initial deposit amount set aside for this milestone.|
|`winner`|`Enums.Winner`|The winner of any dispute related to this milestone, if applicable.|

### Milestone
Represents a milestone within an escrow contract.


```solidity
struct Milestone {
    address contractor;
    uint256 amount;
    uint256 amountToClaim;
    uint256 amountToWithdraw;
    bytes32 contractorData;
    Enums.FeeConfig feeConfig;
    Enums.Status status;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`contractor`|`address`|The address of the contractor responsible for completing the milestone.|
|`amount`|`uint256`|The total amount allocated to the milestone.|
|`amountToClaim`|`uint256`|The amount available to the contractor upon completion of the milestone.|
|`amountToWithdraw`|`uint256`|The amount available for withdrawal if certain conditions are met.|
|`contractorData`|`bytes32`|Data hash containing specific information about the contractor's obligations.|
|`feeConfig`|`Enums.FeeConfig`|Configuration for any applicable fees associated with the milestone.|
|`status`|`Enums.Status`|Current status of the milestone, tracking its lifecycle from creation to completion.|
