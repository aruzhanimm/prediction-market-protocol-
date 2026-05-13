// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GovernanceToken} from "../../src/tokens/GovernanceToken.sol";
import {FeeVault} from "../../src/vault/FeeVault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Simple ERC20 used as vault asset in tests.
contract MockLP is ERC20 {
    constructor() ERC20("MockLP", "MLP") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title FuzzGovernanceVaultTest
/// @notice Four additional fuzz tests pushing total fuzz count to ≥10.
///   1. Governance voting power after transfer is consistent with delegation.
///   2. Governance voting power delegated correctly across multiple holders.
///   3. Vault deposit/redeem round-trip: user gets back ≤ deposited (no inflation).
///   4. Vault share price is monotonically non-decreasing after harvest.
contract FuzzGovernanceVaultTest is Test {
    GovernanceToken internal token;
    MockLP internal lp;
    FeeVault internal vault;

    address internal team = makeAddr("team");
    address internal treasury_ = makeAddr("treasury_");
    address internal community = makeAddr("community");
    address internal liquidity = makeAddr("liquidity");
    address internal vaultOwner = makeAddr("vaultOwner");

    function setUp() public {
        token = new GovernanceToken(team, treasury_, community, liquidity);
        lp = new MockLP();
        vault = new FeeVault(address(lp), "Vault Share", "vMLP", vaultOwner);
    }

    // Fuzz 7: voting power after single transfer

    /// @notice After transferring `amount` tokens and delegating to self,
    ///         getPastVotes equals the transferred amount (after one block).
    function testFuzz_votingPower_afterTransfer(uint256 amount) public {
        // Bound to realistic range
        uint256 totalTeam = token.balanceOf(team);
        amount = bound(amount, 1, totalTeam);

        address voter = makeAddr("fuzzVoter");

        vm.prank(team);
        token.transfer(voter, amount);

        vm.prank(voter);
        token.delegate(voter);

        // Advance one block so snapshot is recorded
        uint256 snap = block.number;
        vm.roll(block.number + 1);

        uint256 votes = token.getPastVotes(voter, snap);
        assertEq(votes, amount, "Votes should equal transferred amount");
    }

    // Fuzz 8: multi-holder delegation consistency

    /// @notice Splitting supply across n holders and delegating to self:
    ///         sum of all past votes == total tokens distributed.
    function testFuzz_votingPower_splitDelegation(uint256 splitA, uint256 splitB) public {
        uint256 totalTeam = token.balanceOf(team);
        // Ensure splits fit within supply
        splitA = bound(splitA, 1, totalTeam / 3);
        splitB = bound(splitB, 1, totalTeam / 3);

        address voterA = makeAddr("fuzzVoterA");
        address voterB = makeAddr("fuzzVoterB");

        vm.startPrank(team);
        token.transfer(voterA, splitA);
        token.transfer(voterB, splitB);
        vm.stopPrank();

        vm.prank(voterA);
        token.delegate(voterA);
        vm.prank(voterB);
        token.delegate(voterB);

        uint256 snap = block.number;
        vm.roll(block.number + 1);

        uint256 votesA = token.getPastVotes(voterA, snap);
        uint256 votesB = token.getPastVotes(voterB, snap);

        assertEq(votesA, splitA, "VoterA votes mismatch");
        assertEq(votesB, splitB, "VoterB votes mismatch");
        // Total delegated = sum of individual votes
        assertEq(votesA + votesB, splitA + splitB, "Sum mismatch");
    }

    // Fuzz 9: vault deposit/redeem round-trip

    /// @notice Depositing `assets` and immediately redeeming should return
    ///         ≤ assets (no free money; virtual offset means slight rounding loss is OK).
    function testFuzz_vault_depositRedeem_noFreeProfit(uint256 assets) public {
        assets = bound(assets, 2, 1_000_000 ether); // min 2 to avoid zero-share rounding

        address user = makeAddr("fuzzUser");
        lp.mint(user, assets);

        vm.startPrank(user);
        lp.approve(address(vault), assets);

        uint256 shares = vault.deposit(assets, user);
        assertGt(shares, 0, "No shares minted");

        // Immediately redeem all shares
        vault.approve(address(vault), shares); // vault share allowance for redeem-on-behalf not needed here
        uint256 assetsOut = vault.redeem(shares, user, user);
        vm.stopPrank();

        // User should get back ≤ what they put in (virtual offset causes ≤1 wei rounding loss)
        assertLe(assetsOut, assets, "User got more than deposited - share price inflation");
        // And should get back nearly all (within 2 wei due to virtual offset)
        assertGe(assetsOut + 2, assets, "User lost more than 2 wei - unexpected loss");
    }

    // Fuzz 10: vault share price non-decreasing after harvest

    /// @notice After harvesting yield, the price per share (convertToAssets(1e18))
    ///         must be ≥ the price before harvest.
    function testFuzz_vault_sharePriceNonDecreasingAfterHarvest(uint256 initialDeposit, uint256 yieldAmount) public {
        initialDeposit = bound(initialDeposit, 1_000, 1_000_000 ether);
        yieldAmount = bound(yieldAmount, 1, 500_000 ether);

        address depositor = makeAddr("fuzzDepositor");
        lp.mint(depositor, initialDeposit);
        lp.mint(vaultOwner, yieldAmount);

        // Initial deposit
        vm.startPrank(depositor);
        lp.approve(address(vault), initialDeposit);
        vault.deposit(initialDeposit, depositor);
        vm.stopPrank();

        uint256 priceBefore = vault.convertToAssets(1 ether);

        // Harvest
        vm.startPrank(vaultOwner);
        lp.approve(address(vault), yieldAmount);
        vault.harvest(yieldAmount);
        vm.stopPrank();

        uint256 priceAfter = vault.convertToAssets(1 ether);

        assertGe(priceAfter, priceBefore, "Share price decreased after harvest");
    }
}
