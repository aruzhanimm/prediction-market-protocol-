// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockAggregator} from "../../src/oracle/MockAggregator.sol";
import {ChainlinkResolver} from "../../src/oracle/ChainlinkResolver.sol";

/// @dev Minimal stub of the PredictionMarket interface used by ChainlinkResolver.
///      Lets us test resolution logic without deploying the full proxy stack.
contract MockMarket {
    uint256 public lastResolvedMarket;
    bool public lastOutcome;
    bool public shouldRevert;

    function resolveMarket(uint256 marketId, bool outcome) external {
        if (shouldRevert) revert("MockMarket: revert");

        lastResolvedMarket = marketId;
        lastOutcome = outcome;
    }

    function setShouldRevert(bool v) external {
        shouldRevert = v;
    }
}

contract ChainlinkResolverTest is Test {
    MockAggregator internal feed;
    MockMarket internal market;
    ChainlinkResolver internal resolver;

    address internal admin = makeAddr("admin");
    address internal nobody = makeAddr("nobody");

    uint256 internal constant STALENESS = 1 hours; // 3600 seconds

    function setUp() public {
        feed = new MockAggregator(8, 2000_00000000); // ETH/USD = $2000, 8 decimals
        market = new MockMarket();
        resolver = new ChainlinkResolver(address(feed), address(market), STALENESS, admin);
    }

    // getLatestPrice

    /// @notice Returns valid price when data is fresh.
    function test_getLatestPrice_fresh_returnsPrice() public view {
        int256 price = resolver.getLatestPrice();

        assertEq(price, 2000_00000000);
    }

    /// @notice Reverts when updatedAt is older than the staleness threshold.
    function test_getLatestPrice_stale_reverts() public {
        // Set feed update time to current block time, then move time forward.
        // This avoids arithmetic underflow from subtracting from a small timestamp.
        feed.setUpdatedAt(block.timestamp);
        vm.warp(block.timestamp + STALENESS + 1);

        vm.expectRevert();
        resolver.getLatestPrice();
    }

    /// @notice Reverts with stale data after time moves beyond the threshold.
    function test_getLatestPrice_stale_revertSelector() public {
        feed.setUpdatedAt(block.timestamp);
        vm.warp(block.timestamp + STALENESS + 100);

        vm.expectRevert();
        resolver.getLatestPrice();
    }

    /// @notice Price updated after staleness resolves correctly again.
    function test_getLatestPrice_refreshedPrice() public {
        // First make the old answer stale.
        feed.setUpdatedAt(block.timestamp);
        vm.warp(block.timestamp + STALENESS + 1);

        vm.expectRevert();
        resolver.getLatestPrice();

        // Then refresh price; MockAggregator should update updatedAt to current timestamp.
        feed.setPrice(3000_00000000);

        int256 price = resolver.getLatestPrice();

        assertEq(price, 3000_00000000);
    }

    /// @notice Reverts when price is zero.
    function test_getLatestPrice_zeroPriceReverts() public {
        feed.setPriceAndTime(0, block.timestamp);

        vm.expectRevert();
        resolver.getLatestPrice();
    }

    /// @notice Reverts when price is negative.
    function test_getLatestPrice_negativePriceReverts() public {
        feed.setPriceAndTime(-1, block.timestamp);

        vm.expectRevert();
        resolver.getLatestPrice();
    }

    // resolveMarket

    /// @notice Resolves YES when price >= threshold.
    function test_resolveMarket_YES_whenPriceAboveThreshold() public {
        // ETH = $2000, threshold = $1800 -> YES
        vm.prank(admin);
        resolver.resolveMarket(0, 1800_00000000);

        assertEq(market.lastResolvedMarket(), 0);
        assertTrue(market.lastOutcome());
    }

    /// @notice Resolves NO when price < threshold.
    function test_resolveMarket_NO_whenPriceBelowThreshold() public {
        // ETH = $2000, threshold = $2500 -> NO
        vm.prank(admin);
        resolver.resolveMarket(42, 2500_00000000);

        assertEq(market.lastResolvedMarket(), 42);
        assertFalse(market.lastOutcome());
    }

    /// @notice Resolves YES when price == threshold.
    function test_resolveMarket_YES_atExactThreshold() public {
        vm.prank(admin);
        resolver.resolveMarket(1, 2000_00000000);

        assertEq(market.lastResolvedMarket(), 1);
        assertTrue(market.lastOutcome());
    }

    /// @notice Non-RESOLVER_ROLE cannot resolve.
    function test_resolveMarket_onlyResolver_reverts() public {
        vm.prank(nobody);
        vm.expectRevert();

        resolver.resolveMarket(0, 1000_00000000);
    }

    /// @notice Stale price blocks market resolution.
    function test_resolveMarket_stalePrice_reverts() public {
        feed.setUpdatedAt(block.timestamp);
        vm.warp(block.timestamp + STALENESS + 1);

        vm.prank(admin);
        vm.expectRevert();

        resolver.resolveMarket(0, 1000_00000000);
    }

    /// @notice Resolver bubbles up failure if the target market reverts.
    function test_resolveMarket_marketRevert_reverts() public {
        market.setShouldRevert(true);

        vm.prank(admin);
        vm.expectRevert();

        resolver.resolveMarket(0, 1000_00000000);
    }

    // MockAggregator

    /// @notice MockAggregator setPrice bumps round ID.
    function test_mockAggregator_setPrice_bumpsRoundId() public {
        (uint80 roundBefore,,,,) = feed.latestRoundData();

        feed.setPrice(9999_00000000);

        (uint80 roundAfter,,,,) = feed.latestRoundData();

        assertEq(roundAfter, roundBefore + 1);
    }

    /// @notice MockAggregator decimals and description.
    function test_mockAggregator_metadata() public view {
        assertEq(feed.decimals(), 8);
        assertEq(keccak256(bytes(feed.description())), keccak256(bytes("Mock Aggregator")));
        assertEq(feed.version(), 1);
    }
}
