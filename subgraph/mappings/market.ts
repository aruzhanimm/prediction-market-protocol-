import { BigInt } from "@graphprotocol/graph-ts";
import {
  MarketCreated,
  MarketResolved,
  MarketCancelled,
  SharesRedeemed,
} from "../generated/PredictionMarket/PredictionMarket";
import { Market } from "../generated/schema";

export function handleMarketCreated(event: MarketCreated): void {
  let id = event.params.marketId.toString();
  let market = new Market(id);

  market.marketId = event.params.marketId;
  market.creator = event.params.creator;
  market.question = event.params.question;
  market.resolutionTime = event.params.resolutionTime;
  market.status = "Open";

  // The outcome is unknown while the market is open.
  // Do not assign null directly to Boolean in AssemblyScript.
  market.unset("outcome");

  market.totalShares = BigInt.fromI32(0);
  market.createdAt = event.block.timestamp;
  market.txHash = event.transaction.hash;

  market.save();
}

export function handleMarketResolved(event: MarketResolved): void {
  let market = Market.load(event.params.marketId.toString());

  if (market == null) {
    return;
  }

  market.status = "Resolved";
  market.outcome = event.params.outcome;

  market.save();
}

export function handleMarketCancelled(event: MarketCancelled): void {
  let market = Market.load(event.params.marketId.toString());

  if (market == null) {
    return;
  }

  market.status = "Cancelled";

  market.save();
}

export function handleSharesRedeemed(event: SharesRedeemed): void {
  let market = Market.load(event.params.marketId.toString());

  if (market == null) {
    return;
  }

  market.totalShares = market.totalShares.minus(event.params.sharesBurned);

  market.save();
}