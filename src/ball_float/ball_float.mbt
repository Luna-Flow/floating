pub struct BallFloat {
  priv center_ : @bin_float.BinFloat
  priv radius_ : @bin_float.BinFloat
  priv precision_ : Int
} derive(Eq)

fn validate_ball(center : @bin_float.BinFloat, radius : @bin_float.BinFloat) -> Unit {
  guard center.classify() == FpClass::Finite else { abort("ball center must be finite") }
  guard radius.classify() == FpClass::Finite else { abort("ball radius must be finite") }
  guard radius.sign() != Sign::Negative else { abort("ball radius must be non-negative") }
}

fn exact_precision(x : @bin_float.BinFloat) -> Int {
  if x.is_zero() {
    1
  } else {
    @internal.abs_bigint(x.significand()).bit_length()
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

fn outward_round(x : @bin_float.BinFloat, precision : Int) -> @bin_float.BinFloat {
  x.with_precision(precision, RoundingMode::AwayFromZero).abs()
}

fn outward_sum(a : @bin_float.BinFloat, b : @bin_float.BinFloat, precision : Int) -> @bin_float.BinFloat {
  outward_round(exact_add(a, b), precision)
}

fn store_ball(
  center : @bin_float.BinFloat,
  radius : @bin_float.BinFloat,
  precision : Int,
) -> BallFloat {
  validate_ball(center, radius)
  { center_: center, radius_: radius, precision_: precision }
}

fn quantize_ball_exact_center(
  center : @bin_float.BinFloat,
  radius : @bin_float.BinFloat,
  precision : Int,
  mode : RoundingMode,
) -> BallFloat {
  let precision = Int::max(1, precision)
  let rounded_center = center.with_precision(precision, mode)
  let center_error = outward_round(exact_sub(center, rounded_center).abs(), precision)
  let rounded_radius = outward_round(radius, precision)
  let total_radius = outward_sum(rounded_radius, center_error, precision)
  store_ball(rounded_center, total_radius, precision)
}

fn quantize_ball_approx_center(
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
  store_ball(rounded_center, total_radius, precision)
}

fn div_high_precision(
  numerator : @bin_float.BinFloat,
  denominator : @bin_float.BinFloat,
  precision : Int,
) -> (@bin_float.BinFloat, @bin_float.BinFloat) {
  let high_precision = Int::max(precision + 4, precision * 2 + 4)
  let q = numerator.with_precision(high_precision, RoundingMode::ToNearestEven) / denominator.with_precision(high_precision, RoundingMode::ToNearestEven)
  (q.with_precision(high_precision, RoundingMode::ToNearestEven), q.ulp())
}

pub fn BallFloat::new(
  center : @bin_float.BinFloat,
  radius : @bin_float.BinFloat,
  precision? : Int = Int::max(center.precision(), radius.precision()),
) -> BallFloat {
  validate_ball(center, radius)
  quantize_ball_exact_center(center, radius, precision, RoundingMode::ToNearestEven)
}

pub fn BallFloat::exact(x : @bin_float.BinFloat, precision? : Int = x.precision()) -> BallFloat {
  guard x.classify() == FpClass::Finite else { abort("ball exact source must be finite") }
  BallFloat::new(x, @bin_float.BinFloat::zero(precision=exact_precision(x)), precision=precision)
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

pub fn BallFloat::center(self : BallFloat) -> @bin_float.BinFloat {
  self.center_
}

pub fn BallFloat::radius(self : BallFloat) -> @bin_float.BinFloat {
  self.radius_
}

pub fn BallFloat::precision(self : BallFloat) -> Int {
  self.precision_
}

pub fn BallFloat::classify(_self : BallFloat) -> FpClass {
  FpClass::Finite
}

pub fn BallFloat::sign(self : BallFloat) -> Sign {
  if self.radius_.is_zero() {
    self.center_.sign()
  } else {
    let lo = self.center_ - self.radius_
    let hi = self.center_ + self.radius_
    if lo.sign() == Sign::Positive {
      Sign::Positive
    } else if hi.sign() == Sign::Negative {
      Sign::Negative
    } else {
      Sign::Zero
    }
  }
}

pub fn BallFloat::normalized(self : BallFloat) -> BallFloat {
  quantize_ball_exact_center(self.center_.normalized(), self.radius_.normalized(), self.precision_, RoundingMode::ToNearestEven)
}

pub fn BallFloat::with_precision(
  self : BallFloat,
  precision : Int,
  mode : RoundingMode,
) -> BallFloat {
  quantize_ball_exact_center(self.center_, self.radius_, precision, mode)
}

pub fn BallFloat::contains(self : BallFloat, x : @bin_float.BinFloat) -> Bool {
  guard x.classify() == FpClass::Finite else { return false }
  let delta = (x - self.center_).abs()
  delta.compare(self.radius_) <= 0
}

pub fn BallFloat::overlaps(self : BallFloat, other : BallFloat) -> Bool {
  let distance = (self.center_ - other.center_).abs()
  distance.compare(self.radius_ + other.radius_) <= 0
}

pub fn BallFloat::separated_from(self : BallFloat, other : BallFloat) -> Bool {
  !self.overlaps(other)
}

pub fn BallFloat::definitely_lt(self : BallFloat, other : BallFloat) -> Bool {
  (self.center_ + self.radius_).compare(other.center_ - other.radius_) < 0
}

pub fn BallFloat::definitely_gt(self : BallFloat, other : BallFloat) -> Bool {
  (self.center_ - self.radius_).compare(other.center_ + other.radius_) > 0
}

pub fn BallFloat::maybe_overlap(self : BallFloat, other : BallFloat) -> Bool {
  self.overlaps(other)
}

fn add_ball_impl(a : BallFloat, b : BallFloat) -> BallFloat {
  let precision = Int::max(a.precision_, b.precision_)
  let center = exact_add(a.center_, b.center_)
  let radius = exact_add(a.radius_, b.radius_)
  quantize_ball_exact_center(center, radius, precision, RoundingMode::ToNearestEven)
}

fn mul_ball_impl(a : BallFloat, b : BallFloat) -> BallFloat {
  let precision = Int::max(a.precision_, b.precision_)
  let center = exact_mul(a.center_, b.center_)
  let radius =
    exact_add(
      exact_add(
        exact_mul(a.center_.abs(), b.radius_),
        exact_mul(b.center_.abs(), a.radius_),
      ),
      exact_mul(a.radius_, b.radius_),
    )
  quantize_ball_exact_center(center, radius, precision, RoundingMode::ToNearestEven)
}

fn div_ball_impl(a : BallFloat, b : BallFloat) -> BallFloat {
  let precision = Int::max(a.precision_, b.precision_)
  let denom_abs = b.center_.abs()
  if denom_abs.compare(b.radius_) <= 0 {
    abort("division ball contains zero")
  }
  let (center_high, center_high_error) = div_high_precision(a.center_, b.center_, precision)
  let numerator = exact_add(
    exact_mul(a.center_.abs(), b.radius_),
    exact_mul(denom_abs, a.radius_),
  )
  let denominator = exact_mul(denom_abs, exact_sub(denom_abs, b.radius_))
  let (radius_high, radius_high_error) = div_high_precision(numerator, denominator, precision)
  let radius = outward_sum(radius_high.abs(), radius_high_error, Int::max(radius_high.precision(), radius_high_error.precision()))
  quantize_ball_approx_center(center_high, center_high_error, radius, precision, RoundingMode::ToNearestEven)
}

pub fn BallFloat::add(self : BallFloat, other : BallFloat) -> BallFloat {
  add_ball_impl(self, other)
}

pub fn BallFloat::sub(self : BallFloat, other : BallFloat) -> BallFloat {
  let precision = Int::max(self.precision_, other.precision_)
  let center = exact_sub(self.center_, other.center_)
  let radius = exact_add(self.radius_, other.radius_)
  quantize_ball_exact_center(center, radius, precision, RoundingMode::ToNearestEven)
}

pub fn BallFloat::mul(self : BallFloat, other : BallFloat) -> BallFloat {
  mul_ball_impl(self, other)
}

pub fn BallFloat::div(self : BallFloat, other : BallFloat) -> BallFloat {
  div_ball_impl(self, other)
}

pub impl Add for BallFloat with fn add(self, other) {
  add_ball_impl(self, other)
}

pub impl Sub for BallFloat with fn sub(self, other) {
  self.sub(other)
}

pub impl Mul for BallFloat with fn mul(self, other) {
  mul_ball_impl(self, other)
}

pub impl Div for BallFloat with fn div(self, other) {
  div_ball_impl(self, other)
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
  self.center_.to_string() + " +/- " + self.radius_.to_string()
}
