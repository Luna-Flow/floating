# internal/decimal_kernel API

## Purpose

`internal/decimal_kernel` holds the integer arithmetic on decimal coefficients
that `decimal` (IEEE 754) and `decimal_gda` (General Decimal Arithmetic) both
need: a persistent coefficient type, addition, subtraction, comparison,
shifts by powers of ten, digit counts, trailing-zero trimming, division by a
limb, and the multiplication and division algorithms with their per-target
thresholds. Every function is an exact function of its arguments. The package
raises no condition and has no notion of a rounding mode, a context or a flag;
those belong to the standard-specific finalizers of the two decimal packages.
It is an internal package: code outside `Luna-Flow/floating` cannot import it,
and neither decimal package exposes its types. See the
[tutorial](../../tutorial/internal/decimal_kernel.md) and the
[design page](../../design/internal/decimal_kernel.md).

## Importing

Inside the module, add the package to `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/internal/decimal_kernel" @decimal_kernel,
}
```

and bring the names a package uses into scope once, for example in a file of
its own:

```moonbit nocheck
///|
using @decimal_kernel {
  type DecCoeff,
  dec_coeff_from_int,
  dec_coeff_magnitude_add_repr,
}
```

The manual's example checker has no alias for internal subpackages, so the
examples are marked `nocheck`.

## The coefficient type

### `DecCoeff`

A non-negative integer, either `Small(UInt64)` for values below $10^{18}$ or
`Limbs(units, digits)`: little-endian base-$10^9$ limbs without a leading zero
limb, with the digit count cached. The value is persistent; no function mutates
the limbs of an operand. The constructors are public because the two decimal
packages pattern-match on them in a few fast paths; prefer the functions below.

### `DecCoeffRounding`

The eight rounding directions (`HalfEven`, `HalfUp`, `HalfDown`, `Down`,
`Ceiling`, `Floor`, `Up`, `ZeroFiveUp`) as a plain enum. It is a direction, not
a status: each decimal package converts its own rounding-mode type into it with
a total match, and the functions in the rounding family answer only whether a
kept magnitude grows by one unit in the last place.

### `SignedDecCoeff`

A sign and a `DecCoeff` magnitude, for algorithms whose intermediate values can
be negative (Toom-3, the Newton reciprocal). Zero is never negative. The type is
`pub`: its fields can be read, but a value is built only by this package.

## Function families

All functions are named `dec_coeff_*`; the ones without that prefix are
`remove_factor10_repr`, `exact_divide_by_power_of_ten_repr` and
`trim_trailing_decimal_zeros_repr`.

| Family | Functions |
| --- | --- |
| build and convert | `dec_coeff_zero`, `dec_coeff_from_int`, `dec_coeff_from_nonnegative_int`, `dec_coeff_from_int_magnitude`, `dec_coeff_from_decimal_digits_repr`, `dec_coeff_from_bigint_repr`, `dec_coeff_to_bigint_repr`, `DecCoeff::to_string`, `dec_coeff_from_unit_accumulator`, `DecCoeff::to_bigint` |
| shape | `DecCoeff::digits10`, `DecCoeff::is_zero`, `dec_coeff_unit_len`, `dec_coeff_limb_at`, `dec_coeff_is_odd`, `dec_coeff_copy_limbs`, `dec_coeff_small_value`, `dec_coeff_matches_unit_repr`, `dec_coeff_slice`, `dec_coeff_small_digits` |
| add, subtract, compare | `dec_coeff_magnitude_add_repr`, `dec_coeff_magnitude_sub_repr`, `dec_coeff_magnitude_add_unit`, `dec_coeff_magnitude_sub_unit`, `dec_coeff_signed_add_repr`, `dec_coeff_compare_repr`, `dec_coeff_compare_scaled_repr`, `dec_coeff_compare_half_power10`, `dec_coeff_unit_add_sub` |
| powers of ten and trimming | `dec_coeff_shift_power10_repr`, `dec_coeff_power10_repr`, `remove_factor10_repr`, `exact_divide_by_power_of_ten_repr`, `trim_trailing_decimal_zeros_repr` |
| multiply | `dec_coeff_multiply_repr`, `dec_coeff_square_repr`, `dec_coeff_multiply_by_unit_repr` |
| divide | `dec_coeff_div_rem_repr`, `dec_coeff_mod_repr`, `dec_coeff_div_rem_by_unit_repr`, `dec_coeff_div_rem_knuth_repr`, `dec_coeff_div_rem_burnikel_ziegler`, `dec_coeff_div_rem_newton_try` |
| number theory | `dec_coeff_gcd_repr`, `dec_coeff_count_factor_unit_repr`, `dec_coeff_pow_unit_repr`, `dec_coeff_exact_power_repr`, `dec_coeff_exact_power_if_fits_repr` |
| rounding decisions | `DecCoeffRounding`, `dec_coeff_should_increment`, `dec_coeff_round_div`, `dec_coeff_round_div_bigint`, `dec_coeff_round_div_pow10`, `dec_coeff_round_div_pow10_owned`, `dec_coeff_round_to_digits`, `dec_coeff_huge_shift_rounded_unit`, `dec_coeff_sqrt_should_increment`, `dec_coeff_addend_rounding_step`, `dec_coeff_round_div_expansion` |
| exact helpers | `compare_finite_magnitude_repr`, `dec_coeff_integer_sqrt_rem_repr`, `dec_coeff_floor_nth_root_repr`, `dec_coeff_exact_nth_root_repr`, `has_finite_decimal_expansion_repr`, `decimal_ln_atanh_scaled_coeff`, `decimal_round_scaled_coeff`, `decimal_floor_div_scaled_repr`, `dec_coeff_shift_power10_mod_wide_repr`, `dec_coeff_to_bounded_int`, `is_power_of_ten_coeff`, `decimal_small_pow10`, `dec_coeff_shift_power10_mod_repr` |
| digit-wise logic | `logical_binary_digits_repr`, `coefficient_shift_digits_repr`, `coefficient_rotate_digits_repr`, `logical_coeff_digits_lsd`, `logical_coeff_from_digits_lsd` |
| signed values | `SignedDecCoeff`, `SignedDecCoeff::add`, `SignedDecCoeff::neg`, `SignedDecCoeff::sub`, `dec_coeff_signed_compare_int_repr`, `dec_coeff_signed_step_unit_repr`, `signed_dec_coeff`, `signed_dec_coeff_from_int_product` |
| thresholds and constants | `dec_coeff_base`, `dec_coeff_burnikel_ziegler_threshold`, `dec_coeff_burnikel_ziegler_threshold_16k`, `dec_coeff_burnikel_ziegler_threshold_8k`, `dec_coeff_burnikel_ziegler_threshold_large`, `dec_coeff_dpun`, `dec_coeff_karatsuba_square_threshold`, `dec_coeff_karatsuba_threshold`, `dec_coeff_newton_enabled`, `dec_coeff_newton_threshold`, `dec_coeff_ntt_mul_threshold`, `dec_coeff_ntt_mul_threshold_16k`, `dec_coeff_ntt_mul_threshold_32k`, `dec_coeff_ntt_mul_threshold_64k`, `dec_coeff_ntt_mul_threshold_large`, `dec_coeff_ntt_square_threshold`, `dec_coeff_ntt_square_threshold_16k`, `dec_coeff_ntt_square_threshold_32k`, `dec_coeff_ntt_square_threshold_64k`, `dec_coeff_ntt_square_threshold_8k`, `dec_coeff_ntt_square_threshold_large`, `dec_coeff_ntt_square_toom3_threshold`, `dec_coeff_ntt_square_toom3_threshold_16k`, `dec_coeff_ntt_square_toom3_threshold_32k`, `dec_coeff_ntt_square_toom3_threshold_64k`, `dec_coeff_ntt_square_toom3_threshold_8k`, `dec_coeff_ntt_square_toom3_threshold_large`, `dec_coeff_small_limit`, `dec_coeff_small_powers10`, `dec_coeff_toom3_threshold`, chosen per target in `coeff_thresholds_<target>.mbt` where they differ |

Preconditions are checked with `abort` (a negative shift, a zero divisor, a
subtraction that would go below zero, a unit divisor outside $[1, 10^9)$): they
are programmer errors of the caller, never conditions of an operation.

## Complete public interface

This snapshot is the generated `pkg.generated.mbti` of the package. It is the authority when prose and interface disagree.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/internal/decimal_kernel"

import {
  "moonbitlang/core/bigint",
  "moonbitlang/core/debug",
}

// Values
pub fn coefficient_rotate_digits_repr(DecCoeff, Int32, Int32) -> DecCoeff

pub fn coefficient_shift_digits_repr(DecCoeff, Int32, Int32) -> DecCoeff

pub fn compare_finite_magnitude_repr(DecCoeff, Int32, DecCoeff, Int32) -> Int32

pub fn dec_coeff_addend_rounding_step(Bool, Bool, Bool, Bool, Int32, DecCoeffRounding) -> Int32

pub let dec_coeff_base : Int32

pub let dec_coeff_burnikel_ziegler_threshold : Int32

pub let dec_coeff_burnikel_ziegler_threshold_16k : Int32

pub let dec_coeff_burnikel_ziegler_threshold_8k : Int32

pub let dec_coeff_burnikel_ziegler_threshold_large : Int32

pub fn dec_coeff_compare_half_power10(DecCoeff) -> Int32

pub fn dec_coeff_compare_repr(DecCoeff, DecCoeff) -> Int32

pub fn dec_coeff_compare_scaled_repr(DecCoeff, DecCoeff, Int32) -> Int32

pub fn dec_coeff_copy_limbs(DecCoeff) -> Array[UInt32]

pub fn dec_coeff_count_factor_unit_repr(DecCoeff, Int32) -> (DecCoeff, Int32)

pub fn dec_coeff_div_rem_burnikel_ziegler(DecCoeff, DecCoeff) -> (DecCoeff, DecCoeff)

pub fn dec_coeff_div_rem_by_unit_repr(DecCoeff, Int32) -> (DecCoeff, Int32)

pub fn dec_coeff_div_rem_knuth_repr(DecCoeff, DecCoeff) -> (DecCoeff, DecCoeff)

pub fn dec_coeff_div_rem_newton_try(DecCoeff, DecCoeff) -> (DecCoeff, DecCoeff)?

pub fn dec_coeff_div_rem_repr(DecCoeff, DecCoeff) -> (DecCoeff, DecCoeff)

pub let dec_coeff_dpun : Int32

pub fn dec_coeff_exact_nth_root_repr(DecCoeff, Int32) -> DecCoeff?

pub fn dec_coeff_exact_power_if_fits_repr(DecCoeff, Int32, Int32) -> DecCoeff?

pub fn dec_coeff_exact_power_repr(DecCoeff, Int32) -> DecCoeff

pub fn dec_coeff_floor_nth_root_repr(DecCoeff, Int32) -> DecCoeff

pub fn dec_coeff_from_bigint_repr(@bigint.BigInt) -> DecCoeff

pub fn dec_coeff_from_decimal_digits_repr(String) -> DecCoeff?

pub fn dec_coeff_from_int(Int32) -> DecCoeff

pub fn dec_coeff_from_int_magnitude(Int32) -> DecCoeff

pub fn dec_coeff_from_nonnegative_int(Int32) -> DecCoeff

pub fn dec_coeff_from_unit_accumulator(Array[UInt32], Int32) -> DecCoeff

pub fn dec_coeff_gcd_repr(DecCoeff, DecCoeff) -> DecCoeff

pub fn dec_coeff_huge_shift_rounded_unit(DecCoeff, Bool, DecCoeffRounding) -> DecCoeff

pub fn dec_coeff_integer_sqrt_rem_repr(DecCoeff) -> (DecCoeff, DecCoeff)

pub fn dec_coeff_is_odd(DecCoeff) -> Bool

pub let dec_coeff_karatsuba_square_threshold : Int32

pub let dec_coeff_karatsuba_threshold : Int32

pub fn dec_coeff_limb_at(DecCoeff, Int32) -> UInt32

pub fn dec_coeff_magnitude_add_repr(DecCoeff, DecCoeff) -> DecCoeff

pub fn dec_coeff_magnitude_add_unit(DecCoeff, Int32) -> DecCoeff

pub fn dec_coeff_magnitude_sub_repr(DecCoeff, DecCoeff) -> DecCoeff

pub fn dec_coeff_magnitude_sub_unit(DecCoeff, Int32) -> DecCoeff

pub fn dec_coeff_matches_unit_repr(DecCoeff, Int32) -> Bool

pub fn dec_coeff_mod_repr(DecCoeff, DecCoeff) -> DecCoeff

pub fn dec_coeff_multiply_by_unit_repr(DecCoeff, Int32) -> DecCoeff

pub fn dec_coeff_multiply_repr(DecCoeff, DecCoeff) -> DecCoeff

pub let dec_coeff_newton_enabled : Bool

pub let dec_coeff_newton_threshold : Int32

pub let dec_coeff_ntt_mul_threshold : Int32

pub let dec_coeff_ntt_mul_threshold_16k : Int32

pub let dec_coeff_ntt_mul_threshold_32k : Int32

pub let dec_coeff_ntt_mul_threshold_64k : Int32

pub let dec_coeff_ntt_mul_threshold_large : Int32

pub let dec_coeff_ntt_square_threshold : Int32

pub let dec_coeff_ntt_square_threshold_16k : Int32

pub let dec_coeff_ntt_square_threshold_32k : Int32

pub let dec_coeff_ntt_square_threshold_64k : Int32

pub let dec_coeff_ntt_square_threshold_8k : Int32

pub let dec_coeff_ntt_square_threshold_large : Int32

pub let dec_coeff_ntt_square_toom3_threshold : Int32

pub let dec_coeff_ntt_square_toom3_threshold_16k : Int32

pub let dec_coeff_ntt_square_toom3_threshold_32k : Int32

pub let dec_coeff_ntt_square_toom3_threshold_64k : Int32

pub let dec_coeff_ntt_square_toom3_threshold_8k : Int32

pub let dec_coeff_ntt_square_toom3_threshold_large : Int32

pub fn dec_coeff_pow_unit_repr(Int32, Int32) -> DecCoeff

pub fn dec_coeff_power10_repr(Int32) -> DecCoeff

pub fn dec_coeff_round_div(DecCoeff, DecCoeff, Bool, DecCoeffRounding) -> DecCoeff

pub fn dec_coeff_round_div_bigint(@bigint.BigInt, @bigint.BigInt, Bool, DecCoeffRounding) -> @bigint.BigInt

pub fn dec_coeff_round_div_expansion(DecCoeff, DecCoeff, Bool, DecCoeffRounding) -> (DecCoeff, Bool)

pub fn dec_coeff_round_div_pow10(DecCoeff, Int32, Bool, DecCoeffRounding) -> (DecCoeff, Bool)

pub fn dec_coeff_round_div_pow10_owned(Array[UInt32], Int32, Int32, Bool, DecCoeffRounding) -> (DecCoeff, Bool)

pub fn dec_coeff_round_to_digits(DecCoeff, Int32, Int32, Bool, DecCoeffRounding) -> (DecCoeff, Int32, Bool, Bool)

pub fn dec_coeff_shift_power10_mod_repr(DecCoeff, Int32, DecCoeff) -> DecCoeff

pub fn dec_coeff_shift_power10_mod_wide_repr(DecCoeff, Int64, DecCoeff) -> DecCoeff

pub fn dec_coeff_shift_power10_repr(DecCoeff, Int32) -> DecCoeff

pub fn dec_coeff_should_increment(DecCoeff, DecCoeff, DecCoeff, Bool, DecCoeffRounding) -> Bool

pub fn dec_coeff_signed_add_repr(Bool, DecCoeff, Bool, DecCoeff) -> (Bool, DecCoeff)

pub fn dec_coeff_signed_compare_int_repr(Bool, DecCoeff, Int32) -> Int32

pub fn dec_coeff_signed_step_unit_repr(Bool, DecCoeff, Bool) -> (Bool, DecCoeff)

pub fn dec_coeff_slice(DecCoeff, Int32, Int32) -> DecCoeff

pub fn dec_coeff_small_digits(UInt64) -> Int32

pub let dec_coeff_small_limit : UInt64

pub let dec_coeff_small_powers10 : Array[UInt64]

pub fn dec_coeff_small_value(DecCoeff) -> UInt64?

pub fn dec_coeff_sqrt_should_increment(DecCoeff, Int32, Bool, DecCoeffRounding) -> Bool

pub fn dec_coeff_square_repr(DecCoeff) -> DecCoeff

pub fn dec_coeff_to_bigint_repr(DecCoeff) -> @bigint.BigInt

pub fn dec_coeff_to_bounded_int(DecCoeff, Int32) -> Int32?

pub let dec_coeff_toom3_threshold : Int32

pub fn dec_coeff_unit_add_sub(Array[UInt32], Int32, Array[UInt32], Int32, Int32, Array[UInt32], Int32) -> Int32

pub fn dec_coeff_unit_len(DecCoeff) -> Int32

pub fn dec_coeff_zero() -> DecCoeff

pub fn decimal_floor_div_scaled_repr(Bool, DecCoeff, DecCoeff) -> Int32

pub fn decimal_ln_atanh_scaled_coeff(DecCoeff, DecCoeff, Int32) -> SignedDecCoeff

pub fn decimal_round_scaled_coeff(SignedDecCoeff, Int32) -> SignedDecCoeff

pub fn decimal_small_pow10(Int32) -> Int32

pub fn exact_divide_by_power_of_ten_repr(DecCoeff, Int32) -> DecCoeff?

pub fn has_finite_decimal_expansion_repr(DecCoeff, DecCoeff) -> Bool

pub fn is_power_of_ten_coeff(DecCoeff) -> Bool

pub fn logical_binary_digits_repr(DecCoeff, DecCoeff, Int32, (Bool, Bool) -> Bool) -> DecCoeff

pub fn logical_coeff_digits_lsd(DecCoeff, Int32) -> Array[Int32]

pub fn logical_coeff_from_digits_lsd(Array[Int32]) -> DecCoeff

pub fn remove_factor10_repr(DecCoeff, Int32) -> (DecCoeff, Int32)

pub fn signed_dec_coeff(Bool, DecCoeff) -> SignedDecCoeff

pub fn signed_dec_coeff_from_int_product(Int32, DecCoeff) -> SignedDecCoeff

pub fn trim_trailing_decimal_zeros_repr(DecCoeff, Int32, max_drop? : Int32) -> (DecCoeff, Int32, Int32)

// Errors

// Types and methods
#derive(@debug.Debug)
pub(all) enum DecCoeff {
  Small(UInt64)
  Limbs(Array[UInt32], Int32)
}
pub fn DecCoeff::digits10(Self) -> Int32
pub fn DecCoeff::is_zero(Self) -> Bool
pub fn DecCoeff::to_bigint(Self) -> @bigint.BigInt
pub fn DecCoeff::to_string(Self) -> String

#derive(Eq)
pub(all) enum DecCoeffRounding {
  HalfEven
  HalfUp
  HalfDown
  Down
  Ceiling
  Floor
  Up
  ZeroFiveUp
}

pub struct SignedDecCoeff {
  negative : Bool
  magnitude : DecCoeff
}
pub fn SignedDecCoeff::add(Self, Self) -> Self
pub fn SignedDecCoeff::neg(Self) -> Self
pub fn SignedDecCoeff::sub(Self, Self) -> Self

// Type aliases

// Traits
```
<!-- generated-api-end -->
