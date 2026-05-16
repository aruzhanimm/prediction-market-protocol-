import { BigInt } from "@graphprotocol/graph-ts";
import {
  Swap,
  LiquidityAdded,
  LiquidityRemoved,
} from "../generated/MarketAMM/MarketAMM";
import { Trade, LiquidityPosition } from "../generated/schema";

// AMM is tied to marketId 0 in the current deployed AMM instance.
const MARKET_ID = "0";

export function handleSwap(event: Swap): void {
  let id = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  let trade = new Trade(id);

  trade.market = MARKET_ID;
  trade.trader = event.params.trader;
  trade.buyYes = event.params.buyYes;
  trade.amountIn = event.params.amountIn;
  trade.amountOut = event.params.amountOut;
  trade.timestamp = event.block.timestamp;
  trade.txHash = event.transaction.hash;
  trade.blockNumber = event.block.number;

  trade.save();
}

export function handleLiquidityAdded(event: LiquidityAdded): void {
  let id = event.params.provider.toHex() + "-" + MARKET_ID;
  let position = LiquidityPosition.load(id);

  if (position == null) {
    position = new LiquidityPosition(id);
    position.market = MARKET_ID;
    position.provider = event.params.provider;
    position.lpTokens = BigInt.fromI32(0);
    position.yesDeposited = BigInt.fromI32(0);
    position.noDeposited = BigInt.fromI32(0);
  }

  position.lpTokens = position.lpTokens.plus(event.params.lpMinted);
  position.yesDeposited = position.yesDeposited.plus(event.params.yesAmount);
  position.noDeposited = position.noDeposited.plus(event.params.noAmount);
  position.lastUpdated = event.block.timestamp;

  position.save();
}

export function handleLiquidityRemoved(event: LiquidityRemoved): void {
  let id = event.params.provider.toHex() + "-" + MARKET_ID;
  let position = LiquidityPosition.load(id);

  if (position == null) {
    return;
  }

  position.lpTokens = position.lpTokens.minus(event.params.lpBurned);
  position.lastUpdated = event.block.timestamp;

  position.save();
}