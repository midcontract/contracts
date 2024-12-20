# EscrowFixedPrice
[Git Source](https://github.com/midcontract/contracts/blob/846255a5e3f946c40a5e526a441b2695f1307e48/src/EscrowFixedPrice.sol)

**Inherits:**
[IEscrowFixedPrice](/src/interfaces/IEscrowFixedPrice.sol/interface.IEscrowFixedPrice.md), [ERC1271](/src/common/ERC1271.sol/abstract.ERC1271.md)

Manages lifecycle of fixed-price contracts including deposits, approvals, submissions, claims,
withdrawals, and dispute resolutions.


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


### client
*Address of the client who initiates the escrow contract.*


```solidity
address public client;
```


### currentContractId
*Tracks the last issued contract ID, incrementing with each new contract creation.*


```solidity
uint256 private currentContractId;
```


### initialized
*Indicates that the contract has been initialized.*


```solidity
bool public initialized;
```


### deposits
*Maps each contract ID to its corresponding deposit details.*


```solidity
mapping(uint256 contractId => Deposit) public deposits;
```


## Functions
### onlyClient

*Modifier to restrict functions to the client address.*


```solidity
modifier onlyClient();
```

### initialize

Initializes the escrow contract.


```solidity
function initialize(address _client, address _adminManager, address _registry) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_client`|`address`|Address of the client initiating actions within the escrow.|
|`_adminManager`|`address`|Address of the adminManager contract of the escrow platform.|
|`_registry`|`address`|Address of the registry contract.|


### deposit

Creates a new deposit for a fixed-price contract within the escrow system.


```solidity
function deposit(Deposit calldata _deposit) external onlyClient;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_deposit`|`Deposit`|Details of the deposit to be created.|


### submit

Submits work for a contract by the contractor.

*This function allows the contractor to submit their work details for a contract.*


```solidity
function submit(uint256 _contractId, bytes calldata _data, bytes32 _salt) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the deposit to be submitted.|
|`_data`|`bytes`|Contractor’s details or work summary.|
|`_salt`|`bytes32`|Unique salt for cryptographic operations.|


### approve

Approves a submitted deposit by the client or an administrator.

*Allows the client or an admin to officially approve a deposit that has been submitted by a contractor.*


```solidity
function approve(uint256 _contractId, uint256 _amountApprove, address _receiver) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the deposit to be approved.|
|`_amountApprove`|`uint256`|Amount to approve for the deposit.|
|`_receiver`|`address`|Address of the contractor receiving the approved amount.|


### refill

Adds additional funds to a specific deposit.

*Enhances a deposit's total amount, which can be crucial for ongoing contracts needing extra funds.*


```solidity
function refill(uint256 _contractId, uint256 _amountAdditional) external onlyClient;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|The identifier of the deposit to be refilled.|
|`_amountAdditional`|`uint256`|The extra amount to be added to the deposit.|


### claim

Claims the approved funds for a contract by the contractor.

*Allows contractors to retrieve funds that have been approved for their work.*


```solidity
function claim(uint256 _contractId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|Identifier of the deposit from which funds will be claimed.|


### withdraw

Withdraws funds from a deposit under specific conditions after a refund approval or resolution.

*Handles the withdrawal process including fee deductions and state updates.*


```solidity
function withdraw(uint256 _contractId) external onlyClient;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|Identifier of the deposit from which funds will be withdrawn.|


### requestReturn

Requests the return of funds by the client for a specific contract.

*The contract must be in an eligible state to request a return (not in disputed or already returned status).*


```solidity
function requestReturn(uint256 _contractId) external onlyClient;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the deposit for which the return is requested.|


### approveReturn

Approves the return of funds, which can be called by the contractor or platform admin.

*This changes the status of the deposit to allow the client to withdraw their funds.*


```solidity
function approveReturn(uint256 _contractId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the deposit for which the return is approved.|


### cancelReturn

Cancels a previously requested return and resets the deposit's status.

*Allows reverting the deposit status from RETURN_REQUESTED to an active state.*


```solidity
function cancelReturn(uint256 _contractId, Enums.Status _status) external onlyClient;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|The unique identifier of the deposit for which the return is being cancelled.|
|`_status`|`Enums.Status`|The new status to set for the deposit, must be ACTIVE, SUBMITTED, APPROVED, or COMPLETED.|


### createDispute

Creates a dispute over a specific deposit.

*Initiates a dispute status for a deposit that can be activated by the client or contractor
when they disagree on the previously submitted work.*


```solidity
function createDispute(uint256 _contractId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the deposit where the dispute is to be created. This function can only be called if the deposit status is either RETURN_REQUESTED or SUBMITTED.|


### resolveDispute

Resolves a dispute over a specific deposit.

*Handles the resolution of disputes by assigning the funds according to the outcome of the dispute.
Admin intervention is required to resolve disputes to ensure fairness.*


```solidity
function resolveDispute(uint256 _contractId, Enums.Winner _winner, uint256 _clientAmount, uint256 _contractorAmount)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|ID of the deposit where the dispute occurred.|
|`_winner`|`Enums.Winner`|Specifies who the winner is: Client, Contractor, or Split.|
|`_clientAmount`|`uint256`|Amount to be allocated to the client if Split or Client wins.|
|`_contractorAmount`|`uint256`|Amount to be allocated to the contractor if Split or Contractor wins. This function ensures that the total resolution amounts do not exceed the deposited amount and adjusts the status of the deposit based on the dispute outcome.|


### transferClientOwnership

Transfers ownership of the client account to a new account.

*Can only be called by the account recovery module registered in the system.*


```solidity
function transferClientOwnership(address _newAccount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newAccount`|`address`|The address to which the client ownership will be transferred.|


### transferContractorOwnership

Transfers ownership of the contractor account to a new account for a specified contract.

*Can only be called by the account recovery module registered in the system.*


```solidity
function transferContractorOwnership(uint256 _contractId, address _newAccount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|The identifier of the contract for which contractor ownership is being transferred.|
|`_newAccount`|`address`|The address to which the contractor ownership will be transferred.|


### updateRegistry

Updates the registry address used for fetching escrow implementations.


```solidity
function updateRegistry(address _registry) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_registry`|`address`|New registry address.|


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


### getCurrentContractId

Retrieves the current contract ID.


```solidity
function getCurrentContractId() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The current contract ID.|


### getContractorDataHash

Generates a hash for the contractor data.

*This external function computes the hash value for the contractor data using the provided data and salt.*


```solidity
function getContractorDataHash(bytes calldata _data, bytes32 _salt) external pure returns (bytes32);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_data`|`bytes`|Contractor data.|
|`_salt`|`bytes32`|Salt value for generating the hash.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|Hash value of the contractor data.|


### _getContractorDataHash

Generates a hash for the contractor data.

*This internal function computes the hash value for the contractor data using the provided data and salt.*


```solidity
function _getContractorDataHash(bytes calldata _data, bytes32 _salt) internal pure returns (bytes32);
```

### _computeDepositAmountAndFee

Computes the total deposit amount and the applied fee.

*This internal function calculates the total deposit amount and the fee applied based on the client, deposit
amount, and fee configuration.*


```solidity
function _computeDepositAmountAndFee(
    uint256 _contractId,
    address _client,
    uint256 _depositAmount,
    Enums.FeeConfig _feeConfig
) internal view returns (uint256 totalDepositAmount, uint256 feeApplied);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|The specific contract ID within the proxy instance.|
|`_client`|`address`|Address of the client making the deposit.|
|`_depositAmount`|`uint256`|Amount of the deposit.|
|`_feeConfig`|`Enums.FeeConfig`|Fee configuration for the deposit.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`totalDepositAmount`|`uint256`|Total deposit amount after applying the fee.|
|`feeApplied`|`uint256`|Fee applied to the deposit.|


### _computeClaimableAmountAndFee

Computes the claimable amount and the fee deducted from the claimed amount.

*This internal function calculates the claimable amount for the contractor and the fees deducted from the
claimed amount based on the contractor, claimed amount, and fee configuration.*


```solidity
function _computeClaimableAmountAndFee(
    uint256 _contractId,
    address _contractor,
    uint256 _claimedAmount,
    Enums.FeeConfig _feeConfig
) internal view returns (uint256 claimableAmount, uint256 feeDeducted, uint256 clientFee);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contractId`|`uint256`|The specific contract ID within the proxy instance.|
|`_contractor`|`address`|Address of the contractor claiming the amount.|
|`_claimedAmount`|`uint256`|Amount claimed by the contractor.|
|`_feeConfig`|`Enums.FeeConfig`|Fee configuration for the deposit.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`claimableAmount`|`uint256`|Amount claimable by the contractor.|
|`feeDeducted`|`uint256`|Fee deducted from the claimed amount.|
|`clientFee`|`uint256`|Fee to be paid by the client for covering the claim.|


### _sendPlatformFee

Sends the platform fee to the treasury.

*This internal function transfers the platform fee to the treasury address.*


```solidity
function _sendPlatformFee(address _paymentToken, uint256 _feeAmount) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_paymentToken`|`address`|Address of the payment token for the fee.|
|`_feeAmount`|`uint256`|Amount of the fee to be transferred.|


### _isValidSignature

Internal function to validate the signature of the provided data.

*Verifies if the signature is from the msg.sender, which can be an externally owned account (EOA) or a
contract implementing ERC-1271.*


```solidity
function _isValidSignature(bytes32 _hash, bytes calldata _signature) internal view override returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_hash`|`bytes32`|The hash of the data that was signed.|
|`_signature`|`bytes`|The signature byte array associated with the hash.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the signature is valid, false otherwise.|


