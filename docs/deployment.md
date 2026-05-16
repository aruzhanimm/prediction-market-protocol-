# Deployment Guide - Arbitrum Sepolia

## Network

| Field | Value |
|---|---|
| Network | Arbitrum Sepolia |
| Chain ID | 421614 |
| Explorer | https://sepolia.arbiscan.io |
| RPC environment variable | `ARBITRUM_SEPOLIA_RPC_URL` |

## Required environment variables

Before deployment, set the following variables:

```powershell
$env:PRIVATE_KEY="0xYOUR_PRIVATE_KEY"
$env:ARBITRUM_SEPOLIA_RPC_URL="https://..."
$env:ARBISCAN_API_KEY="YOUR_ARBISCAN_API_KEY"
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
  --rpc-url $env:ARBITRUM_SEPOLIA_RPC_URL `
  --broadcast `
  --verify `
  --etherscan-api-key $env:ARBISCAN_API_KEY
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
  --rpc-url $env:ARBITRUM_SEPOLIA_RPC_URL
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
| GovernanceToken | `0x1d8F27C369BC460f26C8fb5AAb897b4230c2E22c` | https://sepolia.arbiscan.io/search?f=0&q=0x1d8F27C369BC460f26C8fb5AAb897b4230c2E22c |
| TimelockController | `0xa3317a62CccA788e5924BDDC6cDe36B6ba4984B1` | https://sepolia.arbiscan.io/search?f=0&q=0xa3317a62CccA788e5924BDDC6cDe36B6ba4984B1 |
| MyGovernor | `0x61E3585B25F8FDEaa127264Bc08f8fc335D92ce2` | https://sepolia.arbiscan.io/search?f=0&q=0x61E3585B25F8FDEaa127264Bc08f8fc335D92ce2 |
| Treasury | `0x411Df3c1ad4e253302fA4BB553A29d78D65A07A6` | https://sepolia.arbiscan.io/search?f=0&q=0x411Df3c1ad4e253302fA4BB553A29d78D65A07A6 |
| OutcomeShareToken | `0x2872B16A1b58ce92a5D1d8Da80BcE1abC4eae865` | https://sepolia.arbiscan.io/search?f=0&q=0x2872B16A1b58ce92a5D1d8Da80BcE1abC4eae865 |
| PredictionMarket Implementation V1 | `0x7C115581124B15187d66045b9910EB1E5F454960` | https://sepolia.arbiscan.io/search?f=0&q=0x7C115581124B15187d66045b9910EB1E5F454960 |
| PredictionMarket Proxy | `0xc95dE1BAFabE53B2c9a743a4425296Ce4293530e` | https://sepolia.arbiscan.io/search?f=0&q=0xc95dE1BAFabE53B2c9a743a4425296Ce4293530e |
| PredictionMarket Implementation V2 | `0xc9BD3412ABD9210963142E220ceD49253FB113eA` | https://sepolia.arbiscan.io/search?f=0&q=0xc9BD3412ABD9210963142E220ceD49253FB113eA |
| MarketAMM | `0xB4d820DD5cD9A5c2eE92AdA161D48c4Ce5cb9dD6` | https://sepolia.arbiscan.io/search?f=0&q=0xB4d820DD5cD9A5c2eE92AdA161D48c4Ce5cb9dD6 |
| FeeVault | `0xbE5ec37e14B44E0675Fedec533BF235c744367f2` | https://sepolia.arbiscan.io/search?f=0&q=0xbE5ec37e14B44E0675Fedec533BF235c744367f2 |
| MarketFactory | `0x7549bC2A3F0ce716C067570af1615f97E7A93792` | https://sepolia.arbiscan.io/search?f=0&q=0x7549bC2A3F0ce716C067570af1615f97E7A93792 |
| ChainlinkResolver | `0x237555EcbF1329821e9245fb255979D512B76592` | https://sepolia.arbiscan.io/search?f=0&q=0x237555EcbF1329821e9245fb255979D512B76592 |

## Notes

The deployment script is parameterized through environment variables. This allows the protocol to be redeployed to a fresh L2 testnet without manually editing Solidity files.

The `PredictionMarket` contract is deployed through an `ERC1967Proxy`, while `PredictionMarketV2` is deployed as a separate implementation for the documented V1 to V2 upgrade path.

The `TimelockController` is configured with a 2-day delay. The Governor receives proposer and canceller permissions, while execution is open to anyone after the delay.
