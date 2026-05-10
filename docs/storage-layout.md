# Storage Layout — Upgradeable Contracts

> **Purpose:** Prove that PredictionMarket V2 cannot collide with V1 storage slots.
> Required reading before any upgrade deployment.

---

## PredictionMarket (UUPS Proxy)

### How UUPS storage works (OZ v5)

OpenZeppelin v5 uses **ERC-7201 namespaced storage** for all framework contracts
(`UUPSUpgradeable`, `Initializable`).  Their internal slots are derived via
`keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.XYZ")) - 1)) & ~bytes32(uint256(0xff))`
— meaning they never collide with sequential user slots.

`AccessControl` in OZ v5 stores role data in a namespaced slot:
`keccak256("openzeppelin.storage.AccessControl")` → not at slot 0.

### PredictionMarket own sequential slots

| Slot | Variable | Type | Notes |
|------|----------|------|-------|
| 0 | `marketCount` | `uint256` | Sequential market ID counter |
| 1 | `markets` | `mapping(uint256 => MarketData)` | Per-market data |
| 2 | `outcomeToken` | `address` (20 bytes) | ERC-1155 share token |
| 3 | `factory` | `address` | MarketFactory address |
| 4 | `resolver` | `address` | ChainlinkResolver address |

### V2 Upgrade Rule

V2 **MUST NOT** reorder, remove, or resize any V1 slot.
V2 may **only** append new variables after slot 4.

Example V2 extension (safe):
```solidity
// V2 appends here — slot 5 onward
uint256 public disputeWindow;        // slot 5
mapping(uint256 => bool) public disputed; // slot 6
```

### MarketData struct (packed inside `markets` mapping)

Each `MarketData` occupies 4 storage slots within the mapping:

| Field | Type | Slot offset |
|-------|------|-------------|
| `marketId` | `uint256` | +0 |
| `question` | `string` (dynamic) | +1 (pointer) |
| `resolutionTime` | `uint256` | +2 |
| `status` (3 values) + `outcome` (bool) + `creator` (address) | packed | +3 |
| `totalShares` | `uint256` | +4 |

---

## MarketAMM (Non-upgradeable — storage layout for reference)

| Slot | Variable | Type |
|------|----------|------|
| 0 | ERC20 `_name` | `string` |
| 1 | ERC20 `_symbol` | `string` |
| 2 | ERC20 `_totalSupply` | `uint256` |
| 3 | ERC20 `_balances` | `mapping` |
| 4 | ERC20 `_allowances` | `mapping` |
| 5 | ReentrancyGuard (OZ v5 namespaced — no sequential slot) | — |
| 6 | `reserveYes` | `uint256` |
| 7 | `reserveNo` | `uint256` |

Immutables (`outcomeToken`, `marketId`, `yesTokenId`, `noTokenId`) are stored
in bytecode, not storage.

---

## FeeVault (Non-upgradeable ERC-4626 — storage layout for reference)

| Slot | Variable | Type |
|------|----------|------|
| 0–4 | ERC20 internal (name, symbol, totalSupply, balances, allowances) | — |
| 5 | ReentrancyGuard (namespaced) | — |
| 6 | Ownable `_owner` | `address` |
| 7 | `totalYieldAccrued` | `uint256` |

`_asset` is `immutable` — bytecode, not storage.

---

## V1 → V2 Upgrade Checklist

- [ ] Run `forge inspect PredictionMarket storage-layout` on V1 and V2
- [ ] Diff the two outputs — no existing variable may move
- [ ] New variables must be appended at the end
- [ ] Call `upgradeToAndCall(newImpl, "")` through Timelock (2-day delay)
- [ ] Run `PostDeployVerify.s.sol` after upgrade to confirm state preserved
