// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Test, console2} from "forge-std/Test.sol";
import {GovernanceToken} from "../../src/tokens/GovernanceToken.sol";

contract GovernanceTokenTest is Test {
    address internal team = makeAddr("team");
    address internal treasury = makeAddr("treasury");
    address internal community = makeAddr("community");
    address internal liquidity = makeAddr("liquidity");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    GovernanceToken internal token;

    function setUp() public {
        token = new GovernanceToken(team, treasury, community, liquidity);
    }

    // Test 1 — Total supply
    function test_totalSupply() public view {
        assertEq(token.totalSupply(), token.TOTAL_SUPPLY(), "total supply mismatch");
    }

    // Test 2 — Distribution sums to TOTAL_SUPPLY
    function test_distributionSumsToTotalSupply() public view {
        uint256 total = token.TOTAL_SUPPLY();
        uint256 sum =
            token.balanceOf(team) + token.balanceOf(treasury) + token.balanceOf(community) + token.balanceOf(liquidity);
        assertEq(sum, total, "distribution does not sum to total supply");
    }

    // Test 3 — Team receives 40 %
    function test_teamBalance() public view {
        uint256 expected = (token.TOTAL_SUPPLY() * 4_000) / 10_000;
        assertEq(token.balanceOf(team), expected, "team balance incorrect");
    }

    // Test 4 — Treasury receives 30 %
    function test_treasuryBalance() public view {
        uint256 expected = (token.TOTAL_SUPPLY() * 3_000) / 10_000;
        assertEq(token.balanceOf(treasury), expected, "treasury balance incorrect");
    }

    // Test 5 — Community receives 20 %
    function test_communityBalance() public view {
        uint256 expected = (token.TOTAL_SUPPLY() * 2_000) / 10_000;
        assertEq(token.balanceOf(community), expected, "community balance incorrect");
    }

    // Test 6 — Liquidity receives 10 %
    function test_liquidityBalance() public view {
        uint256 expected = (token.TOTAL_SUPPLY() * 1_000) / 10_000;
        assertEq(token.balanceOf(liquidity), expected, "liquidity balance incorrect");
    }

    // Test 7 — Transfer tokens
    function test_transfer() public {
        uint256 amount = 1_000 ether;
        vm.prank(team);
        token.transfer(alice, amount);
        assertEq(token.balanceOf(alice), amount, "alice balance after transfer");
    }

    // Test 8 — Transfer reverts on insufficient balance
    function test_transfer_reverts_insufficientBalance() public {
        vm.prank(alice); // alice has 0 tokens
        vm.expectRevert();
        token.transfer(bob, 1 ether);
    }

    // Test 9 — Approve and transferFrom
    function test_approveAndTransferFrom() public {
        uint256 amount = 500 ether;
        vm.prank(team);
        token.approve(alice, amount);
        vm.prank(alice);
        token.transferFrom(team, bob, amount);
        assertEq(token.balanceOf(bob), amount, "bob balance after transferFrom");
        assertEq(token.allowance(team, alice), 0, "allowance should be 0 after use");
    }

    // Test 10 — Self-delegation grants voting power
    function test_selfDelegation_grantsVotingPower() public {
        uint256 balance = token.balanceOf(team);
        vm.prank(team);
        token.delegate(team);
        assertEq(token.getVotes(team), balance, "voting power should equal balance after self-delegation");
    }

    // Test 11 — Delegation to another address transfers voting power
    function test_delegateToAlice_transfersVotingPower() public {
        uint256 balance = token.balanceOf(team);
        vm.prank(team);
        token.delegate(alice);
        assertEq(token.getVotes(alice), balance, "alice should hold team's voting power");
        assertEq(token.getVotes(team), 0, "team should have 0 voting power after delegation");
    }

    // Test 12 — Voting power snapshot (getPastVotes)
    function test_pastVotes_snapshot() public {
        // Delegate in block N
        vm.prank(team);
        token.delegate(team);
        uint256 snapshotBlock = block.number;
        // Advance one block so the snapshot is in the past
        vm.roll(block.number + 1);
        uint256 expected = token.balanceOf(team);
        assertEq(
            token.getPastVotes(team, snapshotBlock),
            expected,
            "getPastVotes should return voting power at snapshot block"
        );
    }

    // Test 13 — Constructor reverts on zero teamWallet
    function test_constructor_reverts_zeroTeamWallet() public {
        vm.expectRevert();
        new GovernanceToken(address(0), treasury, community, liquidity);
    }

    // Test 14 — Permit nonce starts at 0
    function test_permit_nonceStartsAtZero() public view {
        assertEq(token.nonces(alice), 0, "nonce should start at 0");
    }

    // Test 15 — Token name and symbol
    function test_nameAndSymbol() public view {
        assertEq(token.name(), "PredictToken", "name mismatch");
        assertEq(token.symbol(), "PRED", "symbol mismatch");
    }
}
