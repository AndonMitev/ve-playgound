# USDe Vault

A Veda BoringVault deployment for USDe deposits with an unrestricted multi-manager system and a custom 3-day withdrawal queue. Shares represent pro-rata ownership of the vault's USDe — deposit mints shares, withdrawal burns them at the current exchange rate.

## Approach

Uses boring-vault's core deposit infrastructure (`BoringVault` + `TellerWithMultiAssetSupport` + `AccountantWithRateProviders`) unmodified, with two custom contracts written from scratch:

- **`UnrestrictedManager`** (64 lines) — replaces `ManagerWithMerkleVerification` to allow unrestricted vault management
- **`WithdrawQueue`** (~130 lines) — replaces `BoringOnChainQueue` + `BoringSolver` with a simpler single-contract queue

| Contract | Source | Custom? |
|---|---|---|
| `BoringVault` | boring-vault | No |
| `AccountantWithRateProviders` | boring-vault | No |
| `TellerWithMultiAssetSupport` | boring-vault | No |
| `RolesAuthority` | solmate | No |
| **`UnrestrictedManager`** | **custom** | **Yes (64 lines)** |
| **`WithdrawQueue`** | **custom** | **Yes (~130 lines)** |

Configured deployment uses USDe as the sole deposit asset. The Teller supports multi-asset, but only USDe is whitelisted via `teller.updateAssetData()`.

## Requirements

| Requirement | How |
|---|---|
| Deposit USDe, get vault shares | `teller.deposit()` is a public capability — anyone can call it |
| Manager = multiple addresses, no restrictions | `UnrestrictedManager` forwards arbitrary calldata to `vault.manage()`. Any number of EOAs can be granted `MANAGER_INTERNAL_ROLE` |
| Add/remove managers via external authority | `RolesAuthority` owner calls `setUserRole(addr, MANAGER_INTERNAL_ROLE, true/false)` |
| 3-day withdraw queue | Custom `WithdrawQueue` with `MATURITY_PERIOD = 259200` (72 hours). Enforced on-chain — solver cannot fill before maturity |

## Auth Flow

```
DEPOSIT
  User --> teller.deposit() [PUBLIC]
    --> vault.enter() [Teller has MINTER_ROLE]

MANAGE
  Manager EOA --> manager.manageVault() [MANAGER_INTERNAL_ROLE]
    --> vault.manage() [Manager contract has MANAGER_ROLE]

WITHDRAW (request)
  User --> queue.requestWithdraw() [PUBLIC]
    --> shares transferred to queue
    ... 3 days pass ...

WITHDRAW (solve)
  Solver --> queue.solveWithdraw() [SOLVER_ROLE]
    --> teller.bulkWithdraw() [Queue has TELLER_ROLE]
    --> vault.exit() [Teller has BURNER_ROLE]
    --> USDe sent to users

CANCEL
  User --> queue.cancelWithdraw() [PUBLIC]
    --> shares returned
```

## WithdrawQueue Design

- Users can have **multiple concurrent requests**, each tracked by a unique `requestId` (auto-incrementing `uint96`)
- Struct is packed into 2 storage slots: `{user, amountOfShares}` (slot 0) + `{creationTime, completed}` (slot 1)
- `solveWithdraw` supports batched execution — aggregates shares, calls `teller.bulkWithdraw()` once, distributes USDe pro-rata via `mulDivDown`
- Cancel is only available to the original requester and only if not yet completed
- Solver cannot execute before the 3-day maturity — enforced on-chain, not off-chain
- Direct `teller.bulkWithdraw()` by users is blocked (requires `TELLER_ROLE`, only the queue has it)

## Roles

| Role | ID | Purpose |
|---|---|---|
| MANAGER_ROLE | 1 | UnrestrictedManager → vault.manage() |
| MINTER_ROLE | 2 | Teller → vault.enter() |
| BURNER_ROLE | 3 | Teller → vault.exit() |
| MANAGER_INTERNAL_ROLE | 4 | EOAs → manager.manageVault() |
| UPDATE_EXCHANGE_RATE_ROLE | 5 | Updater → accountant.updateExchangeRate() |
| SOLVER_ROLE | 6 | Solver EOA → queue.solveWithdraw() |
| TELLER_ROLE | 7 | WithdrawQueue → teller.bulkWithdraw() |

## Security Considerations

- **Managers are intentionally omnipotent** — they can execute arbitrary calldata via `vault.manage()`. This matches the bounty requirement ("no restrictions") but is not production-safe without additional timelocks or limits.
- **Teller bypass is blocked** — users cannot call `bulkWithdraw` directly; only the `WithdrawQueue` contract has `TELLER_ROLE`. Verified by `test_tellerDirectWithdraw_reverts`.
- **Pro-rata rounding** — uses solmate's `mulDivDown` to prevent rounding exploits during batched withdrawals.
- **Struct packing** — `WithdrawRequest` fits in 2 slots for gas efficiency.

## Tests

34 tests passing (unit + integration + fuzz):

```
WithdrawQueueTest
  [PASS] test_constructor_revertsZeroAddress
  [PASS] test_constructor_setsImmutables
  [PASS] test_requestWithdraw_revertsZeroShares
  [PASS] test_requestWithdraw_revertsBelowMinimum
  [PASS] test_requestWithdraw_valid
  [PASS] test_cancelWithdraw_revertsNotFound
  [PASS] test_cancelWithdraw_revertsNotOwner
  [PASS] test_cancelWithdraw_revertsAlreadyCompleted
  [PASS] test_cancelWithdraw_valid
  [PASS] test_solveWithdraw_revertsUnauthorized
  [PASS] test_solveWithdraw_revertsNotMatured
  [PASS] test_solveWithdraw_revertsAlreadyCompleted
  [PASS] test_solveWithdraw_singleRequest
  [PASS] test_solveWithdraw_batchRequests
  [PASS] test_getRequest_returnsStruct
  [PASS] test_isMatured
  [PASS] testFuzz_requestAndCancel_returnsExactShares
  [PASS] testFuzz_solveOnlyAfterMaturity

UnrestrictedManagerTest
  [PASS] test_constructor_revertsZeroVault
  [PASS] test_constructor_setsVaultAndAuthority
  [PASS] test_manageVault_single_authorizedForwards
  [PASS] test_manageVault_single_unauthorizedReverts
  [PASS] test_manageVault_batch_authorizedForwards
  [PASS] test_manageVault_batch_unauthorizedReverts
  [PASS] test_roleManagement_addManager
  [PASS] test_roleManagement_removeManager
  [PASS] testFuzz_manageVault_forwardsArbitraryCalldata

VaultIntegrationTest
  [PASS] test_deposit_userReceivesShares
  [PASS] testFuzz_deposit_variableAmounts
  [PASS] test_withdraw_requestTransfersShares
  [PASS] test_withdraw_solveAfterMaturity
  [PASS] test_withdraw_solveBeforeMaturityReverts
  [PASS] test_withdraw_cancelReturnsShares
  [PASS] test_tellerDirectWithdraw_reverts
```

## How to Verify

```bash
forge install
forge build
forge test -vvv
```

Key flows to trace: `deposit → requestWithdraw → wait 3 days → solveWithdraw` and `deposit → requestWithdraw → cancelWithdraw`.

## Deploy

```bash
ADMIN=0x... \
USDE=0x... \
WETH=0x... \
EXCHANGE_RATE_UPDATER=0x... \
SOLVER_OPERATOR=0x... \
MANAGERS=0x...,0x... \
forge script script/DeployVault.s.sol --broadcast --rpc-url $RPC_URL
```

## Project Structure

```
src/
  UnrestrictedManager.sol       # Custom manager (64 lines)
  WithdrawQueue.sol             # Custom withdraw queue (~130 lines)
script/
  DeployVault.s.sol             # Deploys 6 contracts, wires 7 roles, transfers ownership
test/
  UnrestrictedManager.t.sol     # 9 unit + fuzz tests
  UnrestrictedManager.tree      # Branching tree spec
  WithdrawQueue.t.sol           # 18 unit + fuzz tests
  WithdrawQueue.tree            # Branching tree spec
  VaultIntegration.t.sol        # 7 integration + fuzz tests
  VaultIntegration.tree         # Branching tree spec
  mocks/
    MockERC20.sol
```
