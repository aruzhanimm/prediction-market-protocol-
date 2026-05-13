// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MarketAMM} from "../../src/core/MarketAMM.sol";
import {FeeVault} from "../../src/vault/FeeVault.sol";
import {OutcomeShareToken} from "../../src/tokens/OutcomeShareToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Minimal ERC-20 for vault fuzz tests.
contract MockLP is ERC20 {
    constructor() ERC20("Mock LP", "MLP") {}

    function mint(address to, uint256 a) external {
        _mint(to, a);
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// Fuzz 1 — AMM swap: k never decreases
// ═════════════════════════════════════════════════════════════════════════════

contract FuzzAMMSwap is Test {
    OutcomeShareToken internal outcomeToken;
    MarketAMM internal amm;

    address internal admin = makeAddr("admin");
    address internal minter = makeAddr("minter");
    address internal lp = makeAddr("lp");
    address internal trader = makeAddr("trader");

    uint256 internal constant MARKET_ID = 0;
    uint256 internal constant RESERVE = 100_000 ether;

    function setUp() public {
        outcomeToken = new OutcomeShareToken("https://api.example.com/", admin);

        bytes32 minterRole = outcomeToken.MINTER_ROLE();

        vm.prank(admin);
        outcomeToken.grantRole(minterRole, minter);

        amm = new MarketAMM(address(outcomeToken), MARKET_ID);

        // Seed pool with 100k YES/NO liquidity from a normal LP address.
        vm.prank(minter);
        outcomeToken.mintOutcomes(MARKET_ID, lp, RESERVE);

        vm.prank(lp);
        outcomeToken.setApprovalForAll(address(amm), true);

        vm.prank(lp);
        amm.addLiquidity(RESERVE, RESERVE, 0);

        // Approve AMM to transfer trader outcome tokens during swaps.
        vm.prank(trader);
        outcomeToken.setApprovalForAll(address(amm), true);
    }

    /// @notice Fuzz test: k must never decrease after any valid swap.
    /// @param amountIn Bounded to [1 wei, 10% of pool] to avoid total-drain reverts.
    /// @param buyYes Direction of swap.
    function testFuzz_swap_kNeverDecreases(uint256 amountIn, bool buyYes) public {
        amountIn = bound(amountIn, 1, RESERVE / 10);

        vm.prank(minter);
        outcomeToken.mintOutcomes(MARKET_ID, trader, amountIn * 2);

        (,, uint256 kBefore) = amm.getReserves();

        vm.prank(trader);
        try amm.swap(buyYes, amountIn, 0) {
            (,, uint256 kAfter) = amm.getReserves();
            assertGe(kAfter, kBefore, "k must not decrease after swap");
        } catch {
            (,, uint256 kAfterRevert) = amm.getReserves();
            assertEq(kAfterRevert, kBefore, "k unchanged on revert");
        }
    }

    /// @notice Fuzz: getAmountOut always returns less than reserveOut.
    function testFuzz_getAmountOut_belowReserve(uint256 amountIn, bool buyYes) public view {
        amountIn = bound(amountIn, 1, RESERVE / 2);

        uint256 reserveOut = buyYes ? amm.reserveYes() : amm.reserveNo();

        try amm.getAmountOut(buyYes, amountIn) returns (uint256 amountOut) {
            assertLt(amountOut, reserveOut, "output must be < reserveOut");
        } catch {
            // Revert is acceptable for edge inputs.
        }
    }

    /// @notice Fuzz: fee must always be paid (output < input for balanced pool).
    function testFuzz_swap_outputLessThanInput_balancedPool(uint256 amountIn) public view {
        amountIn = bound(amountIn, 1 ether, RESERVE / 10);

        uint256 amountOut = amm.getAmountOut(true, amountIn);

        assertLt(amountOut, amountIn, "output must be less than input in balanced pool");
    }
}
// ═════════════════════════════════════════════════════════════════════════════
// Fuzz 2 — FeeVault deposit / withdraw round-trip
// ═════════════════════════════════════════════════════════════════════════════

contract FuzzFeeVaultDepositWithdraw is Test {
    MockLP internal lpToken;
    FeeVault internal vault;

    address internal owner = makeAddr("owner");
    address internal user = makeAddr("user");

    function setUp() public {
        lpToken = new MockLP();
        vault = new FeeVault(address(lpToken), "Vault", "vLP", owner);

        lpToken.mint(user, type(uint128).max);
        vm.prank(user);
        lpToken.approve(address(vault), type(uint256).max);
    }

    /// @notice Fuzz: depositing then redeeming all shares should return ≤ deposited amount.
    ///         (ERC-4626 rounding is always in favour of the vault.)
    function testFuzz_depositWithdraw_roundTripAtMostDeposited(uint256 assets) public {
        assets = bound(assets, 2, type(uint96).max);

        uint256 balanceBefore = lpToken.balanceOf(user);

        vm.startPrank(user);
        uint256 shares = vault.deposit(assets, user);
        uint256 returned = vault.redeem(shares, user, user);
        vm.stopPrank();

        // Must not get MORE back than deposited (rounding down)
        assertLe(returned, assets, "cannot withdraw more than deposited");
        assertLe(returned, balanceBefore, "cannot exceed original balance");
        // Must not lose more than 1 wei per operation
        assertGe(returned + 2, assets, "loss must be within 2 wei");
    }

    /// @notice Fuzz: share price only increases or stays the same after harvest.
    function testFuzz_harvest_sharePriceMonotone(uint256 depositAmt, uint256 yieldAmt) public {
        depositAmt = bound(depositAmt, 1_000, type(uint64).max);
        yieldAmt = bound(yieldAmt, 1, type(uint64).max);

        lpToken.mint(user, depositAmt);
        vm.prank(user);
        vault.deposit(depositAmt, user);

        uint256 priceBefore = vault.convertToAssets(1 ether);

        lpToken.mint(owner, yieldAmt);
        vm.prank(owner);
        lpToken.approve(address(vault), yieldAmt);
        vm.prank(owner);
        vault.harvest(yieldAmt);

        uint256 priceAfter = vault.convertToAssets(1 ether);

        assertGe(priceAfter, priceBefore, "share price must not decrease after harvest");
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// Fuzz 3 — AMM LP mint/burn: total supply and reserves consistent
// ═════════════════════════════════════════════════════════════════════════════

contract FuzzAMMLPMintBurn is Test {
    OutcomeShareToken internal outcomeToken;
    MarketAMM internal amm;

    address internal admin = makeAddr("admin");
    address internal minter = makeAddr("minter");
    address internal lp = makeAddr("lp");

    uint256 internal constant MARKET_ID = 0;
    uint256 internal constant MIN_FUZZ_AMOUNT = 2_000 ether;
    uint256 internal constant MAX_FUZZ_AMOUNT = 1_000_000 ether;

    function setUp() public {
        outcomeToken = new OutcomeShareToken("https://api.example.com/", admin);

        bytes32 minterRole = outcomeToken.MINTER_ROLE();

        vm.prank(admin);
        outcomeToken.grantRole(minterRole, minter);

        amm = new MarketAMM(address(outcomeToken), MARKET_ID);

        vm.prank(lp);
        outcomeToken.setApprovalForAll(address(amm), true);
    }

    /// @notice Fuzz: after addLiquidity + removeLiquidity(full), reserves remain only as minimum-liquidity dust.
    function testFuzz_lpMintBurn_reservesConsistent(uint256 amount) public {
        amount = bound(amount, MIN_FUZZ_AMOUNT, MAX_FUZZ_AMOUNT);

        vm.prank(minter);
        outcomeToken.mintOutcomes(MARKET_ID, lp, amount);

        vm.startPrank(lp);

        uint256 lpMinted = amm.addLiquidity(amount, amount, 0);
        amm.removeLiquidity(lpMinted, 0, 0);

        vm.stopPrank();

        (uint256 rYes, uint256 rNo,) = amm.getReserves();

        // The first liquidity provider cannot remove the permanently locked minimum liquidity.
        // Therefore a tiny reserve residue is expected and acceptable.
        assertLe(rYes, 1001, "residual YES reserve should only be minimum-liquidity dust");
        assertLe(rNo, 1001, "residual NO reserve should only be minimum-liquidity dust");
        assertEq(amm.balanceOf(lp), 0, "LP provider should have no removable LP left");
    }
}
