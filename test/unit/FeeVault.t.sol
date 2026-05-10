// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FeeVault} from "../../src/vault/FeeVault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Minimal ERC-20 used as the vault's underlying LP token in tests.
contract MockLPToken is ERC20 {
    constructor() ERC20("Mock LP Token", "mLP") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract FeeVaultTest is Test {
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    MockLPToken internal lpToken;
    FeeVault internal vault;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant INITIAL_DEPOSIT = 1_000 ether;

    function setUp() public {
        lpToken = new MockLPToken();
        vault = new FeeVault(address(lpToken), "Predict LP Vault", "vPRED-LP", owner);

        // Fund alice and bob with mock LP tokens
        lpToken.mint(alice, 100_000 ether);
        lpToken.mint(bob, 100_000 ether);

        // Give vault approval to pull LP tokens from users
        vm.prank(alice);
        lpToken.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        lpToken.approve(address(vault), type(uint256).max);

        vm.prank(owner);
        lpToken.approve(address(vault), type(uint256).max);
    }

    // Test 1 - asset() returns LP token address
    function test_asset_returnsLPToken() public view {
        assertEq(vault.asset(), address(lpToken), "asset address");
    }

    // Test 2 - deposit mints correct shares in an empty vault
    function test_deposit_emptyVault_oneToOneRatio() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(INITIAL_DEPOSIT, alice);

        // With the virtual +1 offset, first deposit should be approximately 1:1
        assertApproxEqAbs(shares, INITIAL_DEPOSIT, 1, "shares approximately equal assets");
        assertEq(vault.balanceOf(alice), shares, "alice shares");
        assertEq(vault.totalAssets(), INITIAL_DEPOSIT, "total assets");
    }

    // Test 3 - deposit increases totalAssets
    function test_deposit_increments_totalAssets() public {
        vm.prank(alice);
        vault.deposit(INITIAL_DEPOSIT, alice);

        vm.prank(bob);
        vault.deposit(500 ether, bob);

        assertEq(vault.totalAssets(), INITIAL_DEPOSIT + 500 ether);
    }

    // Test 4 - withdraw returns underlying LP tokens
    function test_withdraw_returnsAssets() public {
        vm.prank(alice);
        vault.deposit(INITIAL_DEPOSIT, alice);

        uint256 aliceLPBefore = lpToken.balanceOf(alice);
        uint256 sharesToBurn = vault.previewWithdraw(INITIAL_DEPOSIT / 2);

        vm.prank(alice);
        vault.withdraw(INITIAL_DEPOSIT / 2, alice, alice);

        assertApproxEqAbs(lpToken.balanceOf(alice) - aliceLPBefore, INITIAL_DEPOSIT / 2, 1, "returned LP tokens");
        assertLt(vault.balanceOf(alice), sharesToBurn * 2 + 2, "shares burned");
    }

    // Test 5 - redeem returns proportional assets
    function test_redeem_proportional() public {
        vm.prank(alice);
        vault.deposit(INITIAL_DEPOSIT, alice);

        uint256 shares = vault.balanceOf(alice);
        uint256 half = shares / 2;

        vm.prank(alice);
        uint256 assets = vault.redeem(half, alice, alice);

        assertApproxEqAbs(assets, INITIAL_DEPOSIT / 2, 1, "redeem half returns half assets");
    }

    // Test 6 - mint mints exact shares and pulls correct assets
    function test_mint_exactShares() public {
        // First deposit initializes the vault share price
        vm.prank(alice);
        vault.deposit(INITIAL_DEPOSIT, alice);

        uint256 sharesToMint = 1_000 ether;
        uint256 assetsNeeded = vault.previewMint(sharesToMint);
        uint256 bobLPBefore = lpToken.balanceOf(bob);

        vm.prank(bob);
        uint256 assets = vault.mint(sharesToMint, bob);

        assertEq(assets, assetsNeeded, "assets pulled equals previewMint");
        assertEq(vault.balanceOf(bob), sharesToMint, "bob received exact shares");
        assertApproxEqAbs(lpToken.balanceOf(bob), bobLPBefore - assetsNeeded, 1, "bob LP deducted");
    }

    // Test 7 - harvest increases share price while totalSupply stays unchanged
    function test_harvest_increasesSharePrice() public {
        vm.prank(alice);
        vault.deposit(INITIAL_DEPOSIT, alice);

        uint256 sharesBefore = vault.totalSupply();
        uint256 assetsBefore = vault.totalAssets();
        uint256 priceBefore = vault.convertToAssets(1 ether);

        // Owner harvests additional yield into the vault
        uint256 yieldAmount = 200 ether;
        lpToken.mint(owner, yieldAmount);

        vm.prank(owner);
        vault.harvest(yieldAmount);

        uint256 priceAfter = vault.convertToAssets(1 ether);
        uint256 assetsAfter = vault.totalAssets();

        assertEq(vault.totalSupply(), sharesBefore, "supply unchanged after harvest");
        assertEq(assetsAfter, assetsBefore + yieldAmount, "assets increased by yield");
        assertGt(priceAfter, priceBefore, "share price increased after harvest");
    }

    // Test 8 - harvest reverts for non-owner
    function test_harvest_reverts_nonOwner() public {
        vm.prank(alice);
        vm.expectRevert();

        vault.harvest(100 ether);
    }

    // Test 9 - harvest reverts on zero yield
    function test_harvest_reverts_zeroYield() public {
        vm.prank(owner);
        vm.expectRevert("FeeVault: zero yield");

        vault.harvest(0);
    }

    // Test 10 - deposit reverts on zero assets
    function test_deposit_reverts_zeroAssets() public {
        vm.prank(alice);
        vm.expectRevert("FeeVault: zero assets");

        vault.deposit(0, alice);
    }

    // Test 11 - convertToShares / convertToAssets round-trip follows rounding rules
    function test_convertRoundTrip() public {
        vm.prank(alice);
        vault.deposit(INITIAL_DEPOSIT, alice);

        uint256 shares = vault.convertToShares(500 ether);
        uint256 back = vault.convertToAssets(shares);

        // Due to rounding, converting back should not exceed the original asset amount
        assertLe(back, 500 ether, "convertToAssets rounds down");
        assertApproxEqAbs(back, 500 ether, 2, "within 2 wei");
    }

    // Test 12 - two equal depositors receive proportional yield after harvest
    function test_twoDepositors_proportionalAfterHarvest() public {
        vm.prank(alice);
        vault.deposit(INITIAL_DEPOSIT, alice);

        vm.prank(bob);
        vault.deposit(INITIAL_DEPOSIT, bob);

        // Harvest 200 ether yield
        uint256 yield = 200 ether;
        lpToken.mint(owner, yield);

        vm.prank(owner);
        vault.harvest(yield);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares = vault.balanceOf(bob);

        // Equal deposits should result in approximately equal shares
        assertApproxEqAbs(aliceShares, bobShares, 2, "equal depositors have equal shares");

        uint256 aliceAssets = vault.previewRedeem(aliceShares);
        uint256 bobAssets = vault.previewRedeem(bobShares);

        // Each depositor should receive roughly their deposit plus half the harvested yield
        uint256 expectedEach = INITIAL_DEPOSIT + yield / 2;

        assertApproxEqAbs(aliceAssets, expectedEach, 2, "alice proportional yield");
        assertApproxEqAbs(bobAssets, expectedEach, 2, "bob proportional yield");
    }

    // Test 13 - deposit emits Deposit event
    function test_deposit_emitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, false, address(vault));

        emit Deposit(alice, alice, INITIAL_DEPOSIT, 0);
        vault.deposit(INITIAL_DEPOSIT, alice);
    }

    // Test 14 - withdraw emits Withdraw event
    function test_withdraw_emitsEvent() public {
        vm.prank(alice);
        vault.deposit(INITIAL_DEPOSIT, alice);

        vm.prank(alice);
        vm.expectEmit(true, true, true, false, address(vault));

        emit Withdraw(alice, alice, alice, INITIAL_DEPOSIT / 2, 0);
        vault.withdraw(INITIAL_DEPOSIT / 2, alice, alice);
    }

    // Test 15 - maxWithdraw equals converted share balance
    function test_maxWithdraw_equalsConvertedBalance() public {
        vm.prank(alice);
        vault.deposit(INITIAL_DEPOSIT, alice);

        uint256 maxW = vault.maxWithdraw(alice);
        uint256 converted = vault.convertToAssets(vault.balanceOf(alice));

        assertEq(maxW, converted, "maxWithdraw equals converted balance");
    }
}
