///|
pub struct IntervalContext {
  priv precision : Int32
  priv e_min : Int32
  priv e_max : Int32
}

///|
#derive(Eq)
pub struct IntervalFlags {
  priv inexact : Bool
  priv overflow : Bool
  priv underflow : Bool
}

///|
pub fn IntervalFlags::new() -> IntervalFlags {
  { inexact: false, overflow: false, underflow: false, }
}

///|
pub fn IntervalFlags::combine(
  self : IntervalFlags,
  other : IntervalFlags,
) -> IntervalFlags {
  {
    inexact: self.inexact || other.inexact,
    overflow: self.overflow || other.overflow,
    underflow: self.underflow || other.underflow,
  }
}

///|
pub fn IntervalFlags::inexact(self : IntervalFlags) -> Bool {
  self.inexact
}

///|
pub fn IntervalFlags::overflow(self : IntervalFlags) -> Bool {
  self.overflow
}

///|
pub fn IntervalFlags::underflow(self : IntervalFlags) -> Bool {
  self.underflow
}

///|
/// A binary format of IEEE 754-2019 3.3 for the endpoints of an interval:
/// `precision` bits and the exponent range `[1 - e_max, e_max]`. The legality
/// of the pair is decided by `@binary.BinaryContext`, so the two packages
/// have one definition of a format. `e_max` absent is the implementation limit
/// `@binary.binary_implementation_e_max`.
pub fn IntervalContext::try_new(
  precision~ : Int32 = 53,
  e_max? : Int32,
) -> Result[IntervalContext, @def.ArithmeticError] {
  let format = match e_max {
    Some(value) => @binary.BinaryContext::try_new(precision~, e_max=value)
    None => @binary.BinaryContext::try_new(precision~)
  }
  format.map(fn(format) {
    {
      precision: format.precision(),
      e_min: format.e_min(),
      e_max: format.e_max(),
    }
  })
}

///|
/// `try_new` that aborts on an illegal precision or exponent range, naming
/// the parameter.
pub fn IntervalContext::new(
  precision~ : Int32 = 53,
  e_max? : Int32,
) -> IntervalContext {
  match IntervalContext::try_new(precision~, e_max?) {
    Ok(context) => context
    Err(error) => abort("IntervalContext::new: " + error.message)
  }
}

///|
pub fn IntervalContext::precision(self : IntervalContext) -> Int32 {
  self.precision
}

///|
pub fn IntervalContext::e_min(self : IntervalContext) -> Int32 {
  self.e_min
}

///|
pub fn IntervalContext::e_max(self : IntervalContext) -> Int32 {
  self.e_max
}

///|
/// The same format with another precision; aborts when it is not legal.
pub fn IntervalContext::with_precision(
  self : IntervalContext,
  precision : Int32,
) -> IntervalContext {
  IntervalContext::new(precision~, e_max=self.e_max)
}

///|
/// The same precision with another largest exponent (`e_min` becomes
/// `1 - e_max`); aborts when it is not legal.
pub fn IntervalContext::with_e_max(
  self : IntervalContext,
  e_max : Int32,
) -> IntervalContext {
  IntervalContext::new(precision=self.precision, e_max~)
}

///|
fn interval_context_from_format(
  format : @binary.BinaryContext,
) -> IntervalContext {
  IntervalContext::new(precision=format.precision(), e_max=format.e_max())
}

///|
pub fn IntervalContext::binary16() -> IntervalContext {
  interval_context_from_format(@binary.BinaryContext::binary16())
}

///|
pub fn IntervalContext::binary32() -> IntervalContext {
  interval_context_from_format(@binary.BinaryContext::binary32())
}

///|
pub fn IntervalContext::binary64() -> IntervalContext {
  interval_context_from_format(@binary.BinaryContext::binary64())
}

///|
pub fn IntervalContext::binary128() -> IntervalContext {
  interval_context_from_format(@binary.BinaryContext::binary128())
}

///|
fn finite_adjusted_exponent(value : @binary.Binary) -> Int32 {
  match value.ilogb() {
    Some(top) => top
    None => value.exponent2() - 1
  }
}

///|
fn context_max_finite(ctx : IntervalContext) -> @binary.Binary {
  let coefficient = coeff_sub(
    coeff_shift_left(coeff_one(), ctx.precision),
    coeff_one(),
  )
  @binary.Binary::make(
    coefficient,
    ctx.e_max - ctx.precision + 1,
    ctx.precision,
  )
}

///|
fn interval_round_shift(
  magnitude : @binary.BinCoeff,
  shift : Int32,
  negative : Bool,
  mode : BinaryRoundingMode,
) -> @binary.BinCoeff {
  if shift <= 0 {
    return magnitude
  }
  let quotient = coeff_shift_right(magnitude, shift)
  let remainder = coeff_sub(magnitude, coeff_shift_left(quotient, shift))
  if remainder.is_zero() {
    return quotient
  }
  let increment = match mode {
    BinaryRoundingMode::RoundTowardZero => false
    BinaryRoundingMode::RoundTowardPositive => !negative
    BinaryRoundingMode::RoundTowardNegative => negative
    BinaryRoundingMode::RoundTiesToEven => {
      let comparison = coeff_shift_left(remainder, 1).compare(
        coeff_shift_left(coeff_one(), shift),
      )
      comparison > 0 || (comparison == 0 && coeff_test_bit(quotient, 0))
    }
    BinaryRoundingMode::RoundTiesToAway =>
      coeff_shift_left(remainder, 1).compare(
        coeff_shift_left(coeff_one(), shift),
      ) >=
      0
  }
  if increment {
    coeff_increment(quotient)
  } else {
    quotient
  }
}

///|
fn context_round_subnormal(
  value : @binary.Binary,
  ctx : IntervalContext,
  mode : BinaryRoundingMode,
) -> (@binary.Binary, Bool, Bool) {
  let e_tiny = ctx.e_min - ctx.precision + 1
  if value.exponent2() >= e_tiny {
    return (value, false, false)
  }
  let negative = value.signum() == Sign::Negative
  let shift = e_tiny - value.exponent2()
  let rounded_magnitude = interval_round_shift(
    value.coefficient(),
    shift,
    negative,
    mode,
  )
  let rounded = @binary.Binary::make(
    rounded_magnitude,
    e_tiny,
    ctx.precision,
    negative~,
  )
  let inexact = rounded.compare(value) != 0
  (rounded, inexact, inexact)
}

///|
/// IEEE 754 tininess after rounding: `rounded` is the value rounded to the
/// context precision with an unbounded exponent range. Underflow is raised
/// when the result is tiny and inexact, whichever rounding step lost the bits.
fn context_is_tiny(rounded : @binary.Binary, ctx : IntervalContext) -> Bool {
  rounded.classify() == FpClass::Finite &&
  !rounded.is_zero() &&
  finite_adjusted_exponent(rounded) < ctx.e_min
}

///|
fn context_round_lower(
  value : @binary.Binary,
  ctx : IntervalContext,
) -> (@binary.Binary, Bool, Bool, Bool) {
  if value.classify() != FpClass::Finite || value.is_zero() {
    return (value, false, false, false)
  }
  let rounded = value.with_precision(
    ctx.precision,
    @binary.BinaryRoundingMode::RoundTowardNegative,
  )
  if finite_adjusted_exponent(rounded) > ctx.e_max {
    let overflowed = if rounded.signum() == Sign::Negative {
      neg_inf(ctx.precision)
    } else {
      context_max_finite(ctx)
    }
    return (overflowed, true, false, true)
  }
  let (result, _, tiny_inexact) = context_round_subnormal(
    rounded,
    ctx,
    BinaryRoundingMode::RoundTowardNegative,
  )
  let inexact = tiny_inexact || rounded.compare(value) != 0
  (result, false, inexact && context_is_tiny(rounded, ctx), inexact)
}

///|
fn context_round_upper(
  value : @binary.Binary,
  ctx : IntervalContext,
) -> (@binary.Binary, Bool, Bool, Bool) {
  if value.classify() != FpClass::Finite || value.is_zero() {
    return (value, false, false, false)
  }
  let rounded = value.with_precision(
    ctx.precision,
    @binary.BinaryRoundingMode::RoundTowardPositive,
  )
  if finite_adjusted_exponent(rounded) > ctx.e_max {
    let overflowed = if rounded.signum() == Sign::Positive {
      pos_inf(ctx.precision)
    } else {
      context_max_finite(ctx).neg()
    }
    return (overflowed, true, false, true)
  }
  let (result, _, tiny_inexact) = context_round_subnormal(
    rounded,
    ctx,
    BinaryRoundingMode::RoundTowardPositive,
  )
  let inexact = tiny_inexact || rounded.compare(value) != 0
  (result, false, inexact && context_is_tiny(rounded, ctx), inexact)
}

///|
pub fn Interval::apply_ctx(
  self : Interval,
  ctx : IntervalContext,
) -> (Interval, IntervalFlags) {
  if self.is_empty() {
    return (Interval::empty(precision=ctx.precision), IntervalFlags::new())
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
    { inexact: lo_inexact || hi_inexact, overflow, underflow, },
  )
}

///|
/// `midpoint` in the format of `ctx`. When the precision of `ctx` is lower than
/// the number of bits of the endpoints the rounded midpoint can lie outside the
/// interval: the format is then not compatible with the interval (the NOTE of
/// IEEE 1788-2015 12.12.8: for `[1 + u, 1 + 2u]` of binary64 in binary32 no
/// F-number lies in the interval and `mid` is 1). With the precision of the
/// interval (`midpoint`) the midpoint is a member.
pub fn Interval::midpoint_ctx(
  self : Interval,
  ctx : IntervalContext,
) -> (@binary.Binary, IntervalFlags) {
  // IEEE 1788-2015 12.12.8: mid is NaN for Empty, 0 for Entire, the finite
  // number of largest magnitude of the result format (the context) for a
  // half-bounded interval, and the exact midpoint rounded to nearest
  // otherwise. A Level 1 value of 0 is returned as +0.
  if self.is_empty() {
    return (@binary.Binary::nan(precision=ctx.precision), IntervalFlags::new())
  }
  if self.is_entire() {
    return (@binary.Binary::zero(precision=ctx.precision), IntervalFlags::new())
  }
  if !self.is_common_interval() {
    let max = context_max_finite(ctx)
    return (
      if is_neg_inf(self.lo_) {
        max.neg()
      } else {
        max
      },
      IntervalFlags::new(),
    )
  }
  // the centre is rounded once to the precision of the context: the sum of the
  // bounds keeps every bit down to it (and to the precision of the interval)
  let exact = interval_center(self, Int32::max(ctx.precision, self.precision_))
  if exact.is_zero() {
    return (@binary.Binary::zero(precision=ctx.precision), IntervalFlags::new())
  }
  // Round once, straight to the grid the result lives on. Rounding a tiny
  // center to the context precision first and then to the subnormal grid
  // rounds twice to nearest and can pick the wrong grid point.
  let normal_rounding = exact.with_precision(
    ctx.precision,
    @binary.BinaryRoundingMode::RoundTiesToEven,
  )
  let rounded = if finite_adjusted_exponent(exact) < ctx.e_min {
    // A tiny center has fewer than `precision` bits above the grid, so the
    // final `with_precision` only sets the precision tag.
    context_round_subnormal(exact, ctx, BinaryRoundingMode::RoundTiesToEven).0.with_precision(
      ctx.precision,
      @binary.BinaryRoundingMode::RoundTiesToEven,
    )
  } else {
    normal_rounding
  }
  let inexact = rounded.compare(exact) != 0
  if !rounded.is_zero() && finite_adjusted_exponent(rounded) > ctx.e_max {
    // Round to nearest overflows to an infinity of the center's sign.
    return (
      @binary.Binary::inf(
        negative=exact.is_sign_minus(),
        precision=ctx.precision,
      ),
      { inexact: true, overflow: true, underflow: false, },
    )
  }
  let underflow = inexact && context_is_tiny(normal_rounding, ctx)
  (rounded, { inexact, overflow: false, underflow, })
}

///|
pub extend IntervalFlags with Eq::{not_equal, equal}
