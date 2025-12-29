# inventory-orders-solidity
This repository contains a Solidity-based Inventory and Orders system,
designed as a learning and portfolio project.

### Inventory.sol
- Item storage with total / reserved accounting
- Reservation, release, and finalization logic
- Global state machine (Active / Frozen / Closed)
- Emergency handling without locking users

### OrderRegistry.sol
- Order lifecycle: Created → Paid → Shipped
- Order cancellation
- Inventory integration via interface
- Strict state validation and invariants

### Security & Design Focus
- Single Source of Truth
- State machines (contract-level and order-level)
- Safe external calls via interfaces
- Explicit invariants (`reserved <= quantity`)
- Separation of concerns (Inventory vs Orders)

### Purpose
This project is part of my Solidity learning path, focused on
writing production-style smart contracts with security-oriented thinking.

### Stack
- Solidity ^0.8.x
- No frameworks (pure Solidity)

### Deployment(REMIX)
- Deploy Inventory
- Deploy OrderRegistry(inventoryAddress)
- inventory.setOperator(orderRegistryAddress)
- addItem
- createOrder -> reserve
- markPaid -> finalize
- markShipped
---

Author: @kiko21213
