// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";

// Minimal interface for Chainlink mainnet feed.
interface IChainlinkFeed {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function decimals() external view returns (uint8);
}

// Minimal ERC-20 interface for fork tests.
interface IERC20Minimal {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}

// Minimal Uniswap V2 Router interface.
interface IUniswapV2Router {
    function factory() external view returns (address);
    function WETH() external view returns (address);
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
}

// Minimal Uniswap V2 Factory interface.
interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

/// @title ForkTests
/// @notice Three fork tests satisfying the required mainnet-fork testing component.
/// @dev Run with:
///      forge test --match-path test/fork/Fork.t.sol --fork-url $ETH_MAINNET_RPC -vv
contract ForkTests is Test {
    /// @dev Chainlink ETH/USD feed on Ethereum mainnet.
    address internal constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    /// @dev USDC token on Ethereum mainnet.
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @dev Uniswap V2 Router02 on Ethereum mainnet.
    address internal constant UNI_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    /// @dev WETH token on Ethereum mainnet.
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @dev Well-known USDC holder used for a balance sanity check.
    address internal constant USDC_WHALE = 0x55FE002aefF02F77364de339a1292923A15844B8;

    string internal mainnetRpc;
    uint256 internal forkId;

    function setUp() public {
        mainnetRpc = vm.envOr("ETH_MAINNET_RPC", string(""));

        if (bytes(mainnetRpc).length == 0) {
            vm.skip(true);
        }

        forkId = vm.createFork(mainnetRpc);
        vm.selectFork(forkId);
    }

    // Fork Test 1: Chainlink ETH/USD feed

    /// @notice Reads the Chainlink ETH/USD price feed on mainnet.
    ///         Validates that the answer is positive, reasonable, complete, and fresh.
    function test_fork_chainlinkEthUsd_latestAnswer() public view {
        IChainlinkFeed feed = IChainlinkFeed(CHAINLINK_ETH_USD);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            feed.latestRoundData();

        console2.log("ETH/USD roundId:", roundId);
        console2.log("ETH/USD answer:", uint256(answer));
        console2.log("ETH/USD updatedAt:", updatedAt);
        console2.log("ETH/USD decimals:", feed.decimals());

        assertGt(answer, 0, "ETH/USD price not positive");
        assertGt(answer, 100e8, "ETH price suspiciously low");
        assertLt(answer, 100_000e8, "ETH price suspiciously high");
        assertGe(answeredInRound, roundId, "Incomplete round");
        assertLt(block.timestamp - updatedAt, 7200, "Price is stale");
        assertLe(startedAt, updatedAt);
        assertEq(feed.decimals(), 8);
    }

    // Fork Test 2: USDC ERC-20

    /// @notice Reads USDC totalSupply and a known holder balance on mainnet.
    ///         Confirms that ERC-20 reads work correctly on a fork.
    function test_fork_usdc_totalSupplyAndBalance() public view {
        IERC20Minimal usdc = IERC20Minimal(USDC);

        uint256 supply = usdc.totalSupply();
        uint256 whaleBalance = usdc.balanceOf(USDC_WHALE);
        uint8 dec = usdc.decimals();

        console2.log("USDC totalSupply raw:", supply);
        console2.log("USDC holder balance:", whaleBalance);
        console2.log("USDC decimals:", dec);

        assertEq(dec, 6, "USDC decimals should be 6");
        assertGt(supply, 0, "USDC totalSupply is zero");
        assertGt(supply, 1_000_000_000 * 1e6, "USDC supply suspiciously low");
        assertGt(whaleBalance, 0, "USDC holder balance is zero");
    }

    // Fork Test 3: Uniswap V2 Router

    /// @notice Queries Uniswap V2 Router getAmountsOut for the WETH/USDC path.
    ///         This verifies interaction with a real mainnet DeFi protocol.
    function test_fork_uniswapV2_getAmountsOut_WETH_USDC() public view {
        IUniswapV2Router router = IUniswapV2Router(UNI_V2_ROUTER);
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());

        assertEq(router.WETH(), WETH, "WETH address mismatch");

        address pair = factory.getPair(WETH, USDC);
        assertNotEq(pair, address(0), "WETH/USDC pair does not exist");

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;

        uint256 amountIn = 1 ether;
        uint256[] memory amounts = router.getAmountsOut(amountIn, path);

        uint256 usdcOut = amounts[1];

        console2.log("Uniswap V2 WETH to USDC: 1 ETH =", usdcOut / 1e6, "USDC approx");

        assertGt(usdcOut, 100 * 1e6, "WETH price suspiciously low on Uniswap V2");
        assertLt(usdcOut, 100_000 * 1e6, "WETH price suspiciously high on Uniswap V2");
        assertEq(amounts[0], amountIn);
        assertEq(amounts.length, 2);
    }
}
