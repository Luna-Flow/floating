///|
pub struct BallContext {
  priv precision : Int
  priv e_min : Int
  priv e_max : Int
}

///|
pub struct BallFlags {
  inexact : Bool
  overflow : Bool
  underflow : Bool
} derive(Eq)

///|
pub fn BallFlags::new() -> BallFlags {
  { inexact: false, overflow: false, underflow: false }
}

///|
pub fn BallFlags::combine(self : BallFlags, other : BallFlags) -> BallFlags {
  {
    inexact: self.inexact || other.inexact,
    overflow: self.overflow || other.overflow,
    underflow: self.underflow || other.underflow,
  }
}

///|
pub fn BallFlags::inexact(self : BallFlags) -> Bool {
  self.inexact
}

///|
pub fn BallFlags::overflow(self : BallFlags) -> Bool {
  self.overflow
}

///|
pub fn BallFlags::underflow(self : BallFlags) -> Bool {
  self.underflow
}

///|
pub fn BallContext::try_new(
  precision? : Int = 53,
  e_min? : Int = -1022,
  e_max? : Int = 1023,
) -> Result[BallContext, @def.ArithmeticError] {
  guard precision > 0 else {
    return Err(
      @def.ArithmeticError::domain_error(
        "BallContext::try_new: precision must be positive",
      ),
    )
  }
  guard e_min <= e_max else {
    return Err(
      @def.ArithmeticError::domain_error(
        "BallContext::try_new: e_min must not exceed e_max",
      ),
    )
  }
  Ok({ precision, e_min, e_max })
}

///|
pub fn BallContext::new(
  precision? : Int = 53,
  e_min? : Int = -1022,
  e_max? : Int = 1023,
) -> BallContext {
  guard precision > 0 else {
    abort("BallContext::new: precision must be positive")
  }
  guard e_min <= e_max else {
    abort("BallContext::new: e_min must not exceed e_max")
  }
  { precision, e_min, e_max }
}

///|
pub fn BallContext::precision(self : BallContext) -> Int {
  self.precision
}

///|
pub fn BallContext::e_min(self : BallContext) -> Int {
  self.e_min
}

///|
pub fn BallContext::e_max(self : BallContext) -> Int {
  self.e_max
}

///|
fn ball_context_from_format(
  format : @bin_float.BinaryInterchangeFormat,
) -> BallContext {
  BallContext::new(
    precision=format.precision(),
    e_min=format.e_min(),
    e_max=format.e_max(),
  )
}

///|
pub fn BallContext::binary32() -> BallContext {
  ball_context_from_format(@bin_float.BinaryInterchangeFormat::Binary32)
}

///|
pub fn BallContext::binary64() -> BallContext {
  ball_context_from_format(@bin_float.BinaryInterchangeFormat::Binary64)
}

///|
fn finite_adjusted_exponent(value : @bin_float.BinFloat) -> Int {
  value.exponent2() + value.coefficient().bit_length() - 1
}

///|
fn context_max_finite(ctx : BallContext) -> @bin_float.BinFloat {
  let coefficient = @bin_float.BinCoeff::one()
    .shift_left(ctx.precision)
    .sub_checked(@bin_float.BinCoeff::one())
    .unwrap()
  @bin_float.BinFloat::make(
    coefficient,
    ctx.e_max - ctx.precision + 1,
    ctx.precision,
  )
}

///|
fn ball_round_shift(
  magnitude : @bin_float.BinCoeff,
  shift : Int,
  negative : Bool,
  mode : RoundingMode,
) -> @bin_float.BinCoeff {
  if shift <= 0 {
    return magnitude
  }
  let quotient = magnitude.shift_right(shift)
  let remainder = magnitude.sub_checked(quotient.shift_left(shift)).unwrap()
  if remainder.is_zero() {
    return quotient
  }
  let increment = match mode {
    RoundingMode::TowardZero => false
    RoundingMode::TowardPositive => !negative
    RoundingMode::TowardNegative => negative
    RoundingMode::AwayFromZero => true
    RoundingMode::ToNearestEven => {
      let comparison = remainder
        .shift_left(1)
        .compare(@bin_float.BinCoeff::one().shift_left(shift))
      comparison > 0 || (comparison == 0 && quotient.test_bit(0))
    }
  }
  if increment {
    quotient.add(@bin_float.BinCoeff::one())
  } else {
    quotient
  }
}

///|
fn context_round_subnormal(
  value : @bin_float.BinFloat,
  ctx : BallContext,
  mode : RoundingMode,
) -> (@bin_float.BinFloat, Bool, Bool) {
  let e_tiny = ctx.e_min - ctx.precision + 1
  if value.exponent2() >= e_tiny {
    return (value, false, false)
  }
  let negative = value.sign() == Sign::Negative
  let shift = e_tiny - value.exponent2()
  let rounded_magnitude = ball_round_shift(
    value.coefficient(),
    shift,
    negative,
    mode,
  )
  let rounded = @bin_float.BinFloat::make(
    rounded_magnitude,
    e_tiny,
    ctx.precision,
    negative~,
  )
  let inexact = rounded.compare(value) != 0
  (rounded, inexact, inexact)
}

///|
fn context_round_lower(
  value : @bin_float.BinFloat,
  ctx : BallContext,
) -> (@bin_float.BinFloat, Bool, Bool, Bool) {
  if value.classify() != FpClass::Finite || value.is_zero() {
    return (value, false, false, false)
  }
  let rounded = value.with_precision(
    ctx.precision,
    RoundingMode::TowardNegative,
  )
  if finite_adjusted_exponent(rounded) > ctx.e_max {
    let overflowed = if rounded.sign() == Sign::Negative {
      neg_inf(ctx.precision)
    } else {
      context_max_finite(ctx)
    }
    return (overflowed, true, false, true)
  }
  let (result, underflow, tiny_inexact) = context_round_subnormal(
    rounded,
    ctx,
    RoundingMode::TowardNegative,
  )
  (result, false, underflow, tiny_inexact || rounded.compare(value) != 0)
}

///|
fn context_round_upper(
  value : @bin_float.BinFloat,
  ctx : BallContext,
) -> (@bin_float.BinFloat, Bool, Bool, Bool) {
  if value.classify() != FpClass::Finite || value.is_zero() {
    return (value, false, false, false)
  }
  let rounded = value.with_precision(
    ctx.precision,
    RoundingMode::TowardPositive,
  )
  if finite_adjusted_exponent(rounded) > ctx.e_max {
    let overflowed = if rounded.sign() == Sign::Positive {
      pos_inf(ctx.precision)
    } else {
      context_max_finite(ctx).neg()
    }
    return (overflowed, true, false, true)
  }
  let (result, underflow, tiny_inexact) = context_round_subnormal(
    rounded,
    ctx,
    RoundingMode::TowardPositive,
  )
  (result, false, underflow, tiny_inexact || rounded.compare(value) != 0)
}

///|
pub fn BallFloat::apply_ctx(
  self : BallFloat,
  ctx : BallContext,
) -> (BallFloat, BallFlags) {
  if self.is_empty() {
    return (BallFloat::empty(precision=ctx.precision), BallFlags::new())
  }
  let (lo, lo_overflow, lo_underflow, lo_inexact) = context_round_lower(
    self.lo_,
    ctx,
  )
  let (hi, hi_overflow, hi_underflow, hi_inexact) = context_round_upper(
    self.hi_,
    ctx,
  )
  let overflow = lo_overflow || hi_overflow
  let underflow = lo_underflow || hi_underflow
  (
    store_interval(lo, hi, ctx.precision),
    { inexact: lo_inexact || hi_inexact, overflow, underflow },
  )
}

///|
pub fn BallFloat::midpoint_ctx(
  self : BallFloat,
  ctx : BallContext,
) -> (@bin_float.BinFloat, BallFlags) {
  if self.is_entire() {
    return (
      @bin_float.BinFloat::zero(precision=ctx.precision),
      BallFlags::new(),
    )
  }
  let exact = interval_center(self)
  let rounded = exact.with_precision(ctx.precision, RoundingMode::ToNearestEven)
  let (result, underflow, tiny_inexact) = context_round_subnormal(
    rounded,
    ctx,
    RoundingMode::ToNearestEven,
  )
  (
    result,
    {
      inexact: tiny_inexact || rounded.compare(exact) != 0,
      overflow: false,
      underflow,
    },
  )
}

///|
pub fn BallFloat::add_ctx(
  self : BallFloat,
  other : BallFloat,
  ctx : BallContext,
) -> (BallFloat, BallFlags) {
  (self + other).apply_ctx(ctx)
}

///|
pub fn BallFloat::sub_ctx(
  self : BallFloat,
  other : BallFloat,
  ctx : BallContext,
) -> (BallFloat, BallFlags) {
  (self - other).apply_ctx(ctx)
}

///|
pub fn BallFloat::mul_ctx(
  self : BallFloat,
  other : BallFloat,
  ctx : BallContext,
) -> (BallFloat, BallFlags) {
  (self * other).apply_ctx(ctx)
}

///|
pub fn BallFloat::div_ctx(
  self : BallFloat,
  other : BallFloat,
  ctx : BallContext,
) -> (BallFloat, BallFlags) {
  (self / other).apply_ctx(ctx)
}
