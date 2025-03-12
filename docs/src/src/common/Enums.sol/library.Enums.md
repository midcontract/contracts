# Enums
[Git Source](https://github.com/midcontract/contracts/blob/71e459a676c50fe05291a09ea107d28263f8dabb/src/common/Enums.sol)

This library defines various enums used across the contract for managing fees, statuses, escrow types, and more.


## Enums
### FeeConfig
Enumerates the different configurations of fee responsibilities.


```solidity
enum FeeConfig {
    CLIENT_COVERS_ALL,
    CLIENT_COVERS_ONLY,
    CONTRACTOR_COVERS_CLAIM,
    NO_FEES,
    INVALID
}
```

### Status
Enumerates the different statuses for a contract.


```solidity
enum Status {
    NONE,
    ACTIVE,
    SUBMITTED,
    APPROVED,
    COMPLETED,
    RETURN_REQUESTED,
    DISPUTED,
    RESOLVED,
    REFUND_APPROVED,
    CANCELED
}
```

### Winner
Enumerates the potential outcomes of a dispute resolution.

*Describes who the winner of a dispute can be in various contexts, including partial resolutions.*


```solidity
enum Winner {
    NONE,
    CLIENT,
    CONTRACTOR,
    SPLIT
}
```

### EscrowType
Defines the types of escrow contracts that can be created.

*Used in the factory contract to specify which type of escrow contract to deploy.*


```solidity
enum EscrowType {
    FIXED_PRICE,
    MILESTONE,
    HOURLY,
    INVALID
}
```

### RefillType
Specifies the types of refills possible within an escrow contract.

*Used to determine whether a refill operation is targeting the overall contract prepayment or a specific week's payment within the contract.*


```solidity
enum RefillType {
    PREPAYMENT,
    WEEK_PAYMENT
}
```

### AccountTypeRecovery
Enumerates the types of accounts that can be subject to recovery processes in the escrow system.

*Used to specify the type of account (client or contractor) that needs recovery in case of access issues.*


```solidity
enum AccountTypeRecovery {
    CLIENT,
    CONTRACTOR
}
```

