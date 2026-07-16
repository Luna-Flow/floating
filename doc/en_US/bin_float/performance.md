# `bin_float` Performance

<!-- historical-performance-baseline: 0.6.1 -->

## Contract

Performance thresholds, limb layout, NTT primes, scratch storage, and fallback selection are implementation details. Public results, flags, and interchange bits must be identical across algorithms and targets.

## Representation

Non-JS targets use inline 64/128-bit coefficients and little-endian 32-bit limbs; JavaScript uses a hidden host `bigint` adapter. The public `BinCoeff` type keeps that backend choice unobservable.

## Multiplication

Balanced multiplication uses schoolbook below 96 limbs, then Karatsuba, Toom-3, and a two-prime Montgomery NTT with CRT when transform bounds fit. Unbalanced inputs use block multiplication or overlap-add. Native/LLVM currently select Toom-3 and NTT multiplication at 2,048 limbs and NTT square at 768; Wasm/Wasm-GC use 4,096 and 3,072. Native square dispatch switches from specialized schoolbook to recursive multiplication at 512 limbs; other targets retain the previous 768-limb boundary.

## Division, Square Root, And GCD

Division uses a one-limb path, Knuth below 48 divisor limbs, Burnikel–Ziegler from 48, and Newton reciprocal division from 1,024. Square root uses fixed-width kernels through 512 bits and divide-and-conquer above that. Large GCD uses Lehmer batching.

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

## Trade-offs

Schoolbook minimizes setup and allocation, recursive algorithms reduce asymptotic work, and NTT improves very large balanced inputs at the cost of transforms and temporary storage. Every fast path retains an exact fallback, so performance dispatch cannot alter semantics.
