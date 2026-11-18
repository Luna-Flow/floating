# bin_float performance

<!-- historical-performance-baseline: 0.6.1 -->
<!-- historical-performance-baseline: 0.7.1 -->

## Contract

Performance thresholds, limb layout, NTT primes, scratch storage, and fallback selection are implementation details. Public results, flags, and interchange bits must be identical across algorithms and targets.

## Representation

Non-JS targets use inline 64/128-bit coefficients and little-endian 32-bit limbs; JavaScript uses a hidden host `bigint` adapter. The public `BinCoeff` type keeps that backend choice unobservable.

## Fixed-point exponential

The certified `exp` enclosure bounds the Taylor series of the reduced argument (at most 1/8) in fixed point with 16 fractional bits beyond the working precision when the argument is exact at the working precision, instead of with one rounded floating-point operation per term. Each computed term rounds down, so their sum is a lower bound; each carries an error below 3 units of the last place, which gives an upper bound with a rigorous tail. The enclosure is about as wide as the floating-point one, the 12-attempt refinement loop and its working precisions are unchanged, and arguments that are not exact at the working precision still use the previous series. White-box tests check that the enclosure contains a much tighter one and that the final correctly rounded results and flags equal those of the previous series. Paired runs: `exp` is 9 to 10 times faster on Native at 53 to 2,048 bits, 7 to 11 times on Wasm and Wasm-GC, and decimal `exp` 1.7 to 2.2 times.

## Multiplication

Balanced multiplication uses schoolbook below 96 limbs, then Karatsuba, Toom-3, and a two-prime Montgomery NTT with CRT when transform bounds fit. Unbalanced inputs use block multiplication or overlap-add. Native/LLVM currently select Toom-3 and NTT multiplication at 2,048 limbs and NTT square at 768; Wasm/Wasm-GC use 4,096 and 3,072. Native square dispatch switches from specialized schoolbook to recursive multiplication at 512 limbs; other targets retain the previous 768-limb boundary.

## Division, square root and GCD

Division uses a one-limb path, Knuth below 48 divisor limbs, Burnikel–Ziegler from 48, and Newton reciprocal division from 1,024. Square root uses fixed-width kernels through 512 bits and divide-and-conquer above that; the recursion stops at the same fixed-width kernels once a block is at most 256 bits on Native/LLVM and 512 bits on Wasm/Wasm-GC (a restoring loop on heap integers at 128 bits before), which makes a 1,024-bit radicand (a 512-bit `sqrt`) about 3.4 times faster on Native and 3.1 to 3.3 times on Wasm in paired runs. The cutoff is per-target policy measured with paired runs; the LLVM value is not measured because that backend is not available in the toolchain used. Large GCD uses Lehmer batching on a common 63-bit window of both operands and takes a single division step when the shorter operand has no bits in that window, so operands of very different lengths are reduced at once.

## Certified constants

The certified elementary functions memoize the constant enclosures they need (`ln 2`, `ln 10` and `pi`) per working precision, in small per-constant caches of six precisions up to 65,536 bits. A cached enclosure is the value a recomputation returns, so results never depend on cache state or call order. Before this, every `ln`, `log2`, `log10`, `sin`, `cos`, `tan` and `atan2` call re-ran an `ln 2` series or an `atan(1)` evaluation that cost as much as the function itself. Paired native runs: `ln` 2.4 to 2.6 times faster at 53 to 512 bits, `sin` 2.4 to 3.7 times, decimal `ln` 2.5 times; on Wasm and Wasm-GC `ln` and `sin` are 1.7 to 2.2 times faster. `exp` has no such constant and is unchanged.

## Measurement

The unified Maremark harness under `bench/bin_float` compares coefficient kernels, numeric cores, checked full paths, and semantically equivalent square candidates with balanced blocks. Auto-tune emits a versioned per-scale policy and applies a threshold only to the measured target; every threshold change still requires correctness tests on all targets.

The elementary release gate separately archives the immutable `0.6.1` commit
and the dirty candidate tree, injects one identical add/mul/div/sqrt workload,
and collects ten alternating AB/BA native pairs at 53, 128, and 512 bits.
Maremark blocks release only when the candidate is at least 3% slower and the
95% bootstrap interval has a positive lower bound. Functions first introduced
in `0.7.1` run as a candidate workload; this release becomes their first valid
baseline, because inventing `0.6.1` timings for APIs that did not exist would
be meaningless.

## Certified series

The enclosure of `exp` evaluates its Taylor series once, not twice, when the argument is exact at the working precision (the usual case), because the lower and upper endpoints are then the same value and only one bound of each series is read. The trigonometric enclosure evaluates only the sine or cosine series that the requested function and quadrant read, two series instead of four for `sin` and `cos`. Both skips return the exact enclosures of before, which white-box tests check against copies of the previous code. Paired native runs: `exp` 1.8 to 2.0 times faster at 53 to 512 bits, decimal `exp` 1.3 to 1.4 times, `sin` 1.15 to 1.2 times on its own; on Wasm and Wasm-GC `exp` is 1.7 to 1.9 times faster.

## Trade-offs

Schoolbook minimizes setup and allocation, recursive algorithms reduce asymptotic work, and NTT improves very large balanced inputs at the cost of transforms and temporary storage. Every fast path retains an exact fallback, so performance dispatch cannot alter semantics.
