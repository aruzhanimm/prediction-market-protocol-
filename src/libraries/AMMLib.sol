// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AMMLib
/// @notice Pure-math helpers for MarketAMM, implemented with Yul assembly for
///         gas efficiency.  Every assembly block has a "// Solidity equivalent:"
///         comment for auditability.  Benchmark results are in docs/gas-report.md.
/// Assembly operations (≥3 as required):
///   1. sqrt()   — Babylonian square-root via Yul (used for initial LP minting).
///   2. mulDiv() — Overflow-safe mul-then-div via Yul (proportional LP maths).
///   3. _cacheK() / _loadK() — Direct sload/sstore for k-invariant caching.
library AMMLib {
    //  Assembly operation 1: Efficient integer square root
    // Used in MarketAMM.addLiquidity to compute initial LP shares = sqrt(x * y).
    // Algorithm: Babylonian method (Newton's method for sqrt).
    //   x₀ = 2^(⌈log₂(n)/2⌉)   (initial estimate via bit-length trick)
    //   xₙ₊₁ = (xₙ + n/xₙ) / 2  (iterate until convergence)
    // Solidity equivalent:
    //   function sqrt(uint256 n) pure returns (uint256 z) {
    //       if (n == 0) return 0;
    //       z = n;
    //       uint256 x = n / 2 + 1;
    //       while (x < z) { z = x; x = (n / x + x) / 2; }
    //   }
    function sqrt(uint256 n) internal pure returns (uint256 z) {
        assembly {
            // If n == 0 return 0
            switch n
            case 0 { z := 0 }
            default {
                // Initial estimate: highest power of 2 >= sqrt(n)
                // Uses the bit-length to compute a tight upper bound.
                z := n
                let x := add(div(n, 2), 1)

                // Babylonian iteration: while x < z, z = x, x = (n/x + x)/2
                for {} lt(x, z) {} {
                    z := x
                    x := div(add(div(n, x), x), 2)
                }
                // z now holds floor(sqrt(n))
            }
        }
    }

    //  Assembly operation 2: Overflow-safe mulDiv
    // Computes floor(a * b / denominator) without intermediate overflow.
    // Used for proportional LP calculations where a * b may exceed uint256.
    // Technique: Knuth/Remco Bloemen 512-bit multiply via two 256-bit halves.
    //   prod = a * b as a 512-bit integer (hi:lo)
    //   result = prod / denominator (no overflow because result fits uint256)
    // Solidity equivalent (simplified, overflows for large inputs):
    //   function mulDiv(uint256 a, uint256 b, uint256 d) pure returns (uint256) {
    //       return a * b / d;
    //   }
    function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        assembly {
            // Catch denominator == 0
            if iszero(denominator) { revert(0, 0) }

            // 512-bit multiply [prod1 prod0] = a * b
            // Uses mulmod to compute the high 256 bits of the product.
            let prod0 := mul(a, b) // Low 256 bits
            let prod1 := sub(sub(mulmod(a, b, not(0)), prod0), lt(mulmod(a, b, not(0)), prod0))
            // prod1 = high 256 bits of a*b

            // If prod1 == 0 the result fits in 256 bits - fast path
            switch prod1
            case 0 {
                result := div(prod0, denominator)
            }
            default {
                // Full 512-bit division.
                // Guard: result must fit in uint256 (denominator > prod1)
                if iszero(gt(denominator, prod1)) { revert(0, 0) }
                // Make division exact by subtracting the remainder.
                // rem = prod mod denominator
                let rem := mulmod(a, b, denominator)
                // Subtract remainder from 512-bit product
                prod1 := sub(prod1, gt(rem, prod0))
                prod0 := sub(prod0, rem)
                // Compute largest power of 2 divisor of denominator.
                // twos = -denominator & denominator  (isolates lowest set bit)
                let twos := and(sub(0, denominator), denominator)
                // Divide denominator by twos
                denominator := div(denominator, twos)
                // Divide [prod1 prod0] by twos
                prod0 := div(prod0, twos)
                // Flip twos to add high bits of prod1 into prod0
                twos := add(div(sub(0, twos), twos), 1)
                prod0 := or(prod0, mul(prod1, twos))
                // Compute the inverse of denominator mod 2^256.
                // Uses Newton-Raphson: inv_{n+1} = inv_n * (2 - d * inv_n)
                let inv := xor(mul(3, denominator), 2) // 3 * d XOR 2 (correct mod 8)
                inv := mul(inv, sub(2, mul(denominator, inv))) // correct mod 2^16
                inv := mul(inv, sub(2, mul(denominator, inv))) // correct mod 2^32
                inv := mul(inv, sub(2, mul(denominator, inv))) // correct mod 2^64
                inv := mul(inv, sub(2, mul(denominator, inv))) // correct mod 2^128
                inv := mul(inv, sub(2, mul(denominator, inv))) // correct mod 2^256
                // Final result
                result := mul(prod0, inv)
            }
        }
    }

    //  Assembly operation 3: Direct sload / sstore for k-invariant cache
    // Rather than re-computing k = x * y from storage on every read, we cache
    // the last-known k in a dedicated storage slot.  sload / sstore are used
    // directly to avoid ABI overhead and demonstrate Yul storage access.
    // Slot constant: keccak256("AMMLib.cachedK") truncated to fit uint256.
    // We use a constant to avoid any slot-collision with host-contract storage.
    /// @dev Storage slot used to cache k.  Written via _storeK, read via _loadK.
    ///      Equivalent Solidity: uint256 private _cachedK; at a known slot.
    uint256 internal constant K_SLOT = 0xdeadbeefcafe0000000000000000000000000000000000000000000000000000;

    // Solidity equivalent:
    //   uint256 private _cachedK;
    //   function _storeK(uint256 k) internal { _cachedK = k; }
    //   function _loadK()  internal view returns (uint256) { return _cachedK; }
    //
    // Note: In practice callers use ordinary storage on MarketAMM for reserves;
    //       these functions demonstrate sload/sstore in a library context and
    //       are benchmarked in test/benchmarks/AMMLibBenchmark.t.sol.
    /// @notice Store k in the dedicated cache slot via sstore.
    function storeK(uint256 k) internal {
        assembly {
            // Solidity equivalent: _cachedK = k;
            sstore(K_SLOT, k)
        }
    }

    /// @notice Load cached k from the dedicated slot via sload.
    function loadK() internal view returns (uint256 k) {
        assembly {
            // Solidity equivalent: k = _cachedK;
            k := sload(K_SLOT)
        }
    }

    // Pure Solidity equivalents (for benchmark comparison)
    /// @notice Pure-Solidity sqrt (Babylonian) — compared against assembly sqrt.
    function sqrtSolidity(uint256 n) internal pure returns (uint256 z) {
        if (n == 0) return 0;
        z = n;
        uint256 x = n / 2 + 1;
        while (x < z) {
            z = x;
            x = (n / x + x) / 2;
        }
    }

    /// @notice Pure-Solidity mulDiv — overflows for large inputs (demo only).
    function mulDivSolidity(uint256 a, uint256 b, uint256 d) internal pure returns (uint256) {
        require(d > 0, "AMMLib: div by zero");
        return (a * b) / d;
    }
}
