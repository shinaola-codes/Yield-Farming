# Yield Farming Protocol Smart Contract

A Clarity smart contract implementing a decentralized yield farming protocol that allows users to deposit token pairs and earn rewards through staking mechanisms.

## Overview

The Yield Farming Protocol enables users to deposit two different tokens into farming vaults and receive yield rewards based on their staking duration and share allocation. The protocol implements a time-locked staking mechanism with administrative controls for managing yield rates and protocol status.

## Key Features

- **Dual Token Staking**: Deposit pairs of tokens (primary and secondary) to earn yield
- **Share-Based Rewards**: Proportional reward distribution based on liquidity share allocation
- **Time-Lock Security**: 24-hour lock period prevents immediate withdrawals
- **Administrative Controls**: Protocol admin can adjust yield rates and manage protocol status
- **Custom Minimum Function**: Implements efficient minimum value calculation
- **Fee Accumulation**: Built-in fee collection mechanism (0.3% protocol fee)

## Contract Architecture

### Core Components

1. **Yield Positions Map**: Tracks individual farmer stakes and positions
2. **Farming Vaults Map**: Manages token reserves and share distributions
3. **Fungible Token Trait**: Interface for token contract interactions
4. **Administrative Functions**: Owner-only protocol management

### Key Constants

- `MIN_DEPOSIT_AMOUNT`: 100,000 units minimum deposit
- `LOCKUP_DURATION`: 144 blocks (~24 hours)
- `BASE_YIELD_RATE`: 100 (1.00x base multiplier)
- `PROTOCOL_FEE_RATE`: 30 (0.3% fee)

## Main Functions

### Public Functions

#### `deposit-tokens`
```clarity
(deposit-tokens primary-token secondary-token primary-amount secondary-amount)
```
- Deposits token pairs into the farming vault
- Calculates and allocates proportional shares
- Initiates lock period for the position
- **Requirements**: Minimum deposit amounts, no existing position

#### `withdraw-tokens`
```clarity
(withdraw-tokens primary-token secondary-token)
```
- Withdraws deposited tokens plus earned yield rewards
- Requires lock period to have expired
- Automatically calculates and includes yield rewards
- **Requirements**: Active position, lock period expired

### Read-Only Functions

#### `get-farmer-position`
```clarity
(get-farmer-position farmer-principal)
```
Returns detailed information about a farmer's position including amounts, shares, and timing.

#### `get-vault-details`
```clarity
(get-vault-details vault-id)
```
Returns vault information including total reserves, outstanding shares, and accumulated fees.

#### `compute-share-allocation`
```clarity
(compute-share-allocation primary-deposit secondary-deposit)
```
Calculates the number of shares that would be allocated for given deposit amounts.

### Administrative Functions

#### `transfer-admin-rights`
```clarity
(transfer-admin-rights new-admin)
```
Transfers protocol administration rights to a new address (admin-only).

#### `adjust-yield-rate`
```clarity
(adjust-yield-rate new-rate)
```
Updates the protocol yield rate multiplier (admin-only).

#### `toggle-protocol-status`
```clarity
(toggle-protocol-status)
```
Enables/disables the protocol (admin-only).

## Error Codes

| Code | Error | Description |
|------|-------|-------------|
| u1 | ERR-UNAUTHORIZED-ACCESS | Caller not authorized for admin functions |
| u2 | ERR-INSUFFICIENT-RESERVES | Not enough reserves for operation |
| u3 | ERR-EXISTING-POSITION | User already has an active position |
| u4 | ERR-NO-ACTIVE-POSITION | User has no active farming position |
| u5 | ERR-BELOW-MINIMUM-THRESHOLD | Deposit below minimum required amount |
| u6 | ERR-STILL-LOCKED | Position still within lock period |
| u7 | ERR-INVALID-TOKEN-PAIR | Invalid or mismatched token contracts |
| u8 | ERR-COMPUTATION-FAILED | Mathematical calculation error |
| u9 | ERR-INVALID-ADDRESS | Invalid principal address |
| u10 | ERR-OWNERSHIP-VALIDATION-FAILED | Admin validation requirements not met |

## Security Features

- **Time-Lock Protection**: 24-hour mandatory lock period prevents flash loan attacks
- **Minimum Deposit Requirements**: Prevents dust attacks and ensures meaningful participation
- **Admin Validation**: New admin must have active, unlocked position
- **Token Contract Validation**: Ensures only approved token contracts are used
- **Overflow Protection**: Safe arithmetic operations with proper error handling

## Usage Example

```clarity
;; Deposit tokens to start farming
(contract-call? .yield-farming-protocol deposit-tokens 
    .primary-token 
    .secondary-token 
    u1000000    ;; 1M primary tokens
    u500000)    ;; 500K secondary tokens

;; After lock period, withdraw with rewards
(contract-call? .yield-farming-protocol withdraw-tokens 
    .primary-token 
    .secondary-token)
```
