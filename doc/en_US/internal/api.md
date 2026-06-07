# @internal

This page tracks the current repository implementation and is written as the `0.2.0` API baseline.

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
