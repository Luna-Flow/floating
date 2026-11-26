# binary performance

<!-- historical-performance-baseline: 0.6.1 -->
<!-- historical-performance-baseline: 0.7.1 -->

## Contract

Performance thresholds, limb layout, NTT primes, scratch storage, and fallback selection are implementation details. Public results, flags, and interchange bits must be identical across algorithms and targets.

## Measurement

The unified Maremark harness under `tooling/src/bench/binary` compares coefficient kernels, numeric cores, and checked full paths with balanced blocks. Auto-tune emits a versioned per-scale policy and applies a threshold only to the measured target; every threshold change still requires correctness tests on all targets.

The elementary release gate separately archives the immutable `0.6.1` commit
and the dirty candidate tree, injects one identical add/mul/div/sqrt workload,
and collects ten alternating AB/BA native pairs at 53, 128, and 512 bits.
Maremark blocks release only when the candidate is at least 3% slower and the
95% bootstrap interval has a positive lower bound. Functions that `0.6.1`
does not have run as a candidate workload; this release becomes their first valid
baseline, because inventing `0.6.1` timings for APIs that did not exist would
be meaningless.

In the tables below, "times faster" is the time of the baseline divided by the time of the current implementation, and "times fewer" is the retired instructions of the baseline divided by those of the current implementation. The sentence before a table names its baseline or says that it is not recorded. Unless a table shows them, absolute times or counts, machine, operating system, toolchain, commit and command are not recorded. A cell that reads "not stated" marks a target, precision or condition that was not recorded with the number.

## Representation

Non-JS targets use inline 64/128-bit coefficients and little-endian 64-bit limbs above 128 bits; JavaScript uses a hidden host `bigint` adapter. The public `BinCoeff` type keeps that backend choice unobservable. The move from 32-bit to 64-bit limbs (issue #19) is staged: addition, subtraction, comparison, shifts, the schoolbook multiplication and squaring, and the Karatsuba and Toom-3 steps work on 64-bit limbs; division, the square-root kernels and the NTT digit conversion work on 64-bit limbs as well (the Wasm routes on 32-bit limbs and the Wasm NTT conversion excepted, see below). A 64-bit limb product needs the high half of a 64 by 64 bit multiplication, which MoonBit has no instruction for, so it is computed from four 32 by 32 bit products in the portable loops (Native uses a 128-bit product in its C and assembly rows); the schoolbook kernel is faster than on 32-bit limbs (first table below) because it runs a quarter of the limb steps.

Paired runs against the 32-bit implementation; the rows of the whole stage are paired Native runs.

| Workload | Target | Precision | Reported speedup |
| --- | --- | --- | --- |
| 64-bit limb schoolbook product | Native | not stated | 2.7 to 3.7 times faster |
| 64-bit limb schoolbook product | Wasm-GC | not stated | 1.7 to 1.9 times faster |
| Whole-stage multiplication | Native | 2,048 to 8,192 bits | 2.2 times faster |
| Whole-stage addition | Native | 8,192 bits | 2.3 times faster |
| `exp` and `ln` | Native | 2,048 bits | 2.0 times faster |
| Multiplication | Wasm and Wasm-GC | below about 6,000 bits | 1.3 to 1.7 times faster |

## Multiplication

Balanced multiplication uses schoolbook below 32 64-bit limbs (2,048 bits on LLVM, Wasm and Wasm-GC and on Native with the portable and C rows; 48 limbs on Native with the assembly rows), then Karatsuba on limb arrays (a few small temporaries per step, no intermediate `BinCoeff`), Toom-3, and a two-prime Montgomery NTT with CRT when transform bounds fit. Unbalanced inputs use block multiplication or overlap-add. Native and LLVM select Toom-3 and NTT multiplication at 4,096 64-bit limbs and NTT square at 3,584; Wasm and Wasm-GC at 2,048 and 1,536 (the values of the version before the 64-bit limbs, 4,096 and 3,072 in 32-bit limbs, halved; not measured again on those targets). A 64-bit limb product costs four `i64.mul` on Wasm, so from 160 limbs (10,240 bits) Wasm and Wasm-GC split the operands into 32-bit limbs, multiply there with the same Karatsuba and pack the result back (the conversions are linear); squaring uses the 32-bit half-product schoolbook from 80 limbs. On Native and LLVM the square dispatch runs the word Karatsuba square from its cutoff (see Squaring below), never the recursive multiplication; on Wasm and Wasm-GC the schoolbook square runs below 384 64-bit limbs (768 of 32 bits) and Toom-3 from there. Cutoffs measured per target with paired runs of coefficient multiplication at 1,024 to 65,536 bits.

Paired runs against the 32-bit implementation.

| Target | Workload | Reported speedup |
| --- | --- | --- |
| Native | Coefficient multiplication, 1,024 to 32,768 bits | 2 to 3 times faster |
| Wasm-GC | Coefficient multiplication | 1.1 to 2.2 times faster |
| Wasm | Coefficient multiplication | 1.1 to 2.1 times faster |
| Native | `Binary` `mul`, 512 bits | 1.6 times faster |
| Native | `Binary` `mul`, 2,048 bits | 2.5 times faster |
| Native | `Binary` `mul`, 8,192 bits | 2.9 times faster |
| not stated | `Binary` `add`, 2,048 bits | 1.9 times faster |
| not stated | `Binary` `add`, 8,192 bits | 2.4 times faster |
| not stated | `Binary` `sqrt`, 2,048 bits | 1.5 times faster |
| not stated | `Binary` `sqrt`, 8,192 bits | 2.0 times faster |

## Squaring

Squaring on Native and LLVM no longer runs the half-product schoolbook (and, from 16,384 bits, the general product) up to the NTT: from 36 64-bit limbs (2,304 bits; 36 with the portable loops and on LLVM, 64 with the C rows and 96 with the assembly rows of Native) a word-range Karatsuba square computes $a_0^2$, $a_1^2$ and $(a_0 - a_1)^2$ on array ranges, with the middle term $a_0^2 + a_1^2 - (a_0 - a_1)^2$ added in place, and the NTT square starts at 7,168 32-bit limbs (229,376 bits) instead of 768, because the Karatsuba square is cheaper up to there. The Karatsuba multiplication of the word ranges now takes one scratch array per product, carved into the temporaries of each node, instead of five arrays and two copies per node, with the same results. The schoolbook square stays below 36 limbs (the paired runs put the crossover between 32 and 40 limbs). Wasm and Wasm-GC keep their squaring (`bin_coeff_square_words_enabled` is false there until paired wall-clock runs decide), and LLVM takes the Native values, unmeasured. White-box tests compare the scratch-buffer product with the allocating Karatsuba of the previous build and the schoolbook product at and around the cutoff with unbalanced shapes, the Karatsuba square with the schoolbook square and the product, and the dispatch against the schoolbook around 36, 64, 128, 256, 384 and 512 limbs and against the NTT and Karatsuba squares at the NTT cutoff.

Retired instructions, against the previous build. The target is not stated (the paragraph concerns Native and LLVM, and LLVM is unmeasured).

| Workload | Precision | Reported result |
| --- | --- | --- |
| One square | 12,288 bits | 1.64 times fewer |
| One square | 32,768 bits | 2.2 times fewer |
| One square | 98,304 bits | 1.7 times fewer |
| One square | 131,072 bits | 1.09 times fewer |
| One square | 196,608 bits | 1.18 times fewer |
| One square | from 262,144 bits | equal |
| Word-range Karatsuba product | 2,048 to 65,536 bits | 1.02 to 1.04 times fewer |

The word-range Karatsuba multiplication uses one scratch array per product in place of five arrays and two copies per node. Retired instructions per operation on Native, against the previous build.

| Operation | Precision | Reported result |
| --- | --- | --- |
| `sqr` | 512 bits | 1.00 times fewer |
| `sqr` | 2,048 bits | 1.00 times fewer |
| `sqr` | 8,192 bits | 1.39 times fewer |
| `sqr` | 65,536 bits | 1.52 times fewer |
| `mul` | 512 bits | 1.00 times fewer |
| `mul` | 2,048 bits | 1.02 times fewer |
| `mul` | 8,192 bits | 1.04 times fewer |
| `mul` | 65,536 bits | 1.04 times fewer |
| Integer square root of a 65,536-bit root | 65,536 bits | 1.23 times fewer |

## Single-word fast paths

`Binary::add`, `mul`, `div` and `sqrt` on operands whose coefficients fit one machine word (up to 64 bits) and whose precision is at most 62 bits (60 for `div` and `sqrt`) skip the general path, which builds several coefficient values, a context, a flags record and a result tuple for each operation. The fast path computes on `UInt64` pairs (128-bit sums and products, a 128 by 64 bit division, a double-precision estimate refined by a Newton step and settled by exact comparisons for the square root), rounds to nearest even with the round and sticky bits, and allocates only the result. It declines a NaN, an infinity, a zero, an exact zero sum, wider coefficients or precision, operands whose exponents are far apart or near the implementation limits, and JavaScript, where the general path answers; the results are the same values with the same precision and exponent. White-box tests compare 40,000 random operand pairs per operation, ties, carries, cancellation and perfect squares with the general path. Operands of 128 bits and more are unchanged.

Paired runs; the Native rows are at 53 bits. The baseline is not recorded.

| Operation | Target | Precision | Reported speedup |
| --- | --- | --- | --- |
| `add` | Native | 53 bits | 2.9 times faster |
| `mul` | Native | 53 bits | 3.0 times faster |
| `div` | Native | 53 bits | 4.9 times faster |
| `sqrt` | Native | 53 bits | 2.8 times faster |
| not stated | Wasm | not stated | 3.1 to 5.1 times faster |
| not stated | Wasm-GC | not stated | 3.9 to 7.6 times faster |

## Two-word and coefficient fast paths

Above the single-word range, `Binary::add` and `mul` on coefficients of up to 128 bits at a precision of at most 128 bits run on `UInt64` words as well: a 192-bit aligned sum or difference and a 256-bit product (four word products, the high halves by 32-bit pieces), rounded to nearest even from the words with the round and sticky bits, and only the result is allocated. Wider operands, `div` above 128 bits (up to 128 bits it has a two-word path of its own in `binary_fast_pair_nonjs.mbt`) and `sqrt` at any size go through coefficient-level paths that do the same exact integer arithmetic as the general path but skip its context, flags record, result tuple and repeated rounding decisions: the sum is built in one window array of the width of the result plus three bits (the operand with the larger top bit placed, the other read through its shift, a sticky bit for what lies below it), the product is the short product of the high limbs when its rounding is certain (`bin_words_mul_short`), otherwise the limb-array product (`bin_words_mul`), the quotient carries at least two bits more than the precision plus a sticky bit from the remainder, the square root rounds from the integer root and its remainder (`remainder > root` decides, there are no ties), and the kept bits are copied once into the array that becomes the coefficient. Each path declines a NaN, an infinity, a zero, an exact zero sum, coefficients or precisions above 2^20 bits, operands whose exponents are far apart or near the implementation limits, and JavaScript, where the general path answers; the results are the same values with the same precision and exponent. White-box tests compare tens of thousands of random, all-ones, sparse, tie, exact-quotient, perfect-square and cancelling operand sets per operation with the general path on Native, Wasm and Wasm-GC (JavaScript keeps the general path).

Paired runs against the previous build. The target is not stated for some rows. For `div` at 128 to 512 bits the Knuth division dominates.

| Operation | Target | Precision | Reported speedup |
| --- | --- | --- | --- |
| `add` | Native | 128 bits | 3.3 times faster |
| `mul` | Native | 128 bits | 3.5 times faster |
| `add` | Wasm-GC | 128 bits | 2.5 times faster |
| `mul` | Wasm-GC | 128 bits | 3.7 times faster |
| `add` | Wasm | 128 bits | 3.5 times faster |
| `mul` | Wasm | 128 bits | 3.0 times faster |
| `add` and `mul` | not stated | 256 bits | 1.9 to 2.2 times faster |
| `add` and `mul` | not stated | 512 bits | 1.5 to 1.9 times faster |
| `add` and `mul` | not stated | 1,024 bits | 1.2 times faster |
| `sqrt` | not stated | 128 bits | 1.4 times faster |
| `sqrt` | Wasm-GC | 128 bits | 1.9 times faster |
| `sqrt` | not stated | 512 and 2,048 bits | 1.1 times faster |
| `div` | not stated | 128 to 512 bits | 1.1 to 1.2 times faster |

## Division, square root and GCD

Division uses a one-limb path, Knuth's algorithm D on 64-bit digits (a 128 by 64 bit quotient estimate and a 128-bit correction test) below the Burnikel–Ziegler cutoff (also as the leaf of its recursion, up to 64 limbs of 64 bits), and Burnikel–Ziegler from 96 limbs of 64 bits (192 of 32 bits) on Wasm, Wasm-GC and LLVM and from 208, 352 or 752 limbs of 64 bits on Native, with the portable, C or assembly rows. The dispatch does not select Newton reciprocal division, because it is slower than Burnikel–Ziegler from 32,768 bits (first table below), so the dispatch never reaches it; the routine stays, covered by tests, and the threshold constant is per target. Native multiplication switched to the NTT at 8,192 limbs of 32 bits (4,096 limbs of 64 bits, see Multiplication) instead of 2,048 limbs of 32 bits now that the Karatsuba is faster. Square root uses fixed-width kernels through 256 bits (the word kernels on Native, LLVM and Wasm-GC, the restoring loops on linear Wasm) and Zimmermann's `SqrtRem` on word arrays above that on every target except JavaScript; the recursion stops at the same fixed-width kernels once a block is at most 256 bits (a restoring loop on heap integers at 128 bits before), which makes a 1,024-bit radicand (a 512-bit `sqrt`) faster in paired runs on Native and Wasm (second table below). The cutoff is per-target policy measured with paired runs; the LLVM value is not measured because that backend is not available in the toolchain used. Large GCD uses Lehmer batching on a common 63-bit window of both operands and takes a single division step when the shorter operand has no bits in that window, so operands of very different lengths are reduced at once.

Newton reciprocal division against Burnikel–Ziegler, measured once multiplication was 2 to 3 times faster than before.

| Comparison | Precision | Reported result | Newton reciprocal division | Burnikel–Ziegler |
| --- | --- | --- | --- | --- |
| Newton reciprocal division against Burnikel–Ziegler | from 32,768 bits | 3 to 12 times slower | not recorded | not recorded |
| Newton reciprocal division against Burnikel–Ziegler | 32,768 bits | 4.4 ms against 0.37 ms | 4.4 ms | 0.37 ms |

Paired runs against the previous kernels.

| Operation | Target | Input | Reported speedup |
| --- | --- | --- | --- |
| `div` | Native | 512 bits | 1.5 times faster |
| `div` | Native | 2,048 bits | 2.3 times faster |
| `div` | Native | 8,192 bits | 2.9 times faster |
| `div` | Wasm-GC | 2,048 bits | 1.9 times faster |
| `div` | Wasm-GC | 8,192 bits | 3.3 times faster |
| `div` | Wasm | 2,048 bits | 1.3 times faster |
| `div` | Wasm | 8,192 bits | 3.3 times faster |
| `sqrt` | Native, Wasm-GC and Wasm | 8,192 bits | 1.5 to 1.8 times faster |
| `sqrt` | Native | 512-bit root from a 1,024-bit radicand | about 3.4 times faster |
| `sqrt` | Wasm | 512-bit root from a 1,024-bit radicand | 3.1 to 3.3 times faster |

The integer square root of a value of up to 256 bits (a 128-bit root, the base case of the divide-and-conquer root and the whole root at precisions up to 128 bits) no longer runs a bit-by-bit loop on Native, LLVM and Wasm-GC: up to 128 bits it is a double-precision estimate refined by one Newton step on 128-bit arithmetic and settled by exact comparisons, and up to 256 bits Zimmermann's word-level Karatsuba square root (the root of the upper two words, one 128 by 64 bit division for the low half, an exact settle on the 256-bit square) on a value normalized by an even shift. Linear Wasm keeps the loops (its 64-bit multiplication makes the word kernels no faster there). LLVM takes the Native settings, unmeasured because the toolchain used does not provide that backend. White-box tests compare the word kernels with the loops and with a BigInt oracle at every width from 1 to 256 bits (random, all ones, single bits, runs, the neighbours of exact squares near the extreme roots of each width). On Wasm (not on Wasm-GC) these roots still run the restoring loops: the word kernels are not enabled there and were not measured on that target.

Paired runs of the fixed-width square-root kernels against the previous kernels, with the coefficient-level paths above. The target of the 200-bit and 256-bit rows is not stated. The larger sizes are dominated by the division and squaring of the recursion, not by its base case.

| Target | Root precision | Reported result |
| --- | --- | --- |
| Native and Wasm-GC | 100 bits | 2.0 times faster |
| Native and Wasm-GC | 128 bits | 2.3 times faster |
| not stated | 200 bits | 1.4 times faster |
| not stated | 256 bits | 1.5 times faster |
| Native | 512 bits | 1.1 times faster |
| Native | 2,048 bits | 1.05 times faster |
| Wasm-GC | 256 and 512 bits | unchanged |
| linear Wasm | everywhere | unchanged |

## Square root above 256 bits

Above 256 bits the integer square root on every target except JavaScript runs Zimmermann's `SqrtRem` on word arrays instead of the `BinCoeff` divide-and-conquer root, which built about twenty-five temporaries per level (a `BinCoeff` operation on a few limbs costs 600 to 700 instructions, more than the division it surrounds). The radicand is shifted left by an even number of bits, below 128, to an even number $n$ of 64-bit limbs with the top two bits not both zero; each level cuts it into blocks of $n/4$ limbs, takes the root and remainder of the upper part from the recursion, one division by twice that root and one squaring of the quotient through the coefficient dispatch, and corrects the root by at most one; a quotient of a whole block is capped one below, which is the root. The remainder of the original radicand comes back from the normalized one with a one-limb product, $(r' + e(2s' - e)) \gg 2t$ with $e = s' \bmod 2^t$ for the shift $2t$. The recursion ends in the fixed-width kernels at 256 bits. No size is slower on any target (see the table below), so the word recursion is selected on every target except JavaScript (there is no per-target switch: `bin_coeff_sqrt_words_enabled` only selects the word or the restoring kernels of the base case, and the previous recursion remains as the test reference). White-box tests compare it with the previous recursion, the restoring loop and a BigInt oracle from 257 to 4,097 bits (random, all ones, single bits, zero limbs inside the value, the neighbours of exact squares), and with the defining inequalities up to 33,000 bits.

One root, radicand of twice the root width. The Native rows are retired instructions of a release build, paired with the previous build. The Wasm-GC and linear Wasm rows are paired wall-clock runs (medians of five, stated for the Wasm-GC runs), and the Native wall-clock rows are in line with the instruction counts; the baseline of the wall-clock rows is not stated. At the larger sizes the division and the squaring of the recursion dominate.

| Target and metric | Root width | Reported result |
| --- | --- | --- |
| Native, retired instructions | 256 bits | 1.8 times fewer |
| Native, retired instructions | 512 bits | 2.0 times fewer |
| Native, retired instructions | 2,048 bits | 1.85 times fewer |
| Native, retired instructions | 8,192 bits | 1.3 times fewer |
| Native, retired instructions | 65,536 bits | 1.04 times fewer |
| Wasm-GC, wall-clock time | 512 bits | 4.9 times faster |
| Wasm-GC, wall-clock time | 2,048 bits | 2.2 times faster |
| Wasm-GC, wall-clock time | 8,192 bits | 1.3 times faster |
| Wasm-GC, wall-clock time | 65,536 bits | 1.07 times faster |
| linear Wasm, wall-clock time | 512 bits | 2.2 times faster |
| linear Wasm, wall-clock time | 2,048 bits | 2.0 times faster |
| linear Wasm, wall-clock time | 8,192 bits | 1.4 times faster |
| linear Wasm, wall-clock time | 65,536 bits | 1.05 times faster |
| Native, wall-clock time | 512 bits | 2.0 times faster |
| Native, wall-clock time | 2,048 bits | 1.8 times faster |
| Native, wall-clock time | 8,192 bits | 1.3 times faster |
| Native, wall-clock time | 65,536 bits | 1.05 times faster |

## Kernels on 64-bit limbs

The last stage of the 64-bit limb work moves the remaining coefficient kernels off the 32-bit view of the storage, so that only the 32-bit-limb routes of Wasm (multiplication, squaring and Knuth division on 32-bit limbs) use it, and every cutoff is named and documented in 64-bit limbs (`bin_coeff_ntt_mul_min_words`, `bin_coeff_ntt_square_min_words`, `bin_coeff_toom3_min_words`, `bin_coeff_bz_division_min_words`, `bin_coeff_bz_leaf_words`, `bin_coeff_radix_format_dc_words`, `bin_coeff_sparse_min_words` (in `coeff_nonjs.mbt`) and the others of the threshold files, the same values halved). Converted: the multiplication and squaring dispatch, the unbalanced product (the block multiplication of the word Karatsuba replaces the `BinCoeff`-level one), the Burnikel–Ziegler recursion, the NTT digit conversion and overlap-add (the transforms keep their 32-bit Montgomery primes), the one-limb division, the sparse product, the bit operations, the byte and power-of-two radix conversions, the Lehmer threshold and the 256-bit square root kernel. The old divide-and-conquer root, its 512-bit kernel and the restoring loop are test-only references now. Results are unchanged: the regression digests recorded with the 32-bit implementation, the BigInt oracle tests, and new tests of the converted kernels against their 32-bit-limb definitions, the Knuth division, the schoolbook product and each other. The cutoffs keep their values (halved from limbs of 32 bits), except that LLVM now carries the cutoffs of the Native portable loops, not the values of the C and assembly rows of Native (its Burnikel–Ziegler cutoff is 96 limbs as on Wasm, against 208 on the Native portable loops), instead of an old copy of the Wasm ones; the elementary bit-burst precisions depend on multiplication cost, which this stage does not change. The NTT digit conversion stays on the 32-bit view on Wasm and Wasm-GC (`bin_coeff_ntt_limb32_conversion`), because the 64-bit limb conversion measured slower on Wasm-GC (third table below).

Retired instructions per operation on Native, against the previous build.

| Workload | Precision or operand condition | Reported result |
| --- | --- | --- |
| Sparse product | 8,192-bit operands; 4 and 12 nonzero limbs | 3.3 times fewer |
| `bit_and` plus `bit_xor` | 8,192 bits | 2.8 times fewer |
| Division | one-limb divisor below $2^{32}$ | 2.2 times fewer |
| `from_bytes_be` | not stated | 1.2 times fewer |
| Products, divisions, NTT products and gcd | 2,048 to 300,000 bits | 1.00 to 1.09 times fewer; nothing is slower |

Paired wall-clock runs on Wasm and Wasm-GC of in-place radix conversion against divide and conquer, from 4,096 to 131,072 bits.

| Conversion | Target | Input range | Reported result |
| --- | --- | --- | --- |
| Parsing | Wasm and Wasm-GC | 4,096 to 131,072 bits | in place is 1.2 to 6.5 times faster up to 131,072 bits |
| Formatting | Wasm and Wasm-GC | above 4,096 bits | divide and conquer is 1.2 to 3 times faster |

On Wasm-GC, seven paired runs per operation at 300,000 bits, each outside the spread. The values are the speed of the 64-bit limb conversion relative to the 32-bit limb conversion.

| Operation | Comparison | Reported result |
| --- | --- | --- |
| Product | 64-bit limb conversion relative to 32-bit limb conversion | 0.88 times as fast |
| Square | 64-bit limb conversion relative to 32-bit limb conversion | 0.78 times as fast |

## Radix conversion

`BinCoeff::to_radix_string` and `BinCoeff::parse` in a radix that is not a power of two work on one limb array in place below their divide-and-conquer cutoffs. Formatting divides a copy of the 64-bit limbs by the chunk power (9 decimal digits, the largest power of the radix below $2^{32}$) one pass per chunk, and parsing accumulates `value * chunk_power + chunk` in place; each limb is two 32-bit halves with one 64 by 32 bit division or multiplication each, and the digits of a chunk are written into one string builder from a scratch array. The earlier path sent every chunk through the 32-bit limb accessors and allocated a coefficient (the first table below gives its cost per limb step). Chunks of 64 bits (19 decimal digits) are not used: a 128 by 64 bit quotient digit needs two hardware divisions where two 64 by 32 bit steps need one each, so by construction a pass over the limbs costs about the same per digit, and what was wrong was the per-chunk overhead, which is gone either way (not measured separately). The divide-and-conquer conversion starts at 6,144 32-bit limbs (196,608 bits) for formatting and at 4,608 chunks (about 41,000 digits) for parsing on Native and LLVM. Paired wall-clock runs of the conversion on Wasm and Wasm-GC put the parsing cutoff at 4,608 chunks as on Native and keep the formatting cutoff at 128 limbs of 32 bits (64 of 64 bits); the second table of Kernels on 64-bit limbs gives the runs. White-box tests check, for the radixes 3, 10 and 36, the powers of the radix and their neighbours around chunk edges up to 130 chunks, and the in-place conversion against divide and conquer (formatting and parsing) at 1 to 1,025 limbs on both sides of the cutoffs; a CPython oracle checks both directions for further radixes.

Retired instructions per 32-bit limb step, before the in-place conversion and now.

| Quantity | Earlier accessor path | In-place path |
| --- | --- | --- |
| Instructions per 32-bit limb step | about 113 | about 10 |

Crossovers of the divide-and-conquer cutoffs, measured with retired instructions on Native and LLVM.

| Conversion | Target | Cutoff | Workload | In-place instructions | Divide-and-conquer instructions |
| --- | --- | --- | --- | --- | --- |
| Formatting | Native and LLVM | 6,144 32-bit limbs (196,608 bits) | 65,536 bits | 14.5 million | 25.5 million |
| Formatting | Native and LLVM | 6,144 32-bit limbs (196,608 bits) | 262,144 bits | 220 million | 181 million |
| Parsing | Native and LLVM | 4,608 chunks (about 41,000 digits) | 131,072 bits | 47.2 million | 48.3 million |
| Parsing | Native and LLVM | 4,608 chunks (about 41,000 digits) | 262,144 bits | 201 million | 146 million |

Retired instructions per operation on Native, base 10, against the previous build.

| Conversion | Radix | Precision | Reported result |
| --- | --- | --- | --- |
| Formatting | 10 | 512 bits | 4.9 times fewer |
| Formatting | 10 | 2,048 bits | 5.7 times fewer |
| Formatting | 10 | 8,192 bits | 4.2 times fewer |
| Formatting | 10 | 65,536 bits | 2.0 times fewer |
| Parsing | 10 | 512 bits | 6.1 times fewer |
| Parsing | 10 | 2,048 bits | 8.3 times fewer |
| Parsing | 10 | 8,192 bits | 4.7 times fewer |
| Parsing | 10 | 65,536 bits | 1.5 times fewer |
| Formatting and parsing | 16 | not stated | unchanged |

## Fixed-point exponential

The certified `exp` enclosure bounds the Taylor series of the reduced argument (at most 1/8) in fixed point with 16 fractional bits beyond the working precision when the argument is exact at the working precision, instead of with one rounded floating-point operation per term. Each computed term rounds down, so their sum is a lower bound; each carries an error below 3 units of the last place, which gives an upper bound with a rigorous tail. The enclosure is about as wide as the floating-point one, the 12-attempt refinement loop and its working precisions are unchanged, and arguments that are not exact at the working precision still use the previous series. White-box tests check that the enclosure contains a much tighter one and that the final correctly rounded results and flags equal those of the previous series.

Paired runs. The baseline is not recorded.

| Operation | Target | Precision | Reported speedup |
| --- | --- | --- | --- |
| `exp` | Native | 53 to 2,048 bits | 9 to 10 times faster |
| `exp` | Wasm and Wasm-GC | 53 to 2,048 bits | 7 to 11 times faster |
| decimal `exp` | not stated | not stated | 1.7 to 2.2 times faster |

## Fixed-point sine and cosine

The Taylor series of `sin` and `cos` on the reduced argument (at most 1 in magnitude) is summed in fixed point when the argument is exact at the working precision, with 20 guard bits and, for the sine, the leading zero bits of the argument, so a small argument keeps `precision + 20` significant bits. Each computed term rounds down and is short by at most 4 units, the series alternates with decreasing terms, and so `signed sum +- (4n + 24)` encloses the value, with the sign flipped for a negative sine argument. Arguments that are not exact, or so small that its leading zero bits would exceed four times the working precision plus 64, use the previous floating-point series; the refinement loop and its working precisions are unchanged. White-box tests check containment of a much tighter enclosure, a bound on the width, and the sine and cosine identities.

Paired runs on top of the memoized constants (without them the `pi` recomputation hides the series). The series is about nine tenths of the time only once `pi` is cached, which is why the change on its own gives the smaller ratio of the third row.

| Workload | Target | Precision or condition | Reported result |
| --- | --- | --- | --- |
| `sin` | Native | 53 to 2,048 bits | 4.3 to 5.7 times faster |
| `sin` | Wasm-GC | not stated | 4.6 times faster |
| Fixed-point change on its own | not stated | not stated | 1.3 to 1.4 times faster |

## Fixed-point logarithm

The certified `ln` enclosure on the normalized argument in [1, 2] (and, below a working precision of 64 bits, the `ln 2` and `ln 10` constants built from it) sums the series `2 * sum z^(2k+1) / (2k+1)`, `z = (v - 1) / (v + 1)`, in fixed point when the argument is exact at the working precision. The fraction has 16 guard bits plus the leading zero bits of `z`, so the enclosure keeps `precision + 16` significant bits even for an argument close to 1; every operation rounds down, which makes the sum a lower bound, and a proven error of less than 2 units per term and a tail bound give the upper bound. Arguments that are not exact, or so close to 1 that the leading zero bits of `z` would exceed four times the working precision plus 64, use the previous floating-point series, so the refinement loop and its working precisions are unchanged. White-box tests check containment of a much tighter enclosure, a bound on the width, and equality of the final correctly rounded results and flags with those of the previous series.

Paired runs without the constant cache. The baseline is not recorded.

| Operation | Target | Precision | Reported speedup |
| --- | --- | --- | --- |
| `ln` | Native | 53 to 2,048 bits | 5 to 7 times faster |
| `ln` | Wasm and Wasm-GC | 53 to 2,048 bits | 5.5 to 7.5 times faster |
| decimal `ln` | not stated | not stated | 6 times faster |

## Certified constants

The certified elementary functions memoize the constant enclosures they need (`ln 2`, `ln 10` and `pi`) per working precision, in small per-constant caches of six precisions up to 65,536 bits. A cached enclosure is the value a recomputation returns, so results never depend on cache state or call order. Before this, every `ln`, `log2`, `log10`, `sin`, `cos`, `tan` and `atan2` call re-ran an `ln 2` series or an `atan(1)` evaluation that cost as much as the function itself.

Paired runs, compared with recomputing the constants.

| Operation | Target | Precision | Reported speedup |
| --- | --- | --- | --- |
| `ln` | Native | 53 to 512 bits | 2.4 to 2.6 times faster |
| `sin` | Native | not stated | 2.4 to 3.7 times faster |
| decimal `ln` | Native | not stated | 2.5 times faster |
| `ln` and `sin` | Wasm and Wasm-GC | not stated | 1.7 to 2.2 times faster |
| `exp` | not stated | not stated | unchanged; it has no such constant |

## Certified series

The enclosure of `exp` evaluates its Taylor series once, not twice, when the argument is exact at the working precision (the usual case), because the lower and upper bounds are then the same value and only one bound of each series is read. The trigonometric enclosure evaluates only the sine or cosine series that the requested function and quadrant read, one series instead of four for `sin` and `cos` (evaluated at the midpoint of the reduced interval and widened by its radius). The `exp` skip returns the exact enclosures of before, and the trigonometric one the same correctly rounded results, which white-box tests check against copies of the previous code.

Paired runs. The baseline is not recorded.

| Operation | Target | Precision | Reported speedup |
| --- | --- | --- | --- |
| `exp` | Native | 53 to 512 bits | 1.8 to 2.0 times faster |
| decimal `exp` | Native | not stated | 1.3 to 1.4 times faster |
| `sin` | Native | not stated | 1.15 to 1.2 times faster on its own |
| `exp` | Wasm and Wasm-GC | not stated | 1.7 to 1.9 times faster |

## Trade-offs

Schoolbook minimizes setup and allocation, recursive algorithms reduce asymptotic work, and NTT improves very large balanced inputs at the cost of transforms and temporary storage. Every fast path retains an exact fallback, so performance dispatch cannot alter semantics.
