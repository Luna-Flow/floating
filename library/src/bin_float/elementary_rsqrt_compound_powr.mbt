// `rsqrt` (rSqrt), `compound` and `powr` of IEEE 754-2019 9.2 (Table 9.1:
// 1/sqrt(x), (1 + x)^n, x^y for x >= 0), on the certified `rootn`, `pown` and
// `pow` machinery and the shared layer of `elementary_range.mbt`.
//
// 9.2.1: "rSqrt(+∞) is +0 with no exception. rSqrt(±0) is ±∞ and signals the
// divideByZero exception."
//
// 9.2.1, for the compound operation: "compound (x, 0) is 1 for x ≥ −1 or quiet
// NaN"; "compound (−1, n) is +∞ and signals the divideByZero exception for
// n < 0"; "compound (−1, n) is +0 for n > 0"; "compound (±0, n) is 1";
// "compound (+∞, n) is +∞ for n > 0"; "compound (+∞, n) is +0 for n < 0";
// "compound (x, n) is qNaN and signals the invalid operation exception for
// x < −1"; "compound (qNaN, n) is qNaN for n ≠ 0".
//
// 9.2.1, for the powr operation: "powr (x, ±0) is 1 for finite x > 0"; "powr
// (±0, y) is +∞ and signals the divideByZero exception for finite y < 0"; "powr
// (±0, −∞) is +∞"; "powr (±0, y) is +0 for y > 0"; "powr (+1, y) is 1 for
// finite y"; "powr (x, y) signals the invalid operation exception for x < 0";
// "powr (±0, ±0) signals the invalid operation exception"; "powr (+∞, ±0)
// signals the invalid operation exception"; "powr (+1, ±∞) signals the invalid
// operation exception"; "powr (x, qNaN) is qNaN for x ≥ 0"; "powr (qNaN, y) is
// qNaN."

///|
/// 1 / sqrt(x). Positive finite `x` is `rootn(x, -2)`, whose exact case
/// (a power of 4) and range handling it shares.
pub fn BinFloat::try_rsqrt_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  match binary_nan_unary(self, context) {
    Some(result) => return Ok(result)
    None => ()
  }
  match self.class() {
    FpClass::NaN => abort("unreachable rsqrt NaN")
    FpClass::Infinity =>
      if self.is_negative() {
        Ok(binary_invalid_value(context))
      } else {
        Ok(
          (BinFloat::zero_raw(precision=context.precision), BinaryFlags::new()),
        )
      }
    FpClass::Finite if self.is_zero() =>
      Ok(binary_pole_result(self.is_negative(), context))
    FpClass::Finite if self.is_negative() => Ok(binary_invalid_value(context))
    FpClass::Finite => self.try_rootn_ctx(-2, context)
  }
}

///|
pub fn BinFloat::rsqrt_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  binary_defined_or_nan(self.try_rsqrt_ctx(context), context)
}

///|
pub fn BinFloat::rsqrt(self : BinFloat) -> BinFloat {
  self.rsqrt_ctx(binary_working_context(self.precision())).0
}

///|
/// The result of `compound(x, n)` for a finite `x > -1` with `|n x| < 2^-(p + 9)`:
/// `1 + delta`, `delta` of the sign of `n x` and below a quarter of the spacing
/// next to 1, so the rounding direction alone decides between 1 and its
/// neighbour. The representative `1 +- 2^-(p + 3)` rounds alike in every
/// direction (always inexact, never underflow).
fn binary_compound_tiny_result(
  positive_delta : Bool,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  let p = context.precision
  let base = Coeff::one().shift_left(p + 3)
  binary_round_dyadic(
    false,
    if positive_delta {
      base.add(Coeff::one())
    } else {
      base.sub_checked(Coeff::one()).unwrap()
    },
    -(p + 3),
    context,
  )
}

///|
/// `(1 + x)^n` for a finite `x > -1`, `x != 0`, `n != 0`.
fn binary_compound_general(
  value : BinFloat,
  degree : Int32,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  let p = context.precision.to_int64()
  let top = value.exact_top().to_int64()
  // |n x| < 2^31 * 2^(top + 1) <= 2^-(p + 9): 1 + n x is just beside 1.
  if top + 32L < -(p + 9L) {
    return Ok(
      binary_compound_tiny_result(value.is_negative() == (degree < 0), context),
    )
  }
  // 1 + x exactly, while it fits: then it is `pown` of an exact base, which
  // owns the exact cases, the range decision and the rounding.
  let integer_bits = Int64::max(top, 0L) + 1L
  let fraction_bits = if value.exponent2_() < 0 {
    -value.exponent2_().to_int64()
  } else {
    0L
  }
  let width = integer_bits + fraction_bits + 1L
  if width <= 67108864L {
    let exact = BinFloat::one_raw(precision=width.to_int()).add_ctx(
        value,
        binary_working_context(width.to_int()),
      ).0
    return Ok(exact.pown_ctx(degree, context))
  }
  // A base wider than that is not representable in the context, and neither
  // is a power of it: the result is inexact. For n = 1 the sum is rounded as
  // such; certain overflow and underflow follow from log2(1 + x) > top.
  if degree == 1 {
    return Ok(
      BinFloat::one_raw(precision=context.precision).add_ctx(value, context),
    )
  }
  let reach = top * degree.to_int64()
  if degree > 0 && reach >= context.range_e_max().to_int64() + 1L {
    return Ok(binary_overflow_result(false, context))
  }
  if degree < 0 &&
    reach < context.range_e_min().to_int64() - context.precision.to_int64() {
    return Ok(binary_tiny_nonzero_result(false, context))
  }
  let argument = Ref((BinFloat::zero_raw(), BinFloat::zero_raw()))
  binary_ziv_round(
    "compound",
    context,
    fn(work) {
      let downward = binary_working_context(work, rounding=RoundTowardNegative)
      let upward = binary_working_context(work, rounding=RoundTowardPositive)
      guard binary_log1p_bounds(value, work) is Some(logarithm) else {
        return None
      }
      let count = BinFloat::from_int_raw(degree, precision=32)
      let scaled = binary_product_bounds(
        logarithm,
        (count, count),
        downward,
        upward,
      )
      argument.val = scaled
      binary_bounds_at_ends(scaled.0, scaled.1, fn(point) {
        binary_exp_bounds(point, work)
      })
    },
    edge_side=fn(work) {
      binary_exp_interval_overflow_side(argument.val.0, argument.val.1, work)
    },
  )
}

///|
/// `(1 + x)^n`, the compound factor (IEEE 754-2019 9.2).
pub fn BinFloat::try_compound_ctx(
  self : BinFloat,
  degree : Int32,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  let one = BinFloat::one_raw(precision=context.precision)
  match self.class() {
    FpClass::NaN =>
      if self.signaling() {
        Ok((binary_quiet_nan(self, context.precision), binary_invalid_flags()))
      } else if degree == 0 {
        Ok((one, BinaryFlags::new()))
      } else {
        Ok((binary_quiet_nan(self, context.precision), BinaryFlags::new()))
      }
    FpClass::Infinity =>
      if self.is_negative() {
        Ok(binary_invalid_value(context))
      } else if degree == 0 {
        Ok((one, BinaryFlags::new()))
      } else if degree > 0 {
        Ok(
          (
            BinFloat::inf_raw(Sign::Positive, precision=context.precision),
            BinaryFlags::new(),
          ),
        )
      } else {
        Ok(
          (BinFloat::zero_raw(precision=context.precision), BinaryFlags::new()),
        )
      }
    FpClass::Finite => {
      let minus_one = BinFloat::one_raw(precision=self.precision()).neg()
      let comparison = self.compare(minus_one)
      if comparison < 0 {
        return Ok(binary_invalid_value(context))
      }
      if degree == 0 || self.is_zero() {
        return Ok((one, BinaryFlags::new()))
      }
      if comparison == 0 {
        return if degree < 0 {
          Ok(binary_pole_result(false, context))
        } else {
          Ok(
            (
              BinFloat::zero_raw(precision=context.precision),
              BinaryFlags::new(),
            ),
          )
        }
      }
      binary_compound_general(self, degree, context)
    }
  }
}

///|
pub fn BinFloat::compound_ctx(
  self : BinFloat,
  degree : Int32,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  binary_defined_or_nan(self.try_compound_ctx(degree, context), context)
}

///|
pub fn BinFloat::compound(self : BinFloat, degree : Int32) -> BinFloat {
  self.compound_ctx(degree, binary_working_context(self.precision())).0
}

///|
/// `x^y` for `x >= 0` (IEEE 754-2019 9.2: "powr(x, y) is defined by considering
/// exp(y × log(x)), and thus its domain excludes negative x"). The table of
/// 9.2.1 is decided here; a positive `x` and a finite nonzero `y` are `pow`.
pub fn BinFloat::try_powr_ctx(
  self : BinFloat,
  exponent : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  // A signaling NaN first (7.2 a), then a quiet NaN base, then the domain.
  if self.is_signaling_nan() || exponent.is_signaling_nan() {
    match binary_nan_pair(self, exponent, context.precision) {
      Some(result) => return Ok(result)
      None => ()
    }
  }
  if self.class() == FpClass::NaN {
    return Ok((binary_quiet_nan(self, context.precision), BinaryFlags::new()))
  }
  if self.is_negative() && !self.is_zero() {
    return Ok(binary_invalid_value(context))
  }
  if exponent.class() == FpClass::NaN {
    return Ok(
      (binary_quiet_nan(exponent, context.precision), BinaryFlags::new()),
    )
  }
  let one = BinFloat::one_raw(precision=context.precision)
  let y_zero = exponent.classify() == FpClass::Finite && exponent.is_zero()
  let y_infinite = exponent.classify() == FpClass::Infinity
  if self.classify() == FpClass::Finite && self.is_zero() {
    // powr(+-0, y)
    if y_zero {
      return Ok(binary_invalid_value(context))
    }
    if y_infinite && exponent.is_negative() {
      return Ok(
        (
          BinFloat::inf_raw(Sign::Positive, precision=context.precision),
          BinaryFlags::new(),
        ),
      )
    }
    if exponent.is_negative() {
      return Ok(binary_pole_result(false, context))
    }
    return Ok(
      (BinFloat::zero_raw(precision=context.precision), BinaryFlags::new()),
    )
  }
  if self.classify() == FpClass::Infinity {
    // powr(+inf, y)
    if y_zero {
      return Ok(binary_invalid_value(context))
    }
    return Ok(
      if exponent.is_negative() {
        (BinFloat::zero_raw(precision=context.precision), BinaryFlags::new())
      } else {
        (
          BinFloat::inf_raw(Sign::Positive, precision=context.precision),
          BinaryFlags::new(),
        )
      },
    )
  }
  // x > 0 and finite
  if self.compare(BinFloat::one_raw(precision=self.precision())) == 0 {
    if y_infinite {
      return Ok(binary_invalid_value(context))
    }
    return Ok((one, BinaryFlags::new()))
  }
  if y_zero {
    return Ok((one, BinaryFlags::new()))
  }
  self.try_pow_ctx(exponent, context)
}

///|
pub fn BinFloat::powr_ctx(
  self : BinFloat,
  exponent : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  binary_defined_or_nan(self.try_powr_ctx(exponent, context), context)
}

///|
pub fn BinFloat::powr(self : BinFloat, exponent : BinFloat) -> BinFloat {
  self.powr_ctx(
    exponent,
    binary_working_context(Int32::max(self.precision(), exponent.precision())),
  ).0
}
