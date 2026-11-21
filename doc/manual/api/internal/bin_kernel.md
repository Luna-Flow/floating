# internal/bin_kernel API

## Purpose

`internal/bin_kernel` holds the integer arithmetic on the coefficients of
`BinFloat`: a non-negative arbitrary-precision integer `Coeff`, its comparison,
addition, subtraction, shifts and bit operations, the multiplication
algorithms (schoolbook, Karatsuba, Toom-3 and the two-prime NTT), division
(Knuth's algorithm D and Burnikel-Ziegler), the integer square root, the GCD,
and the conversions to and from bytes and text in any radix, with the per-target
thresholds that choose between the algorithms. Every function is an exact
function of its arguments. The package raises no condition and has no notion of
a rounding mode, a context or a flag; those belong to `bin_float`.
`internal/bin_kernel` also declares the internal enum `BinRepr`, the representation of `BinFloat` (one file per target: `repr_nonjs.mbt` and `repr_js.mbt`); see the design page of `bin_float`, section "Representation of a value".
It is an internal package: code outside `Luna-Flow/floating` cannot import it.
The public coefficient type `BinCoeff` of `bin_float` is a newtype over `Coeff`
whose methods (construction, conversion, comparison and queries) forward to
this package; the arithmetic exists only here. The name `Coeff` appears in the
interface of `BinCoeff`, but a user outside the module cannot import this
package and so cannot call or compare anything on it. See the [tutorial](../../tutorial/internal/bin_kernel.md) and the
[design page](../../design/internal/bin_kernel.md).

## Importing

Inside the module, add the package to `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/internal/bin_kernel" @bin_kernel,
}
```

and bring the names a package uses into scope once, for example in a file of
its own:

```moonbit nocheck
///|
using @bin_kernel { type Coeff, bin_coeff_word }
```

The manual's example checker has no alias for internal subpackages, so the
examples are marked `nocheck`.

## The coefficient type

### `Coeff`

A non-negative integer. On Native, LLVM, Wasm and Wasm-GC it is a newtype over
`CoeffRepr`; on JavaScript it is a host `bigint`. The value is persistent: no
function mutates an operand.

### `CoeffRepr`

The storage on the targets that are not JavaScript: `Inline64(low)` and
`Inline128(high, low)` for values below $2^{64}$ and $2^{128}$, and
`Heap(words, len)` for larger ones, with `len` little-endian 64-bit limbs of
which the top one is nonzero. The constructors are readable because the
word-sized fast paths of `bin_float` pattern-match on them; build values with
the functions below.

## Function families

| Family | Functions |
| --- | --- |
| build and convert | `Coeff::zero`, `Coeff::one`, `Coeff::from_uint64`, `Coeff::from_bytes_be`, `Coeff::parse`, `bin_coeff_from_words`, `bin_coeff_inline`, `Coeff::to_uint64`, `Coeff::to_bytes_be`, `Coeff::to_radix_string`, `Coeff::to_string` |
| shape | `Coeff::is_zero`, `Coeff::is_odd`, `Coeff::bit_length`, `Coeff::ctz`, `Coeff::test_bit`, `bin_coeff_word` |
| compare | `Coeff::compare`, `Coeff::equal`, `Coeff::not_equal`, `Coeff::op_lt`, `Coeff::op_le`, `Coeff::op_gt`, `Coeff::op_ge` |
| add, subtract, shift | `Coeff::add`, `Coeff::sub_checked`, `Coeff::shift_left`, `Coeff::shift_right`, `Coeff::shl`, `Coeff::shr`, `bin_coeff_add_normalized_odd`, `bin_coeff_sub_normalized_odd` |
| bit operations | `Coeff::bit_and`, `Coeff::bit_or`, `Coeff::bit_xor` |
| multiply and divide | `Coeff::mul`, `bin_coeff_mul_short_ok`, `bin_coeff_mul_short`, `bin_coeff_short_product_limbs`, `Coeff::square`, `Coeff::div_rem_checked`, `bin_coeff_short_div_rem`, `bin_coeff_div_scaled_ok`, `bin_coeff_div_scaled_quotient`, `bin_coeff_div_short_ok`, `bin_coeff_div_short_quotient`, `bin_coeff_short_division_guard_bits` |
| number theory and roots | `Coeff::gcd`, `Coeff::pow_nat`, `bin_coeff_sqrt_rem_kernel`, `bin_coeff_sqrt_rem_scaled`, `bin_coeff_sqrt_scaled_rounded` |
| limb rows (C on native, portable elsewhere) | `bin_limbs_mul_1`, `bin_limbs_addmul_1`, `bin_limbs_submul_1`, `bin_limbs_product`, `bin_limbs_window_combine` |
| machine words | `binary_fast_bits`, `binary_fast_mul_high`, `binary_fast_div_wide`, `binary_fast_shl_high`, `binary_fast_shl_low` |

The per-target thresholds (`bin_coeff_*_min_words`, `*_words`, `*_cutoff`) are
private: they live in `coeff_thresholds_<target>.mbt` and are selected by
`moon.pkg`. Preconditions are checked with `abort` (a negative shift count, a
zero divisor): they are programmer errors of the caller, never conditions of an
operation.

## Complete public interface

This snapshot is the generated `pkg.generated.mbti` of the package. It is the authority when prose and interface disagree.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/internal/bin_kernel"

import {
  "moonbitlang/core/debug",
}

// Values
pub fn bin_coeff_add_normalized_odd(Coeff, Coeff) -> (Coeff, Int32)

pub fn bin_coeff_div_scaled_ok(Coeff, Int32, Coeff) -> Bool

pub fn bin_coeff_div_scaled_quotient(Coeff, Int32, Coeff) -> Coeff

pub fn bin_coeff_div_short_ok(Coeff, Int32, Coeff) -> Bool

pub fn bin_coeff_div_short_quotient(Coeff, Int32, Coeff, Int32) -> Coeff

pub fn bin_coeff_from_words(FixedArray[UInt64], Int32) -> Coeff

pub fn bin_coeff_inline(UInt64, UInt64) -> Coeff

pub fn bin_coeff_mul_short(Coeff, Coeff, Int32) -> Coeff

pub fn bin_coeff_mul_short_ok(Coeff, Coeff, Int32) -> Bool

pub fn bin_coeff_short_div_rem(Coeff, Coeff) -> (Coeff, Coeff)

pub let bin_coeff_short_division_guard_bits : Int32

pub fn bin_coeff_short_product_limbs(Int32) -> Int32

pub fn bin_coeff_sqrt_rem_kernel(Coeff) -> (Coeff, Coeff)

pub fn bin_coeff_sqrt_rem_scaled(Coeff, Int32) -> (Coeff, Coeff)

pub fn bin_coeff_sqrt_scaled_rounded(Coeff, Int32, Int32) -> Coeff

pub fn bin_coeff_sub_normalized_odd(Coeff, Coeff) -> (Coeff, Int32)

pub fn bin_coeff_word(Coeff, Int32) -> UInt64

pub fn bin_limbs_addmul_1(FixedArray[UInt64], Int32, FixedArray[UInt64], Int32, Int32, UInt64) -> UInt64

pub fn bin_limbs_mul_1(FixedArray[UInt64], Int32, FixedArray[UInt64], Int32, Int32, UInt64) -> UInt64

pub fn bin_limbs_product(FixedArray[UInt64], Int32, FixedArray[UInt64], Int32, Int32, FixedArray[UInt64], Int32, Int32) -> Unit

pub fn bin_limbs_submul_1(FixedArray[UInt64], Int32, FixedArray[UInt64], Int32, Int32, UInt64) -> UInt64

pub fn bin_limbs_window_combine(FixedArray[UInt64], Int32, FixedArray[UInt64], Int32, Int32, Int32, FixedArray[UInt64], Int32, Int32, Int32, Bool, UInt64) -> UInt64

pub fn binary_fast_bits(UInt64) -> Int32

pub fn binary_fast_div_wide(UInt64, UInt64, UInt64) -> UInt64

pub fn binary_fast_mul_high(UInt64, UInt64) -> UInt64

pub fn binary_fast_shl_high(UInt64, Int32) -> UInt64

pub fn binary_fast_shl_low(UInt64, Int32) -> UInt64

// Errors

// Types and methods
#derive(Eq, @debug.Debug)
pub(all) enum BinRepr {
  Fin64(negative~ : Bool, word~ : UInt64, exponent2~ : Int32, precision~ : Int32)
  Fin128(negative~ : Bool, high~ : UInt64, low~ : UInt64, exponent2~ : Int32, precision~ : Int32)
  FinBig(negative~ : Bool, coefficient~ : Coeff, exponent2~ : Int32, precision~ : Int32)
  Inf(negative~ : Bool, precision~ : Int32)
  NaN(negative~ : Bool, signaling~ : Bool, payload~ : Coeff, precision~ : Int32)
}

#derive(@debug.Debug)
pub struct Coeff(CoeffRepr)
pub fn Coeff::add(Self, Self) -> Self
pub fn Coeff::add_shifted_left(Self, Int32, Self) -> Self
pub fn Coeff::bit_and(Self, Self) -> Self
pub fn Coeff::bit_length(Self) -> Int32
pub fn Coeff::bit_or(Self, Self) -> Self
pub fn Coeff::bit_xor(Self, Self) -> Self
pub fn Coeff::compare(Self, Self) -> Int32
pub fn Coeff::ctz(Self) -> Int32
pub fn Coeff::div_rem_checked(Self, Self) -> Result[(Self, Self), String]
pub fn Coeff::equal(Self, Self) -> Bool
pub fn Coeff::from_bytes_be(BytesView) -> Self
pub fn Coeff::from_uint64(UInt64) -> Self
pub fn Coeff::gcd(Self, Self) -> Self
pub fn Coeff::is_odd(Self) -> Bool
pub fn Coeff::is_zero(Self) -> Bool
pub fn Coeff::mul(Self, Self) -> Self
pub fn Coeff::not_equal(Self, Self) -> Bool
pub fn Coeff::one() -> Self
pub fn Coeff::op_ge(Self, Self) -> Bool
pub fn Coeff::op_gt(Self, Self) -> Bool
pub fn Coeff::op_le(Self, Self) -> Bool
pub fn Coeff::op_lt(Self, Self) -> Bool
pub fn Coeff::output(Self, &Logger) -> Unit
pub fn Coeff::parse(String, radix? : Int32) -> Result[Self, String]
pub fn Coeff::pow_nat(Self, UInt32) -> Self
pub fn Coeff::shift_left(Self, Int32) -> Self
pub fn Coeff::shift_right(Self, Int32) -> Self
pub fn Coeff::shl(Self, Int32) -> Self
pub fn Coeff::shr(Self, Int32) -> Self
pub fn Coeff::square(Self) -> Self
pub fn Coeff::sub_checked(Self, Self) -> Result[Self, String]
pub fn Coeff::test_bit(Self, Int32) -> Bool
pub fn Coeff::to_bytes_be(Self) -> Bytes
pub fn Coeff::to_radix_string(Self, Int32) -> String
pub fn Coeff::to_repr(Self) -> @debug.Repr
pub fn Coeff::to_string(Self) -> String
pub fn Coeff::to_uint64(Self) -> UInt64?
pub fn Coeff::zero() -> Self
pub impl Add for Coeff
pub impl Compare for Coeff
pub impl Eq for Coeff
pub impl Mul for Coeff
pub impl Shl for Coeff
pub impl Show for Coeff
pub impl Shr for Coeff

#derive(@debug.Debug)
pub enum CoeffRepr {
  Inline64(UInt64)
  Inline128(UInt64, UInt64)
  Heap(FixedArray[UInt64], Int32)
}

// Type aliases

// Traits
```
<!-- generated-api-end -->
