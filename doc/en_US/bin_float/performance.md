# `bin_float` Performance

## Contract

Performance thresholds, limb layout, NTT primes, scratch storage, and fallback selection are implementation details. Public results, flags, and interchange bits must be identical across algorithms and targets.

## Representation

Non-JS targets use inline 64/128-bit coefficients and little-endian 32-bit limbs; JavaScript uses a hidden host `bigint` adapter. The public `BinCoeff` type keeps that backend choice unobservable.

## Multiplication

Balanced multiplication uses schoolbook below 96 limbs, then Karatsuba, Toom-3, and a two-prime Montgomery NTT with CRT when transform bounds fit. Unbalanced inputs use block multiplication or overlap-add. Native/LLVM currently select Toom-3 and NTT multiplication at 2,048 limbs and NTT square at 768; Wasm/Wasm-GC use 4,096 and 3,072.

## Division, Square Root, And GCD

Division uses a one-limb path, Knuth below 48 divisor limbs, Burnikel–Ziegler from 48, and Newton reciprocal division from 1,024. Square root uses fixed-width kernels through 512 bits and divide-and-conquer above that. Large GCD uses Lehmer batching.

## Measurement

Skipped white-box benches force each algorithm around crossover points and compare dense, sparse, square, and unbalanced shapes. A threshold change requires correctness differential tests on every target and reproducible release-mode measurements; a single machine result is not a portable constant.

## Trade-offs

Schoolbook minimizes setup and allocation, recursive algorithms reduce asymptotic work, and NTT improves very large balanced inputs at the cost of transforms and temporary storage. Every fast path retains an exact fallback, so performance dispatch cannot alter semantics.
