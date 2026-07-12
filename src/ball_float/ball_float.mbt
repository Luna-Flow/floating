///|
pub struct BallFloat {
  priv lo_ : @bin_float.BinFloat
  priv hi_ : @bin_float.BinFloat
  priv precision_ : Int
  priv empty_ : Bool
} derive(Eq)

///|
pub(all) enum OverlapState {
  Undefined
  BothEmpty
  FirstEmpty
  SecondEmpty
  Before
  Meets
  OverlapsState
  Starts
  ContainedBy
  Finishes
  EqualIntervals
  After
  MetBy
  OverlappedBy
  StartedBy
  ContainsInterval
  FinishedBy
} derive(Eq, Debug)

///|
fn neg_inf(precision : Int) -> @bin_float.BinFloat {
  @bin_float.BinFloat::inf(Sign::Negative, precision~)
}

///|
fn pos_inf(precision : Int) -> @bin_float.BinFloat {
  @bin_float.BinFloat::inf(Sign::Positive, precision~)
}

///|
fn is_neg_inf(x : @bin_float.BinFloat) -> Bool {
  x.classify() == FpClass::Infinity && x.sign() == Sign::Negative
}

///|
fn is_pos_inf(x : @bin_float.BinFloat) -> Bool {
  x.classify() == FpClass::Infinity && x.sign() == Sign::Positive
}

///|
fn is_finite_bound(x : @bin_float.BinFloat) -> Bool {
  x.classify() == FpClass::Finite
}

///|
fn interval_validation_error(
  lo : @bin_float.BinFloat,
  hi : @bin_float.BinFloat,
) -> String? {
  if lo.classify() == FpClass::NaN || hi.classify() == FpClass::NaN {
    Some("ball bounds must not be NaN")
  } else if is_pos_inf(lo) {
    Some("ball lower bound must not be positive infinity")
  } else if is_neg_inf(hi) {
    Some("ball upper bound must not be negative infinity")
  } else if lo.compare(hi) > 0 {
    Some("ball lower bound must not exceed upper bound")
  } else {
    None
  }
}

///|
fn validate_interval(
  lo : @bin_float.BinFloat,
  hi : @bin_float.BinFloat,
) -> Unit {
  match interval_validation_error(lo, hi) {
    Some(message) => abort(message)
    None => ()
  }
}

///|
fn checked_interval(
  lo : @bin_float.BinFloat,
  hi : @bin_float.BinFloat,
  precision : Int,
) -> Result[BallFloat, String] {
  match interval_validation_error(lo, hi) {
    Some(message) => Err(message)
    None => Ok(quantize_interval(lo, hi, precision))
  }
}

///|
fn checked_exact(
  value : @bin_float.BinFloat,
  precision : Int,
) -> Result[BallFloat, String] {
  guard value.classify() == FpClass::Finite else {
    return Err("ball exact source must be finite")
  }
  Ok(
    zero_radius_interval(
      value.with_precision(exact_precision(value), RoundingMode::ToNearestEven),
      precision,
    ),
  )
}

///|
fn exact_precision(x : @bin_float.BinFloat) -> Int {
  match x.classify() {
    FpClass::Finite =>
      if x.is_zero() {
        1
      } else {
        x.coefficient().bit_length()
      }
    _ => Int::max(1, x.precision())
  }
}

///|
fn exact_make(
  coefficient : @bin_float.BinCoeff,
  exponent2 : Int,
  negative? : Bool = false,
) -> @bin_float.BinFloat {
  @bin_float.BinFloat::make(
    coefficient,
    exponent2,
    Int::max(1, coefficient.bit_length()),
    negative~,
  )
}

///|
fn exact_add(
  a : @bin_float.BinFloat,
  b : @bin_float.BinFloat,
) -> @bin_float.BinFloat {
  let target = Int::min(a.exponent2(), b.exponent2())
  let left = a.coefficient().shift_left(a.exponent2() - target)
  let right = b.coefficient().shift_left(b.exponent2() - target)
  if a.is_negative() == b.is_negative() {
    exact_make(left.add(right), target, negative=a.is_negative())
  } else {
    let comparison = left.compare(right)
    if comparison == 0 {
      exact_make(@bin_float.BinCoeff::zero(), 0)
    } else if comparison > 0 {
      exact_make(
        left.sub_checked(right).unwrap(),
        target,
        negative=a.is_negative(),
      )
    } else {
      exact_make(
        right.sub_checked(left).unwrap(),
        target,
        negative=b.is_negative(),
      )
    }
  }
}

///|
fn exact_sub(
  a : @bin_float.BinFloat,
  b : @bin_float.BinFloat,
) -> @bin_float.BinFloat {
  exact_add(a, b.neg())
}

///|
fn exact_mul(
  a : @bin_float.BinFloat,
  b : @bin_float.BinFloat,
) -> @bin_float.BinFloat {
  exact_make(
    a.coefficient().mul(b.coefficient()),
    a.exponent2() + b.exponent2(),
    negative=a.is_negative() != b.is_negative(),
  )
}

///|
fn exact_half(x : @bin_float.BinFloat) -> @bin_float.BinFloat {
  exact_make(x.coefficient(), x.exponent2() - 1, negative=x.is_negative())
}

///|
fn outward_round(
  x : @bin_float.BinFloat,
  precision : Int,
) -> @bin_float.BinFloat {
  x.with_precision(precision, RoundingMode::AwayFromZero).abs()
}

///|
fn outward_sum(
  a : @bin_float.BinFloat,
  b : @bin_float.BinFloat,
  precision : Int,
) -> @bin_float.BinFloat {
  outward_round(exact_add(a, b), precision)
}

///|
fn quantize_center_radius(
  center : @bin_float.BinFloat,
  radius : @bin_float.BinFloat,
  precision : Int,
  mode : RoundingMode,
) -> BallFloat {
  guard center.classify() == FpClass::Finite else {
    abort("ball center must be finite")
  }
  guard radius.classify() == FpClass::Finite else {
    abort("ball radius must be finite")
  }
  guard radius.sign() != Sign::Negative else {
    abort("ball radius must be non-negative")
  }
  let precision = Int::max(1, precision)
  let rounded_center = center.with_precision(precision, mode)
  let center_error = outward_round(
    exact_sub(center, rounded_center).abs(),
    precision,
  )
  let rounded_radius = outward_round(radius, precision)
  let total_radius = outward_sum(rounded_radius, center_error, precision)
  let lo = exact_sub(rounded_center, total_radius)
  let hi = exact_add(rounded_center, total_radius)
  store_interval(lo, hi, precision)
}

///|
fn lower_round_bound(
  x : @bin_float.BinFloat,
  precision : Int,
) -> @bin_float.BinFloat {
  match x.classify() {
    FpClass::Finite => x.with_precision(precision, RoundingMode::TowardNegative)
    FpClass::Infinity => @bin_float.BinFloat::inf(x.sign(), precision~)
    FpClass::NaN => abort("ball bounds must not be NaN")
  }
}

///|
fn upper_round_bound(
  x : @bin_float.BinFloat,
  precision : Int,
) -> @bin_float.BinFloat {
  match x.classify() {
    FpClass::Finite => x.with_precision(precision, RoundingMode::TowardPositive)
    FpClass::Infinity => @bin_float.BinFloat::inf(x.sign(), precision~)
    FpClass::NaN => abort("ball bounds must not be NaN")
  }
}

///|
fn store_interval(
  lo : @bin_float.BinFloat,
  hi : @bin_float.BinFloat,
  precision : Int,
) -> BallFloat {
  validate_interval(lo, hi)
  { lo_: lo, hi_: hi, precision_: Int::max(1, precision), empty_: false }
}

///|
fn empty_interval(precision : Int) -> BallFloat {
  let precision = Int::max(1, precision)
  {
    lo_: pos_inf(precision),
    hi_: neg_inf(precision),
    precision_: precision,
    empty_: true,
  }
}

///|
fn quantize_interval(
  lo : @bin_float.BinFloat,
  hi : @bin_float.BinFloat,
  precision : Int,
) -> BallFloat {
  let precision = Int::max(1, precision)
  store_interval(
    lower_round_bound(lo, precision),
    upper_round_bound(hi, precision),
    precision,
  )
}

///|
fn interval_center(x : BallFloat) -> @bin_float.BinFloat {
  guard !x.is_empty() else {
    abort("ball center is undefined for an empty interval")
  }
  guard x.is_bounded() else {
    abort("ball center is undefined for unbounded intervals")
  }
  exact_half(exact_add(x.lo_, x.hi_))
}

///|
fn interval_radius(x : BallFloat) -> @bin_float.BinFloat {
  guard !x.is_empty() else {
    abort("ball radius is undefined for an empty interval")
  }
  guard x.is_bounded() else {
    abort("ball radius is undefined for unbounded intervals")
  }
  exact_half(exact_sub(x.hi_, x.lo_)).abs()
}

///|
fn zero_radius_interval(x : @bin_float.BinFloat, precision : Int) -> BallFloat {
  quantize_interval(x, x, precision)
}

///|
fn whole_real(precision : Int) -> BallFloat {
  store_interval(neg_inf(precision), pos_inf(precision), precision)
}

///|
fn division_bounds(
  numerator : @bin_float.BinFloat,
  denominator : @bin_float.BinFloat,
  precision : Int,
) -> (@bin_float.BinFloat, @bin_float.BinFloat) {
  let work = Int::max(precision * 2 + 8, precision + 16)
  let q = numerator.with_precision(work, RoundingMode::ToNearestEven) /
    denominator.with_precision(work, RoundingMode::ToNearestEven)
  if exact_mul(q, denominator).compare(numerator) == 0 {
    (q, q)
  } else {
    let error = q.ulp()
    (exact_sub(q, error), exact_add(q, error))
  }
}

///|
fn extended_division_bounds(
  numerator : @bin_float.BinFloat,
  denominator : @bin_float.BinFloat,
  precision : Int,
) -> (@bin_float.BinFloat, @bin_float.BinFloat) {
  if numerator.is_zero() || denominator.classify() == FpClass::Infinity {
    let zero = @bin_float.BinFloat::zero(precision~)
    return (zero, zero)
  }
  if numerator.classify() == FpClass::Infinity {
    let sign = if numerator.sign() == denominator.sign() {
      Sign::Positive
    } else {
      Sign::Negative
    }
    let infinity = @bin_float.BinFloat::inf(sign, precision~)
    return (infinity, infinity)
  }
  division_bounds(numerator, denominator, precision)
}

///|
fn quotient_interval_nonzero_denominator(
  numerator : BallFloat,
  denominator : BallFloat,
  precision : Int,
) -> BallFloat {
  let (q1_lo, q1_hi) = extended_division_bounds(
    numerator.lo_,
    denominator.lo_,
    precision,
  )
  let (q2_lo, q2_hi) = extended_division_bounds(
    numerator.lo_,
    denominator.hi_,
    precision,
  )
  let (q3_lo, q3_hi) = extended_division_bounds(
    numerator.hi_,
    denominator.lo_,
    precision,
  )
  let (q4_lo, q4_hi) = extended_division_bounds(
    numerator.hi_,
    denominator.hi_,
    precision,
  )
  quantize_interval(
    bin_min(bin_min(q1_lo, q2_lo), bin_min(q3_lo, q4_lo)),
    bin_max(bin_max(q1_hi, q2_hi), bin_max(q3_hi, q4_hi)),
    precision,
  )
}

///|
fn pow_nat(base : BallFloat, exponent : UInt, precision : Int) -> BallFloat {
  let mut n = exponent
  let mut result = BallFloat::from_int(1, precision~)
  let mut factor = base.with_precision(precision, RoundingMode::ToNearestEven)
  while n > 0U {
    if (n & 1U) == 1U {
      result = (result * factor).with_precision(
        precision,
        RoundingMode::ToNearestEven,
      )
    }
    n = n >> 1
    if n > 0U {
      factor = (factor * factor).with_precision(
        precision,
        RoundingMode::ToNearestEven,
      )
    }
  }
  result
}

///|
fn add_ball_impl(a : BallFloat, b : BallFloat) -> BallFloat {
  let precision = Int::max(a.precision_, b.precision_)
  if a.is_empty() || b.is_empty() {
    return empty_interval(precision)
  }
  if a.is_bounded() && b.is_bounded() {
    return quantize_interval(
      exact_add(a.lo_, b.lo_),
      exact_add(a.hi_, b.hi_),
      precision,
    )
  }
  quantize_interval(a.lo_ + b.lo_, a.hi_ + b.hi_, precision)
}

///|
fn sub_ball_impl(a : BallFloat, b : BallFloat) -> BallFloat {
  let precision = Int::max(a.precision_, b.precision_)
  if a.is_empty() || b.is_empty() {
    return empty_interval(precision)
  }
  if a.is_bounded() && b.is_bounded() {
    return quantize_interval(
      exact_sub(a.lo_, b.hi_),
      exact_sub(a.hi_, b.lo_),
      precision,
    )
  }
  quantize_interval(a.lo_ - b.hi_, a.hi_ - b.lo_, precision)
}

///|
fn bin_min(
  a : @bin_float.BinFloat,
  b : @bin_float.BinFloat,
) -> @bin_float.BinFloat {
  if a.compare(b) <= 0 {
    a
  } else {
    b
  }
}

///|
fn bin_max(
  a : @bin_float.BinFloat,
  b : @bin_float.BinFloat,
) -> @bin_float.BinFloat {
  if a.compare(b) >= 0 {
    a
  } else {
    b
  }
}

///|
fn extended_mul(
  a : @bin_float.BinFloat,
  b : @bin_float.BinFloat,
  precision : Int,
) -> @bin_float.BinFloat {
  if a.is_zero() || b.is_zero() {
    return @bin_float.BinFloat::zero(precision~)
  }
  if a.classify() == FpClass::Infinity || b.classify() == FpClass::Infinity {
    let sign = if a.sign() == b.sign() {
      Sign::Positive
    } else {
      Sign::Negative
    }
    return @bin_float.BinFloat::inf(sign, precision~)
  }
  exact_mul(a, b)
}

///|
fn extended_add(
  a : @bin_float.BinFloat,
  b : @bin_float.BinFloat,
) -> @bin_float.BinFloat {
  if a.classify() == FpClass::Infinity {
    return a
  }
  if b.classify() == FpClass::Infinity {
    return b
  }
  exact_add(a, b)
}

///|
fn mul_ball_impl(a : BallFloat, b : BallFloat) -> BallFloat {
  let precision = Int::max(a.precision_, b.precision_)
  if a.is_empty() || b.is_empty() {
    return empty_interval(precision)
  }
  let p1 = extended_mul(a.lo_, b.lo_, precision)
  let p2 = extended_mul(a.lo_, b.hi_, precision)
  let p3 = extended_mul(a.hi_, b.lo_, precision)
  let p4 = extended_mul(a.hi_, b.hi_, precision)
  let lo = bin_min(bin_min(p1, p2), bin_min(p3, p4))
  let hi = bin_max(bin_max(p1, p2), bin_max(p3, p4))
  quantize_interval(lo, hi, precision)
}

///|
fn div_ball_impl(a : BallFloat, b : BallFloat) -> BallFloat {
  let precision = Int::max(a.precision_, b.precision_)
  if a.is_empty() || b.is_empty() {
    return empty_interval(precision)
  }
  if b.lo_.is_zero() && b.hi_.is_zero() {
    return empty_interval(precision)
  }
  if a.lo_.is_zero() && a.hi_.is_zero() {
    return zero_radius_interval(
      @bin_float.BinFloat::zero(precision~),
      precision,
    )
  }
  if !b.contains_zero() {
    return quotient_interval_nonzero_denominator(a, b, precision)
  }
  if b.lo_.sign() == Sign::Negative && b.hi_.sign() == Sign::Positive {
    return whole_real(precision)
  }
  if a.lo_.sign() == Sign::Negative && a.hi_.sign() == Sign::Positive {
    return whole_real(precision)
  }
  if b.lo_.is_zero() {
    let zero = @bin_float.BinFloat::zero(precision~)
    let finite = if is_pos_inf(b.hi_) {
      zero_radius_interval(zero, precision)
    } else {
      let one_sided = BallFloat::from_bounds(b.hi_, b.hi_, precision~)
      quotient_interval_nonzero_denominator(a, one_sided, precision)
    }
    if a.hi_.sign() == Sign::Positive {
      return store_interval(finite.lo_, pos_inf(precision), precision)
    }
    return store_interval(neg_inf(precision), finite.hi_, precision)
  }
  if b.hi_.is_zero() {
    let zero = @bin_float.BinFloat::zero(precision~)
    let finite = if is_neg_inf(b.lo_) {
      zero_radius_interval(zero, precision)
    } else {
      let one_sided = BallFloat::from_bounds(b.lo_, b.lo_, precision~)
      quotient_interval_nonzero_denominator(a, one_sided, precision)
    }
    if a.hi_.sign() == Sign::Positive {
      return store_interval(neg_inf(precision), finite.hi_, precision)
    }
    return store_interval(finite.lo_, pos_inf(precision), precision)
  }
  whole_real(precision)
}

///|
pub fn BallFloat::new(
  center : @bin_float.BinFloat,
  radius : @bin_float.BinFloat,
  precision? : Int = Int::max(center.precision(), radius.precision()),
) -> BallFloat {
  quantize_center_radius(center, radius, precision, RoundingMode::ToNearestEven)
}

///|
pub fn BallFloat::from_bounds(
  lo : @bin_float.BinFloat,
  hi : @bin_float.BinFloat,
  precision? : Int = Int::max(lo.precision(), hi.precision()),
) -> BallFloat {
  match BallFloat::try_from_bounds(lo, hi, precision~) {
    Ok(value) => value
    Err(error) => abort(error.message)
  }
}

///|
pub fn BallFloat::try_from_bounds(
  lo : @bin_float.BinFloat,
  hi : @bin_float.BinFloat,
  precision? : Int = Int::max(lo.precision(), hi.precision()),
) -> Result[BallFloat, @def.ArithmeticError] {
  checked_interval(lo, hi, precision).map_err(fn(message) {
    @def.ArithmeticError::domain_error(message)
  })
}

///|
pub fn BallFloat::exact(
  x : @bin_float.BinFloat,
  precision? : Int = x.precision(),
) -> BallFloat {
  match BallFloat::try_exact(x, precision~) {
    Ok(value) => value
    Err(error) => abort(error.message)
  }
}

///|
pub fn BallFloat::try_exact(
  value : @bin_float.BinFloat,
  precision? : Int = value.precision(),
) -> Result[BallFloat, @def.ArithmeticError] {
  checked_exact(value, precision).map_err(fn(message) {
    @def.ArithmeticError::domain_error(message)
  })
}

///|
pub fn BallFloat::from_int(n : Int, precision? : Int = 16) -> BallFloat {
  BallFloat::exact(
    @bin_float.BinFloat::from_int(n, precision=Int::max(precision, 8)),
    precision~,
  )
}

///|
pub fn BallFloat::from_coefficient(
  coefficient : @bin_float.BinCoeff,
  precision? : Int = 16,
  negative? : Bool = false,
) -> BallFloat {
  BallFloat::exact(
    @bin_float.BinFloat::from_coefficient(
      coefficient,
      precision=Int::max(precision, 8),
      negative~,
    ),
    precision~,
  )
}

///|
pub fn BallFloat::from_double(x : Double, precision? : Int = 53) -> BallFloat {
  match BallFloat::try_from_double(x, precision~) {
    Ok(value) => value
    Err(error) => abort(error.message)
  }
}

///|
pub fn BallFloat::try_from_double(
  value : Double,
  precision? : Int = 53,
) -> Result[BallFloat, @def.ArithmeticError] {
  let bin = @bin_float.BinFloat::from_double(
    value,
    precision=Int::max(precision, 53),
  )
  checked_exact(bin, precision).map_err(fn(_) {
    @def.ArithmeticError::domain_error("ball double source must be finite")
  })
}

///|
pub fn BallFloat::from_float(x : Float, precision? : Int = 24) -> BallFloat {
  match BallFloat::try_from_float(x, precision~) {
    Ok(value) => value
    Err(error) => abort(error.message)
  }
}

///|
pub fn BallFloat::try_from_float(
  value : Float,
  precision? : Int = 24,
) -> Result[BallFloat, @def.ArithmeticError] {
  let bin = @bin_float.BinFloat::from_float(
    value,
    precision=Int::max(precision, 24),
  )
  checked_exact(bin, precision).map_err(fn(_) {
    @def.ArithmeticError::domain_error("ball float source must be finite")
  })
}

///|
pub fn BallFloat::whole(precision? : Int = 53) -> BallFloat {
  whole_real(precision)
}

///|
pub fn BallFloat::empty(precision? : Int = 53) -> BallFloat {
  empty_interval(precision)
}

///|
pub fn BallFloat::lower_bound(self : BallFloat) -> @bin_float.BinFloat {
  self.lo_
}

///|
pub fn BallFloat::upper_bound(self : BallFloat) -> @bin_float.BinFloat {
  self.hi_
}

///|
pub fn BallFloat::is_bounded(self : BallFloat) -> Bool {
  !self.empty_ && is_finite_bound(self.lo_) && is_finite_bound(self.hi_)
}

///|
pub fn BallFloat::is_entire(self : BallFloat) -> Bool {
  !self.empty_ && is_neg_inf(self.lo_) && is_pos_inf(self.hi_)
}

///|
pub fn BallFloat::is_empty(self : BallFloat) -> Bool {
  self.empty_
}

///|
pub fn BallFloat::contains_zero(self : BallFloat) -> Bool {
  if self.is_empty() {
    return false
  }
  self.contains(@bin_float.BinFloat::zero(precision=self.precision_))
}

///|
pub fn BallFloat::center(self : BallFloat) -> @bin_float.BinFloat {
  interval_center(self)
}

///|
pub fn BallFloat::radius(self : BallFloat) -> @bin_float.BinFloat {
  interval_radius(self)
}

///|
pub fn BallFloat::midpoint(self : BallFloat) -> @bin_float.BinFloat {
  if self.is_entire() {
    return @bin_float.BinFloat::zero(precision=self.precision_)
  }
  self.center().with_precision(self.precision_, RoundingMode::ToNearestEven)
}

///|
pub fn BallFloat::width(self : BallFloat) -> @bin_float.BinFloat {
  if self.is_empty() {
    return @bin_float.BinFloat::zero(precision=self.precision_)
  }
  if !self.is_bounded() {
    return pos_inf(self.precision_)
  }
  upper_round_bound(exact_sub(self.hi_, self.lo_), self.precision_)
}

///|
pub fn BallFloat::magnitude(self : BallFloat) -> @bin_float.BinFloat {
  if self.is_empty() {
    return @bin_float.BinFloat::zero(precision=self.precision_)
  }
  bin_max(self.lo_.abs(), self.hi_.abs())
}

///|
pub fn BallFloat::mignitude(self : BallFloat) -> @bin_float.BinFloat {
  if self.is_empty() || self.contains_zero() {
    return @bin_float.BinFloat::zero(precision=self.precision_)
  }
  bin_min(self.lo_.abs(), self.hi_.abs())
}

///|
pub fn BallFloat::radius_extended(self : BallFloat) -> @bin_float.BinFloat {
  if self.is_empty() {
    return @bin_float.BinFloat::zero(precision=self.precision_)
  }
  if !self.is_bounded() {
    return pos_inf(self.precision_)
  }
  self.radius().with_precision(self.precision_, RoundingMode::TowardPositive)
}

///|
pub fn BallFloat::precision(self : BallFloat) -> Int {
  self.precision_
}

///|
pub fn BallFloat::classify(self : BallFloat) -> FpClass {
  if self.is_empty() {
    FpClass::NaN
  } else if self.is_bounded() {
    FpClass::Finite
  } else {
    FpClass::Infinity
  }
}

///|
pub fn BallFloat::sign(self : BallFloat) -> Sign {
  guard !self.is_empty() else { abort("empty interval has no sign") }
  if self.lo_.sign() == Sign::Positive {
    Sign::Positive
  } else if self.hi_.sign() == Sign::Negative {
    Sign::Negative
  } else {
    Sign::Zero
  }
}

///|
pub fn BallFloat::normalized(self : BallFloat) -> BallFloat {
  if self.is_empty() {
    self
  } else if self.is_bounded() {
    BallFloat::new(
      self.center().normalized(),
      self.radius().normalized(),
      precision=self.precision_,
    )
  } else {
    quantize_interval(self.lo_, self.hi_, self.precision_)
  }
}

///|
pub fn BallFloat::with_precision(
  self : BallFloat,
  precision : Int,
  mode : RoundingMode,
) -> BallFloat {
  if self.is_empty() {
    empty_interval(precision)
  } else if self.is_bounded() {
    quantize_center_radius(self.center(), self.radius(), precision, mode)
  } else {
    let precision = Int::max(1, precision)
    let lo = match self.lo_.classify() {
      FpClass::Finite =>
        self.lo_.with_precision(precision, RoundingMode::TowardNegative)
      FpClass::Infinity => @bin_float.BinFloat::inf(self.lo_.sign(), precision~)
      FpClass::NaN => abort("ball bounds must not be NaN")
    }
    let hi = match self.hi_.classify() {
      FpClass::Finite =>
        self.hi_.with_precision(precision, RoundingMode::TowardPositive)
      FpClass::Infinity => @bin_float.BinFloat::inf(self.hi_.sign(), precision~)
      FpClass::NaN => abort("ball bounds must not be NaN")
    }
    store_interval(lo, hi, precision)
  }
}

///|
pub fn BallFloat::neg(self : BallFloat) -> BallFloat {
  if self.is_empty() {
    return self
  }
  store_interval(self.hi_.neg(), self.lo_.neg(), self.precision_)
}

///|
pub fn BallFloat::abs(self : BallFloat) -> BallFloat {
  if self.is_empty() {
    return self
  }
  if self.lo_.sign() == Sign::Positive || self.lo_.is_zero() {
    self
  } else if self.hi_.sign() == Sign::Negative || self.hi_.is_zero() {
    self.neg()
  } else {
    let upper = if is_pos_inf(self.hi_) || is_neg_inf(self.lo_) {
      pos_inf(self.precision_)
    } else {
      let lo_abs = self.lo_.abs()
      let hi_abs = self.hi_.abs()
      if lo_abs.compare(hi_abs) >= 0 {
        lo_abs
      } else {
        hi_abs
      }
    }
    store_interval(
      @bin_float.BinFloat::zero(precision=self.precision_),
      upper,
      self.precision_,
    )
  }
}

///|
pub fn BallFloat::reciprocal(self : BallFloat) -> BallFloat {
  BallFloat::from_int(1, precision=self.precision_) / self
}

///|
pub fn BallFloat::square(self : BallFloat) -> BallFloat {
  if self.is_empty() {
    return self
  }
  let lo_abs = self.lo_.abs()
  let hi_abs = self.hi_.abs()
  let upper_abs = bin_max(lo_abs, hi_abs)
  let upper = extended_mul(upper_abs, upper_abs, self.precision_)
  let lower = if self.contains_zero() {
    @bin_float.BinFloat::zero(precision=self.precision_)
  } else {
    let lower_abs = bin_min(lo_abs, hi_abs)
    extended_mul(lower_abs, lower_abs, self.precision_)
  }
  quantize_interval(lower, upper, self.precision_)
}

///|
fn pown_endpoint_exponent(value : Int, exponent : UInt) -> Int {
  let product = value.to_int64() * exponent.to_uint64().reinterpret_as_int64()
  if product > 2147483647L {
    2147483647
  } else if product < -2147483648L {
    -2147483647 - 1
  } else {
    product.to_int()
  }
}

///|
fn exact_pow_nat_endpoint(
  value : @bin_float.BinFloat,
  exponent : UInt,
) -> @bin_float.BinFloat {
  if value.classify() == FpClass::Infinity {
    let sign = if value.sign() == Sign::Negative && (exponent & 1U) == 1U {
      Sign::Negative
    } else {
      Sign::Positive
    }
    return @bin_float.BinFloat::inf(sign, precision=value.precision())
  }
  if value.is_zero() {
    return @bin_float.BinFloat::zero(precision=value.precision())
  }
  exact_make(
    value.coefficient().pow_nat(exponent),
    pown_endpoint_exponent(value.exponent2(), exponent),
    negative=value.is_negative() && (exponent & 1U) == 1U,
  )
}

///|
fn pown_positive(
  value : BallFloat,
  exponent : UInt,
  precision : Int,
) -> BallFloat {
  if (exponent & 1U) == 1U {
    return quantize_interval(
      exact_pow_nat_endpoint(value.lo_, exponent),
      exact_pow_nat_endpoint(value.hi_, exponent),
      precision,
    )
  }
  let lo_power = exact_pow_nat_endpoint(value.lo_, exponent)
  let hi_power = exact_pow_nat_endpoint(value.hi_, exponent)
  if value.contains_zero() {
    quantize_interval(
      @bin_float.BinFloat::zero(precision~),
      bin_max(lo_power, hi_power),
      precision,
    )
  } else if value.hi_.sign() == Sign::Negative {
    quantize_interval(hi_power, lo_power, precision)
  } else {
    quantize_interval(lo_power, hi_power, precision)
  }
}

///|
pub fn BallFloat::pown(self : BallFloat, exponent : Int) -> BallFloat {
  if self.is_empty() {
    return self
  }
  if exponent == 0 {
    return BallFloat::from_int(1, precision=self.precision_)
  }
  let magnitude = if exponent < 0 {
    (-(exponent + 1)).reinterpret_as_uint() + 1U
  } else {
    exponent.reinterpret_as_uint()
  }
  if magnitude <= 4096U {
    if exponent > 0 {
      return pown_positive(self, magnitude, self.precision_)
    }
    let work = self.precision_ * magnitude.reinterpret_as_int() + 8
    return pown_positive(
      self.with_precision(work, RoundingMode::ToNearestEven),
      magnitude,
      work,
    ).reciprocal()
  }
  let positive = pow_nat(self, magnitude, self.precision_)
  if exponent < 0 {
    positive.reciprocal()
  } else {
    positive
  }
}

///|
pub fn BallFloat::minimum(self : BallFloat, other : BallFloat) -> BallFloat {
  let precision = Int::max(self.precision_, other.precision_)
  if self.is_empty() || other.is_empty() {
    return empty_interval(precision)
  }
  quantize_interval(
    bin_min(self.lo_, other.lo_),
    bin_min(self.hi_, other.hi_),
    precision,
  )
}

///|
pub fn BallFloat::maximum(self : BallFloat, other : BallFloat) -> BallFloat {
  let precision = Int::max(self.precision_, other.precision_)
  if self.is_empty() || other.is_empty() {
    return empty_interval(precision)
  }
  quantize_interval(
    bin_max(self.lo_, other.lo_),
    bin_max(self.hi_, other.hi_),
    precision,
  )
}

///|
pub fn BallFloat::sqrt_interval(self : BallFloat) -> BallFloat {
  if self.is_empty() {
    return self
  }
  if self.hi_.sign() == Sign::Negative {
    return empty_interval(self.precision_)
  }
  let lower = if self.lo_.sign() == Sign::Negative || self.lo_.is_zero() {
    @bin_float.BinFloat::zero(precision=self.precision_)
  } else {
    @bin_float.sqrt_bounds_for_precision(self.lo_, self.precision_).unwrap().0
  }
  let upper = if is_pos_inf(self.hi_) {
    pos_inf(self.precision_)
  } else {
    @bin_float.sqrt_bounds_for_precision(self.hi_, self.precision_).unwrap().1
  }
  quantize_interval(lower, upper, self.precision_)
}

///|
pub fn BallFloat::contains(self : BallFloat, x : @bin_float.BinFloat) -> Bool {
  if self.is_empty() {
    return false
  }
  guard x.classify() == FpClass::Finite else { return false }
  self.lo_.compare(x) <= 0 && self.hi_.compare(x) >= 0
}

///|
pub fn BallFloat::overlaps(self : BallFloat, other : BallFloat) -> Bool {
  if self.is_empty() || other.is_empty() {
    return false
  }
  self.lo_.compare(other.hi_) <= 0 && self.hi_.compare(other.lo_) >= 0
}

///|
pub fn BallFloat::separated_from(self : BallFloat, other : BallFloat) -> Bool {
  !self.overlaps(other)
}

///|
pub fn BallFloat::definitely_lt(self : BallFloat, other : BallFloat) -> Bool {
  if self.is_empty() || other.is_empty() {
    return false
  }
  self.hi_.compare(other.lo_) < 0
}

///|
pub fn BallFloat::definitely_le(self : BallFloat, other : BallFloat) -> Bool {
  if self.is_empty() || other.is_empty() {
    return false
  }
  self.hi_.compare(other.lo_) <= 0
}

///|
pub fn BallFloat::definitely_gt(self : BallFloat, other : BallFloat) -> Bool {
  if self.is_empty() || other.is_empty() {
    return false
  }
  self.lo_.compare(other.hi_) > 0
}

///|
pub fn BallFloat::maybe_eq(self : BallFloat, other : BallFloat) -> Bool {
  self.overlaps(other)
}

///|
pub fn BallFloat::set_equal(self : BallFloat, other : BallFloat) -> Bool {
  (self.is_empty() && other.is_empty()) ||
  (
    !self.is_empty() &&
    !other.is_empty() &&
    self.lo_.compare(other.lo_) == 0 &&
    self.hi_.compare(other.hi_) == 0
  )
}

///|
pub fn BallFloat::subset(self : BallFloat, other : BallFloat) -> Bool {
  self.is_empty() ||
  (
    !other.is_empty() &&
    other.lo_.compare(self.lo_) <= 0 &&
    self.hi_.compare(other.hi_) <= 0
  )
}

///|
pub fn BallFloat::interior(self : BallFloat, other : BallFloat) -> Bool {
  if self.is_empty() {
    return true
  }
  if other.is_empty() {
    return false
  }
  let lower_is_interior = other.lo_.compare(self.lo_) < 0 ||
    (is_neg_inf(other.lo_) && is_neg_inf(self.lo_))
  let upper_is_interior = self.hi_.compare(other.hi_) < 0 ||
    (is_pos_inf(self.hi_) && is_pos_inf(other.hi_))
  lower_is_interior && upper_is_interior
}

///|
pub fn BallFloat::less(self : BallFloat, other : BallFloat) -> Bool {
  (self.is_empty() && other.is_empty()) ||
  (
    !self.is_empty() &&
    !other.is_empty() &&
    self.lo_.compare(other.lo_) <= 0 &&
    self.hi_.compare(other.hi_) <= 0
  )
}

///|
pub fn BallFloat::strictly_less(self : BallFloat, other : BallFloat) -> Bool {
  if self.is_empty() || other.is_empty() {
    return self.is_empty() && other.is_empty()
  }
  let lower_is_less = self.lo_.compare(other.lo_) < 0 ||
    (is_neg_inf(self.lo_) && is_neg_inf(other.lo_))
  let upper_is_less = self.hi_.compare(other.hi_) < 0 ||
    (is_pos_inf(self.hi_) && is_pos_inf(other.hi_))
  lower_is_less && upper_is_less
}

///|
pub fn BallFloat::precedes(self : BallFloat, other : BallFloat) -> Bool {
  self.is_empty() || other.is_empty() || self.hi_.compare(other.lo_) <= 0
}

///|
pub fn BallFloat::strictly_precedes(
  self : BallFloat,
  other : BallFloat,
) -> Bool {
  self.is_empty() || other.is_empty() || self.hi_.compare(other.lo_) < 0
}

///|
pub fn BallFloat::disjoint(self : BallFloat, other : BallFloat) -> Bool {
  self.is_empty() ||
  other.is_empty() ||
  self.hi_.compare(other.lo_) < 0 ||
  other.hi_.compare(self.lo_) < 0
}

///|
pub fn BallFloat::is_common_interval(self : BallFloat) -> Bool {
  self.is_bounded()
}

///|
pub fn BallFloat::is_singleton(self : BallFloat) -> Bool {
  !self.is_empty() && self.lo_.compare(self.hi_) == 0
}

///|
pub fn BallFloat::intersection(
  self : BallFloat,
  other : BallFloat,
) -> BallFloat {
  let precision = Int::max(self.precision_, other.precision_)
  if self.is_empty() || other.is_empty() {
    return empty_interval(precision)
  }
  let lo = bin_max(self.lo_, other.lo_)
  let hi = bin_min(self.hi_, other.hi_)
  if lo.compare(hi) > 0 {
    empty_interval(precision)
  } else {
    quantize_interval(lo, hi, precision)
  }
}

///|
pub fn BallFloat::convex_hull(self : BallFloat, other : BallFloat) -> BallFloat {
  let precision = Int::max(self.precision_, other.precision_)
  if self.is_empty() {
    return other.with_precision(precision, RoundingMode::ToNearestEven)
  }
  if other.is_empty() {
    return self.with_precision(precision, RoundingMode::ToNearestEven)
  }
  quantize_interval(
    bin_min(self.lo_, other.lo_),
    bin_max(self.hi_, other.hi_),
    precision,
  )
}

///|
pub fn BallFloat::cancel_plus(self : BallFloat, other : BallFloat) -> BallFloat {
  let precision = Int::max(self.precision_, other.precision_)
  if self.is_empty() {
    return if other.is_empty() || other.is_bounded() {
      empty_interval(precision)
    } else {
      whole_real(precision)
    }
  }
  if other.is_empty() || !self.is_bounded() || !other.is_bounded() {
    return whole_real(precision)
  }
  let lo = exact_add(self.lo_, other.hi_)
  let hi = exact_add(self.hi_, other.lo_)
  if lo.compare(hi) > 0 {
    whole_real(precision)
  } else {
    quantize_interval(lo, hi, precision)
  }
}

///|
pub fn BallFloat::cancel_minus(
  self : BallFloat,
  other : BallFloat,
) -> BallFloat {
  let precision = Int::max(self.precision_, other.precision_)
  if self.is_empty() {
    return if other.is_empty() || other.is_bounded() {
      empty_interval(precision)
    } else {
      whole_real(precision)
    }
  }
  if other.is_empty() || !self.is_bounded() || !other.is_bounded() {
    return whole_real(precision)
  }
  let lo = exact_sub(self.lo_, other.lo_)
  let hi = exact_sub(self.hi_, other.hi_)
  if lo.compare(hi) > 0 {
    whole_real(precision)
  } else {
    quantize_interval(lo, hi, precision)
  }
}

///|
pub fn BallFloat::overlap_state(
  self : BallFloat,
  other : BallFloat,
) -> OverlapState {
  if self.is_empty() {
    return if other.is_empty() { BothEmpty } else { FirstEmpty }
  }
  if other.is_empty() {
    return SecondEmpty
  }
  let lo_cmp = self.lo_.compare(other.lo_)
  let hi_cmp = self.hi_.compare(other.hi_)
  let self_hi_other_lo = self.hi_.compare(other.lo_)
  let self_lo_other_hi = self.lo_.compare(other.hi_)
  if lo_cmp == 0 && hi_cmp == 0 {
    EqualIntervals
  } else if lo_cmp == 0 && hi_cmp < 0 {
    Starts
  } else if lo_cmp == 0 {
    StartedBy
  } else if hi_cmp == 0 && lo_cmp > 0 {
    Finishes
  } else if hi_cmp == 0 {
    FinishedBy
  } else if self_hi_other_lo < 0 {
    Before
  } else if self_hi_other_lo == 0 && hi_cmp < 0 {
    Meets
  } else if self_lo_other_hi > 0 {
    After
  } else if self_lo_other_hi == 0 && lo_cmp > 0 {
    MetBy
  } else if lo_cmp > 0 && hi_cmp < 0 {
    ContainedBy
  } else if lo_cmp < 0 && hi_cmp > 0 {
    ContainsInterval
  } else if lo_cmp < 0 {
    OverlapsState
  } else {
    OverlappedBy
  }
}

///|
pub fn BallFloat::add(self : BallFloat, other : BallFloat) -> BallFloat {
  add_ball_impl(self, other)
}

///|
pub fn BallFloat::sub(self : BallFloat, other : BallFloat) -> BallFloat {
  sub_ball_impl(self, other)
}

///|
pub fn BallFloat::mul(self : BallFloat, other : BallFloat) -> BallFloat {
  mul_ball_impl(self, other)
}

///|
pub fn BallFloat::div(self : BallFloat, other : BallFloat) -> BallFloat {
  div_ball_impl(self, other)
}

///|
pub fn BallFloat::fma(
  self : BallFloat,
  multiplier : BallFloat,
  addend : BallFloat,
) -> BallFloat {
  let precision = Int::max(
    self.precision_,
    Int::max(multiplier.precision_, addend.precision_),
  )
  if self.is_empty() || multiplier.is_empty() || addend.is_empty() {
    return empty_interval(precision)
  }
  let p1 = extended_mul(self.lo_, multiplier.lo_, precision)
  let p2 = extended_mul(self.lo_, multiplier.hi_, precision)
  let p3 = extended_mul(self.hi_, multiplier.lo_, precision)
  let p4 = extended_mul(self.hi_, multiplier.hi_, precision)
  let product_lo = bin_min(bin_min(p1, p2), bin_min(p3, p4))
  let product_hi = bin_max(bin_max(p1, p2), bin_max(p3, p4))
  quantize_interval(
    extended_add(product_lo, addend.lo_),
    extended_add(product_hi, addend.hi_),
    precision,
  )
}

///|
pub impl @lf_arith.Contains for BallFloat with fn contains(self, other) {
  other.subset(self)
}

///|
pub impl @lf_arith.Overlaps for BallFloat with fn overlaps(self, other) {
  self.overlaps(other)
}

///|
pub impl @lf_arith.DefinitelyLt for BallFloat with fn definitely_lt(self, other) {
  self.definitely_lt(other)
}

///|
pub impl @lf_arith.DefinitelyLe for BallFloat with fn definitely_le(self, other) {
  self.definitely_le(other)
}

///|
pub impl @lf_arith.MaybeEq for BallFloat with fn maybe_eq(self, other) {
  self.maybe_eq(other)
}

///|
pub impl @lf_arith.DivChecked for BallFloat with fn div_checked(
  self,
  other,
  ctx,
) {
  let precision = ctx.precision
  let lhs = self.with_precision(precision, RoundingMode::ToNearestEven)
  let rhs = other.with_precision(precision, RoundingMode::ToNearestEven)
  Ok(lhs.div(rhs).with_precision(precision, RoundingMode::ToNearestEven))
}

///|
pub impl @lf_arith.PowNatChecked for BallFloat with fn pow_nat_checked(
  self,
  exponent,
  ctx,
) {
  let precision = ctx.precision
  let base = self.with_precision(precision, RoundingMode::ToNearestEven)
  Ok(pow_nat(base, exponent, precision))
}

///|
pub impl @lf_arith.PowIntChecked for BallFloat with fn pow_int_checked(
  self,
  exponent,
  ctx,
) {
  let precision = ctx.precision
  let base = self.with_precision(precision, RoundingMode::ToNearestEven)
  Ok(base.pown(exponent).with_precision(precision, RoundingMode::ToNearestEven))
}

///|
pub impl Add for BallFloat with fn add(self, other) {
  add_ball_impl(self, other)
}

///|
pub impl Sub for BallFloat with fn sub(self, other) {
  sub_ball_impl(self, other)
}

///|
pub impl Mul for BallFloat with fn mul(self, other) {
  mul_ball_impl(self, other)
}

///|
pub impl Div for BallFloat with fn div(self, other) {
  div_ball_impl(self, other)
}

///|
pub impl Neg for BallFloat with fn neg(self) {
  self.neg()
}

///|
pub impl @def.Floating for BallFloat with fn classify(self) {
  self.classify()
}

///|
pub impl @def.Floating for BallFloat with fn sign(self) {
  self.sign()
}

///|
pub impl @def.Floating for BallFloat with fn precision(self) {
  self.precision()
}

///|
pub impl @def.Floating for BallFloat with fn with_precision(
  self,
  precision,
  mode,
) {
  self.with_precision(precision, mode)
}

///|
pub impl @def.Floating for BallFloat with fn normalized(self) {
  self.normalized()
}

///|
pub impl Show for BallFloat with fn to_string(self) {
  if self.is_empty() {
    "[empty]"
  } else if self.is_bounded() {
    self.center().to_string() + " +/- " + self.radius().to_string()
  } else {
    "[" + self.lo_.to_string() + ", " + self.hi_.to_string() + "]"
  }
}
