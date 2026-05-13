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

/// @title ForkTests
/// @notice Fork tests for real Ethereum mainnet contracts.
/// @dev Run with:
///      forge test --match-path test/fork/Fork.t.sol --fork-url $ETH_MAINNET_RPC -vv
contract ForkTests is Test {
    /// @dev Chainlink ETH/USD feed on Ethereum mainnet.
    address internal constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    string internal mainnetRpc;
    uint256 internal forkId;

    function setUp() public {
        mainnetRpc = vm.envOr("ETH_MAINNET_RPC", string("https://eth.llamarpc.com"));
        forkId = vm.createFork(mainnetRpc);
        vm.selectFork(forkId);
    }

    // Fork Test 1: Chainlink ETH/USD feed

    /// @notice Reads the Chainlink ETH/USD price feed on mainnet.
    ///         Validates that the answer is positive, reasonable, complete, and fresh.
    function test_fork_chainlinkEthUsd_latestAnswer() public {
        IChainlinkFeed feed = IChainlinkFeed(CHAINLINK_ETH_USD);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            feed.latestRoundData();

        console2.log("ETH/USD roundId:", roundId);
        console2.log("ETH/USD answer:", uint256(answer));
        console2.log("ETH/USD updatedAt:", updatedAt);
        console2.log("ETH/USD decimals:", feed.decimals());

        // Price must be positive.
        assertGt(answer, 0, "ETH/USD price not positive");

        // Sanity range: $100 to $100,000 with 8 decimals.
        assertGt(answer, 100e8, "ETH price suspiciously low");
        assertLt(answer, 100_000e8, "ETH price suspiciously high");

        // Chainlink round completeness check.
        assertGe(answeredInRound, roundId, "Incomplete round");

        // Price should be updated within the last 2 hours.
        assertLt(block.timestamp - updatedAt, 7200, "Price is stale");

        // startedAt must not be after updatedAt.
        assertLe(startedAt, updatedAt);

        // ETH/USD Chainlink feed uses 8 decimals.
        assertEq(feed.decimals(), 8);
    }
}
