pub struct BallFloat {
  priv lo_ : @bin_float.BinFloat
  priv hi_ : @bin_float.BinFloat
  priv precision_ : Int
} derive(Eq)

fn neg_inf(precision : Int) -> @bin_float.BinFloat {
  @bin_float.BinFloat::inf(Sign::Negative, precision=precision)
}

fn pos_inf(precision : Int) -> @bin_float.BinFloat {
  @bin_float.BinFloat::inf(Sign::Positive, precision=precision)
}

fn is_neg_inf(x : @bin_float.BinFloat) -> Bool {
  x.classify() == FpClass::Infinity && x.sign() == Sign::Negative
}

fn is_pos_inf(x : @bin_float.BinFloat) -> Bool {
  x.classify() == FpClass::Infinity && x.sign() == Sign::Positive
}

fn is_finite_bound(x : @bin_float.BinFloat) -> Bool {
  x.classify() == FpClass::Finite
}

fn validate_bound(x : @bin_float.BinFloat) -> Unit {
  guard x.classify() != FpClass::NaN else { abort("ball bounds must not be NaN") }
}

fn validate_interval(lo : @bin_float.BinFloat, hi : @bin_float.BinFloat) -> Unit {
  validate_bound(lo)
  validate_bound(hi)
  guard lo.compare(hi) <= 0 else { abort("ball lower bound must not exceed upper bound") }
}

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

fn exact_make(significand : BigInt, exponent2 : Int) -> @bin_float.BinFloat {
  @bin_float.BinFloat::make(significand, exponent2, Int::max(1, @internal.abs_bigint(significand).bit_length()))
}

fn exact_add(a : @bin_float.BinFloat, b : @bin_float.BinFloat) -> @bin_float.BinFloat {
  let target = Int::min(a.exponent2(), b.exponent2())
  let sa = a.significand() << (a.exponent2() - target)
  let sb = b.significand() << (b.exponent2() - target)
  exact_make(sa + sb, target)
}

fn exact_sub(a : @bin_float.BinFloat, b : @bin_float.BinFloat) -> @bin_float.BinFloat {
  exact_add(a, b.neg())
}

fn exact_mul(a : @bin_float.BinFloat, b : @bin_float.BinFloat) -> @bin_float.BinFloat {
  exact_make(a.significand() * b.significand(), a.exponent2() + b.exponent2())
}

fn exact_half(x : @bin_float.BinFloat) -> @bin_float.BinFloat {
  exact_make(x.significand(), x.exponent2() - 1)
}

fn outward_round(x : @bin_float.BinFloat, precision : Int) -> @bin_float.BinFloat {
  x.with_precision(precision, RoundingMode::AwayFromZero).abs()
}

fn outward_sum(a : @bin_float.BinFloat, b : @bin_float.BinFloat, precision : Int) -> @bin_float.BinFloat {
  outward_round(exact_add(a, b), precision)
}

fn quantize_center_radius_approx(
  center_high : @bin_float.BinFloat,
  center_high_error : @bin_float.BinFloat,
  radius : @bin_float.BinFloat,
  precision : Int,
  mode : RoundingMode,
) -> BallFloat {
  let precision = Int::max(1, precision)
  let rounded_center = center_high.with_precision(precision, mode)
  let retune_error = outward_round(exact_sub(center_high, rounded_center).abs(), precision)
  let rounded_radius = outward_round(radius, precision)
  let high_error = outward_round(center_high_error, precision)
  let total_radius = outward_sum(outward_sum(rounded_radius, high_error, precision), retune_error, precision)
  let lo = exact_sub(rounded_center, total_radius)
  let hi = exact_add(rounded_center, total_radius)
  store_interval(lo, hi, precision)
}

fn div_high_precision(
  numerator : @bin_float.BinFloat,
  denominator : @bin_float.BinFloat,
  precision : Int,
) -> (@bin_float.BinFloat, @bin_float.BinFloat) {
  let high_precision = Int::max(precision + 4, precision * 2 + 4)
  let q =
    numerator.with_precision(high_precision, RoundingMode::ToNearestEven) /
    denominator.with_precision(high_precision, RoundingMode::ToNearestEven)
  (q.with_precision(high_precision, RoundingMode::ToNearestEven), q.ulp())
}

fn lower_round_bound(x : @bin_float.BinFloat, precision : Int) -> @bin_float.BinFloat {
  match x.classify() {
    FpClass::Finite => x.with_precision(precision, RoundingMode::TowardNegative)
    FpClass::Infinity => @bin_float.BinFloat::inf(x.sign(), precision=precision)
    FpClass::NaN => abort("ball bounds must not be NaN")
  }
}

fn upper_round_bound(x : @bin_float.BinFloat, precision : Int) -> @bin_float.BinFloat {
  match x.classify() {
    FpClass::Finite => x.with_precision(precision, RoundingMode::TowardPositive)
    FpClass::Infinity => @bin_float.BinFloat::inf(x.sign(), precision=precision)
    FpClass::NaN => abort("ball bounds must not be NaN")
  }
}

fn store_interval(
  lo : @bin_float.BinFloat,
  hi : @bin_float.BinFloat,
  precision : Int,
) -> BallFloat {
  validate_interval(lo, hi)
  { lo_: lo, hi_: hi, precision_: Int::max(1, precision) }
}

fn quantize_interval(
  lo : @bin_float.BinFloat,
  hi : @bin_float.BinFloat,
  precision : Int,
) -> BallFloat {
  let precision = Int::max(1, precision)
  store_interval(lower_round_bound(lo, precision), upper_round_bound(hi, precision), precision)
}

fn interval_center(x : BallFloat) -> @bin_float.BinFloat {
  guard x.is_bounded() else { abort("ball center is undefined for unbounded intervals") }
  exact_half(exact_add(x.lo_, x.hi_))
}

fn interval_radius(x : BallFloat) -> @bin_float.BinFloat {
  guard x.is_bounded() else { abort("ball radius is undefined for unbounded intervals") }
  exact_half(exact_sub(x.hi_, x.lo_)).abs()
}

fn quantize_center_radius(
  center : @bin_float.BinFloat,
  radius : @bin_float.BinFloat,
  precision : Int,
  mode : RoundingMode,
) -> BallFloat {
  guard center.classify() == FpClass::Finite else { abort("ball center must be finite") }
  guard radius.classify() == FpClass::Finite else { abort("ball radius must be finite") }
  guard radius.sign() != Sign::Negative else { abort("ball radius must be non-negative") }
  let precision = Int::max(1, precision)
  let rounded_center = center.with_precision(precision, mode)
  let center_error = outward_round(exact_sub(center, rounded_center).abs(), precision)
  let rounded_radius = outward_round(radius, precision)
  let total_radius = outward_sum(rounded_radius, center_error, precision)
  let lo = exact_sub(rounded_center, total_radius)
  let hi = exact_add(rounded_center, total_radius)
  store_interval(lo, hi, precision)
}

fn zero_radius_interval(x : @bin_float.BinFloat, precision : Int) -> BallFloat {
  quantize_interval(x, x, precision)
}

fn whole_real(precision : Int) -> BallFloat {
  store_interval(neg_inf(precision), pos_inf(precision), precision)
}

fn nonnegative_ray(precision : Int) -> BallFloat {
  store_interval(@bin_float.BinFloat::zero(precision=precision), pos_inf(precision), precision)
}

fn unit_interval(precision : Int) -> BallFloat {
  quantize_interval(
    @bin_float.BinFloat::from_int(-1, precision=precision),
    @bin_float.BinFloat::from_int(1, precision=precision),
    precision,
  )
}

fn exact_integer_from_bin(x : @bin_float.BinFloat) -> BigInt? {
  guard x.classify() == FpClass::Finite else { return None }
  let d = @decimal.Decimal::from_bin_float(x, precision=Int::max(x.precision() * 2 + 8, 34))
  if d.exponent10() >= 0 {
    Some(d.coefficient() * @internal.pow10(d.exponent10()))
  } else {
    None
  }
}

fn bin_min(a : @bin_float.BinFloat, b : @bin_float.BinFloat) -> @bin_float.BinFloat {
  if a.compare(b) <= 0 { a } else { b }
}

fn bin_max(a : @bin_float.BinFloat, b : @bin_float.BinFloat) -> @bin_float.BinFloat {
  if a.compare(b) >= 0 { a } else { b }
}

fn reciprocal_interval_for_nonzero(x : BallFloat, precision : Int) -> BallFloat {
  guard !x.contains_zero() else { abort("reciprocal interval requires non-zero interval") }
  let lo = x.lo_
  let hi = x.hi_
  if lo.sign() == Sign::Positive {
    quantize_interval(
      @bin_float.BinFloat::one(precision=precision) / hi,
      @bin_float.BinFloat::one(precision=precision) / lo,
      precision,
    )
  } else if hi.sign() == Sign::Negative {
    quantize_interval(
      @bin_float.BinFloat::one(precision=precision) / hi,
      @bin_float.BinFloat::one(precision=precision) / lo,
      precision,
    )
  } else {
    whole_real(precision)
  }
}

fn point_pow_nat(base : BallFloat, exponent : BigInt) -> BallFloat {
  let zero = 0N
  let two = 2N
  let mut n = exponent
  let mut result = zero_radius_interval(@bin_float.BinFloat::one(precision=base.precision_), base.precision_)
  let mut factor = base
  while n > zero {
    if !(n % two).is_zero() {
      result = result * factor
    }
    n = n / two
    if n > zero {
      factor = factor * factor
    }
  }
  result
}

fn lower_scalar(x : @bin_float.BinFloat, precision : Int) -> @bin_float.BinFloat {
  x.with_precision(precision, RoundingMode::TowardNegative)
}

fn upper_scalar(x : @bin_float.BinFloat, precision : Int) -> @bin_float.BinFloat {
  x.with_precision(precision, RoundingMode::TowardPositive)
}

fn monotone_inc_interval(
  lo : @bin_float.BinFloat,
  hi : @bin_float.BinFloat,
  precision : Int,
  f : (@bin_float.BinFloat, Int) -> @bin_float.BinFloat,
) -> BallFloat {
  let work = Int::max(precision * 2 + 24, 96)
  let lo_eval = f(lo.with_precision(work, RoundingMode::TowardNegative), work)
  let hi_eval = f(hi.with_precision(work, RoundingMode::TowardPositive), work)
  quantize_interval(lower_scalar(lo_eval, precision), upper_scalar(hi_eval, precision), precision)
}

fn monotone_dec_interval(
  lo : @bin_float.BinFloat,
  hi : @bin_float.BinFloat,
  precision : Int,
  f : (@bin_float.BinFloat, Int) -> @bin_float.BinFloat,
) -> BallFloat {
  let work = Int::max(precision * 2 + 24, 96)
  let lo_eval = f(lo.with_precision(work, RoundingMode::TowardNegative), work)
  let hi_eval = f(hi.with_precision(work, RoundingMode::TowardPositive), work)
  quantize_interval(lower_scalar(hi_eval, precision), upper_scalar(lo_eval, precision), precision)
}

fn scalar_max(a : @bin_float.BinFloat, b : @bin_float.BinFloat) -> @bin_float.BinFloat {
  if a.compare(b) >= 0 { a } else { b }
}

fn scalar_min(a : @bin_float.BinFloat, b : @bin_float.BinFloat) -> @bin_float.BinFloat {
  if a.compare(b) <= 0 { a } else { b }
}

fn angle_interval(precision : Int) -> BallFloat {
  let work = Int::max(precision * 2 + 24, 96)
  let pi = @bin_float.pi_for_precision(work)
  quantize_interval(lower_scalar(pi.neg(), precision), upper_scalar(pi, precision), precision)
}

fn contains_scalar_interval(
  lo : @bin_float.BinFloat,
  hi : @bin_float.BinFloat,
  x : @bin_float.BinFloat,
) -> Bool {
  lo.compare(x) <= 0 && hi.compare(x) >= 0
}

fn atan2_crosses_branch_cut(
  y_lo : @bin_float.BinFloat,
  y_hi : @bin_float.BinFloat,
  x_lo : @bin_float.BinFloat,
  x_hi : @bin_float.BinFloat,
) -> Bool {
  x_lo |> ignore
  x_hi.sign() == Sign::Negative &&
  contains_scalar_interval(y_lo, y_hi, @bin_float.BinFloat::zero(precision=Int::max(y_lo.precision(), y_hi.precision())))
}

fn atan2_contains_origin(
  y_lo : @bin_float.BinFloat,
  y_hi : @bin_float.BinFloat,
  x_lo : @bin_float.BinFloat,
  x_hi : @bin_float.BinFloat,
) -> Bool {
  contains_scalar_interval(y_lo, y_hi, @bin_float.BinFloat::zero(precision=Int::max(y_lo.precision(), y_hi.precision()))) &&
  contains_scalar_interval(x_lo, x_hi, @bin_float.BinFloat::zero(precision=Int::max(x_lo.precision(), x_hi.precision())))
}

fn sin_interval(lo : @bin_float.BinFloat, hi : @bin_float.BinFloat, precision : Int) -> BallFloat {
  let work = Int::max(precision * 2 + 24, 96)
  let tau = @bin_float.tau_for_precision(work)
  if (hi - lo).abs().compare(tau) >= 0 {
    return unit_interval(precision)
  }
  let sin_lo = @bin_float.sin_for_precision(lo, work)
  let sin_hi = @bin_float.sin_for_precision(hi, work)
  let mut out_lo = scalar_min(sin_lo, sin_hi)
  let mut out_hi = scalar_max(sin_lo, sin_hi)
  let half_pi = @bin_float.half_pi_for_precision(work)
  let q_lo = @bin_float.bin_ceil_integer((lo / half_pi).with_precision(work, RoundingMode::TowardNegative))
  let q_hi = @bin_float.bin_floor_integer((hi / half_pi).with_precision(work, RoundingMode::TowardPositive))
  let span = q_hi - q_lo
  if span >= 0N && span.compare_int(8) <= 0 {
    let count = span.to_int()
    for i in 0..=count {
      let q = q_lo + BigInt::from_int(i)
      let m = ((q % 4N) + 4N) % 4N
      if m == 1N {
        out_hi = @bin_float.BinFloat::one(precision=work)
      } else if m == 3N {
        out_lo = @bin_float.BinFloat::from_int(-1, precision=work)
      }
    }
  }
  quantize_interval(lower_scalar(out_lo, precision), upper_scalar(out_hi, precision), precision)
}

fn cos_interval(lo : @bin_float.BinFloat, hi : @bin_float.BinFloat, precision : Int) -> BallFloat {
  let work = Int::max(precision * 2 + 24, 96)
  let tau = @bin_float.tau_for_precision(work)
  if (hi - lo).abs().compare(tau) >= 0 {
    return unit_interval(precision)
  }
  let cos_lo = @bin_float.cos_for_precision(lo, work)
  let cos_hi = @bin_float.cos_for_precision(hi, work)
  let mut out_lo = scalar_min(cos_lo, cos_hi)
  let mut out_hi = scalar_max(cos_lo, cos_hi)
  let pi = @bin_float.pi_for_precision(work)
  let q_lo = @bin_float.bin_ceil_integer((lo / pi).with_precision(work, RoundingMode::TowardNegative))
  let q_hi = @bin_float.bin_floor_integer((hi / pi).with_precision(work, RoundingMode::TowardPositive))
  let span = q_hi - q_lo
  if span >= 0N && span.compare_int(8) <= 0 {
    let count = span.to_int()
    for i in 0..=count {
      let q = q_lo + BigInt::from_int(i)
      let m = ((q % 2N) + 2N) % 2N
      if m == 0N {
        out_hi = @bin_float.BinFloat::one(precision=work)
      } else {
        out_lo = @bin_float.BinFloat::from_int(-1, precision=work)
      }
    }
  }
  quantize_interval(lower_scalar(out_lo, precision), upper_scalar(out_hi, precision), precision)
}

fn tan_interval(lo : @bin_float.BinFloat, hi : @bin_float.BinFloat, precision : Int) -> BallFloat {
  let work = Int::max(precision * 2 + 24, 96)
  let half_pi = @bin_float.half_pi_for_precision(work)
  let q_lo = @bin_float.bin_ceil_integer((lo / half_pi).with_precision(work, RoundingMode::TowardNegative))
  let q_hi = @bin_float.bin_floor_integer((hi / half_pi).with_precision(work, RoundingMode::TowardPositive))
  let span = q_hi - q_lo
  if span >= 0N && span.compare_int(8) <= 0 {
    let count = span.to_int()
    for i in 0..=count {
      let q = q_lo + BigInt::from_int(i)
      let m = ((q % 2N) + 2N) % 2N
      if m == 1N {
        return whole_real(precision)
      }
    }
  }
  monotone_inc_interval(lo, hi, precision, (x, p) => @bin_float.tan_for_precision(x, p))
}

pub fn BallFloat::new(
  center : @bin_float.BinFloat,
  radius : @bin_float.BinFloat,
  precision? : Int = Int::max(center.precision(), radius.precision()),
) -> BallFloat {
  quantize_center_radius(center, radius, precision, RoundingMode::ToNearestEven)
}

pub fn BallFloat::exact(x : @bin_float.BinFloat, precision? : Int = x.precision()) -> BallFloat {
  guard x.classify() == FpClass::Finite else { abort("ball exact source must be finite") }
  BallFloat::new(x, @bin_float.BinFloat::zero(precision=exact_precision(x)), precision=precision)
}

pub fn BallFloat::from_int(
  n : Int,
  precision? : Int = 16,
) -> BallFloat {
  BallFloat::exact(@bin_float.BinFloat::from_int(n, precision=Int::max(precision, 8)), precision=precision)
}

pub fn BallFloat::from_bigint(
  n : BigInt,
  precision? : Int = 16,
) -> BallFloat {
  BallFloat::exact(@bin_float.BinFloat::from_bigint(n, precision=Int::max(precision, 8)), precision=precision)
}

pub fn BallFloat::from_double(
  x : Double,
  precision? : Int = 53,
) -> BallFloat {
  let bin = @bin_float.BinFloat::from_double(x, precision=Int::max(precision, 53))
  guard bin.classify() == FpClass::Finite else { abort("ball double source must be finite") }
  BallFloat::exact(bin, precision=precision)
}

pub fn BallFloat::from_float(
  x : Float,
  precision? : Int = 24,
) -> BallFloat {
  let bin = @bin_float.BinFloat::from_float(x, precision=Int::max(precision, 24))
  guard bin.classify() == FpClass::Finite else { abort("ball float source must be finite") }
  BallFloat::exact(bin, precision=precision)
}

pub fn BallFloat::from_decimal(
  x : @decimal.Decimal,
  precision? : Int = x.precision(),
) -> BallFloat {
  guard x.classify() == FpClass::Finite else { abort("ball decimal source must be finite") }
  let center = x.to_bin_float(precision=precision)
  let back = @decimal.Decimal::from_bin_float(center, precision=Int::max(precision * 2, x.precision()))
  let diff = (x - back).abs().to_bin_float(precision=precision, mode=RoundingMode::AwayFromZero)
  BallFloat::new(center, diff, precision=precision)
}

pub fn BallFloat::lower_bound(self : BallFloat) -> @bin_float.BinFloat {
  self.lo_
}

pub fn BallFloat::upper_bound(self : BallFloat) -> @bin_float.BinFloat {
  self.hi_
}

pub fn BallFloat::is_bounded(self : BallFloat) -> Bool {
  is_finite_bound(self.lo_) && is_finite_bound(self.hi_)
}

pub fn BallFloat::is_entire(self : BallFloat) -> Bool {
  is_neg_inf(self.lo_) && is_pos_inf(self.hi_)
}

pub fn BallFloat::contains_zero(self : BallFloat) -> Bool {
  self.contains(@bin_float.BinFloat::zero(precision=self.precision_))
}

pub fn BallFloat::center(self : BallFloat) -> @bin_float.BinFloat {
  interval_center(self)
}

pub fn BallFloat::radius(self : BallFloat) -> @bin_float.BinFloat {
  interval_radius(self)
}

pub fn BallFloat::precision(self : BallFloat) -> Int {
  self.precision_
}

pub fn BallFloat::classify(self : BallFloat) -> FpClass {
  if self.is_bounded() { FpClass::Finite } else { FpClass::Infinity }
}

pub fn BallFloat::sign(self : BallFloat) -> Sign {
  if self.lo_.sign() == Sign::Positive {
    Sign::Positive
  } else if self.hi_.sign() == Sign::Negative {
    Sign::Negative
  } else {
    Sign::Zero
  }
}

pub fn BallFloat::normalized(self : BallFloat) -> BallFloat {
  if self.is_bounded() {
    BallFloat::new(self.center().normalized(), self.radius().normalized(), precision=self.precision_)
  } else {
    quantize_interval(self.lo_, self.hi_, self.precision_)
  }
}

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
      FpClass::Finite => self.lo_.with_precision(precision, RoundingMode::TowardNegative)
      FpClass::Infinity => @bin_float.BinFloat::inf(self.lo_.sign(), precision=precision)
      FpClass::NaN => abort("ball bounds must not be NaN")
    }
    let hi = match self.hi_.classify() {
      FpClass::Finite => self.hi_.with_precision(precision, RoundingMode::TowardPositive)
      FpClass::Infinity => @bin_float.BinFloat::inf(self.hi_.sign(), precision=precision)
      FpClass::NaN => abort("ball bounds must not be NaN")
    }
    store_interval(lo, hi, precision)
  }
}

pub fn BallFloat::neg(self : BallFloat) -> BallFloat {
  store_interval(self.hi_.neg(), self.lo_.neg(), self.precision_)
}

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
      if lo_abs.compare(hi_abs) >= 0 { lo_abs } else { hi_abs }
    }
    store_interval(@bin_float.BinFloat::zero(precision=self.precision_), upper, self.precision_)
  }
}

pub fn BallFloat::contains(self : BallFloat, x : @bin_float.BinFloat) -> Bool {
  guard x.classify() == FpClass::Finite else { return false }
  self.lo_.compare(x) <= 0 && self.hi_.compare(x) >= 0
}

pub fn BallFloat::overlaps(self : BallFloat, other : BallFloat) -> Bool {
  self.lo_.compare(other.hi_) <= 0 && self.hi_.compare(other.lo_) >= 0
}

pub fn BallFloat::separated_from(self : BallFloat, other : BallFloat) -> Bool {
  !self.overlaps(other)
}

pub fn BallFloat::definitely_lt(self : BallFloat, other : BallFloat) -> Bool {
  self.hi_.compare(other.lo_) < 0
}

pub fn BallFloat::definitely_gt(self : BallFloat, other : BallFloat) -> Bool {
  self.lo_.compare(other.hi_) > 0
}

pub fn BallFloat::maybe_overlap(self : BallFloat, other : BallFloat) -> Bool {
  self.overlaps(other)
}

pub fn BallFloat::compare(self : BallFloat, other : BallFloat) -> Int {
  if self == other {
    0
  } else if self.definitely_lt(other) {
    -1
  } else if self.definitely_gt(other) {
    1
  } else {
    abort("ball_float compare is undefined for overlapping or otherwise incomparable intervals")
  }
}

pub fn BallFloat::min(self : BallFloat, other : BallFloat) -> BallFloat {
  if self.compare(other) <= 0 { self } else { other }
}

pub fn BallFloat::max(self : BallFloat, other : BallFloat) -> BallFloat {
  if self.compare(other) >= 0 { self } else { other }
}

pub fn BallFloat::clamp(self : BallFloat, min~ : BallFloat, max~ : BallFloat) -> BallFloat {
  guard min.compare(max) <= 0 else { abort("min must not exceed max") }
  if self.compare(min) < 0 {
    min
  } else if self.compare(max) > 0 {
    max
  } else {
    self
  }
}

fn add_ball_impl(a : BallFloat, b : BallFloat) -> BallFloat {
  let precision = Int::max(a.precision_, b.precision_)
  if a.is_bounded() && b.is_bounded() {
    let center = exact_add(a.center(), b.center())
    let radius = exact_add(a.radius(), b.radius())
    return quantize_center_radius(center, radius, precision, RoundingMode::ToNearestEven)
  }
  quantize_interval(a.lo_ + b.lo_, a.hi_ + b.hi_, precision)
}

fn sub_ball_impl(a : BallFloat, b : BallFloat) -> BallFloat {
  let precision = Int::max(a.precision_, b.precision_)
  if a.is_bounded() && b.is_bounded() {
    let center = exact_sub(a.center(), b.center())
    let radius = exact_add(a.radius(), b.radius())
    return quantize_center_radius(center, radius, precision, RoundingMode::ToNearestEven)
  }
  quantize_interval(a.lo_ - b.hi_, a.hi_ - b.lo_, precision)
}

fn mul_ball_impl(a : BallFloat, b : BallFloat) -> BallFloat {
  let precision = Int::max(a.precision_, b.precision_)
  if a.is_bounded() && b.is_bounded() {
    let ac = a.center()
    let ar = a.radius()
    let bc = b.center()
    let br = b.radius()
    let center = exact_mul(ac, bc)
    let radius =
      exact_add(
        exact_add(
          exact_mul(ac.abs(), br),
          exact_mul(bc.abs(), ar),
        ),
        exact_mul(ar, br),
      )
    return quantize_center_radius(center, radius, precision, RoundingMode::ToNearestEven)
  }
  if !a.is_bounded() || !b.is_bounded() {
    if (a.contains_zero() && !b.is_bounded()) || (b.contains_zero() && !a.is_bounded()) {
      return whole_real(precision)
    }
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

fn div_ball_impl(a : BallFloat, b : BallFloat) -> BallFloat {
  if b.contains_zero() {
    abort("division ball contains zero")
  }
  let precision = Int::max(a.precision_, b.precision_)
  if a.is_bounded() && b.is_bounded() {
    let ac = a.center()
    let ar = a.radius()
    let bc = b.center()
    let br = b.radius()
    let denom_abs = bc.abs()
    let (center_high, center_high_error) = div_high_precision(ac, bc, precision)
    let numerator = exact_add(
      exact_mul(ac.abs(), br),
      exact_mul(denom_abs, ar),
    )
    let denominator = exact_mul(denom_abs, exact_sub(denom_abs, br))
    let (radius_high, radius_high_error) = div_high_precision(numerator, denominator, precision)
    let radius = outward_sum(radius_high.abs(), radius_high_error, Int::max(radius_high.precision(), radius_high_error.precision()))
    return quantize_center_radius_approx(center_high, center_high_error, radius, precision, RoundingMode::ToNearestEven)
  }
  a * reciprocal_interval_for_nonzero(b, precision)
}

pub fn BallFloat::add(self : BallFloat, other : BallFloat) -> BallFloat {
  add_ball_impl(self, other)
}

pub fn BallFloat::sub(self : BallFloat, other : BallFloat) -> BallFloat {
  sub_ball_impl(self, other)
}

pub fn BallFloat::mul(self : BallFloat, other : BallFloat) -> BallFloat {
  mul_ball_impl(self, other)
}

pub fn BallFloat::div(self : BallFloat, other : BallFloat) -> BallFloat {
  div_ball_impl(self, other)
}

pub fn BallFloat::pow(self : BallFloat, exponent : BallFloat) -> BallFloat {
  guard exponent.lo_.compare(exponent.hi_) == 0 else {
    abort("ball exponent must be exact")
  }
  match exact_integer_from_bin(exponent.lo_) {
    Some(n) => {
      let precision = Int::max(self.precision_, exponent.precision_)
      if n == 0N {
        zero_radius_interval(@bin_float.BinFloat::one(precision=precision), precision)
      } else if n > 0N {
        point_pow_nat(self.with_precision(precision, RoundingMode::ToNearestEven), n)
      } else {
        if self.contains_zero() {
          return whole_real(precision)
        }
        reciprocal_interval_for_nonzero(
          point_pow_nat(self.with_precision(precision, RoundingMode::ToNearestEven), -n),
          precision,
        )
      }
    }
    None => {
      guard self.lo_.sign() == Sign::Positive else {
        abort("non-integer ball pow requires a positive base interval")
      }
      nonnegative_ray(Int::max(self.precision_, exponent.precision_))
    }
  }
}

pub impl Add for BallFloat with fn add(self, other) {
  add_ball_impl(self, other)
}

pub impl Sub for BallFloat with fn sub(self, other) {
  sub_ball_impl(self, other)
}

pub impl Mul for BallFloat with fn mul(self, other) {
  mul_ball_impl(self, other)
}

pub impl Div for BallFloat with fn div(self, other) {
  div_ball_impl(self, other)
}

pub impl Neg for BallFloat with fn neg(self) {
  self.neg()
}

pub impl Compare for BallFloat with fn compare(self, other) {
  self.compare(other)
}

pub impl @lg.Zero for BallFloat with fn zero() -> BallFloat {
  zero_radius_interval(@bin_float.BinFloat::zero(precision=1), 1)
}

pub impl @lg.One for BallFloat with fn one() -> BallFloat {
  zero_radius_interval(@bin_float.BinFloat::one(precision=1), 1)
}

pub impl @lg.Inverse for BallFloat with fn inv(self) -> BallFloat {
  if self.contains_zero() {
    whole_real(self.precision_)
  } else {
    reciprocal_interval_for_nonzero(self, self.precision_)
  }
}

pub impl @lg.AddMonoid for BallFloat

pub impl @lg.MulMonoid for BallFloat

pub impl @lg.AddGroup for BallFloat

pub impl @lg.MulGroup for BallFloat

pub impl @lg.Semiring for BallFloat

pub impl @lg.Ring for BallFloat

pub impl @lg.Field for BallFloat

pub impl @lg.Num for BallFloat with fn abs(self) -> BallFloat {
  self.abs()
}

pub impl @lg.Num for BallFloat with fn signum(self) -> BallFloat {
  if self.lo_.sign() == Sign::Positive {
    zero_radius_interval(@bin_float.BinFloat::one(precision=self.precision_), self.precision_)
  } else if self.hi_.sign() == Sign::Negative {
    zero_radius_interval(@bin_float.BinFloat::from_int(-1, precision=self.precision_), self.precision_)
  } else if self.lo_.is_zero() && self.hi_.is_zero() {
    zero_radius_interval(@bin_float.BinFloat::zero(precision=self.precision_), self.precision_)
  } else {
    unit_interval(self.precision_)
  }
}

pub impl @arith.Sqrt for BallFloat with fn sqrt(self) -> BallFloat {
  guard self.hi_.sign() != Sign::Negative else { abort("sqrt requires a non-negative interval") }
  let lo =
    if self.lo_.sign() == Sign::Negative || self.lo_.is_zero() {
      @bin_float.BinFloat::zero(precision=self.precision_)
    } else {
      self.lo_
    }
  monotone_inc_interval(lo, self.hi_, self.precision_, (x, p) => @bin_float.sqrt_for_precision(x, p))
}

pub impl @arith.Cbrt for BallFloat with fn cbrt(self) -> BallFloat {
  monotone_inc_interval(self.lo_, self.hi_, self.precision_, (x, p) => @bin_float.cbrt_for_precision(x, p))
}

pub impl @arith.Radical for BallFloat

pub impl @arith.Exponential for BallFloat with fn exp(self) -> BallFloat {
  monotone_inc_interval(self.lo_, self.hi_, self.precision_, (x, p) => @bin_float.exp_for_precision(x, p))
}

pub impl @arith.Exponential for BallFloat with fn exp2(self) -> BallFloat {
  monotone_inc_interval(self.lo_, self.hi_, self.precision_, (x, p) => @bin_float.exp2_for_precision(x, p))
}

pub impl @arith.Logarithmic for BallFloat with fn ln(self) -> BallFloat {
  guard self.lo_.sign() == Sign::Positive else { abort("ln requires a positive interval") }
  monotone_inc_interval(self.lo_, self.hi_, self.precision_, (x, p) => @bin_float.ln_for_precision(x, p))
}

pub impl @arith.Logarithmic for BallFloat with fn log2(self) -> BallFloat {
  guard self.lo_.sign() == Sign::Positive else { abort("log2 requires a positive interval") }
  monotone_inc_interval(self.lo_, self.hi_, self.precision_, (x, p) => @bin_float.log2_for_precision(x, p))
}

pub impl @arith.Logarithmic for BallFloat with fn log10(self) -> BallFloat {
  guard self.lo_.sign() == Sign::Positive else { abort("log10 requires a positive interval") }
  monotone_inc_interval(self.lo_, self.hi_, self.precision_, (x, p) => @bin_float.log10_for_precision(x, p))
}

pub impl @arith.Power for BallFloat with fn pow(self, exponent) -> BallFloat {
  self.pow(exponent)
}

pub impl @arith.Trigonometric for BallFloat with fn sin(self) -> BallFloat {
  sin_interval(self.lo_, self.hi_, self.precision_)
}

pub impl @arith.Trigonometric for BallFloat with fn cos(self) -> BallFloat {
  cos_interval(self.lo_, self.hi_, self.precision_)
}

pub impl @arith.Trigonometric for BallFloat with fn tan(self) -> BallFloat {
  tan_interval(self.lo_, self.hi_, self.precision_)
}

pub impl @arith.InverseTrigonometric for BallFloat with fn asin(self) -> BallFloat {
  guard self.lo_.compare(@bin_float.BinFloat::from_int(-1, precision=self.precision_)) >= 0 &&
    self.hi_.compare(@bin_float.BinFloat::one(precision=self.precision_)) <= 0 else {
    abort("asin requires an interval inside [-1, 1]")
  }
  monotone_inc_interval(self.lo_, self.hi_, self.precision_, (x, p) => @bin_float.asin_for_precision(x, p))
}

pub impl @arith.InverseTrigonometric for BallFloat with fn acos(self) -> BallFloat {
  guard self.lo_.compare(@bin_float.BinFloat::from_int(-1, precision=self.precision_)) >= 0 &&
    self.hi_.compare(@bin_float.BinFloat::one(precision=self.precision_)) <= 0 else {
    abort("acos requires an interval inside [-1, 1]")
  }
  monotone_dec_interval(self.lo_, self.hi_, self.precision_, (x, p) => @bin_float.acos_for_precision(x, p))
}

pub impl @arith.InverseTrigonometric for BallFloat with fn atan(self) -> BallFloat {
  monotone_inc_interval(self.lo_, self.hi_, self.precision_, (x, p) => @bin_float.atan_for_precision(x, p))
}

pub impl @arith.InverseTrigonometric for BallFloat with fn atan2(self, other) -> BallFloat {
  let precision = Int::max(self.precision_, other.precision_)
  if atan2_contains_origin(self.lo_, self.hi_, other.lo_, other.hi_) ||
    atan2_crosses_branch_cut(self.lo_, self.hi_, other.lo_, other.hi_) {
    return angle_interval(precision)
  }
  let work = Int::max(precision * 2 + 24, 96)
  let candidates = [
    @bin_float.atan2_for_precision(self.lo_, other.lo_, work),
    @bin_float.atan2_for_precision(self.lo_, other.hi_, work),
    @bin_float.atan2_for_precision(self.hi_, other.lo_, work),
    @bin_float.atan2_for_precision(self.hi_, other.hi_, work),
  ]
  let mut lo = candidates[0]
  let mut hi = candidates[0]
  for c in candidates {
    lo = scalar_min(lo, c)
    hi = scalar_max(hi, c)
  }
  quantize_interval(lower_scalar(lo, precision), upper_scalar(hi, precision), precision)
}

pub impl @arith.Hyperbolic for BallFloat with fn sinh(self) -> BallFloat {
  monotone_inc_interval(self.lo_, self.hi_, self.precision_, (x, p) => @bin_float.sinh_for_precision(x, p))
}

pub impl @arith.Hyperbolic for BallFloat with fn cosh(self) -> BallFloat {
  if self.lo_.compare(@bin_float.BinFloat::zero(precision=self.precision_)) <= 0 &&
    self.hi_.compare(@bin_float.BinFloat::zero(precision=self.precision_)) >= 0 {
    let hi = scalar_max(
      @bin_float.cosh_for_precision(self.lo_, Int::max(self.precision_ * 2 + 24, 96)),
      @bin_float.cosh_for_precision(self.hi_, Int::max(self.precision_ * 2 + 24, 96)),
    )
    quantize_interval(
      @bin_float.BinFloat::one(precision=self.precision_),
      upper_scalar(hi, self.precision_),
      self.precision_,
    )
  } else if self.hi_.sign() == Sign::Negative {
    monotone_dec_interval(self.lo_, self.hi_, self.precision_, (x, p) => @bin_float.cosh_for_precision(x, p))
  } else {
    monotone_inc_interval(self.lo_, self.hi_, self.precision_, (x, p) => @bin_float.cosh_for_precision(x, p))
  }
}

pub impl @arith.Hyperbolic for BallFloat with fn tanh(self) -> BallFloat {
  monotone_inc_interval(self.lo_, self.hi_, self.precision_, (x, p) => @bin_float.tanh_for_precision(x, p))
}

pub impl @arith.InverseHyperbolic for BallFloat with fn asinh(self) -> BallFloat {
  monotone_inc_interval(self.lo_, self.hi_, self.precision_, (x, p) => @bin_float.asinh_for_precision(x, p))
}

pub impl @arith.InverseHyperbolic for BallFloat with fn acosh(self) -> BallFloat {
  guard self.lo_.compare(@bin_float.BinFloat::one(precision=self.precision_)) >= 0 else {
    abort("acosh requires an interval >= 1")
  }
  monotone_inc_interval(self.lo_, self.hi_, self.precision_, (x, p) => @bin_float.acosh_for_precision(x, p))
}

pub impl @arith.InverseHyperbolic for BallFloat with fn atanh(self) -> BallFloat {
  guard self.lo_.compare(@bin_float.BinFloat::from_int(-1, precision=self.precision_)) > 0 &&
    self.hi_.compare(@bin_float.BinFloat::one(precision=self.precision_)) < 0 else {
    abort("atanh requires an interval inside (-1, 1)")
  }
  monotone_inc_interval(self.lo_, self.hi_, self.precision_, (x, p) => @bin_float.atanh_for_precision(x, p))
}

pub impl @arith.Constants for BallFloat with fn pi() -> BallFloat {
  let p = @bin_float.pi_for_precision(96)
  quantize_interval(lower_scalar(p, 53), upper_scalar(p, 53), 53)
}

pub impl @arith.Constants for BallFloat with fn tau() -> BallFloat {
  let t = @bin_float.tau_for_precision(96)
  quantize_interval(lower_scalar(t, 53), upper_scalar(t, 53), 53)
}

pub impl @arith.Constants for BallFloat with fn e() -> BallFloat {
  let e = @bin_float.e_for_precision(96)
  quantize_interval(lower_scalar(e, 53), upper_scalar(e, 53), 53)
}

pub impl @def.Floating for BallFloat with fn classify(self) {
  self.classify()
}

pub impl @def.Floating for BallFloat with fn sign(self) {
  self.sign()
}

pub impl @def.Floating for BallFloat with fn precision(self) {
  self.precision()
}

pub impl @def.Floating for BallFloat with fn with_precision(self, precision, mode) {
  self.with_precision(precision, mode)
}

pub impl @def.Floating for BallFloat with fn normalized(self) {
  self.normalized()
}

pub impl Show for BallFloat with fn to_string(self) {
  if self.is_bounded() {
    self.center().to_string() + " +/- " + self.radius().to_string()
  } else {
    "[" + self.lo_.to_string() + ", " + self.hi_.to_string() + "]"
  }
}
