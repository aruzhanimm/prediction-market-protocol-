// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {GovernanceToken} from "../../src/tokens/GovernanceToken.sol";

/// @dev Handler contract that performs random token transfers and delegations.
///      Foundry invariant runner calls these functions to generate state changes.
contract GovernanceTokenHandler is Test {
    GovernanceToken internal token;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    address[] internal actors;

    constructor(GovernanceToken _token, address teamWallet) {
        token = _token;

        actors.push(alice);
        actors.push(bob);
        actors.push(carol);

        // Seed actors with tokens from the team wallet.
        vm.startPrank(teamWallet);
        token.transfer(alice, 1_000_000 ether);
        token.transfer(bob, 1_000_000 ether);
        token.transfer(carol, 500_000 ether);
        vm.stopPrank();
    }

    /// @dev Random transfer between known actors.
    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];

        if (from == to) return;

        uint256 balance = token.balanceOf(from);
        if (balance == 0) return;

        amount = bound(amount, 0, balance);

        vm.prank(from);
        token.transfer(to, amount);
    }

    /// @dev Random delegation between known actors.
    function delegate(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];

        vm.prank(from);
        token.delegate(to);
    }
}

/// @title GovernanceTokenInvariantTest
/// @notice Invariants for GovernanceToken supply conservation.
/// @dev Transfers and delegation must never change totalSupply because the token
///      has no public mint or burn function after deployment.
contract GovernanceTokenInvariantTest is StdInvariant, Test {
    GovernanceToken internal token;
    GovernanceTokenHandler internal handler;

    address internal team = makeAddr("team");
    address internal treasury_ = makeAddr("treasury_");
    address internal community = makeAddr("community");
    address internal liquidity = makeAddr("liquidity");

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    uint256 internal expectedTotalSupply;

    function setUp() public {
        token = new GovernanceToken(team, treasury_, community, liquidity);

        expectedTotalSupply = token.totalSupply();

        handler = new GovernanceTokenHandler(token, team);

        // Only handler functions should be called during invariant runs.
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = GovernanceTokenHandler.transfer.selector;
        selectors[1] = GovernanceTokenHandler.delegate.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @notice Total supply must stay constant after arbitrary transfers/delegations.
    function invariant_totalSupplyIsConstant() public view {
        assertEq(token.totalSupply(), expectedTotalSupply, "GovernanceToken totalSupply changed");
    }

    /// @notice Sum of all tracked balances must equal totalSupply.
    /// @dev The handler only moves tokens among these known addresses.
    function invariant_balanceSumEqualsSupply() public view {
        uint256 sum;

        sum += token.balanceOf(team);
        sum += token.balanceOf(treasury_);
        sum += token.balanceOf(community);
        sum += token.balanceOf(liquidity);

        sum += token.balanceOf(alice);
        sum += token.balanceOf(bob);
        sum += token.balanceOf(carol);

        assertEq(sum, expectedTotalSupply, "Balance sum != totalSupply");
    }
}
