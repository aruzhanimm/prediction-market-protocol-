# Prediction Market Protocol

> On-Chain Prediction Market

A full-stack decentralized prediction market protocol built on Ethereum L2. Users trade binary outcome shares (YES / NO) on real-world events using a constant-product AMM. Chainlink oracles resolve markets, LP fees flow into an ERC-4626 vault, and all protocol parameters are governed by a DAO.

---

## Team

| Name | Role |
|---|---|
| Aruzhan Kartam | Smart contracts — AMM, ERC-4626 vault, governance |
| Sergey Chepurnenko | Smart contracts — oracles, factory, tokens, L2 deployment |

---

## Architecture Overview

```
User
 │
 ├─▶ MarketFactory (CREATE / CREATE2)
 │        └─▶ PredictionMarket [UUPS Proxy]
 │                 ├─▶ MarketAMM          (CPMM x·y=k, 0.3% fee)
 │                 ├─▶ OutcomeShareToken  (ERC-1155 YES/NO shares)
 │                 ├─▶ FeeVault           (ERC-4626, LP yield)
 │                 └─▶ ChainlinkResolver  (staleness-checked oracle)
 │
 └─▶ DAO Governor
          ├─▶ GovernanceToken  (ERC-20Votes + ERC-20Permit)
          └─▶ TimelockController (2-day delay)
                   └─▶ Treasury
```

Full architecture document: [`docs/architecture.md`](docs/architecture.md)

---

## Technical Stack

| Layer | Technology |
|---|---|
| Smart contracts | Solidity 0.8.24, Foundry |
| Token standards | ERC-20Votes, ERC-1155, ERC-4626 |
| Upgradeability | UUPS proxy (OpenZeppelin) |
| Oracles | Chainlink price feeds |
| Indexing | The Graph |
| Governance | OpenZeppelin Governor + TimelockController |
| L2 deployment | Arbitrum Sepolia |
| Frontend | HTML / JS + Ethers.js |

---

## Project Structure

```
prediction-market-protocol/
├── src/
│   ├── core/            # PredictionMarket (UUPS), MarketFactory, MarketAMM
│   ├── tokens/          # GovernanceToken (ERC-20Votes), OutcomeShareToken (ERC-1155)
│   ├── vault/           # FeeVault (ERC-4626)
│   ├── oracle/          # ChainlinkResolver, MockAggregator
│   ├── governance/      # MyGovernor, Treasury
│   ├── libraries/       # AMMLib (Yul assembly)
│   └── interfaces/      # All contract interfaces
├── test/
│   ├── unit/            # ≥ 50 unit tests
│   ├── fuzz/            # ≥ 10 fuzz tests
│   ├── invariant/       # ≥ 5 invariant tests
│   └── fork/            # ≥ 3 mainnet fork tests
├── script/              # Deploy.s.sol, PostDeployVerify.s.sol
├── subgraph/            # The Graph subgraph (schema, mappings)
├── frontend/            # dApp (HTML/JS + Ethers.js)
└── docs/                # Architecture, audit report, gas report
```

---

## Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (latest nightly)
- Git

### Install

```shell
git clone https://github.com/aruzhanimm/prediction-market-protocol-
cd prediction-market-protocol
forge install
```

### Environment

```shell
cp .env.example .env
# Fill in RPC URLs and API keys
```

### Build

```shell
forge build
```

### Test

```shell
# Run all tests
forge test -vvv

# Run a specific test file
forge test --match-path test/unit/GovernanceTokenTest.t.sol -vvv

# Run with gas report
forge test --gas-report
```

### Coverage

```shell
forge coverage --report summary
```

### Format

```shell
forge fmt
```

### Gas Snapshots

```shell
forge snapshot
```

### Static Analysis

```shell
slither . --config-file slither.config.json
```

---

## Deployment

Deploy to Arbitrum Sepolia:

```shell
forge script script/Deploy.s.sol \
  --rpc-url arbitrum_sepolia \
  --broadcast \
  --verify \
  -vvvv
```

Verify post-deployment configuration:

```shell
forge script script/PostDeployVerify.s.sol \
  --rpc-url arbitrum_sepolia \
  -vvvv
```

### Deployed Contracts (Arbitrum Sepolia)

| Contract | Address |
|---|---|
| GovernanceToken | [`0x1d8F27C369BC460f26C8fb5AAb897b4230c2E22c`](https://sepolia.arbiscan.io/address/0x1d8F27C369BC460f26C8fb5AAb897b4230c2E22c) |
| OutcomeShareToken | [`0x2872B16A1b58ce92a5D1d8Da80BcE1abC4eae865`](https://sepolia.arbiscan.io/address/0x2872B16A1b58ce92a5D1d8Da80BcE1abC4eae865) |
| MarketFactory | [`0x7549bC2A3F0ce716C067570af1615f97E7A93792`](https://sepolia.arbiscan.io/address/0x7549bC2A3F0ce716C067570af1615f97E7A93792) |
| PredictionMarket (proxy) | [`0xc95dE1BAFabE53B2c9a743a4425296Ce4293530e`](https://sepolia.arbiscan.io/address/0xc95dE1BAFabE53B2c9a743a4425296Ce4293530e) |
| PredictionMarket (impl V1) | [`0x7C115581124B15187d66045b9910EB1E5F454960`](https://sepolia.arbiscan.io/address/0x7C115581124B15187d66045b9910EB1E5F454960) |
| PredictionMarket (impl V2) | [`0xc9BD3412ABD9210963142E220ceD49253FB113eA`](https://sepolia.arbiscan.io/address/0xc9BD3412ABD9210963142E220ceD49253FB113eA) |
| MarketAMM | [`0xB4d820DD5cD9A5c2eE92AdA161D48c4Ce5cb9dD6`](https://sepolia.arbiscan.io/address/0xB4d820DD5cD9A5c2eE92AdA161D48c4Ce5cb9dD6) |
| FeeVault | [`0xbE5ec37e14B44E0675Fedec533BF235c744367f2`](https://sepolia.arbiscan.io/address/0xbE5ec37e14B44E0675Fedec533BF235c744367f2) |
| ChainlinkResolver | [`0x237555EcbF1329821e9245fb255979D512B76592`](https://sepolia.arbiscan.io/address/0x237555EcbF1329821e9245fb255979D512B76592) |
| MyGovernor | [`0x61E3585B25F8FDEaa127264Bc08f8fc335D92ce2`](https://sepolia.arbiscan.io/address/0x61E3585B25F8FDEaa127264Bc08f8fc335D92ce2) |
| TimelockController | [`0xa3317a62CccA788e5924BDDC6cDe36B6ba4984B1`](https://sepolia.arbiscan.io/address/0xa3317a62CccA788e5924BDDC6cDe36B6ba4984B1) |
| Treasury | [`0x411Df3c1ad4e253302fA4BB553A29d78D65A07A6`](https://sepolia.arbiscan.io/address/0x411Df3c1ad4e253302fA4BB553A29d78D65A07A6) |

Block explorer: [Arbitrum Sepolia](https://sepolia.arbiscan.io)

---

## The Graph

The protocol events are indexed via The Graph on Arbitrum Sepolia.

**Subgraph endpoint:**
```
https://api.studio.thegraph.com/query/1753370/prediction-market-protocol/v0.0.3
```

**Indexed entities:** Market, Trade, LiquidityPosition, GovernanceProposal

**Documented queries:** [`docs/graphql-queries.md`](docs/graphql-queries.md)

---

## Documentation

| Document | Description |
|---|---|
| [`docs/architecture.md`](docs/architecture.md) | System design, C4 diagrams, sequence flows, storage layouts |
| [`docs/audit-report.md`](docs/audit-report.md) | Internal security audit, Slither findings, attack analysis |
| [`docs/gas-report.md`](docs/gas-report.md) | L1 vs L2 gas comparison, Yul vs Solidity benchmarks |
| [`docs/coverage-report.md`](docs/coverage-report.md) | Line coverage report (≥ 90%) |
| [`docs/graphql-queries.md`](docs/graphql-queries.md) | 5 documented GraphQL queries for the subgraph |

---

## Foundry Reference

| Command | Description |
|---|---|
| `forge build` | Compile contracts |
| `forge test` | Run test suite |
| `forge fmt` | Format Solidity code |
| `forge snapshot` | Generate gas snapshots |
| `forge coverage` | Measure test coverage |
| `anvil` | Start local EVM node |
| `cast <subcommand>` | Interact with contracts |

Full docs: [book.getfoundry.sh](https://book.getfoundry.sh/)

---

## License

MIT