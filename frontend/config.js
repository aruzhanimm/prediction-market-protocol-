window.APP_CONFIG = {
  chain: {
    chainIdDecimal: 421614,
    chainIdHex: "0x66eee",
    chainName: "Arbitrum Sepolia",
    rpcUrls: ["https://sepolia-rollup.arbitrum.io/rpc"],
    blockExplorerUrls: ["https://sepolia.arbiscan.io"],
    nativeCurrency: {
      name: "Ethereum",
      symbol: "ETH",
      decimals: 18,
    },
  },

  subgraphUrl:
    "https://api.studio.thegraph.com/query/1753370/prediction-market-protocol/v0.0.3",

  addresses: {
    governanceToken: "0x1d8F27C369BC460f26C8fb5AAb897b4230c2E22c",
    timelockController: "0xa3317a62CccA788e5924BDDC6cDe36B6ba4984B1",
    myGovernor: "0x61E3585B25F8FDEaa127264Bc08f8fc335D92ce2",
    treasury: "0x411Df3c1ad4e253302fA4BB553A29d78D65A07A6",
    outcomeShareToken: "0x2872B16A1b58ce92a5D1d8Da80BcE1abC4eae865",
    predictionMarketProxy: "0xc95dE1BAFabE53B2c9a743a4425296Ce4293530e",
    predictionMarketV1Implementation: "0x7C115581124B15187d66045b9910EB1E5F454960",
    predictionMarketV2Implementation: "0xc9BD3412ABD9210963142E220ceD49253FB113eA",
    marketAMM: "0xB4d820DD5cD9A5c2eE92AdA161D48c4Ce5cb9dD6",
    feeVault: "0xbE5ec37e14B44E0675Fedec533BF235c744367f2",
    marketFactory: "0x7549bC2A3F0ce716C067570af1615f97E7A93792",
    chainlinkResolver: "0x237555EcbF1329821e9245fb255979D512B76592",
  },
};