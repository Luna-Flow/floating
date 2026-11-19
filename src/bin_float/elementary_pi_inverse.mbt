// `asinpi`, `acospi`, `atanpi` and `atan2pi` (asinPi, acosPi, atanPi, atan2Pi)
// of IEEE 754-2019 9.2: the inverse circular functions with the angle measured
// in half-revolutions, asin(x)/π, acos(x)/π, atan(x)/π and atan2(y, x)/π.
//
// Table 9.1: "asinPi asin(x)/π [−1, +1] |x| > 1: invalid operation; underflow",
// "acosPi acos(x)/π [−1, +1] |x| > 1: invalid operation", "atanPi atan(x)/π
// [−∞, +∞] underflow", "atan2Pi(y, x) see 9.2.1 [−∞, +∞] × [−∞, +∞] underflow".
//
// 9.2.1: "For the operations sin, tan, sinPi, tanPi, asin, atan, asinPi, atanPi,
// ... f (+0) is +0 and f (−0) is −0 with no exception." "acos(1), acosPi(1), and
// acosh(1) are +0." "atanPi(±∞) is ±½ with no exception." "atan2Pi(y, x) is the
// angle subtended at the origin by the point (x, y) and the positive x-axis.
// The range of atan2Pi is [−1, +1]." "For y with positive sign bit, the general
// cases of atan2Pi(y, x) for finite non-zero numeric x are correctly rounded
// from the following expressions: atan2Pi(y, x) for finite x > 0 is
// atan(|y/x|)/π, which could signal the underflow exception; atan2Pi(y, x) for
// finite x < 0 is 1 − atan(|y/x|)/π. The special cases of atan2Pi(y, x)
// involving 0 and ∞ are exact constants that signal no exception:
// atan2Pi(±0, −0) is ±1; atan2Pi(±0, +0) is ±0; atan2Pi(±0, x) is ±1 for x < 0;
// atan2Pi(±0, x) is ±0 for x > 0; atan2Pi(y, ±0) is −½ for y < 0; atan2Pi(y, ±0)
// is +½ for y > 0; atan2Pi(±y, −∞) is ±1 for finite y > 0; atan2Pi(±y, +∞) is ±0
// for finite y > 0; atan2Pi(±∞, x) is ±½ for finite x; atan2Pi(±∞, −∞) is ±¾;
// atan2Pi(±∞, +∞) is ±¼."
//
// Exact values. By Niven's theorem, asin(x)/π, acos(x)/π and atan(x)/π are
// rational for a rational x only at x = 0, ±1/2, ±1 (asin, acos) and x = 0, ±1
// (atan); the dyadic ones are the constants above and atanPi(±1) = ±1/4,
// atan2Pi(±a, ±a) = ±1/4 or ±3/4. asinPi(±1/2) = ±1/6 and acosPi(±1/2) = 1/3,
// 2/3 are rational but not dyadic, so they are never a rounding breakpoint and
// go through the Ziv loop like every other value. Every other finite argument
// gives an inexact result, which is what the Ziv driver of
// `elementary_range.mbt` requires.
//
// Range decisions (the defect class of #271 to #316). The result of a function
// is never built by `BinFloat::make`; exact results are rounded as dyadics, and
// the results that cluster at a representable anchor are decided from a
// certified distance to it by `binary_tiny_argument_result` before the Ziv loop
// (atanPi(x) = ±1/2 ∓ δ for a huge |x|; acosPi(x) = 1/2 ∓ δ for a tiny |x|;
// atan2Pi(y, x) at the anchors ±1/2 and ±1 for the extreme ratios |y/x|, whose
// exponent can lie beyond the exponent range of the working precision).

///|
/// The enclosure of `angle / π` from an enclosure of the angle and of π, both
/// at the working precision `work` (directed divisions).
fn binary_pi_scaled_enclosure(
  angle : (BinFloat, BinFloat),
  pi : (BinFloat, BinFloat),
  work : Int32,
) -> (BinFloat, BinFloat) {
  let downward = BinaryContext::unbounded(work, rounding=RoundTowardNegative)
  let upward = BinaryContext::unbounded(work, rounding=RoundTowardPositive)
  let lower = if angle.0.is_negative() {
    angle.0.div_ctx(pi.0, downward).0
  } else {
    angle.0.div_ctx(pi.1, downward).0
  }
  let upper = if angle.1.is_negative() {
    angle.1.div_ctx(pi.1, upward).0
  } else {
    angle.1.div_ctx(pi.0, upward).0
  }
  (lower, upper)
}

///|
/// `n * 2^exponent` with the sign of `negative`, an exact constant rounded as
/// a dyadic (the constants ±1/4, ±1/2, ±3/4 and ±1 of IEEE 754-2019 9.2.1).
fn binary_pi_constant(
  negative : Bool,
  numerator : UInt64,
  exponent : Int32,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  binary_round_dyadic(
    negative,
    BinCoeff::from_uint64(numerator),
    exponent,
    context,
  )
}

///|
fn binary_pi_signed_zero(
  negative : Bool,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  (
    if negative {
      BinFloat::negative_zero(precision=context.precision)
    } else {
      BinFloat::zero(precision=context.precision)
    },
    BinaryFlags::new(),
  )
}

///|
/// The leading-bit exponent of a finite nonzero value, as an `Int64`.
fn binary_pi_top(value : BinFloat) -> Int64 {
  value.exponent2().to_int64() +
  (value.coefficient().bit_length() - 1).to_int64()
}

///|
/// The anchor ±1/2 of a result `±(1/2 ∓ δ)`.
fn binary_pi_half(negative : Bool) -> BinFloat {
  let half = BinFloat::make(BinCoeff::one(), -1, 2)
  if negative {
    half.neg()
  } else {
    half
  }
}

///|
/// asin(x)/π.
pub fn BinFloat::try_asinpi_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  match binary_nan_unary(self, context) {
    Some(result) => return Ok(result)
    None => ()
  }
  if self.classify() == FpClass::Infinity {
    return binary_invalid_domain("asinpi requires an input in [-1, 1]")
  }
  let comparison = self.abs().compare(BinFloat::one(precision=self.precision()))
  if comparison > 0 {
    return binary_invalid_domain("asinpi requires an input in [-1, 1]")
  }
  // f(±0) = ±0 with no exception.
  if self.is_zero() {
    return Ok(self.round_ctx(context))
  }
  // asinPi(±1) = ±1/2.
  if comparison == 0 {
    return Ok(binary_pi_constant(self.is_negative(), 1UL, -1, context))
  }
  binary_ziv_round("asinpi", context, fn(work) {
    let w = Int32::max(work, self.precision() + 16)
    match (binary_asin_bounds(self, w), binary_pi_bounds(w)) {
      (Some(angle), Some(pi)) => Some(binary_pi_scaled_enclosure(angle, pi, w))
      _ => None
    }
  })
}

///|
pub fn BinFloat::asinpi_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  binary_defined_or_nan(self.try_asinpi_ctx(context), context)
}

///|
pub fn BinFloat::asinpi(self : BinFloat) -> BinFloat {
  self.asinpi_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
/// acos(x)/π = 1/2 − asin(x)/π.
pub fn BinFloat::try_acospi_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  match binary_nan_unary(self, context) {
    Some(result) => return Ok(result)
    None => ()
  }
  if self.classify() == FpClass::Infinity {
    return binary_invalid_domain("acospi requires an input in [-1, 1]")
  }
  let comparison = self.abs().compare(BinFloat::one(precision=self.precision()))
  if comparison > 0 {
    return binary_invalid_domain("acospi requires an input in [-1, 1]")
  }
  // acosPi(1) = +0, acosPi(-1) = 1, acosPi(±0) = 1/2: exact constants.
  if comparison == 0 {
    return Ok(
      if self.is_negative() {
        binary_pi_constant(false, 1UL, 0, context)
      } else {
        binary_pi_signed_zero(false, context)
      },
    )
  }
  if self.is_zero() {
    return Ok(binary_pi_constant(false, 1UL, -1, context))
  }
  // 0 < |asin(x)/π| <= |x|/2 < 2^(topb - 1) for |x| < 2^topb: the result is
  // within that distance of 1/2, above it for a negative x.
  if binary_tiny_argument_result(
      binary_pi_half(false),
      self.is_negative(),
      binary_top_bound(self) - 1L,
      context,
    )
    is Some(result) {
    return Ok(result)
  }
  binary_ziv_round("acospi", context, fn(work) {
    let w = Int32::max(work, self.precision() + 16)
    match (binary_asin_bounds(self, w), binary_pi_bounds(w)) {
      (Some(angle), Some(pi)) => {
        let sine = binary_pi_scaled_enclosure(angle, pi, w)
        let half = BinFloat::make(BinCoeff::one(), -1, w)
        Some(
          (
            half.sub_ctx(
              sine.1,
              BinaryContext::unbounded(w, rounding=RoundTowardNegative),
            ).0,
            half.sub_ctx(
              sine.0,
              BinaryContext::unbounded(w, rounding=RoundTowardPositive),
            ).0,
          ),
        )
      }
      _ => None
    }
  })
}

///|
pub fn BinFloat::acospi_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  binary_defined_or_nan(self.try_acospi_ctx(context), context)
}

///|
pub fn BinFloat::acospi(self : BinFloat) -> BinFloat {
  self.acospi_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
/// atan(x)/π.
pub fn BinFloat::try_atanpi_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  match binary_nan_unary(self, context) {
    Some(result) => return Ok(result)
    None => ()
  }
  // atanPi(±∞) = ±1/2 with no exception.
  if self.classify() == FpClass::Infinity {
    return Ok(binary_pi_constant(self.is_negative(), 1UL, -1, context))
  }
  if self.is_zero() {
    return Ok(self.round_ctx(context))
  }
  // atanPi(±1) = ±1/4.
  if self.abs().compare(BinFloat::one(precision=self.precision())) == 0 {
    return Ok(binary_pi_constant(self.is_negative(), 1UL, -2, context))
  }
  // 2^top <= |x| huge: atanPi(x) = ±(1/2 − δ), 0 < δ < 1/(π |x|) < 2^(-top).
  let top = binary_pi_top(self)
  if top >= context.precision.to_int64() + 8L &&
    binary_tiny_argument_result(
      binary_pi_half(self.is_negative()),
      self.is_negative(),
      -top,
      context,
    )
    is Some(result) {
    return Ok(result)
  }
  binary_ziv_round("atanpi", context, fn(work) {
    let w = Int32::max(work, self.precision() + 16)
    match (binary_atan_finite_bounds(self, w), binary_pi_bounds(w)) {
      (Some(angle), Some(pi)) => Some(binary_pi_scaled_enclosure(angle, pi, w))
      _ => None
    }
  })
}

///|
pub fn BinFloat::atanpi_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  binary_defined_or_nan(self.try_atanpi_ctx(context), context)
}

///|
pub fn BinFloat::atanpi(self : BinFloat) -> BinFloat {
  self.atanpi_ctx(BinaryContext::unbounded(self.precision())).0
}

///|
/// atan2(y, x)/π for `self = y` and `abscissa = x`.
pub fn BinFloat::try_atan2pi_ctx(
  self : BinFloat,
  abscissa : BinFloat,
  context : BinaryContext,
) -> Result[(BinFloat, BinaryFlags), @def.ArithmeticError] {
  match binary_nan_pair(self, abscissa, context.precision) {
    Some(result) => return Ok(result)
    None => ()
  }
  let negative = self.is_negative()
  let behind = abscissa.is_negative()
  let self_infinite = self.classify() == FpClass::Infinity
  let abscissa_infinite = abscissa.classify() == FpClass::Infinity
  // The exact constants of 9.2.1 (a zero ordinate keeps its sign; the sign
  // bit of a zero abscissa chooses the half-plane).
  if self.is_zero() {
    return Ok(
      if behind {
        binary_pi_constant(negative, 1UL, 0, context)
      } else {
        binary_pi_signed_zero(negative, context)
      },
    )
  }
  if self_infinite {
    return Ok(
      if abscissa_infinite {
        binary_pi_constant(
          negative,
          if behind {
            3UL
          } else {
            1UL
          },
          -2,
          context,
        )
      } else {
        binary_pi_constant(negative, 1UL, -1, context)
      },
    )
  }
  if abscissa.is_zero() {
    return Ok(binary_pi_constant(negative, 1UL, -1, context))
  }
  if abscissa_infinite {
    return Ok(
      if behind {
        binary_pi_constant(negative, 1UL, 0, context)
      } else {
        binary_pi_signed_zero(negative, context)
      },
    )
  }
  // Finite nonzero operands: |y/x| = 1 is the only exact angle (±1/4, ±3/4).
  let ordinate_magnitude = self.abs()
  let abscissa_magnitude = abscissa.abs()
  if ordinate_magnitude.compare(abscissa_magnitude) == 0 {
    return Ok(
      binary_pi_constant(negative, if behind { 3UL } else { 1UL }, -2, context),
    )
  }
  // The leading-bit exponents decide the extreme ratios: with
  // D = top(y) - top(x), 2^(D - 1) < |y/x| < 2^(D + 1).
  let distance = binary_pi_top(self) - binary_pi_top(abscissa)
  let precision = context.precision.to_int64()
  if distance >= precision + 8L {
    // atan(t)/π = 1/2 − δ, 0 < δ < 1/(π t) < 2^(-D); in the left half-plane
    // the result is 1/2 + δ. The magnitude is above 1/2 when behind, and the
    // sign of the ordinate mirrors the direction.
    if binary_tiny_argument_result(
        binary_pi_half(negative),
        behind != negative,
        -distance,
        context,
      )
      is Some(result) {
      return Ok(result)
    }
  } else if distance <= -(precision + 8L) {
    if behind {
      // 1 − δ with 0 < δ < t/π < 2^D.
      if binary_tiny_argument_result(
          BinFloat::one(precision=2).copy_sign(self),
          negative,
          distance,
          context,
        )
        is Some(result) {
        return Ok(result)
      }
    } else if distance <= context.range_e_min().to_int64() - precision - 1L {
      // atan(t)/π < t/π < 2^D is below a quarter of the smallest subnormal.
      return Ok(binary_tiny_nonzero_result(negative, context))
    }
  }
  binary_ziv_round("atan2pi", context, fn(work) {
    let w = Int32::max(
      work,
      Int32::max(self.precision(), abscissa.precision()) + 16,
    )
    let downward = BinaryContext::unbounded(w, rounding=RoundTowardNegative)
    let upward = BinaryContext::unbounded(w, rounding=RoundTowardPositive)
    let ratio_lower = ordinate_magnitude.div_ctx(abscissa_magnitude, downward).0
    let ratio_upper = ordinate_magnitude.div_ctx(abscissa_magnitude, upward).0
    match
      (
        binary_atan_pair_bounds(ratio_lower, ratio_upper, w),
        binary_pi_bounds(w),
      ) {
      (Some(angle), Some(pi)) => {
        let fraction = binary_pi_scaled_enclosure(angle, pi, w)
        let magnitude = if behind {
          let one = BinFloat::one(precision=w)
          (
            one.sub_ctx(fraction.1, downward).0,
            one.sub_ctx(fraction.0, upward).0,
          )
        } else {
          fraction
        }
        Some(
          if negative {
            (magnitude.1.neg(), magnitude.0.neg())
          } else {
            magnitude
          },
        )
      }
      _ => None
    }
  })
}

///|
pub fn BinFloat::atan2pi_ctx(
  self : BinFloat,
  abscissa : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  binary_defined_or_nan(self.try_atan2pi_ctx(abscissa, context), context)
}

///|
pub fn BinFloat::atan2pi(self : BinFloat, abscissa : BinFloat) -> BinFloat {
  self.atan2pi_ctx(
    abscissa,
    BinaryContext::unbounded(Int32::max(self.precision(), abscissa.precision())),
  ).0
}
