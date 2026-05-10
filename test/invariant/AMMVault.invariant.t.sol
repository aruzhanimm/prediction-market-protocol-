// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, StdInvariant} from "forge-std/Test.sol";
import {MarketAMM} from "../../src/core/MarketAMM.sol";
import {FeeVault} from "../../src/vault/FeeVault.sol";
import {OutcomeShareToken} from "../../src/tokens/OutcomeShareToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// ─────────────────────────────────────────────────────────────────────────
/// Handler: drives MarketAMM state via random calls (used by Foundry's
/// invariant engine).  All invariants are verified in the invariant_* functions
/// defined in the test contracts below.
/// ─────────────────────────────────────────────────────────────────────────
contract AMMHandler is Test {
    MarketAMM internal amm;
    OutcomeShareToken internal outcomeToken;

    address internal minter;
    address internal lp;
    address internal trader;

    uint256 internal constant MARKET_ID = 0;
    uint256 internal constant MAX_AMOUNT = 50_000 ether;

    constructor(MarketAMM _amm, OutcomeShareToken _outcomeToken, address _minter, address _lp, address _trader) {
        amm = _amm;
        outcomeToken = _outcomeToken;
        minter = _minter;
        lp = _lp;
        trader = _trader;
    }

    function addLiquidity(uint256 amount) external {
        amount = bound(amount, 2_000, MAX_AMOUNT);
        vm.prank(minter);
        outcomeToken.mintOutcomes(MARKET_ID, lp, amount);

        vm.prank(lp);
        try amm.addLiquidity(amount, amount, 0) {} catch {}
    }

    function removeLiquidity(uint256 lpAmount) external {
        uint256 bal = amm.balanceOf(lp);
        if (bal == 0) return;
        lpAmount = bound(lpAmount, 1, bal);

        vm.prank(lp);
        try amm.removeLiquidity(lpAmount, 0, 0) {} catch {}
    }

    function swap(bool buyYes, uint256 amountIn) external {
        amountIn = bound(amountIn, 1, MAX_AMOUNT / 20);
        vm.prank(minter);
        outcomeToken.mintOutcomes(MARKET_ID, trader, amountIn * 2);

        vm.prank(trader);
        try amm.swap(buyYes, amountIn, 0) {} catch {}
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// Invariant 1 — k (reserveYes * reserveNo) never decreases
// ═════════════════════════════════════════════════════════════════════════════

contract Invariant_KNeverDecreases is StdInvariant, Test {
    MarketAMM internal amm;
    OutcomeShareToken internal outcomeToken;
    AMMHandler internal handler;

    address internal admin = makeAddr("admin");
    address internal minter = makeAddr("minter");
    address internal lp = makeAddr("lp");
    address internal trader = makeAddr("trader");

    uint256 internal lastK;

    function setUp() public {
        outcomeToken = new OutcomeShareToken("https://api.example.com/", admin);

        bytes32 minterRole = outcomeToken.MINTER_ROLE();

        vm.prank(admin);
        outcomeToken.grantRole(minterRole, minter);

        amm = new MarketAMM(address(outcomeToken), 0);

        vm.prank(lp);
        outcomeToken.setApprovalForAll(address(amm), true);

        vm.prank(trader);
        outcomeToken.setApprovalForAll(address(amm), true);

        // Seed initial liquidity so k > 0.
        vm.prank(minter);
        outcomeToken.mintOutcomes(0, lp, 10_000 ether);

        vm.prank(lp);
        amm.addLiquidity(10_000 ether, 10_000 ether, 0);

        (,, lastK) = amm.getReserves();

        handler = new AMMHandler(amm, outcomeToken, minter, lp, trader);

        // For this invariant, removeLiquidity must be excluded because it
        // intentionally decreases reserves and therefore can decrease k.
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = AMMHandler.addLiquidity.selector;
        selectors[1] = AMMHandler.swap.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @notice The CPMM invariant: k = reserveYes * reserveNo must never decrease.
    function invariant_kNeverDecreases() public view {
        (,, uint256 k) = amm.getReserves();
        assertGe(k, lastK, "INVARIANT: k decreased");
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// Invariant 2 — LP total supply is consistent with reserves being non-zero
// ═════════════════════════════════════════════════════════════════════════════

contract Invariant_LPSupplyConsistency is StdInvariant, Test {
    MarketAMM internal amm;
    OutcomeShareToken internal outcomeToken;
    AMMHandler internal handler;

    address internal admin = makeAddr("admin");
    address internal minter = makeAddr("minter");
    address internal lp = makeAddr("lp");
    address internal trader = makeAddr("trader");

    function setUp() public {
        outcomeToken = new OutcomeShareToken("https://api.example.com/", admin);
        bytes32 minterRole = outcomeToken.MINTER_ROLE();
        vm.prank(admin);
        outcomeToken.grantRole(minterRole, minter);

        amm = new MarketAMM(address(outcomeToken), 0);

        vm.prank(lp);
        outcomeToken.setApprovalForAll(address(amm), true);
        vm.prank(trader);
        outcomeToken.setApprovalForAll(address(amm), true);

        vm.prank(minter);
        outcomeToken.mintOutcomes(0, lp, 10_000 ether);
        vm.prank(lp);
        amm.addLiquidity(10_000 ether, 10_000 ether, 0);

        handler = new AMMHandler(amm, outcomeToken, minter, lp, trader);
        targetContract(address(handler));
    }

    /// @notice If LP totalSupply > 0, both reserves must be > 0 and vice versa.
    function invariant_lpSupplyAndReservesConsistent() public view {
        uint256 supply = amm.totalSupply();
        (uint256 rYes, uint256 rNo,) = amm.getReserves();

        if (supply > 0) {
            assertGt(rYes, 0, "INVARIANT: supply>0 but reserveYes==0");
            assertGt(rNo, 0, "INVARIANT: supply>0 but reserveNo==0");
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// Invariant 3 — FeeVault: totalAssets >= totalSupply converted to assets
// ═════════════════════════════════════════════════════════════════════════════

contract MockLPForInvariant is ERC20 {
    constructor() ERC20("Mock LP", "MLP") {}

    function mint(address to, uint256 a) external {
        _mint(to, a);
    }
}

contract VaultHandler is Test {
    FeeVault internal vault;
    MockLPForInvariant internal lpToken;
    address internal user;
    address internal owner;

    constructor(FeeVault _vault, MockLPForInvariant _lp, address _user, address _owner) {
        vault = _vault;
        lpToken = _lp;
        user = _user;
        owner = _owner;
    }

    function deposit(uint256 amount) external {
        amount = bound(amount, 1, 10_000 ether);
        lpToken.mint(user, amount);
        vm.prank(user);
        vault.deposit(amount, user);
    }

    function redeem(uint256 shares) external {
        uint256 bal = vault.balanceOf(user);
        if (bal == 0) return;
        shares = bound(shares, 1, bal);
        vm.prank(user);
        try vault.redeem(shares, user, user) {} catch {}
    }

    function harvest(uint256 amount) external {
        amount = bound(amount, 1, 1_000 ether);
        lpToken.mint(owner, amount);
        vm.startPrank(owner);
        lpToken.approve(address(vault), amount);
        vault.harvest(amount);
        vm.stopPrank();
    }
}

contract Invariant_VaultAccounting is StdInvariant, Test {
    MockLPForInvariant internal lpToken;
    FeeVault internal vault;
    VaultHandler internal handler;

    address internal owner = makeAddr("owner");
    address internal user = makeAddr("user");

    function setUp() public {
        lpToken = new MockLPForInvariant();
        vault = new FeeVault(address(lpToken), "V", "vV", owner);

        lpToken.mint(user, 1_000_000 ether);
        vm.prank(user);
        lpToken.approve(address(vault), type(uint256).max);

        handler = new VaultHandler(vault, lpToken, user, owner);
        targetContract(address(handler));
    }

    /// @notice totalAssets must always equal the vault's actual LP token balance.
    function invariant_totalAssetsMatchBalance() public view {
        assertEq(vault.totalAssets(), lpToken.balanceOf(address(vault)), "INVARIANT: totalAssets != actual balance");
    }

    /// @notice previewRedeem(totalSupply) must be <= totalAssets (no bank run possible in accounting).
    function invariant_noAccountingOverflow() public view {
        uint256 supply = vault.totalSupply();
        if (supply == 0) return;

        uint256 maxRedeemable = vault.previewRedeem(supply);
        assertLe(
            maxRedeemable,
            vault.totalAssets() + 1, // +1 for rounding
            "INVARIANT: maxRedeemable > totalAssets"
        );
    }
}
