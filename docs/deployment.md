# Deployment Guide — Base Sepolia

## Network

| Field | Value |
|---|---|
| Network | Base Sepolia |
| Chain ID | 84532 |
| Explorer | https://sepolia.basescan.org |
| RPC environment variable | `BASE_SEPOLIA_RPC_URL` |

## Required environment variables

Before deployment, set the following variables:

```powershell
$env:PRIVATE_KEY="0xYOUR_PRIVATE_KEY"
$env:BASE_SEPOLIA_RPC_URL="https://..."
$env:BASESCAN_API_KEY="YOUR_BASESCAN_API_KEY"
$env:CHAINLINK_FEED="0x..."
```

Optional wallet variables:

```powershell
$env:TEAM_WALLET="0x..."
$env:TREASURY_WALLET="0x..."
$env:COMMUNITY_WALLET="0x..."
$env:LIQUIDITY_WALLET="0x..."
```

If optional wallet variables are not provided, the deployment script uses the deployer address.

## Deployment command

```powershell
forge script script/Deploy.s.sol:Deploy `
  --rpc-url $env:BASE_SEPOLIA_RPC_URL `
  --broadcast `
  --verify `
  --etherscan-api-key $env:BASESCAN_API_KEY
```

## Post-deployment check

After deployment, copy the deployed addresses into environment variables:

```powershell
$env:TIMELOCK="0x..."
$env:GOVERNOR="0x..."
$env:TREASURY="0x..."
$env:OUTCOME_TOKEN="0x..."
$env:PREDICTION_MARKET_PROXY="0x..."
$env:MARKET_FACTORY="0x..."
$env:CHAINLINK_RESOLVER="0x..."
```

Run:

```powershell
forge script script/PostDeployCheck.s.sol:PostDeployCheck `
  --rpc-url $env:BASE_SEPOLIA_RPC_URL
```

Expected output:

```text
Timelock check passed.
Governor check passed.
PredictionMarket check passed.
OutcomeShareToken check passed.
Treasury check passed.
Post-deployment checks passed.
```

## Deployed contracts

> Status: pending real deployment.

| Contract | Address | Explorer |
|---|---:|---|
| GovernanceToken | `0x0000000000000000000000000000000000000000` | Pending |
| TimelockController | `0x0000000000000000000000000000000000000000` | Pending |
| MyGovernor | `0x0000000000000000000000000000000000000000` | Pending |
| Treasury | `0x0000000000000000000000000000000000000000` | Pending |
| OutcomeShareToken | `0x0000000000000000000000000000000000000000` | Pending |
| PredictionMarket Implementation V1 | `0x0000000000000000000000000000000000000000` | Pending |
| PredictionMarket Proxy | `0x0000000000000000000000000000000000000000` | Pending |
| PredictionMarket Implementation V2 | `0x0000000000000000000000000000000000000000` | Pending |
| MarketAMM | `0x0000000000000000000000000000000000000000` | Pending |
| FeeVault | `0x0000000000000000000000000000000000000000` | Pending |
| MarketFactory | `0x0000000000000000000000000000000000000000` | Pending |
| ChainlinkResolver | `0x0000000000000000000000000000000000000000` | Pending |

## Notes

The deployment script is parameterized through environment variables. This allows the protocol to be redeployed to a fresh L2 testnet without manually editing Solidity files.

The `PredictionMarket` contract is deployed through an `ERC1967Proxy`, while `PredictionMarketV2` is deployed as a separate implementation for the documented V1 to V2 upgrade path.

The `TimelockController` is configured with a 2-day delay. The Governor receives proposer and canceller permissions, while execution is open to anyone after the delay.
