// `exp2m1`, `exp10m1`, `log2p1` and `log10p1` of IEEE 754-2019 9.2 (Table 9.1:
// 2^x - 1, 10^x - 1, log2(1 + x), log10(1 + x)), on the certified enclosures of
// `expm1` and `log1p` and the shared layer of `elementary_range.mbt`.
//
// 9.2.1: "For the operations sin, tan, sinPi, tanPi, asin, atan, asinPi, atanPi,
// sinh, tanh, asinh, atanh, expm1, exp2m1, exp10m1, logp1, log2p1, and log10p1,
// f (+0) is +0 and f (−0) is −0 with no exception." "For the operations expm1,
// exp2m1, and exp10m1, f (+∞) is +∞ and f (−∞) is −1 with no exception." "For
// the operations log, log2, log10, logp1, log2p1, and log10p1, f (+∞) is +∞
// with no exception." "For the operations logp1, log2p1, and log10p1, f (−1) is
// −∞ and signals the divideByZero exception." Table 9.1: log2p1 and log10p1 have
// domain [−1, +∞], "x < −1: invalid operation; underflow".

///|
fn binary_exp_base_minus_one_bounds(
  value : Binary,
  ln_base_bounds : (Int32) -> (Binary, Binary)?,
  work_precision : Int32,
) -> (Binary, Binary)? {
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  guard ln_base_bounds(work_precision) is Some(ln_base) else { return None }
  let value_bounds = (
    value.with_precision_raw(
      work_precision,
      BinaryRoundingMode::RoundTowardNegative,
    ),
    value.with_precision_raw(
      work_precision,
      BinaryRoundingMode::RoundTowardPositive,
    ),
  )
  let scaled = binary_product_bounds(value_bounds, ln_base, downward, upward)
  binary_bounds_at_ends(scaled.0, scaled.1, fn(point) {
    binary_expm1_bounds(point, work_precision)
  })
}

///|
fn binary_log_base_p1_bounds(
  value : Binary,
  ln_base_bounds : (Int32) -> (Binary, Binary)?,
  work_precision : Int32,
) -> (Binary, Binary)? {
  let downward = binary_working_context(
    work_precision,
    rounding=RoundTowardNegative,
  )
  let upward = binary_working_context(
    work_precision,
    rounding=RoundTowardPositive,
  )
  guard ln_base_bounds(work_precision) is Some(ln_base) &&
    binary_log1p_bounds(value, work_precision) is Some(logarithm) else {
    return None
  }
  binary_quotient_bounds(logarithm, ln_base, downward, upward)
}

///|
/// `x = 2^k - 1` (so `1 + x = 2^k`) for a finite nonzero `x > -1`: `k`. For
/// `x > 0` this is an odd integer `c` with `c + 1` a power of two; for
/// `x < 0` it is `-(1 - 2^e)`, `c = 2^|e| - 1`, and then `k = e`.
fn binary_log2p1_exact_exponent(value : Binary) -> Int32? {
  let coefficient = value.coefficient_()
  let next = coefficient.add(Coeff::one())
  let power_of_two = next.shift_right(next.ctz()).compare(Coeff::one()) == 0
  if !value.is_sign_minus() {
    if value.exponent2() == 0 && power_of_two {
      Some(next.bit_length() - 1)
    } else {
      None
    }
  } else if value.exponent2() < 0 &&
    power_of_two &&
    next.bit_length() - 1 == -value.exponent2() {
    Some(value.exponent2())
  } else {
    None
  }
}

///|
/// `x = 10^k - 1` for a positive integer `x` (an odd `c` with exponent 0):
/// `k`, found by comparing `c + 1` with the powers of ten of the right size.
fn binary_log10p1_exact_exponent(value : Binary) -> Int32? {
  if value.is_sign_minus() || value.exponent2() != 0 {
    return None
  }
  let next = value.coefficient_().add(Coeff::one())
  let estimate = (next.bit_length() - 1) * 30103 / 100000
  for k in estimate..<=(estimate + 1) {
    if k > 0 &&
      Coeff::from_uint64(10UL).pow_nat(k.reinterpret_as_uint()).compare(next) ==
      0 {
      return Some(k)
    }
  }
  None
}

///|
/// Shared `try_*` body of `exp2m1` and `exp10m1` for a finite nonzero `x`.
fn binary_try_exp_base_minus_one(
  operation : String,
  value : Binary,
  saturation_limit : Int32,
  saturation_is_third : Bool,
  base_is_two : Bool,
  scale_bounds : () -> (Binary, Binary)?,
  ln_base_bounds : (Int32) -> (Binary, Binary)?,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  // 2^x - 1 = -1 + d with d < 2^-(p + 3) once x <= -(p + 3); for 10^x it is
  // enough that x <= -ceil((p + 3) / 3), as 10^(-1/3) < 1/2.
  if value.is_sign_minus() {
    let limit = if saturation_is_third {
      -((saturation_limit + 2) / 3)
    } else {
      -saturation_limit
    }
    if value.compare(Binary::from_int_raw(limit, precision=53)) <= 0 {
      return Ok(binary_saturated_minus_one(context))
    }
  }
  match
    binary_positive_exp_minus_one_overflow(
      value, scale_bounds, 2, base_is_two, context,
    ) {
    Some(result) => return Ok(result)
    None => ()
  }
  binary_ziv_round(
    operation,
    context,
    fn(work) { binary_exp_base_minus_one_bounds(value, ln_base_bounds, work) },
    edge_side=fn(work) {
      if base_is_two {
        // 2^x - 1 >= 2^(e_max + 1) once x exceeds e_max + 1 (an integer x was
        // decided above); compared exactly: a float above e_max + 1 = 2^30 is at
        // least one unit in the last place of the argument above it, at least
        // 2^-(precision of x) beyond `T' = log2(2^(e_max + 1) + 1)`, which lies
        // above 2^30 by less than 2^-(2^30).
        Some(
          value.compare(
            Binary::from_int_raw(binary_implementation_e_max + 1, precision=32),
          ) >
          0,
        )
      } else {
        // 10^x - 1 < 10^x: "at or above" carries the margin of the side function.
        binary_exp_overflow_side(value, work, decimal=true, inexact_above=true)
      }
    },
  )
}

///|
pub fn Binary::try_exp2m1_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  match binary_nan_unary(self, context) {
    Some(result) => return Ok(result)
    None => ()
  }
  match self.class() {
    FpClass::NaN => abort("unreachable exp2m1 NaN")
    FpClass::Infinity =>
      Ok(
        (
          if self.is_sign_minus() {
            Binary::one_raw(precision=context.precision).neg()
          } else {
            Binary::inf_raw(Sign::Positive, precision=context.precision)
          },
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite if self.is_zero() => Ok(self.apply_ctx(context))
    FpClass::Finite => {
      match binary_exact_bounded_int(self) {
        Some(n) => return Ok(binary_pow2_minus_one_integer(n, context))
        None => ()
      }
      binary_try_exp_base_minus_one(
        "exp2m1",
        self,
        context.precision + 3,
        false,
        true,
        fn() {
          let unit = Binary::one_raw(precision=binary_range_check_precision)
          Some((unit, unit))
        },
        fn(work) { binary_ln2_bounds(work) },
        context,
      )
    }
  }
}

///|
pub fn Binary::exp2m1_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_exp2m1_ctx(context), context)
}

///|
pub fn Binary::exp2m1(self : Binary) -> Binary {
  self.exp2m1_ctx(binary_working_context(self.precision())).0
}

///|
pub fn Binary::try_exp10m1_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  match binary_nan_unary(self, context) {
    Some(result) => return Ok(result)
    None => ()
  }
  match self.class() {
    FpClass::NaN => abort("unreachable exp10m1 NaN")
    FpClass::Infinity =>
      Ok(
        (
          if self.is_sign_minus() {
            Binary::one_raw(precision=context.precision).neg()
          } else {
            Binary::inf_raw(Sign::Positive, precision=context.precision)
          },
          BinaryFlags::new(),
        ),
      )
    FpClass::Finite if self.is_zero() => Ok(self.apply_ctx(context))
    FpClass::Finite => {
      // 10^n - 1 for a small integer n >= 1 is an exact integer, whose
      // rounding is exact or a tie; a larger power is left to the loop, as for
      // exp10.
      match binary_exact_bounded_int(self) {
        Some(n) if n >= 1 && n <= Int32::max(4096, context.precision) =>
          return Ok(
            binary_round_dyadic(
              false,
              Coeff::from_uint64(10UL)
              .pow_nat(n.reinterpret_as_uint())
              .sub_checked(Coeff::one())
              .unwrap(),
              0,
              context,
            ),
          )
        _ => ()
      }
      binary_try_exp_base_minus_one(
        "exp10m1",
        self,
        context.precision + 3,
        true,
        false,
        binary_log2_10_bounds,
        fn(work) { binary_ln10_bounds(work) },
        context,
      )
    }
  }
}

///|
pub fn Binary::exp10m1_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_exp10m1_ctx(context), context)
}

///|
pub fn Binary::exp10m1(self : Binary) -> Binary {
  self.exp10m1_ctx(binary_working_context(self.precision())).0
}

///|
/// Shared `try_*` body of `log2p1` and `log10p1`.
fn binary_try_log_base_p1(
  operation : String,
  value : Binary,
  exact_exponent : (Binary) -> Int32?,
  ln_base_bounds : (Int32) -> (Binary, Binary)?,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  match binary_nan_unary(value, context) {
    Some(result) => return Ok(result)
    None => ()
  }
  match value.class() {
    FpClass::NaN => abort("unreachable " + operation + " NaN")
    FpClass::Infinity =>
      if value.is_sign_minus() {
        Ok(
          (Binary::nan_raw(precision=context.precision), binary_invalid_flags()),
        )
      } else {
        Ok(
          (
            Binary::inf_raw(Sign::Positive, precision=context.precision),
            BinaryFlags::new(),
          ),
        )
      }
    FpClass::Finite => {
      let minus_one = Binary::one_raw(precision=value.precision()).neg()
      let comparison = value.compare(minus_one)
      if comparison < 0 {
        return Ok(binary_invalid_value(context))
      }
      if comparison == 0 {
        return Ok(binary_pole_result(true, context))
      }
      if value.is_zero() {
        return Ok(value.apply_ctx(context))
      }
      match exact_exponent(value) {
        Some(k) => return Ok(binary_integer_result(k, context))
        None => ()
      }
      binary_ziv_round(operation, context, fn(work) {
        binary_log_base_p1_bounds(value, ln_base_bounds, work)
      })
    }
  }
}

///|
pub fn Binary::try_log2p1_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  binary_try_log_base_p1(
    "log2p1",
    self,
    binary_log2p1_exact_exponent,
    fn(work) { binary_ln2_bounds(work) },
    context,
  )
}

///|
pub fn Binary::log2p1_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_log2p1_ctx(context), context)
}

///|
pub fn Binary::log2p1(self : Binary) -> Binary {
  self.log2p1_ctx(binary_working_context(self.precision())).0
}

///|
pub fn Binary::try_log10p1_ctx(
  self : Binary,
  context : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  binary_try_log_base_p1(
    "log10p1",
    self,
    binary_log10p1_exact_exponent,
    fn(work) { binary_ln10_bounds(work) },
    context,
  )
}

///|
pub fn Binary::log10p1_ctx(
  self : Binary,
  context : BinaryContext,
) -> (Binary, BinaryFlags) {
  binary_defined_or_nan(self.try_log10p1_ctx(context), context)
}

///|
pub fn Binary::log10p1(self : Binary) -> Binary {
  self.log10p1_ctx(binary_working_context(self.precision())).0
}
