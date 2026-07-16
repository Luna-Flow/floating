///|
let binary_int_min : Int = -2147483648

///|
let binary_int_max : Int = 2147483647

///|
fn binary_add_sat(left : Int, right : Int) -> Int {
  let value = left.to_int64() + right.to_int64()
  if value > 2147483647L {
    binary_int_max
  } else if value < -2147483648L {
    binary_int_min
  } else {
    value.to_int()
  }
}

///|
fn binary_sub_sat(left : Int, right : Int) -> Int {
  let value = left.to_int64() - right.to_int64()
  if value > 2147483647L {
    binary_int_max
  } else if value < -2147483648L {
    binary_int_min
  } else {
    value.to_int()
  }
}

///|
fn binary_mul_sat(left : Int, right : Int) -> Int {
  let value = left.to_int64() * right.to_int64()
  if value > 2147483647L {
    binary_int_max
  } else if value < -2147483648L {
    binary_int_min
  } else {
    value.to_int()
  }
}

///|
fn binary_mul_int_uint_sat(left : Int, right : UInt) -> Int {
  let value = left.to_int64() * right.to_uint64().reinterpret_as_int64()
  if value > 2147483647L {
    binary_int_max
  } else if value < -2147483648L {
    binary_int_min
  } else {
    value.to_int()
  }
}

///|
fn binary_abs_uint(value : Int) -> UInt {
  if value < 0 {
    (-(value + 1)).reinterpret_as_uint() + 1U
  } else {
    value.reinterpret_as_uint()
  }
}

///|
fn binary_floor_div2(value : Int) -> Int {
  if value >= 0 {
    value / 2
  } else {
    -(-(value + 1) / 2) - 1
  }
}

///|
fn binary_exact_top(magnitude : BinCoeff, exponent2 : Int) -> Int {
  binary_add_sat(magnitude.bit_length() - 1, exponent2)
}

///|
fn binary_apply_round_bits(
  retained : BinCoeff,
  round_bit : Bool,
  sticky : Bool,
  negative : Bool,
  mode : BinaryRoundingMode,
) -> BinCoeff {
  let inexact = round_bit || sticky
  let increment = match mode {
    RoundTiesToEven => round_bit && (sticky || retained.test_bit(0))
    RoundTiesToAway => round_bit
    RoundTowardZero => false
    RoundTowardPositive => !negative && inexact
    RoundTowardNegative => negative && inexact
    RoundAwayFromZero => inexact
  }
  if increment {
    retained.add(BinCoeff::one())
  } else {
    retained
  }
}

///|
fn binary_split_quotient(
  numerator : BinCoeff,
  denominator : BinCoeff,
) -> (BinCoeff, Bool, Bool) {
  let (quotient, remainder) = bin_coeff_short_div_rem(numerator, denominator)
  if remainder.is_zero() {
    return (quotient, false, false)
  }
  let half_comparison = remainder.shift_left(1).compare(denominator)
  (quotient, half_comparison >= 0, half_comparison != 0)
}

///|
fn binary_split_shift(
  magnitude : BinCoeff,
  shift : Int,
) -> (BinCoeff, Bool, Bool) {
  if shift <= 0 {
    return (magnitude, false, false)
  }
  if magnitude.is_zero() {
    return (magnitude, false, false)
  }
  let quotient = magnitude.shift_right(shift)
  let trailing_zeros = magnitude.ctz()
  if trailing_zeros >= shift {
    (quotient, false, false)
  } else {
    let round_bit = magnitude.test_bit(shift - 1)
    (quotient, round_bit, trailing_zeros < shift - 1)
  }
}

///|
fn binary_compare_shifted(
  left : BinCoeff,
  left_shift : Int,
  right : BinCoeff,
  right_shift : Int,
) -> Int {
  if left.is_zero() || right.is_zero() {
    return left.compare(right)
  }
  let left_bits = left.bit_length().to_int64() + left_shift.to_int64()
  let right_bits = right.bit_length().to_int64() + right_shift.to_int64()
  if left_bits != right_bits {
    return if left_bits < right_bits { -1 } else { 1 }
  }
  if left_shift > right_shift {
    left.shift_left(left_shift - right_shift).compare(right)
  } else if right_shift > left_shift {
    left.compare(right.shift_left(right_shift - left_shift))
  } else {
    left.compare(right)
  }
}

///|
fn binary_split_scaled_quotient(
  numerator : BinCoeff,
  denominator : BinCoeff,
  scale : Int,
) -> (BinCoeff, Bool, Bool) {
  if scale >= 0 {
    return binary_split_quotient(numerator.shift_left(scale), denominator)
  }
  if scale == binary_int_min {
    return (BinCoeff::zero(), false, true)
  }
  let denominator_shift = -scale
  if binary_compare_shifted(numerator, 0, denominator, denominator_shift) < 0 {
    let half_comparison = binary_compare_shifted(
      numerator, 1, denominator, denominator_shift,
    )
    return (BinCoeff::zero(), half_comparison >= 0, half_comparison != 0)
  }
  binary_split_quotient(numerator, denominator.shift_left(denominator_shift))
}

///|
fn binary_overflow_to_infinity(
  negative : Bool,
  mode : BinaryRoundingMode,
) -> Bool {
  match mode {
    RoundTiesToEven | RoundTiesToAway | RoundAwayFromZero => true
    RoundTowardZero => false
    RoundTowardPositive => !negative
    RoundTowardNegative => negative
  }
}

///|
fn binary_max_finite(negative : Bool, context : BinaryContext) -> BinFloat {
  let e_max = context.e_max.unwrap()
  let magnitude = BinCoeff::one()
    .shift_left(context.precision)
    .sub_checked(BinCoeff::one())
    .unwrap()
  finite_from_parts(
    negative,
    magnitude,
    binary_sub_sat(e_max, context.precision - 1),
    context.precision,
  )
}

///|
fn binary_overflow_result(
  negative : Bool,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  let value = if binary_overflow_to_infinity(negative, context.rounding) {
    BinFloat::inf(
      if negative {
        Sign::Negative
      } else {
        Sign::Positive
      },
      precision=context.precision,
    )
  } else {
    binary_max_finite(negative, context)
  }
  (value, binary_overflow_flags())
}

///|
fn binary_tiny_nonzero_result(
  negative : Bool,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  let rounds_away = match context.rounding {
    RoundTowardPositive => !negative
    RoundTowardNegative => negative
    RoundAwayFromZero => true
    RoundTiesToEven | RoundTiesToAway | RoundTowardZero => false
  }
  let value = if rounds_away {
    let exponent2 = match context.e_min {
      Some(e_min) => binary_sub_sat(e_min, context.precision - 1)
      None => binary_int_min
    }
    finite_from_parts(negative, BinCoeff::one(), exponent2, context.precision)
  } else {
    finite_from_parts(negative, BinCoeff::zero(), 0, context.precision)
  }
  (value, binary_inexact_flags(context.e_min is Some(_)))
}

///|
fn binary_finalize_rounded(
  negative : Bool,
  magnitude : BinCoeff,
  exponent2 : Int,
  inexact : Bool,
  exact_top : Int,
  unbounded_rounded_top : Int,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  let rounded_top = if magnitude.is_zero() {
    exact_top
  } else {
    binary_exact_top(magnitude, exponent2)
  }
  match context.e_max {
    Some(e_max) if !magnitude.is_zero() && rounded_top > e_max =>
      return binary_overflow_result(negative, context)
    _ => ()
  }
  let value = finite_from_parts(
    negative,
    magnitude,
    exponent2,
    context.precision,
  )
  if !inexact {
    return (value, BinaryFlags::new())
  }
  let tiny = match context.e_min {
    None => false
    Some(e_min) =>
      match context.tininess {
        BeforeRounding => exact_top < e_min
        AfterRounding => unbounded_rounded_top < e_min
      }
  }
  (value, binary_inexact_flags(tiny))
}

///|
fn binary_round_pack(
  negative : Bool,
  retained : BinCoeff,
  round_bit : Bool,
  sticky : Bool,
  exponent2 : Int,
  exact_top : Int,
  unbounded_rounded_top : Int,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  binary_finalize_rounded(
    negative,
    binary_apply_round_bits(
      retained,
      round_bit,
      sticky,
      negative,
      context.rounding,
    ),
    exponent2,
    round_bit || sticky,
    exact_top,
    unbounded_rounded_top,
    context,
  )
}

///|
fn binary_round_dyadic(
  negative : Bool,
  magnitude : BinCoeff,
  exponent2 : Int,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  if magnitude.is_zero() {
    return (
      finite_from_parts(negative, BinCoeff::zero(), 0, context.precision),
      BinaryFlags::new(),
    )
  }
  let bits = magnitude.bit_length()
  if bits <= context.precision && context.e_min is None && context.e_max is None {
    return (
      finite_from_parts(negative, magnitude, exponent2, context.precision),
      BinaryFlags::new(),
    )
  }
  let precision_shift = Int::max(0, bits - context.precision)
  let (precision_retained, precision_guard, precision_sticky) = binary_split_shift(
    magnitude, precision_shift,
  )
  let precision_rounded = binary_apply_round_bits(
    precision_retained,
    precision_guard,
    precision_sticky,
    negative,
    context.rounding,
  )
  let unbounded_rounded_top = binary_exact_top(
    precision_rounded,
    binary_add_sat(exponent2, precision_shift),
  )
  let range_shift = match context.e_min {
    Some(e_min) =>
      Int::max(
        0,
        binary_sub_sat(binary_sub_sat(e_min, context.precision - 1), exponent2),
      )
    None => 0
  }
  let shift = Int::max(precision_shift, range_shift)
  let (retained, round_bit, sticky) = if shift == precision_shift {
    (precision_retained, precision_guard, precision_sticky)
  } else {
    binary_split_shift(magnitude, shift)
  }
  binary_round_pack(
    negative,
    retained,
    round_bit,
    sticky,
    binary_add_sat(exponent2, shift),
    binary_exact_top(magnitude, exponent2),
    unbounded_rounded_top,
    context,
  )
}

///|
fn binary_floor_log2_ratio(numerator : BinCoeff, denominator : BinCoeff) -> Int {
  let candidate = numerator.bit_length() - denominator.bit_length()
  if candidate >= 0 {
    if numerator.compare(denominator.shift_left(candidate)) < 0 {
      candidate - 1
    } else {
      candidate
    }
  } else if numerator.shift_left(-candidate).compare(denominator) < 0 {
    candidate - 1
  } else {
    candidate
  }
}

///|
fn binary_target_exponent(exact_top : Int, context : BinaryContext) -> Int {
  let normal = binary_sub_sat(exact_top, context.precision - 1)
  match context.e_min {
    Some(e_min) =>
      Int::max(normal, binary_sub_sat(e_min, context.precision - 1))
    None => normal
  }
}

///|
fn binary_round_rational(
  negative : Bool,
  numerator : BinCoeff,
  denominator : BinCoeff,
  exponent2 : Int,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  let exact_top = binary_add_sat(
    binary_floor_log2_ratio(numerator, denominator),
    exponent2,
  )
  let target_exponent = binary_target_exponent(exact_top, context)
  let scale = binary_sub_sat(exponent2, target_exponent)
  let (retained, round_bit, sticky) = binary_split_scaled_quotient(
    numerator, denominator, scale,
  )
  let unbounded_target = binary_sub_sat(exact_top, context.precision - 1)
  let unbounded_scale = binary_sub_sat(exponent2, unbounded_target)
  let (unbounded_retained, unbounded_guard, unbounded_sticky) = if target_exponent ==
    unbounded_target {
    (retained, round_bit, sticky)
  } else {
    binary_split_scaled_quotient(numerator, denominator, unbounded_scale)
  }
  let unbounded_rounded = binary_apply_round_bits(
    unbounded_retained,
    unbounded_guard,
    unbounded_sticky,
    negative,
    context.rounding,
  )
  binary_round_pack(
    negative,
    retained,
    round_bit,
    sticky,
    target_exponent,
    exact_top,
    binary_exact_top(unbounded_rounded, unbounded_target),
    context,
  )
}

///|
fn binary_sqrt_split(
  magnitude : BinCoeff,
  scale : Int,
) -> (BinCoeff, Bool, Int) {
  if scale >= 0 {
    let radicand = magnitude.shift_left(scale)
    let (root, remainder) = bin_coeff_sqrt_rem_kernel(radicand)
    let exact = remainder.is_zero()
    let midpoint = root.shift_left(1).add(BinCoeff::one()).square()
    (
      root,
      exact,
      magnitude.shift_left(binary_add_sat(scale, 2)).compare(midpoint),
    )
  } else if scale == binary_int_min {
    (BinCoeff::zero(), false, -1)
  } else {
    let denominator_shift = -scale
    let (root, _) = bin_coeff_sqrt_rem_kernel(
      magnitude.shift_right(denominator_shift),
    )
    let root_square = root.square()
    let exact = !root.is_zero() &&
      binary_compare_shifted(root_square, denominator_shift, magnitude, 0) == 0
    let midpoint = root.shift_left(1).add(BinCoeff::one()).square()
    (
      root,
      exact,
      binary_compare_shifted(magnitude, 2, midpoint, denominator_shift),
    )
  }
}

///|
fn binary_sqrt_round_bits(
  exact : Bool,
  midpoint_comparison : Int,
) -> (Bool, Bool) {
  if exact {
    (false, false)
  } else if midpoint_comparison == 0 {
    (true, false)
  } else if midpoint_comparison > 0 {
    (true, true)
  } else {
    (false, true)
  }
}

///|
fn binary_round_sqrt(
  magnitude : BinCoeff,
  exponent2 : Int,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  let exact_top = binary_floor_div2(binary_exact_top(magnitude, exponent2))
  match context.e_max {
    Some(e_max) if exact_top > e_max =>
      return binary_overflow_result(false, context)
    _ => ()
  }
  let target_exponent = binary_target_exponent(exact_top, context)
  let scale = binary_sub_sat(exponent2, binary_mul_sat(2, target_exponent))
  let (floor_root, exact, midpoint_comparison) = binary_sqrt_split(
    magnitude, scale,
  )
  let (round_bit, sticky) = binary_sqrt_round_bits(exact, midpoint_comparison)
  let unbounded_target = binary_sub_sat(exact_top, context.precision - 1)
  let unbounded_scale = binary_sub_sat(
    exponent2,
    binary_mul_sat(2, unbounded_target),
  )
  let (unbounded_root, unbounded_exact, unbounded_midpoint_comparison) = if unbounded_scale ==
    scale {
    (floor_root, exact, midpoint_comparison)
  } else {
    binary_sqrt_split(magnitude, unbounded_scale)
  }
  let (unbounded_guard, unbounded_sticky) = binary_sqrt_round_bits(
    unbounded_exact, unbounded_midpoint_comparison,
  )
  let unbounded_rounded = binary_apply_round_bits(
    unbounded_root,
    unbounded_guard,
    unbounded_sticky,
    false,
    context.rounding,
  )
  binary_round_pack(
    false,
    floor_root,
    round_bit,
    sticky,
    target_exponent,
    exact_top,
    binary_exact_top(unbounded_rounded, unbounded_target),
    context,
  )
}

///|
fn binary_quiet_nan(value : BinFloat, precision : Int) -> BinFloat {
  BinFloat::quiet_nan(
    payload=value.nan_payload,
    negative=value.negative,
    precision~,
  )
}

///|
fn binary_nan_pair(
  left : BinFloat,
  right : BinFloat,
  precision : Int,
) -> (BinFloat, BinaryFlags)? {
  if left.class == FpClass::NaN || right.class == FpClass::NaN {
    let source = if left.class == FpClass::NaN { left } else { right }
    let invalid = left.is_signaling_nan() || right.is_signaling_nan()
    Some(
      (
        binary_quiet_nan(source, precision),
        if invalid {
          binary_invalid_flags()
        } else {
          BinaryFlags::new()
        },
      ),
    )
  } else {
    None
  }
}

///|
fn binary_exact_sum_zero_sign(
  left : BinFloat,
  right : BinFloat,
  mode : BinaryRoundingMode,
) -> Bool {
  if left.is_zero() && right.is_zero() && left.negative == right.negative {
    left.negative
  } else {
    mode == BinaryRoundingMode::RoundTowardNegative
  }
}

///|
fn binary_add_far_exponents(
  left : BinFloat,
  right : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  let left_top = binary_exact_top(left.coefficient_, left.exponent2)
  let right_top = binary_exact_top(right.coefficient_, right.exponent2)
  let (high, low) = if left_top >= right_top {
    (left, right)
  } else {
    (right, left)
  }
  if high.is_zero() {
    return binary_round_dyadic(
      low.negative,
      low.coefficient_,
      low.exponent2,
      context,
    )
  }
  if low.is_zero() {
    return binary_round_dyadic(
      high.negative,
      high.coefficient_,
      high.exponent2,
      context,
    )
  }
  let compression_shift = binary_add_sat(context.precision, 3)
  let high_magnitude = high.coefficient_.shift_left(compression_shift)
  let relative_shift = low.exponent2.to_int64() -
    high.exponent2.to_int64() +
    compression_shift.to_int64()
  let (low_prefix, low_discarded) = if relative_shift > 2147483647L {
    (BinCoeff::zero(), true)
  } else if relative_shift >= 0L {
    (low.coefficient_.shift_left(relative_shift.to_int()), false)
  } else if relative_shift < -2147483647L {
    (BinCoeff::zero(), true)
  } else {
    let (prefix, round_bit, sticky) = binary_split_shift(
      low.coefficient_,
      (-relative_shift).to_int(),
    )
    (prefix, round_bit || sticky)
  }
  let (magnitude, extra_shift) = if high.negative == low.negative {
    let integral = high_magnitude.add(low_prefix)
    if low_discarded {
      (integral.shift_left(1).add(BinCoeff::one()), 1)
    } else {
      (integral, 0)
    }
  } else {
    let integral = high_magnitude.sub_checked(low_prefix).unwrap()
    if low_discarded {
      (
        integral
        .sub_checked(BinCoeff::one())
        .unwrap()
        .shift_left(1)
        .add(BinCoeff::one()),
        1,
      )
    } else {
      (integral, 0)
    }
  }
  binary_round_dyadic(
    high.negative,
    magnitude,
    binary_sub_sat(
      binary_sub_sat(high.exponent2, compression_shift),
      extra_shift,
    ),
    context,
  )
}

///|
pub fn BinFloat::round_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  match self.class {
    FpClass::NaN =>
      (
        binary_quiet_nan(self, context.precision),
        if self.signaling_nan {
          binary_invalid_flags()
        } else {
          BinaryFlags::new()
        },
      )
    FpClass::Infinity =>
      (
        BinFloat::inf(
          if self.negative {
            Sign::Negative
          } else {
            Sign::Positive
          },
          precision=context.precision,
        ),
        BinaryFlags::new(),
      )
    FpClass::Finite =>
      binary_round_dyadic(
        self.negative,
        self.coefficient_,
        self.exponent2,
        context,
      )
  }
}

///|
pub fn BinFloat::add_ctx(
  self : BinFloat,
  other : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  match binary_nan_pair(self, other, context.precision) {
    Some(result) => return result
    None => ()
  }
  match (self.class, other.class) {
    (FpClass::Infinity, FpClass::Infinity) =>
      if self.negative == other.negative {
        (
          BinFloat::inf(
            if self.negative {
              Sign::Negative
            } else {
              Sign::Positive
            },
            precision=context.precision,
          ),
          BinaryFlags::new(),
        )
      } else {
        (BinFloat::nan(precision=context.precision), binary_invalid_flags())
      }
    (FpClass::Infinity, _) =>
      (
        BinFloat::inf(
          if self.negative {
            Sign::Negative
          } else {
            Sign::Positive
          },
          precision=context.precision,
        ),
        BinaryFlags::new(),
      )
    (_, FpClass::Infinity) =>
      (
        BinFloat::inf(
          if other.negative {
            Sign::Negative
          } else {
            Sign::Positive
          },
          precision=context.precision,
        ),
        BinaryFlags::new(),
      )
    (FpClass::Finite, FpClass::Finite) => {
      let self_top = binary_exact_top(self.coefficient_, self.exponent2)
      let other_top = binary_exact_top(other.coefficient_, other.exponent2)
      let top_gap = self_top.to_int64() - other_top.to_int64()
      let far_threshold = binary_add_sat(context.precision, 3).to_int64()
      if top_gap > far_threshold || top_gap < -far_threshold {
        return binary_add_far_exponents(self, other, context)
      }
      let target = Int::min(self.exponent2, other.exponent2)
      let left = self.coefficient_.shift_left(
        binary_sub_sat(self.exponent2, target),
      )
      let right = other.coefficient_.shift_left(
        binary_sub_sat(other.exponent2, target),
      )
      if self.negative == other.negative {
        let (sum, normalization_shift) = bin_coeff_add_normalized_odd(
          left, right,
        )
        binary_round_dyadic(
          self.negative,
          sum,
          binary_add_sat(target, normalization_shift),
          context,
        )
      } else {
        let comparison = left.compare(right)
        if comparison == 0 {
          (
            finite_from_parts(
              binary_exact_sum_zero_sign(self, other, context.rounding),
              BinCoeff::zero(),
              0,
              context.precision,
            ),
            BinaryFlags::new(),
          )
        } else if comparison > 0 {
          let (difference, normalization_shift) = bin_coeff_sub_normalized_odd(
            left, right,
          )
          binary_round_dyadic(
            self.negative,
            difference,
            binary_add_sat(target, normalization_shift),
            context,
          )
        } else {
          let (difference, normalization_shift) = bin_coeff_sub_normalized_odd(
            right, left,
          )
          binary_round_dyadic(
            other.negative,
            difference,
            binary_add_sat(target, normalization_shift),
            context,
          )
        }
      }
    }
    _ => abort("unreachable BinFloat::add_ctx class pair")
  }
}

///|
pub fn BinFloat::sub_ctx(
  self : BinFloat,
  other : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  self.add_ctx(other.neg(), context)
}

///|
pub fn BinFloat::mul_ctx(
  self : BinFloat,
  other : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  match binary_nan_pair(self, other, context.precision) {
    Some(result) => return result
    None => ()
  }
  let negative = self.negative != other.negative
  match (self.class, other.class) {
    (FpClass::Infinity, FpClass::Finite)
    | (FpClass::Finite, FpClass::Infinity) if self.is_zero() || other.is_zero() =>
      (BinFloat::nan(precision=context.precision), binary_invalid_flags())
    (FpClass::Infinity, _) | (_, FpClass::Infinity) =>
      (
        BinFloat::inf(
          if negative {
            Sign::Negative
          } else {
            Sign::Positive
          },
          precision=context.precision,
        ),
        BinaryFlags::new(),
      )
    (FpClass::Finite, FpClass::Finite) =>
      binary_round_dyadic(
        negative,
        self.coefficient_.mul(other.coefficient_),
        binary_add_sat(self.exponent2, other.exponent2),
        context,
      )
    _ => abort("unreachable BinFloat::mul_ctx class pair")
  }
}

///|
pub fn BinFloat::div_ctx(
  self : BinFloat,
  other : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  match binary_nan_pair(self, other, context.precision) {
    Some(result) => return result
    None => ()
  }
  let negative = self.negative != other.negative
  match (self.class, other.class) {
    (FpClass::Infinity, FpClass::Infinity) =>
      (BinFloat::nan(precision=context.precision), binary_invalid_flags())
    (FpClass::Finite, FpClass::Finite) if self.is_zero() && other.is_zero() =>
      (BinFloat::nan(precision=context.precision), binary_invalid_flags())
    (FpClass::Infinity, _) =>
      (
        BinFloat::inf(
          if negative {
            Sign::Negative
          } else {
            Sign::Positive
          },
          precision=context.precision,
        ),
        BinaryFlags::new(),
      )
    (FpClass::Finite, FpClass::Finite) if other.is_zero() =>
      (
        BinFloat::inf(
          if negative {
            Sign::Negative
          } else {
            Sign::Positive
          },
          precision=context.precision,
        ),
        binary_division_by_zero_flags(),
      )
    (_, FpClass::Infinity) =>
      (
        finite_from_parts(negative, BinCoeff::zero(), 0, context.precision),
        BinaryFlags::new(),
      )
    (FpClass::Finite, FpClass::Finite) if self.is_zero() =>
      (
        finite_from_parts(negative, BinCoeff::zero(), 0, context.precision),
        BinaryFlags::new(),
      )
    (FpClass::Finite, FpClass::Finite) =>
      binary_round_rational(
        negative,
        self.coefficient_,
        other.coefficient_,
        binary_sub_sat(self.exponent2, other.exponent2),
        context,
      )
    _ => abort("unreachable BinFloat::div_ctx class pair")
  }
}

///|
pub fn BinFloat::sqrt_ctx(
  self : BinFloat,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  match self.class {
    FpClass::NaN =>
      (
        binary_quiet_nan(self, context.precision),
        if self.signaling_nan {
          binary_invalid_flags()
        } else {
          BinaryFlags::new()
        },
      )
    FpClass::Infinity =>
      if self.negative {
        (BinFloat::nan(precision=context.precision), binary_invalid_flags())
      } else {
        (
          BinFloat::inf(Sign::Positive, precision=context.precision),
          BinaryFlags::new(),
        )
      }
    FpClass::Finite if self.is_zero() =>
      (
        finite_from_parts(self.negative, BinCoeff::zero(), 0, context.precision),
        BinaryFlags::new(),
      )
    FpClass::Finite if self.negative =>
      (BinFloat::nan(precision=context.precision), binary_invalid_flags())
    FpClass::Finite =>
      binary_round_sqrt(self.coefficient_, self.exponent2, context)
  }
}

///|
fn binary_exponent_magnitude(exponent : Int) -> UInt {
  binary_abs_uint(exponent)
}

///|
fn binary_uint_bits(value : UInt) -> Int {
  if value == 0U {
    0
  } else {
    32 - value.clz()
  }
}

///|
priv struct BinaryPowStats {
  mut multiplications : Int
  mut squarings : Int
  mut divisions : Int
  mut ziv_rounds : Int
  mut maximum_work_precision : Int
  mut exact_fallback : Bool
}

///|
fn binary_pow_stats_new() -> BinaryPowStats {
  {
    multiplications: 0,
    squarings: 0,
    divisions: 0,
    ziv_rounds: 0,
    maximum_work_precision: 0,
    exact_fallback: false,
  }
}

///|
fn BinaryPowStats::summary(
  self : BinaryPowStats,
) -> (Int, Int, Int, Int, Int, Bool) {
  (
    self.multiplications,
    self.squarings,
    self.divisions,
    self.ziv_rounds,
    self.maximum_work_precision,
    self.exact_fallback,
  )
}

///|
fn binary_pow_exact_magnitude(
  base : BinFloat,
  exponent : UInt,
  reciprocal : Bool,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  let negative = base.negative && (exponent & 1U) != 0U
  let powered = base.coefficient_.pow_nat(exponent)
  let powered_exponent = binary_mul_int_uint_sat(base.exponent2, exponent)
  if reciprocal {
    binary_round_rational(
      negative,
      BinCoeff::one(),
      powered,
      binary_sub_sat(0, powered_exponent),
      context,
    )
  } else {
    binary_round_dyadic(negative, powered, powered_exponent, context)
  }
}

///|
fn binary_pow_positive_approximation(
  base : BinFloat,
  exponent : UInt,
  work_precision : Int,
) -> (BinFloat, Int, Int) {
  let work_context = BinaryContext::unbounded(
    work_precision,
    rounding=BinaryRoundingMode::RoundTiesToEven,
  )
  let exponent_bits = binary_uint_bits(exponent)
  let magnitude = base.abs()
  match binary_pow_small_addition_chain(magnitude, exponent, work_context) {
    Some(result) => return result
    None => ()
  }
  let mut result = magnitude
  let mut multiplications = 0
  let mut squarings = 0
  let mut bit_index = exponent_bits - 2
  while bit_index >= 0 {
    result = result.mul_ctx(result, work_context).0
    squarings += 1
    if (exponent & (1U << bit_index)) != 0U {
      result = result.mul_ctx(magnitude, work_context).0
      multiplications += 1
    }
    bit_index -= 1
  }
  (result, multiplications, squarings)
}

///|
fn binary_pow_small_addition_chain(
  base : BinFloat,
  exponent : UInt,
  context : BinaryContext,
) -> (BinFloat, Int, Int)? {
  let steps = match exponent {
    3U => [(2, 1, 1), (3, 2, 1)]
    4U => [(2, 1, 1), (4, 2, 2)]
    5U => [(2, 1, 1), (4, 2, 2), (5, 4, 1)]
    6U => [(2, 1, 1), (3, 2, 1), (6, 3, 3)]
    7U => [(2, 1, 1), (3, 2, 1), (6, 3, 3), (7, 6, 1)]
    8U => [(2, 1, 1), (4, 2, 2), (8, 4, 4)]
    9U => [(2, 1, 1), (4, 2, 2), (8, 4, 4), (9, 8, 1)]
    10U => [(2, 1, 1), (4, 2, 2), (5, 4, 1), (10, 5, 5)]
    11U => [(2, 1, 1), (4, 2, 2), (5, 4, 1), (10, 5, 5), (11, 10, 1)]
    12U => [(2, 1, 1), (3, 2, 1), (6, 3, 3), (12, 6, 6)]
    13U => [(2, 1, 1), (3, 2, 1), (6, 3, 3), (12, 6, 6), (13, 12, 1)]
    14U => [(2, 1, 1), (3, 2, 1), (6, 3, 3), (7, 6, 1), (14, 7, 7)]
    15U => [(2, 1, 1), (3, 2, 1), (6, 3, 3), (12, 6, 6), (15, 12, 3)]
    16U => [(2, 1, 1), (4, 2, 2), (8, 4, 4), (16, 8, 8)]
    _ => return None
  }
  let powers = FixedArray::make(17, base)
  powers.unsafe_set(1, base)
  let mut multiplications = 0
  let mut squarings = 0
  for step in steps {
    let value = powers
      .unsafe_get(step.1)
      .mul_ctx(powers.unsafe_get(step.2), context).0
    powers.unsafe_set(step.0, value)
    if step.1 == step.2 {
      squarings += 1
    } else {
      multiplications += 1
    }
  }
  Some(
    (
      powers.unsafe_get(exponent.reinterpret_as_int()),
      multiplications,
      squarings,
    ),
  )
}

///|
fn binary_pow_interval(
  approximation : BinFloat,
  error_shift : Int,
) -> (BinFloat, BinFloat)? {
  let radius = BinCoeff::one().shift_left(error_shift)
  if approximation.coefficient_.compare(radius) <= 0 {
    return None
  }
  let lower = approximation.coefficient_.sub_checked(radius).unwrap()
  let upper = approximation.coefficient_.add(radius)
  Some(
    (
      finite_from_parts(
        false,
        lower,
        approximation.exponent2,
        lower.bit_length(),
      ),
      finite_from_parts(
        false,
        upper,
        approximation.exponent2,
        upper.bit_length(),
      ),
    ),
  )
}

///|
fn binary_pow_can_round_interval(
  lower_magnitude : BinFloat,
  upper_magnitude : BinFloat,
  negative : Bool,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags)? {
  let lower = if negative { upper_magnitude.neg() } else { lower_magnitude }
  let upper = if negative { lower_magnitude.neg() } else { upper_magnitude }
  if lower.is_zero() || upper.is_zero() {
    return None
  }
  let lower_top = binary_exact_top(lower.coefficient_, lower.exponent2)
  let upper_top = binary_exact_top(upper.coefficient_, upper.exponent2)
  if lower_top != upper_top {
    return None
  }
  let lower_rounded = lower.round_ctx(context)
  let upper_rounded = upper.round_ctx(context)
  if lower_rounded.0 != upper_rounded.0 {
    return None
  }
  if lower_rounded.1.overflow() != upper_rounded.1.overflow() {
    return None
  }
  let unbounded_context = BinaryContext::unbounded(
    context.precision,
    rounding=context.rounding,
  )
  let lower_unbounded = lower.round_ctx(unbounded_context).0
  let upper_unbounded = upper.round_ctx(unbounded_context).0
  if lower_unbounded != upper_unbounded {
    return None
  }
  if lower_rounded.1.overflow() {
    return Some((lower_rounded.0, binary_overflow_flags()))
  }
  let rounded = lower_rounded.0
  let unbounded_top = if lower_unbounded.is_zero() {
    lower_top
  } else {
    binary_exact_top(lower_unbounded.coefficient_, lower_unbounded.exponent2)
  }
  Some(
    binary_finalize_rounded(
      rounded.negative,
      rounded.coefficient_,
      rounded.exponent2,
      true,
      lower_top,
      unbounded_top,
      context,
    ),
  )
}

///|
fn binary_pow_initial_work_precision(precision : Int, exponent : UInt) -> Int {
  let precision_bits = binary_uint_bits(precision.reinterpret_as_uint())
  binary_add_sat(
    precision,
    binary_add_sat(binary_uint_bits(exponent), precision_bits + 4),
  )
}

///|
fn binary_pow_exact_positive_if_small(
  base : BinFloat,
  exponent : UInt,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags)? {
  let odd_bits = base.coefficient_.bit_length()
  if odd_bits <= 1 {
    return None
  }
  let available = context.precision - 1
  let growth = odd_bits - 1
  if available < 0 ||
    exponent.to_uint64() >
    (available / growth).reinterpret_as_uint().to_uint64() {
    return None
  }
  let powered = base.coefficient_.pow_nat(exponent)
  if powered.bit_length() > context.precision {
    return None
  }
  let negative = base.negative && (exponent & 1U) != 0U
  let powered_exponent = binary_mul_int_uint_sat(base.exponent2, exponent)
  Some(binary_round_dyadic(negative, powered, powered_exponent, context))
}

///|
fn binary_pow_ziv(
  base : BinFloat,
  exponent : UInt,
  reciprocal : Bool,
  context : BinaryContext,
) -> ((BinFloat, BinaryFlags)?, BinaryPowStats) {
  let stats = binary_pow_stats_new()
  let negative = base.negative && (exponent & 1U) != 0U
  let mut work = binary_pow_initial_work_precision(context.precision, exponent)
  for _ in 0..<12 {
    stats.ziv_rounds += 1
    stats.maximum_work_precision = Int::max(stats.maximum_work_precision, work)
    let approximation_base = if reciprocal {
      stats.divisions += 1
      BinFloat::one(precision=work).div_ctx(
        base.abs(),
        BinaryContext::unbounded(
          work,
          rounding=BinaryRoundingMode::RoundTiesToEven,
        ),
      ).0
    } else {
      base
    }
    let (approximation, multiplications, squarings) = binary_pow_positive_approximation(
      approximation_base, exponent, work,
    )
    stats.multiplications += multiplications
    stats.squarings += squarings
    let error_shift = binary_uint_bits(exponent) +
      (if reciprocal { 3 } else { 2 })
    match binary_pow_interval(approximation, error_shift) {
      Some((lower, upper)) =>
        match binary_pow_can_round_interval(lower, upper, negative, context) {
          Some(result) => return (Some(result), stats)
          None => ()
        }
      None => ()
    }
    let next_work = binary_mul_sat(work, 2)
    if next_work <= work {
      break
    }
    work = next_work
  }
  stats.exact_fallback = true
  (None, stats)
}

///|
fn binary_pow_is_power_of_two(base : BinFloat) -> Bool {
  if base.coefficient_.is_zero() {
    return false
  }
  base.coefficient_.shift_right(base.coefficient_.ctz()) == BinCoeff::one()
}

///|
fn binary_pow_finite(
  base : BinFloat,
  exponent : UInt,
  reciprocal : Bool,
  context : BinaryContext,
) -> ((BinFloat, BinaryFlags), BinaryPowStats) {
  let stats = binary_pow_stats_new()
  if !reciprocal && exponent == 1U {
    return (base.round_ctx(context), stats)
  }
  if !reciprocal && exponent == 2U {
    stats.squarings = 1
    return (base.mul_ctx(base, context), stats)
  }
  if binary_pow_should_use_exact_fast(base, exponent, reciprocal) {
    return (
      binary_pow_exact_magnitude(base, exponent, reciprocal, context),
      stats,
    )
  }
  if !reciprocal {
    match binary_pow_exact_positive_if_small(base, exponent, context) {
      Some(result) => return (result, stats)
      None => ()
    }
  }
  let (candidate, candidate_stats) = binary_pow_ziv(
    base, exponent, reciprocal, context,
  )
  match candidate {
    Some(result) => (result, candidate_stats)
    None => {
      candidate_stats.exact_fallback = true
      (
        binary_pow_exact_magnitude(base, exponent, reciprocal, context),
        candidate_stats,
      )
    }
  }
}

///|
fn binary_pow_should_use_exact_fast(
  base : BinFloat,
  exponent : UInt,
  reciprocal : Bool,
) -> Bool {
  if reciprocal || exponent == 0U {
    return false
  }
  let coefficient_bits = base.coefficient_.bit_length()
  coefficient_bits > 0 &&
  exponent.to_uint64() <=
  (2048 / coefficient_bits).reinterpret_as_uint().to_uint64()
}

///|
fn binary_pow_power_of_two_normalized(
  base : BinFloat,
  exponent : UInt,
  reciprocal : Bool,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  let shift = base.coefficient_.ctz()
  let normalized_exponent = binary_add_sat(base.exponent2, shift)
  let normalized = finite_from_parts(
    base.negative,
    BinCoeff::one(),
    normalized_exponent,
    base.precision_,
  )
  binary_pow_power_of_two(normalized, exponent, reciprocal, context)
}

///|
fn binary_pow_magnitude_with_stats(
  base : BinFloat,
  exponent : UInt,
  reciprocal : Bool,
  context : BinaryContext,
) -> ((BinFloat, BinaryFlags), BinaryPowStats) {
  if binary_pow_is_power_of_two(base) {
    return (
      binary_pow_power_of_two_normalized(base, exponent, reciprocal, context),
      binary_pow_stats_new(),
    )
  }
  binary_pow_finite(base, exponent, reciprocal, context)
}

///|
fn binary_pow_power_of_two(
  base : BinFloat,
  exponent : UInt,
  reciprocal : Bool,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  let negative = base.negative && (exponent & 1U) != 0U
  let magnitude_product = base.exponent2.to_int64() *
    exponent.to_uint64().reinterpret_as_int64()
  let product = if reciprocal { -magnitude_product } else { magnitude_product }
  if product > 2147483647L {
    return binary_overflow_result(negative, context)
  }
  if product < -2147483648L {
    return binary_tiny_nonzero_result(negative, context)
  }
  binary_round_dyadic(negative, BinCoeff::one(), product.to_int(), context)
}

///|
pub fn BinFloat::pow_int_ctx(
  self : BinFloat,
  exponent : Int,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  if exponent == 0 {
    return (BinFloat::one(precision=context.precision), BinaryFlags::new())
  }
  if self.class == FpClass::NaN {
    return (
      binary_quiet_nan(self, context.precision),
      if self.signaling_nan {
        binary_invalid_flags()
      } else {
        BinaryFlags::new()
      },
    )
  }
  let magnitude = binary_exponent_magnitude(exponent)
  let reciprocal = exponent < 0
  let odd = (magnitude & 1U) != 0U
  let negative = self.negative && odd
  match self.class {
    FpClass::Infinity =>
      if exponent < 0 {
        (
          finite_from_parts(negative, BinCoeff::zero(), 0, context.precision),
          BinaryFlags::new(),
        )
      } else {
        (
          BinFloat::inf(
            if negative {
              Sign::Negative
            } else {
              Sign::Positive
            },
            precision=context.precision,
          ),
          BinaryFlags::new(),
        )
      }
    FpClass::Finite if self.is_zero() =>
      if exponent < 0 {
        (
          BinFloat::inf(
            if negative {
              Sign::Negative
            } else {
              Sign::Positive
            },
            precision=context.precision,
          ),
          binary_division_by_zero_flags(),
        )
      } else {
        (
          finite_from_parts(negative, BinCoeff::zero(), 0, context.precision),
          BinaryFlags::new(),
        )
      }
    FpClass::Finite => {
      if exponent == 1 {
        return self.round_ctx(context)
      }
      if exponent == 2 {
        return self.mul_ctx(self, context)
      }
      if binary_pow_should_use_exact_fast(self, magnitude, reciprocal) {
        return binary_pow_exact_magnitude(self, magnitude, reciprocal, context)
      }
      if binary_pow_is_power_of_two(self) {
        return binary_pow_power_of_two_normalized(
          self, magnitude, reciprocal, context,
        )
      }
      let outcome = binary_pow_magnitude_with_stats(
        self, magnitude, reciprocal, context,
      )
      let _ = outcome.1.summary()
      outcome.0
    }
    FpClass::NaN => abort("unreachable BinFloat::pow_int_ctx NaN")
  }
}

///|
fn BinFloat::pow_nat_ctx(
  self : BinFloat,
  exponent : UInt,
  context : BinaryContext,
) -> (BinFloat, BinaryFlags) {
  if exponent == 0U {
    return (BinFloat::one(precision=context.precision), BinaryFlags::new())
  }
  if self.class == FpClass::NaN {
    return (
      binary_quiet_nan(self, context.precision),
      if self.signaling_nan {
        binary_invalid_flags()
      } else {
        BinaryFlags::new()
      },
    )
  }
  let negative = self.negative && (exponent & 1U) != 0U
  match self.class {
    FpClass::Infinity =>
      (
        BinFloat::inf(
          if negative {
            Sign::Negative
          } else {
            Sign::Positive
          },
          precision=context.precision,
        ),
        BinaryFlags::new(),
      )
    FpClass::Finite if self.is_zero() =>
      (
        finite_from_parts(negative, BinCoeff::zero(), 0, context.precision),
        BinaryFlags::new(),
      )
    FpClass::Finite => {
      let outcome = binary_pow_magnitude_with_stats(
        self, exponent, false, context,
      )
      let _ = outcome.1.summary()
      outcome.0
    }
    FpClass::NaN => abort("unreachable BinFloat::pow_nat_ctx NaN")
  }
}
