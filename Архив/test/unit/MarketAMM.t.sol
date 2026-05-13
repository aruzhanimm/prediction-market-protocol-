// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {MarketAMM} from "../../src/core/MarketAMM.sol";
import {OutcomeShareToken} from "../../src/tokens/OutcomeShareToken.sol";

/// @notice Shared setup for all AMM tests.
abstract contract AMMTestBase is Test {
    OutcomeShareToken internal outcomeToken;
    MarketAMM internal amm;

    address internal admin = makeAddr("admin");
    address internal minter = makeAddr("minter");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant MARKET_ID = 0;
    uint256 internal constant INITIAL_LIQUIDITY = 10_000 ether;

    bytes32 internal constant LIQUIDITY_ADDED_SIG = keccak256("LiquidityAdded(address,uint256,uint256,uint256)");
    bytes32 internal constant LIQUIDITY_REMOVED_SIG = keccak256("LiquidityRemoved(address,uint256,uint256,uint256)");
    bytes32 internal constant SWAP_SIG = keccak256("Swap(address,bool,uint256,uint256)");

    function setUp() public virtual {
        // Deploy shared ERC-1155 token
        outcomeToken = new OutcomeShareToken("https://api.example.com/", admin);
        bytes32 minterRole = outcomeToken.MINTER_ROLE();

        vm.prank(admin);
        outcomeToken.grantRole(minterRole, minter);

        // Deploy AMM for market 0
        amm = new MarketAMM(address(outcomeToken), MARKET_ID);

        // Approve AMM to transfer outcome tokens on behalf of users
        vm.prank(alice);
        outcomeToken.setApprovalForAll(address(amm), true);

        vm.prank(bob);
        outcomeToken.setApprovalForAll(address(amm), true);
    }

    /// @dev Mint equal YES and NO shares to `to`.
    function _mintShares(address to, uint256 amount) internal {
        vm.prank(minter);
        outcomeToken.mintOutcomes(MARKET_ID, to, amount);
    }

    /// @dev Converts an address into an indexed event topic.
    function _addressTopic(address account) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(account)));
    }
}

// Section 1 — addLiquidity

contract MarketAMM_AddLiquidity is AMMTestBase {
    // Test 1 — First liquidity provision mints LP tokens (geometric mean minus min liquidity)
    function test_addLiquidity_firstProvider_mintsLP() public {
        _mintShares(alice, INITIAL_LIQUIDITY);

        vm.prank(alice);
        uint256 lpOut = amm.addLiquidity(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY, 0);

        // LP = sqrt(10000e18 * 10000e18) - 1000 = 10000e18 - 1000
        uint256 expectedLP = INITIAL_LIQUIDITY - 1000; // since sqrt(x*x) = x

        assertEq(lpOut, expectedLP, "first provision LP mismatch");
        assertEq(amm.balanceOf(alice), expectedLP, "alice LP balance");
        assertEq(amm.balanceOf(address(1)), 1000, "min liquidity burned to address(1)");
    }

    // Test 2 — Reserves updated correctly after first add
    function test_addLiquidity_firstProvider_reservesCorrect() public {
        _mintShares(alice, INITIAL_LIQUIDITY);

        vm.prank(alice);
        amm.addLiquidity(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY, 0);

        (uint256 rYes, uint256 rNo,) = amm.getReserves();

        assertEq(rYes, INITIAL_LIQUIDITY, "YES reserve");
        assertEq(rNo, INITIAL_LIQUIDITY, "NO reserve");
    }

    // Test 3 — Subsequent provider receives proportional LP
    function test_addLiquidity_subsequentProvider_proportionalLP() public {
        _mintShares(alice, INITIAL_LIQUIDITY);

        vm.prank(alice);
        amm.addLiquidity(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY, 0);

        uint256 addAmount = 1_000 ether;
        _mintShares(bob, addAmount);

        uint256 totalSupplyBefore = amm.totalSupply();
        uint256 reserveYesBefore = amm.reserveYes();

        vm.prank(bob);
        uint256 lpOut = amm.addLiquidity(addAmount, addAmount, 0);

        // Expected LP = addAmount / reserveYes * totalSupply (before add)
        uint256 expectedLP = addAmount * totalSupplyBefore / reserveYesBefore;

        assertEq(lpOut, expectedLP, "subsequent LP proportional");
    }

    // Test 4 — addLiquidity reverts when output below minLPOut
    function test_addLiquidity_reverts_slippage() public {
        _mintShares(alice, INITIAL_LIQUIDITY);

        vm.prank(alice);
        vm.expectRevert();

        amm.addLiquidity(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY, type(uint256).max);
    }

    // Test 5 — addLiquidity reverts on zero amounts
    function test_addLiquidity_reverts_zeroAmount() public {
        _mintShares(alice, INITIAL_LIQUIDITY);

        vm.prank(alice);
        vm.expectRevert();

        amm.addLiquidity(0, INITIAL_LIQUIDITY, 0);
    }

    // Test 6 — ERC-1155 tokens transferred from provider to AMM
    function test_addLiquidity_transfersTokensToAMM() public {
        _mintShares(alice, INITIAL_LIQUIDITY);

        vm.prank(alice);
        amm.addLiquidity(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY, 0);

        uint256 yesId = outcomeToken.yesTokenId(MARKET_ID);
        uint256 noId = outcomeToken.noTokenId(MARKET_ID);

        assertEq(outcomeToken.balanceOf(address(amm), yesId), INITIAL_LIQUIDITY);
        assertEq(outcomeToken.balanceOf(address(amm), noId), INITIAL_LIQUIDITY);
        assertEq(outcomeToken.balanceOf(alice, yesId), 0);
    }
}

// Section 2 — removeLiquidity

contract MarketAMM_RemoveLiquidity is AMMTestBase {
    function setUp() public override {
        super.setUp();

        _mintShares(alice, INITIAL_LIQUIDITY);

        vm.prank(alice);
        amm.addLiquidity(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY, 0);
    }

    // Test 7 — Full removal returns proportional tokens
    function test_removeLiquidity_full() public {
        uint256 lpBalance = amm.balanceOf(alice);

        vm.prank(alice);
        (uint256 yesOut, uint256 noOut) = amm.removeLiquidity(lpBalance, 0, 0);

        // Alice has all LP minus the burned 1000, so she gets back proportional share
        uint256 totalSupply = lpBalance + 1000; // 1000 still held by address(1)
        uint256 expectedYes = INITIAL_LIQUIDITY * lpBalance / totalSupply;
        uint256 expectedNo = INITIAL_LIQUIDITY * lpBalance / totalSupply;

        assertEq(yesOut, expectedYes, "YES returned");
        assertEq(noOut, expectedNo, "NO returned");
        assertEq(amm.balanceOf(alice), 0, "alice LP burned");
    }

    // Test 8 — Partial removal (50%)
    function test_removeLiquidity_partial() public {
        uint256 lpBalance = amm.balanceOf(alice);
        uint256 half = lpBalance / 2;

        vm.prank(alice);
        (uint256 yesOut, uint256 noOut) = amm.removeLiquidity(half, 0, 0);

        assertGt(yesOut, 0, "received some YES");
        assertGt(noOut, 0, "received some NO");
        assertEq(amm.balanceOf(alice), lpBalance - half, "alice remaining LP");
    }

    // Test 9 — Reverts when minYesOut not met
    function test_removeLiquidity_reverts_minYesOut() public {
        uint256 lpBalance = amm.balanceOf(alice);

        vm.prank(alice);
        vm.expectRevert();

        amm.removeLiquidity(lpBalance, type(uint256).max, 0);
    }

    // Test 10 — Reverts when minNoOut not met
    function test_removeLiquidity_reverts_minNoOut() public {
        uint256 lpBalance = amm.balanceOf(alice);

        vm.prank(alice);
        vm.expectRevert();

        amm.removeLiquidity(lpBalance, 0, type(uint256).max);
    }

    // Test 11 — Reverts on zero LP amount
    function test_removeLiquidity_reverts_zeroLP() public {
        vm.prank(alice);
        vm.expectRevert();

        amm.removeLiquidity(0, 0, 0);
    }
}

// Section 3 — swap

contract MarketAMM_Swap is AMMTestBase {
    uint256 internal constant SWAP_AMOUNT = 100 ether;

    function setUp() public override {
        super.setUp();

        _mintShares(alice, INITIAL_LIQUIDITY);

        vm.prank(alice);
        amm.addLiquidity(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY, 0);

        _mintShares(bob, SWAP_AMOUNT * 10); // give bob plenty to swap
    }

    // Test 12 — Swap NO → YES (buyYes = true)
    function test_swap_buyYes() public {
        uint256 noBalanceBefore = outcomeToken.balanceOf(bob, outcomeToken.noTokenId(MARKET_ID));
        uint256 yesBalanceBefore = outcomeToken.balanceOf(bob, outcomeToken.yesTokenId(MARKET_ID));

        vm.prank(bob);
        uint256 amountOut = amm.swap(true, SWAP_AMOUNT, 0);

        assertGt(amountOut, 0, "received YES");
        assertEq(
            outcomeToken.balanceOf(bob, outcomeToken.noTokenId(MARKET_ID)),
            noBalanceBefore - SWAP_AMOUNT,
            "bob NO decreased"
        );
        assertEq(
            outcomeToken.balanceOf(bob, outcomeToken.yesTokenId(MARKET_ID)),
            yesBalanceBefore + amountOut,
            "bob YES increased"
        );
    }

    // Test 13 — Swap YES → NO (buyYes = false)
    function test_swap_buyNo() public {
        vm.prank(bob);
        uint256 amountOut = amm.swap(false, SWAP_AMOUNT, 0);

        assertGt(amountOut, 0, "received NO");
        // NO output must be less than SWAP_AMOUNT due to price impact
        assertLt(amountOut, SWAP_AMOUNT, "output < input due to fee/impact");
    }

    // Test 14 — k never decreases after swap (fee causes it to strictly increase)
    function test_swap_kInvariant_neverDecreases() public {
        (,, uint256 kBefore) = amm.getReserves();

        vm.prank(bob);
        amm.swap(true, SWAP_AMOUNT, 0);

        (,, uint256 kAfter) = amm.getReserves();

        assertGe(kAfter, kBefore, "k must never decrease after swap");
    }

    // Test 15 — Slippage protection: reverts when output below minAmountOut
    function test_swap_reverts_slippageProtection() public {
        uint256 expectedOut = amm.getAmountOut(true, SWAP_AMOUNT);

        vm.prank(bob);
        vm.expectRevert();

        amm.swap(true, SWAP_AMOUNT, expectedOut + 1); // 1 wei more than possible
    }

    // Test 16 — Large swap causes significant price impact
    function test_swap_largeSwap_highPriceImpact() public {
        // Swap 50% of pool — should cause >25% output discount
        uint256 largeAmount = INITIAL_LIQUIDITY / 2;

        _mintShares(bob, largeAmount);

        uint256 amountOut = amm.getAmountOut(true, largeAmount);

        // At 50% of pool, output should be significantly less than 50% of reserve
        assertLt(amountOut, largeAmount * 3 / 4, "high price impact expected");
    }

    // Test 17 — getAmountOut is consistent with actual swap output
    function test_getAmountOut_matchesActualSwap() public {
        uint256 predicted = amm.getAmountOut(true, SWAP_AMOUNT);

        vm.prank(bob);
        uint256 actual = amm.swap(true, SWAP_AMOUNT, 0);

        assertEq(predicted, actual, "getAmountOut must match actual swap");
    }

    // Test 18 — Swap reverts with zero amountIn
    function test_swap_reverts_zeroInput() public {
        vm.prank(bob);
        vm.expectRevert();

        amm.swap(true, 0, 0);
    }
}

// Section 4 — Multiple operations and events

contract MarketAMM_Events is AMMTestBase {
    // Test 19 — LiquidityAdded event emitted
    function test_event_LiquidityAdded() public {
        _mintShares(alice, INITIAL_LIQUIDITY);

        vm.recordLogs();

        vm.prank(alice);
        amm.addLiquidity(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool found;
        uint256 expectedLP = INITIAL_LIQUIDITY - 1000;

        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(amm) && logs[i].topics.length > 1 && logs[i].topics[0] == LIQUIDITY_ADDED_SIG
                    && logs[i].topics[1] == _addressTopic(alice)
            ) {
                (uint256 yesAmount, uint256 noAmount, uint256 lpMinted) =
                    abi.decode(logs[i].data, (uint256, uint256, uint256));

                assertEq(yesAmount, INITIAL_LIQUIDITY, "YES amount");
                assertEq(noAmount, INITIAL_LIQUIDITY, "NO amount");
                assertEq(lpMinted, expectedLP, "LP minted");

                found = true;
            }
        }

        assertTrue(found, "LiquidityAdded event not found");
    }

    // Test 20 — Swap event emitted
    function test_event_Swap() public {
        _mintShares(alice, INITIAL_LIQUIDITY);

        vm.prank(alice);
        amm.addLiquidity(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY, 0);

        _mintShares(bob, 100 ether);

        uint256 expectedOut = amm.getAmountOut(true, 100 ether);

        vm.recordLogs();

        vm.prank(bob);
        amm.swap(true, 100 ether, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool found;

        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(amm) && logs[i].topics.length > 1 && logs[i].topics[0] == SWAP_SIG
                    && logs[i].topics[1] == _addressTopic(bob)
            ) {
                (bool buyYes, uint256 amountIn, uint256 amountOut) = abi.decode(logs[i].data, (bool, uint256, uint256));

                assertTrue(buyYes, "buyYes flag");
                assertEq(amountIn, 100 ether, "amount in");
                assertEq(amountOut, expectedOut, "amount out");

                found = true;
            }
        }

        assertTrue(found, "Swap event not found");
    }

    // Test 21 — LiquidityRemoved event emitted
    function test_event_LiquidityRemoved() public {
        _mintShares(alice, INITIAL_LIQUIDITY);

        vm.prank(alice);
        amm.addLiquidity(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY, 0);

        uint256 lpBalance = amm.balanceOf(alice);

        vm.recordLogs();

        vm.prank(alice);
        amm.removeLiquidity(lpBalance, 0, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool found;

        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(amm) && logs[i].topics.length > 1
                    && logs[i].topics[0] == LIQUIDITY_REMOVED_SIG && logs[i].topics[1] == _addressTopic(alice)
            ) {
                (uint256 yesAmount, uint256 noAmount, uint256 lpBurned) =
                    abi.decode(logs[i].data, (uint256, uint256, uint256));

                assertGt(yesAmount, 0, "YES removed");
                assertGt(noAmount, 0, "NO removed");
                assertEq(lpBurned, lpBalance, "LP burned");

                found = true;
            }
        }

        assertTrue(found, "LiquidityRemoved event not found");
    }
}
