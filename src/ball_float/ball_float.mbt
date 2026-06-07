///|
pub struct BallFloat {
  priv lo_ : @bin_float.BinFloat
  priv hi_ : @bin_float.BinFloat
  priv precision_ : Int
} derive(Eq)

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
fn validate_bound(x : @bin_float.BinFloat) -> Unit {
  guard x.classify() != FpClass::NaN else {
    abort("ball bounds must not be NaN")
  }
}

///|
fn validate_interval(
  lo : @bin_float.BinFloat,
  hi : @bin_float.BinFloat,
) -> Unit {
  validate_bound(lo)
  validate_bound(hi)
  guard lo.compare(hi) <= 0 else {
    abort("ball lower bound must not exceed upper bound")
  }
}

///|
fn exact_precision(x : @bin_float.BinFloat) -> Int {
  match x.classify() {
    FpClass::Finite =>
      if x.is_zero() {
        1
      } else {
        @internal.abs_bigint(x.significand()).bit_length()
      }
    _ => Int::max(1, x.precision())
  }
}

///|
fn exact_make(significand : BigInt, exponent2 : Int) -> @bin_float.BinFloat {
  @bin_float.BinFloat::make(
    significand,
    exponent2,
    Int::max(1, @internal.abs_bigint(significand).bit_length()),
  )
}

///|
fn exact_add(
  a : @bin_float.BinFloat,
  b : @bin_float.BinFloat,
) -> @bin_float.BinFloat {
  let target = Int::min(a.exponent2(), b.exponent2())
  let sa = a.significand() << (a.exponent2() - target)
  let sb = b.significand() << (b.exponent2() - target)
  exact_make(sa + sb, target)
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
  exact_make(a.significand() * b.significand(), a.exponent2() + b.exponent2())
}

///|
fn exact_half(x : @bin_float.BinFloat) -> @bin_float.BinFloat {
  exact_make(x.significand(), x.exponent2() - 1)
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
fn quantize_center_radius_approx(
  center_high : @bin_float.BinFloat,
  center_high_error : @bin_float.BinFloat,
  radius : @bin_float.BinFloat,
  precision : Int,
  mode : RoundingMode,
) -> BallFloat {
  let precision = Int::max(1, precision)
  let rounded_center = center_high.with_precision(precision, mode)
  let retune_error = outward_round(
    exact_sub(center_high, rounded_center).abs(),
    precision,
  )
  let rounded_radius = outward_round(radius, precision)
  let high_error = outward_round(center_high_error, precision)
  let total_radius = outward_sum(
    outward_sum(rounded_radius, high_error, precision),
    retune_error,
    precision,
  )
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
  { lo_: lo, hi_: hi, precision_: Int::max(1, precision) }
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
  guard x.is_bounded() else {
    abort("ball center is undefined for unbounded intervals")
  }
  exact_half(exact_add(x.lo_, x.hi_))
}

///|
fn interval_radius(x : BallFloat) -> @bin_float.BinFloat {
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
fn div_high_precision(
  numerator : @bin_float.BinFloat,
  denominator : @bin_float.BinFloat,
  precision : Int,
) -> (@bin_float.BinFloat, @bin_float.BinFloat) {
  let high_precision = Int::max(precision + 4, precision * 2 + 4)
  let q = numerator.with_precision(high_precision, RoundingMode::ToNearestEven) /
    denominator.with_precision(high_precision, RoundingMode::ToNearestEven)
  (q.with_precision(high_precision, RoundingMode::ToNearestEven), q.ulp())
}

///|
fn reciprocal_interval_for_nonzero(x : BallFloat, precision : Int) -> BallFloat {
  let lo = x.lo_
  let hi = x.hi_
  if lo.sign() == Sign::Positive {
    quantize_interval(
      @bin_float.BinFloat::one(precision~) / hi,
      @bin_float.BinFloat::one(precision~) / lo,
      precision,
    )
  } else if hi.sign() == Sign::Negative {
    quantize_interval(
      @bin_float.BinFloat::one(precision~) / hi,
      @bin_float.BinFloat::one(precision~) / lo,
      precision,
    )
  } else {
    whole_real(precision)
  }
}

///|
fn pow_nat(base : BallFloat, exponent : Int, precision : Int) -> BallFloat {
  let mut n = exponent
  let mut result = BallFloat::from_int(1, precision~)
  let mut factor = base.with_precision(precision, RoundingMode::ToNearestEven)
  while n > 0 {
    if (n & 1) == 1 {
      result = (result * factor).with_precision(
        precision,
        RoundingMode::ToNearestEven,
      )
    }
    n = n >> 1
    if n > 0 {
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
  if a.is_bounded() && b.is_bounded() {
    let center = exact_add(a.center(), b.center())
    let radius = exact_add(a.radius(), b.radius())
    return quantize_center_radius(
      center,
      radius,
      precision,
      RoundingMode::ToNearestEven,
    )
  }
  quantize_interval(a.lo_ + b.lo_, a.hi_ + b.hi_, precision)
}

///|
fn sub_ball_impl(a : BallFloat, b : BallFloat) -> BallFloat {
  let precision = Int::max(a.precision_, b.precision_)
  if a.is_bounded() && b.is_bounded() {
    let center = exact_sub(a.center(), b.center())
    let radius = exact_add(a.radius(), b.radius())
    return quantize_center_radius(
      center,
      radius,
      precision,
      RoundingMode::ToNearestEven,
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
fn mul_ball_impl(a : BallFloat, b : BallFloat) -> BallFloat {
  let precision = Int::max(a.precision_, b.precision_)
  if a.is_bounded() && b.is_bounded() {
    let ac = a.center()
    let ar = a.radius()
    let bc = b.center()
    let br = b.radius()
    let center = exact_mul(ac, bc)
    let radius = exact_add(
      exact_add(exact_mul(ac.abs(), br), exact_mul(bc.abs(), ar)),
      exact_mul(ar, br),
    )
    return quantize_center_radius(
      center,
      radius,
      precision,
      RoundingMode::ToNearestEven,
    )
  }
  if !a.is_bounded() || !b.is_bounded() {
    return whole_real(precision)
  }
  let p1 = a.lo_ * b.lo_
  let p2 = a.lo_ * b.hi_
  let p3 = a.hi_ * b.lo_
  let p4 = a.hi_ * b.hi_
  let lo = bin_min(bin_min(p1, p2), bin_min(p3, p4))
  let hi = bin_max(bin_max(p1, p2), bin_max(p3, p4))
  quantize_interval(lo, hi, precision)
}

///|
fn div_ball_impl(a : BallFloat, b : BallFloat) -> BallFloat {
  let precision = Int::max(a.precision_, b.precision_)
  if b.contains_zero() {
    return whole_real(precision)
  }
  if a.is_bounded() && b.is_bounded() {
    let ac = a.center()
    let ar = a.radius()
    let bc = b.center()
    let br = b.radius()
    let denom_abs = bc.abs()
    let (center_high, center_high_error) = div_high_precision(ac, bc, precision)
    let numerator = exact_add(exact_mul(ac.abs(), br), exact_mul(denom_abs, ar))
    let denominator = exact_mul(denom_abs, exact_sub(denom_abs, br))
    let (radius_high, radius_high_error) = div_high_precision(
      numerator, denominator, precision,
    )
    let radius = outward_sum(
      radius_high.abs(),
      radius_high_error,
      Int::max(radius_high.precision(), radius_high_error.precision()),
    )
    return quantize_center_radius_approx(
      center_high,
      center_high_error,
      radius,
      precision,
      RoundingMode::ToNearestEven,
    )
  }
  a * reciprocal_interval_for_nonzero(b, precision)
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
  quantize_interval(lo, hi, precision)
}

///|
pub fn BallFloat::exact(
  x : @bin_float.BinFloat,
  precision? : Int = x.precision(),
) -> BallFloat {
  guard x.classify() == FpClass::Finite else {
    abort("ball exact source must be finite")
  }
  zero_radius_interval(
    x.with_precision(exact_precision(x), RoundingMode::ToNearestEven),
    precision,
  )
}

///|
pub fn BallFloat::from_int(n : Int, precision? : Int = 16) -> BallFloat {
  BallFloat::exact(
    @bin_float.BinFloat::from_int(n, precision=Int::max(precision, 8)),
    precision~,
  )
}

///|
pub fn BallFloat::from_bigint(n : BigInt, precision? : Int = 16) -> BallFloat {
  BallFloat::exact(
    @bin_float.BinFloat::from_bigint(n, precision=Int::max(precision, 8)),
    precision~,
  )
}

///|
pub fn BallFloat::from_double(x : Double, precision? : Int = 53) -> BallFloat {
  let bin = @bin_float.BinFloat::from_double(
    x,
    precision=Int::max(precision, 53),
  )
  guard bin.classify() == FpClass::Finite else {
    abort("ball double source must be finite")
  }
  BallFloat::exact(bin, precision~)
}

///|
pub fn BallFloat::from_float(x : Float, precision? : Int = 24) -> BallFloat {
  let bin = @bin_float.BinFloat::from_float(
    x,
    precision=Int::max(precision, 24),
  )
  guard bin.classify() == FpClass::Finite else {
    abort("ball float source must be finite")
  }
  BallFloat::exact(bin, precision~)
}

///|
pub fn BallFloat::whole(precision? : Int = 53) -> BallFloat {
  whole_real(precision)
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
  is_finite_bound(self.lo_) && is_finite_bound(self.hi_)
}

///|
pub fn BallFloat::is_entire(self : BallFloat) -> Bool {
  is_neg_inf(self.lo_) && is_pos_inf(self.hi_)
}

///|
pub fn BallFloat::contains_zero(self : BallFloat) -> Bool {
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
pub fn BallFloat::precision(self : BallFloat) -> Int {
  self.precision_
}

///|
pub fn BallFloat::classify(self : BallFloat) -> FpClass {
  if self.is_bounded() {
    FpClass::Finite
  } else {
    FpClass::Infinity
  }
}

///|
pub fn BallFloat::sign(self : BallFloat) -> Sign {
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
  if self.is_bounded() {
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
  if self.is_bounded() {
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
  store_interval(self.hi_.neg(), self.lo_.neg(), self.precision_)
}

///|
pub fn BallFloat::abs(self : BallFloat) -> BallFloat {
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
pub fn BallFloat::contains(self : BallFloat, x : @bin_float.BinFloat) -> Bool {
  guard x.classify() == FpClass::Finite else { return false }
  self.lo_.compare(x) <= 0 && self.hi_.compare(x) >= 0
}

///|
pub fn BallFloat::overlaps(self : BallFloat, other : BallFloat) -> Bool {
  self.lo_.compare(other.hi_) <= 0 && self.hi_.compare(other.lo_) >= 0
}

///|
pub fn BallFloat::separated_from(self : BallFloat, other : BallFloat) -> Bool {
  !self.overlaps(other)
}

///|
pub fn BallFloat::definitely_lt(self : BallFloat, other : BallFloat) -> Bool {
  self.hi_.compare(other.lo_) < 0
}

///|
pub fn BallFloat::definitely_le(self : BallFloat, other : BallFloat) -> Bool {
  self.hi_.compare(other.lo_) <= 0
}

///|
pub fn BallFloat::definitely_gt(self : BallFloat, other : BallFloat) -> Bool {
  self.lo_.compare(other.hi_) > 0
}

///|
pub fn BallFloat::maybe_eq(self : BallFloat, other : BallFloat) -> Bool {
  self.overlaps(other)
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
pub impl @arithmetic.Contains for BallFloat with fn contains(self, other) {
  self.lo_.compare(other.lo_) <= 0 && self.hi_.compare(other.hi_) >= 0
}

///|
pub impl @arithmetic.Overlaps for BallFloat with fn overlaps(self, other) {
  self.overlaps(other)
}

///|
pub impl @arithmetic.DefinitelyLt for BallFloat with fn definitely_lt(
  self,
  other,
) {
  self.definitely_lt(other)
}

///|
pub impl @arithmetic.DefinitelyLe for BallFloat with fn definitely_le(
  self,
  other,
) {
  self.definitely_le(other)
}

///|
pub impl @arithmetic.MaybeEq for BallFloat with fn maybe_eq(self, other) {
  self.maybe_eq(other)
}

///|
pub impl @arithmetic.DivChecked for BallFloat with fn div_checked(
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
pub impl @arithmetic.PowNatChecked for BallFloat with fn pow_nat_checked(
  self,
  exponent,
  ctx,
) {
  let precision = ctx.precision
  let base = self.with_precision(precision, RoundingMode::ToNearestEven)
  Ok(pow_nat(base, exponent.reinterpret_as_int(), precision))
}

///|
pub impl @arithmetic.PowIntChecked for BallFloat with fn pow_int_checked(
  self,
  exponent,
  ctx,
) {
  let precision = ctx.precision
  let base = self.with_precision(precision, RoundingMode::ToNearestEven)
  if exponent == 0 {
    return Ok(BallFloat::from_int(1, precision~))
  }
  if exponent < 0 {
    if base.contains_zero() {
      return Ok(BallFloat::whole(precision~))
    }
    let positive = pow_nat(base, -exponent, precision)
    return @arithmetic.DivChecked::div_checked(
      BallFloat::from_int(1, precision~),
      positive,
      ctx,
    )
  }
  Ok(pow_nat(base, exponent, precision))
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
  if self.is_bounded() {
    self.center().to_string() + " +/- " + self.radius().to_string()
  } else {
    "[" + self.lo_.to_string() + ", " + self.hi_.to_string() + "]"
  }
}
