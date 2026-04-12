# inventory-orders-solidity

A production-style Solidity portfolio project built with a security-first mindset. Implements a full marketplace system with inventory management, order lifecycle, and a feature-rich marketplace — written and tested as a "live product" with a realistic commit history.

> **Stack:** Solidity ^0.8.29 · Foundry · Slither

---

## Architecture

The system is composed of three independent contracts that communicate through interfaces:

```
MarketPlace
    │
    ├── IInventory  ──►  Inventory.sol
    └── IOrderRegistry ──►  OrderRegistry.sol
```

### Inventory.sol
Manages physical stock with a strict accounting model.

- Item storage with `quantity` / `reserved` separation
- Reserve → Release / Finalize lifecycle
- Global state machine: `Active` → `Frozen` → `Closed`
- Role-based access: `admin` + `operators`
- Invariant enforced: `reserved <= quantity` at all times

### OrderRegistry.sol
Handles the order lifecycle with per-order cancel windows.

- State machine: `Created` → `Paid` → `Shipped` / `Cancelled`
- Per-listing cancel window: **10 min** for VIP sellers, **30 min** for standard
- Cancel window stored on-chain per order (`cancelOrder` field)
- Inventory integration via `IInventoryReg` interface
- Operator pattern for trusted caller (MarketPlace)

### MarketPlace.sol
The main user-facing contract. Orchestrates listings, purchases, and seller management.

- **Listing management:** create, activate/deactivate, delist/relist
- **Buy flow:** `msg.value`, deposit, or mixed payment — change goes to deposit
- **Fee system:** configurable BPS fees, VIP seller discount, VIP buyer cashback
- **Promo codes:** per-listing discount codes with usage limits (BPS-based)
- **Seller stats:** `SellerStats` struct tracking active listings, sold items, sold orders, earned ETH
- **Listing limits:** configurable max active listings for VIP / non-VIP sellers
- **Pull payments:** all payouts go to `userBalances` — no push to external addresses
- **Accounting invariant:** `address(this).balance == totalUserBalances + totalPlatformBalance`

---
 
## Security Patterns

| Pattern | Where applied |
|---|---|
| CEI (Checks-Effects-Interactions) | `withdrawForUser`, `withdrawForPlatform` |
| Pull payments | All seller payouts and cashback |
| Custom revert errors | All contracts — gas efficient |
| Role-based access control | `onlyAdmin`, `OnlyAdminOrSeller`, `onlyAdminOrOperator` |
| Interface isolation | MarketPlace never imports Inventory directly |
| Accounting invariant | Verified in every buy/deposit/withdraw path |
| Idempotency guards | `setItemActive`, `delistingItem` counter sync |
| State machine validation | OrderRegistry rejects invalid state transitions |

---

## Testing

```bash
forge test          # run all tests
forge test -vvv     # verbose output
forge test --match-contract MarketPlaceInvariantTest  # invariant only
```

| Test type | Coverage |
|---|---|
| Unit tests | All functions, happy path + revert cases |
| Fuzz tests | `buy()`, `deposit/withdraw`, seller stats, cashback cap |
| Invariant tests | Accounting invariant held across random call sequences |

---

## Static Analysis

Analysed with [Slither](https://github.com/crytic/slither):

```bash
slither . --exclude-dependencies
```
- Remaining warnings are known false positives on trusted internal contracts

---

## Local Setup

```bash
git clone https://github.com/kiko21213/inventory-orders-solidity
cd inventory-orders-solidity
forge install
forge build
forge test
```

**Deployment order:**
```bash
# 1. Deploy Inventory
# 2. Deploy OrderRegistry(inventoryAddress)
# 3. Deploy MarketPlace(inventoryAddress, orderRegistryAddress)
# 4. inventory.setOperator(orderRegistryAddress, true)
# 5. inventory.setOperator(marketPlaceAddress, true)
# 6. orderRegistry.setOperator(marketPlaceAddress)
# 7. marketPlace.setSeller(sellerAddress, true)
```

---

## Author

[@kiko21213](https://github.com/kiko21213) —  focused on security-oriented, production-style smart contract development.
