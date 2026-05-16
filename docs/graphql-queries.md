# GraphQL Queries — Prediction Market Protocol

Subgraph endpoint:
```
https://api.studio.thegraph.com/query/1753370/prediction-market-protocol/v0.0.3
```

---

## Query 1 — All Open Markets

Returns all prediction markets with status "Open", ordered by creation date.

```graphql
{
  markets(
    where: { status: "Open" }
    orderBy: createdAt
    orderDirection: desc
    first: 20
  ) {
    id
    question
    status
    creator
    resolutionTime
    totalShares
    createdAt
  }
}
```

---

## Query 2 — Latest 10 Trades by Market ID

Returns the most recent trades (swaps) on the AMM for a given market.

```graphql
query TradesByMarket($marketId: ID!) {
  trades(
    where: { market: $marketId }
    orderBy: timestamp
    orderDirection: desc
    first: 10
  ) {
    id
    trader
    buyYes
    amountIn
    amountOut
    timestamp
    txHash
    blockNumber
  }
}
```

Example variables:
```json
{ "marketId": "0" }
```

---

## Query 3 — Liquidity Position by Provider

Returns all liquidity positions for a specific wallet address.

```graphql
query LiquidityByProvider($provider: Bytes!) {
  liquidityPositions(
    where: { provider: $provider }
  ) {
    id
    lpTokens
    yesDeposited
    noDeposited
    lastUpdated
    market {
      id
      question
      status
    }
  }
}
```

Example variables:
```json
{ "provider": "0xb2159776c44fd145bf51cd92405e31ce2040ff73" }
```

---

## Query 4 — All Active Governance Proposals

Returns all proposals currently in Pending or Active state.

```graphql
{
  governanceProposals(
    where: { state_in: ["Pending", "Active"] }
    orderBy: createdAt
    orderDirection: desc
  ) {
    id
    proposalId
    proposer
    description
    state
    forVotes
    againstVotes
    abstainVotes
    startBlock
    endBlock
    eta
  }
}
```

---

## Query 5 — Vote History by Proposal ID

Returns full vote breakdown for a specific governance proposal.

```graphql
query ProposalWithVotes($proposalId: ID!) {
  governanceProposal(id: $proposalId) {
    id
    description
    state
    forVotes
    againstVotes
    abstainVotes
    eta
    proposer
    startBlock
    endBlock
  }
}
```

Example variables:
```json
{ "proposalId": "12345" }
```