# internal/bin_kernel design

## Design goal

`BinFloat` is a rounding layer on top of one arithmetic: non-negative integers
of up to $2^{28}$ bits. The integer part should be one package with one
contract, so that an algorithm can be measured, replaced and tested without the
floating-point layer, and so that the rounding layer cannot reach into it. The
package therefore contains only functions from integers to integers.

## Mathematical background

A coefficient $c \ge 0$ is stored as $c = \sum_{i<n} w_i 2^{64 i}$ with
$0 \le w_i < 2^{64}$ and $w_{n-1} \ne 0$; values below $2^{128}$ are kept in
one or two machine words without an array. Every operation computes an exact
result:

- $\operatorname{add}(a,b) = a + b$, $\operatorname{sub}(a,b) = a - b$ for
  $a \ge b$, $\operatorname{mul}(a,b) = ab$;
- $\operatorname{divrem}(a,b) = (q,r)$ with $a = qb + r$ and $0 \le r < b$;
- $\operatorname{shift}(a,k) = a \cdot 2^{k}$ and $\lfloor a / 2^{k} \rfloor$;
- the integer square root $s = \lfloor \sqrt{a} \rfloor$ with remainder
  $a - s^2$, the GCD, and the digits of $a$ in any radix.

The algorithms behind them (schoolbook, Karatsuba, Toom-3, the two-prime NTT,
Knuth's algorithm D, Burnikel-Ziegler, the Zimmermann square root, Lehmer GCD
and the in-place radix conversion), their cutoffs and the argument that they
all compute the same integers are in the section
[The coefficient kernel](../bin_float.md#the-coefficient-kernel) of the
`bin_float` design page. Because every path computes the same integers, the
choice of algorithm cannot change a rounded result, a flag or an encoding.

## Package boundary

| Decision | Choice | Reason |
| --- | --- | --- |
| Where the type lives | `Coeff` is defined here; `BinCoeff` in `bin_float` is a newtype `struct BinCoeff(@bin_kernel.Coeff)` | A re-export of an internal type (`pub using`) does not give another module (the tools module) the methods of the type; a newtype does, and it is erased. |
| Unwrapping | `pub(all) struct BinCoeff(@bin_kernel.Coeff)`; `BinCoeff` has no arithmetic | The other library packages (`ball_float`, `decimal`) do arithmetic on coefficients: `value.0` gives them the kernel type and `BinCoeff(c)` wraps a result. Outside the module the inner type is inert: a method call, `==` and a qualified call on it are compile errors, and the import is refused by the solver, so the public field exposes no operation and no compatibility promise. |
| Why not a record wrapper | A newtype, never `struct BinCoeff { kernel : Coeff }` | A record wrapper allocates a second object per value: +49% retired instructions on a small `add` in the throwaway measurement. A newtype and a call across the package boundary cost nothing measurable. |
| Representation | `Coeff` is a newtype over a three-case enum (`Inline64`, `Inline128`, `Heap`); `BinFloat` stores it directly | One allocation per coefficient instead of two (10 to 15% fewer instructions per `BinFloat` operation at 53 to 512 bits, [#427](https://github.com/Luna-Flow/floating/pull/427)). |
| JavaScript | `Coeff` is a host `bigint` (`coeff_js.mbt`); no kernel algorithms | The host's arbitrary-precision integers are the kernel there. |
| Machine words | `binary_fast_*` live here | The word-wide `mul_high` and `div_wide` are used by the kernel and by the single-word paths of `bin_float`. |

## Limb rows and the native C stub

The inner loops of the schoolbook product and square are row primitives on
64-bit limbs: `mul_1`, `addmul_1`, `submul_1` (each takes arrays and offsets in
limbs and returns a carry limb), the whole-call `school` and `sqr_school`.
Each has a portable MoonBit function (`coeff_limbs_portable_nonjs.mbt`,
`coeff_words_nonjs.mbt`), which is the reference, and a C function of the same
name in `luna_limbs.c`. On the native target the wrappers of
`coeff_limbs_native.mbt` check every range once per call, then call the C
function; on wasm, wasm-gc and llvm the wrappers of `coeff_limbs_other_nonjs.mbt`
call the portable one; JavaScript has no limb loops. The results are the same bit
for bit; a differential test per primitive (`coeff_limbs_native_wbtest.mbt`)
compares the two on lengths 1 to 200, edge limbs, carries through every position
and the aliasing the callers use.

- The C file uses `unsigned __int128` where the compiler defines
  `__SIZEOF_INT128__` (gcc, clang) and four 32-bit products elsewhere. The
  intrinsics of MSVC (`_umul128`, `__umulh`) are not used: they have not been
  compiled and run, so `cl` takes the 32-bit branch (known follow-up).
- Test and benchmark knob: the environment variable `LUNA_FLOATING_PORTABLE`,
  read once at start, set to anything but empty or `0`, makes the native build
  run the portable loops. It changes speed only. `getenv` may warn on MSVC; that
  platform is untested.
- Measured on arm64 (Apple clang, release): about 21 to 23 instructions per limb
  pair in the portable loop, 11 to 12 in C. x86-64: the stub compiles and its
  tests run in CI, no instruction table (not measured).
- Rows are not worth a C version for add, subtract and shifts: the portable loop
  is as short.
- Assembly tier: on Apple arm64 (clang or gcc) the three rows, and through them
  `school` and `sqr_school`, have a third implementation in inline assembly in
  `luna_limbs.c`, written from the AArch64 instruction definitions. Four limbs
  per iteration, two carry chains in sequence: chain A adds the low words of the
  products and the high words of the previous limbs (`adds`, `adcs`, `adc`),
  chain B adds or subtracts the destination limbs, and the carry of chain B
  enters the next block as the initial flag (`cmp x, #1`). The lengths below a
  multiple of four are done first by the C row. Measured instructions per limb
  (arm64, row of 128 limbs): `mul_1` 4.9, `addmul_1` 6.9, `submul_1` 7.0 in
  assembly, 9.2, 12.1 and 13.1 in C. The floor of the loop: each limb needs a
  `mul`, a `umulh`, two carry additions and about 1.5 memory operations, 5.5 for
  `addmul_1`; the block adds 1.25 (finishing the chain A carry, the flag rebuild,
  the chain B carry, the loop). AArch64 has one carry flag and no
  multiply-accumulate with carry, so the two chains cannot be interleaved.
  Anywhere else the assembly entry points are the C rows.
- `bin_limbs_product` (public, for the limb-array loops of `bin_float`): `r[ro ..< ro + an + bn] = a * b` in one call, rows over the limbs of `a` (pass the shorter operand or the multiplier as `a`), both lengths at least 1, `r` not overlapping the operands, every result limb written. On the native tiers with the C or assembly rows it is the schoolbook entry behind one set of range checks; on the portable tier and the other targets it is the loop of portable `mul_1` and `addmul_1` rows, so no target pays more. At 10 by 9 limbs it costs 868 instructions on the assembly tier and 1,145 on the C tier against 1,028 and 1,292 for `mul_1` and eight `addmul_1` through their wrappers (the wrappers and their checks are 134 of the C figure).
- Selection: `LUNA_FLOATING_PORTABLE` (portable loops) and
  `LUNA_FLOATING_LIMBS=c` (C rows) are read once at start; the default is
  assembly where the tier exists, else C. The differential test compares all
  three on the same arrays and logs the tier that ran. Linux arm64 has not been
  run; the tier is enabled for Apple arm64 only.

## Thresholds

The cutoffs are named `*_min_words` or `*_words` (64-bit limbs) and chosen per
target in `coeff_thresholds_<target>.mbt`. They are policy, not semantics: the
dispatch tests cross every one of them and compare with the schoolbook result.
The cutoffs of the elementary functions are not kernel policy and stay in
`bin_float`.

## Invariants

- A `Heap` coefficient has `len >= 3` limbs, the top limb is nonzero, and no
  function mutates the array of an operand.
- The producers of fresh values (`Coeff::mul` for nonzero operands, `bin_coeff_div_scaled_quotient`, `bin_coeff_div_short_quotient`, `bin_coeff_mul_short`, `bin_coeff_sqrt_scaled_rounded`) return a `Heap` coefficient whose array no operand and no other value refers to; inline results and the shared `Coeff::zero()` carry no array, and a shift by zero returns its receiver. A caller may keep or modify such an array.
- `Inline64` and `Inline128` are the only representations of values below
  $2^{128}$; `bin_coeff_from_words` normalizes.
- No function aborts except on a violated precondition (a zero divisor, a
  negative shift).
