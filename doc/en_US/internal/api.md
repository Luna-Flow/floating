# @internal

This page tracks the `0.6.0` implementation helper API, not a stable
application contract.

`@internal` is an implementation-facing package. Its functions are documented here for maintainers and advanced contributors, not as a stable public API promise.

---

## BigInt Helpers

- **`fn bigint_zero() -> BigInt`**
  Returns `0` as a `BigInt`.

- **`fn bigint_one() -> BigInt`**
  Returns `1` as a `BigInt`.

- **`fn abs_bigint(x : BigInt) -> BigInt`**
  Returns the absolute value of `x`.

- **`fn sign_of_bigint(x : BigInt) -> Sign`**
  Converts a `BigInt` sign into `Sign::Negative`, `Sign::Zero`, or `Sign::Positive`.

---

## Power Helpers

- **`fn pow2(n : Int) -> BigInt`**
  Returns `2^n`. Rejects negative `n`.

- **`fn pow5(n : Int) -> BigInt`**
  Returns `5^n`. Rejects negative `n`.

- **`fn pow10(n : Int) -> BigInt`**
  Returns `10^n`. Rejects negative `n`.

- **`fn digits10(x : BigInt) -> Int`**
  Returns the decimal digit count of the absolute value of `x`.

---

## Normalization Helpers

- **`fn remove_factor2(sig : BigInt, exp : Int) -> (BigInt, Int)`**
  Removes all factors of `2` from `sig` and compensates them into the returned exponent.

- **`fn remove_factor10(coeff : BigInt, exp : Int) -> (BigInt, Int)`**
  Removes all factors of `10` from `coeff` and compensates them into the returned exponent.

- **`fn exact_divide_by_power_of_ten(value : BigInt, exponent : Int) -> BigInt?`**
  Returns the exact quotient when `value` is divisible by `10^exponent`; otherwise returns `None`.

- **`fn trim_trailing_decimal_zeros(value : BigInt, exponent : Int, max_drop? : Int) -> (BigInt, Int, Int)`**
  Removes at most `max_drop` trailing decimal zeros, adjusts the exponent, and reports the number removed.

---

## Rounding Helpers

- **`fn round_positive_div(numerator : BigInt, denominator : BigInt, negative : Bool, mode : RoundingMode) -> BigInt`**
  Rounds the positive quotient `numerator / denominator` according to `mode`. The `negative` flag lets the routine interpret directed rounding correctly for signed values.

- **`fn round_shift(magnitude : BigInt, shift : Int, negative : Bool, mode : RoundingMode) -> BigInt`**
  Rounds a right-shift-by-`shift` operation on a non-negative magnitude.

- **`fn compare_abs(a : BigInt, b : BigInt) -> Int`**
  Compares absolute values only.

---

## Decimal Parsing Helper

- **`fn split_decimal_string(src : String) -> (Bool, String, Int)?`**
  Splits a decimal string into:
  - sign flag
  - digit string without separators
  - base-10 exponent adjustment

It accepts plain decimals and scientific notation in the currently implemented parser.

## Complete Public Interface

The following snapshot is the complete generated package interface for `0.6.0`. Public declarations are authoritative; prose above groups them by behavior.

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/internal"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/def",
  "moonbitlang/core/bigint",
}

// Values
pub fn abs_bigint(@bigint.BigInt) -> @bigint.BigInt

pub fn bigint_one() -> @bigint.BigInt

pub fn bigint_zero() -> @bigint.BigInt

pub fn compare_abs(@bigint.BigInt, @bigint.BigInt) -> Int

pub fn digits10(@bigint.BigInt) -> Int

pub fn exact_divide_by_power_of_ten(@bigint.BigInt, Int) -> @bigint.BigInt?

pub fn pow10(Int) -> @bigint.BigInt

pub fn pow2(Int) -> @bigint.BigInt

pub fn pow5(Int) -> @bigint.BigInt

pub fn remove_factor10(@bigint.BigInt, Int) -> (@bigint.BigInt, Int)

pub fn remove_factor2(@bigint.BigInt, Int) -> (@bigint.BigInt, Int)

pub fn[A, B, E, C] result_lift2(Result[A, E], Result[B, E], (A, B) -> C) -> Result[C, E]

pub fn[A, B, E, C] result_lift2_checked(Result[A, E], Result[B, E], (A, B) -> Result[C, E]) -> Result[C, E]

pub fn round_positive_div(@bigint.BigInt, @bigint.BigInt, Bool, @arithmetic.RoundingMode) -> @bigint.BigInt

pub fn round_shift(@bigint.BigInt, Int, Bool, @arithmetic.RoundingMode) -> @bigint.BigInt

pub fn sign_of_bigint(@bigint.BigInt) -> @def.Sign

pub fn split_decimal_string(String) -> (Bool, String, Int)?

pub fn trim_trailing_decimal_zeros(@bigint.BigInt, Int, max_drop? : Int) -> (@bigint.BigInt, Int, Int)

// Errors

// Types and methods
pub struct ExactRat {
  // private fields
} derive(Eq)
pub fn ExactRat::denominator(Self) -> @bigint.BigInt
pub fn ExactRat::new(@bigint.BigInt, @bigint.BigInt) -> Self
pub fn ExactRat::numerator(Self) -> @bigint.BigInt

// Type aliases

// Traits
```
<!-- generated-api-end -->
