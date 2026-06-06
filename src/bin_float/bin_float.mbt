pub struct BinFloat {
  priv class : FpClass
  priv significand : BigInt
  priv exponent2 : Int
  priv precision_ : Int
} derive(Eq)

fn normalize_finite(
  significand : BigInt,
  exponent2 : Int,
  precision : Int,
  mode : RoundingMode,
) -> BinFloat {
  let precision = Int::max(1, precision)
  if significand.is_zero() {
    return { class: FpClass::Finite, significand, exponent2: 0, precision_: precision }
  }
  let (sig0, exp0) = remove_factor2(significand, exponent2)
  let negative = sig0 < bigint_zero()
  let magnitude0 = abs_bigint(sig0)
  let bits = magnitude0.bit_length()
  let (magnitude1, exp1) = if bits > precision {
    let shift = bits - precision
    (round_shift(magnitude0, shift, negative, mode), exp0 + shift)
  } else {
    (magnitude0, exp0)
  }
  let sig1 = if negative { -magnitude1 } else { magnitude1 }
  let (sig2, exp2) = remove_factor2(sig1, exp1)
  { class: FpClass::Finite, significand: sig2, exponent2: exp2, precision_: precision }
}

pub fn BinFloat::make(
  significand : BigInt,
  exponent2 : Int,
  precision : Int,
  mode? : RoundingMode = RoundingMode::ToNearestEven,
) -> BinFloat {
  normalize_finite(significand, exponent2, precision, mode)
}

pub fn BinFloat::zero(precision? : Int = 53) -> BinFloat {
  BinFloat::make(bigint_zero(), 0, precision)
}

pub fn BinFloat::one(precision? : Int = 53) -> BinFloat {
  BinFloat::make(bigint_one(), 0, precision)
}

pub fn BinFloat::inf(sign : Sign, precision? : Int = 53) -> BinFloat {
  let sig = match sign {
    Sign::Negative => -bigint_one()
    Sign::Positive => bigint_one()
    Sign::Zero => bigint_one()
  }
  { class: FpClass::Infinity, significand: sig, exponent2: 0, precision_: Int::max(1, precision) }
}

pub fn BinFloat::nan(precision? : Int = 53) -> BinFloat {
  { class: FpClass::NaN, significand: bigint_zero(), exponent2: 0, precision_: Int::max(1, precision) }
}

pub fn BinFloat::from_int(n : Int, precision? : Int = 53) -> BinFloat {
  BinFloat::make(BigInt::from_int(n), 0, precision)
}

pub fn BinFloat::from_bigint(n : BigInt, precision? : Int = 53) -> BinFloat {
  BinFloat::make(n, 0, precision)
}

pub fn BinFloat::from_double(x : Double, precision? : Int = 53) -> BinFloat {
  let precision = Int::max(1, precision)
  if x.is_nan() {
    return BinFloat::nan(precision=precision)
  }
  if x.is_pos_inf() {
    return BinFloat::inf(Sign::Positive, precision=precision)
  }
  if x.is_neg_inf() {
    return BinFloat::inf(Sign::Negative, precision=precision)
  }
  let bits = x.reinterpret_as_uint64()
  let negative = (bits >> 63) != 0UL
  let exponent_bits = ((bits >> 52) & 0x7ffUL).to_int()
  let fraction_bits = bits & 0x000f_ffff_ffff_ffffUL
  if exponent_bits == 0 {
    if fraction_bits == 0UL {
      return BinFloat::zero(precision=precision)
    }
    let sig = BigInt::from_uint64(fraction_bits)
    let signed = if negative { -sig } else { sig }
    return BinFloat::make(signed, -1074, precision)
  }
  let significand = BigInt::from_uint64((1UL << 52) | fraction_bits)
  let signed = if negative { -significand } else { significand }
  BinFloat::make(signed, exponent_bits - 1075, precision)
}

pub fn BinFloat::from_float(x : Float, precision? : Int = 24) -> BinFloat {
  BinFloat::from_double(x.to_double(), precision=precision)
}

pub fn BinFloat::classify(self : BinFloat) -> FpClass {
  self.class
}

pub fn BinFloat::precision(self : BinFloat) -> Int {
  self.precision_
}

pub fn BinFloat::sign(self : BinFloat) -> Sign {
  match self.class {
    FpClass::NaN => Sign::Zero
    FpClass::Infinity => sign_of_bigint(self.significand)
    FpClass::Finite => sign_of_bigint(self.significand)
  }
}

pub fn BinFloat::significand(self : BinFloat) -> BigInt {
  self.significand
}

pub fn BinFloat::exponent2(self : BinFloat) -> Int {
  self.exponent2
}

pub fn BinFloat::normalized(self : BinFloat) -> BinFloat {
  match self.class {
    FpClass::Finite => normalize_finite(self.significand, self.exponent2, self.precision_, RoundingMode::ToNearestEven)
    _ => self
  }
}

pub fn BinFloat::with_precision(
  self : BinFloat,
  precision : Int,
  mode : RoundingMode,
) -> BinFloat {
  match self.class {
    FpClass::Finite => BinFloat::make(self.significand, self.exponent2, precision, mode=mode)
    FpClass::Infinity => { ..self, precision_: Int::max(1, precision) }
    FpClass::NaN => { ..self, precision_: Int::max(1, precision) }
  }
}

pub fn BinFloat::neg(self : BinFloat) -> BinFloat {
  match self.class {
    FpClass::NaN => self
    _ => { ..self, significand: -self.significand }
  }
}

pub fn BinFloat::abs(self : BinFloat) -> BinFloat {
  if self.sign() == Sign::Negative { self.neg() } else { self }
}

fn max_precision(a : BinFloat, b : BinFloat) -> Int {
  Int::max(a.precision_, b.precision_)
}

fn compare_finite(a : BinFloat, b : BinFloat) -> Int {
  let ea = a.exponent2
  let eb = b.exponent2
  if ea == eb {
    return a.significand.compare(b.significand)
  }
  let target = Int::min(ea, eb)
  let sa = a.significand << (ea - target)
  let sb = b.significand << (eb - target)
  sa.compare(sb)
}

pub fn BinFloat::compare(self : BinFloat, other : BinFloat) -> Int {
  guard self.class != FpClass::NaN && other.class != FpClass::NaN else {
    abort("NaN is unordered")
  }
  match (self.class, other.class) {
    (FpClass::Infinity, FpClass::Infinity) => self.significand.compare(other.significand)
    (FpClass::Infinity, _) => if self.sign() == Sign::Negative { -1 } else { 1 }
    (_, FpClass::Infinity) => if other.sign() == Sign::Negative { 1 } else { -1 }
    (FpClass::Finite, FpClass::Finite) => compare_finite(self, other)
    _ => 0
  }
}

pub fn BinFloat::min(self : BinFloat, other : BinFloat) -> BinFloat {
  if self.classify() == FpClass::NaN {
    other
  } else if other.classify() == FpClass::NaN {
    self
  } else if self.compare(other) <= 0 {
    self
  } else {
    other
  }
}

pub fn BinFloat::max(self : BinFloat, other : BinFloat) -> BinFloat {
  if self.classify() == FpClass::NaN {
    other
  } else if other.classify() == FpClass::NaN {
    self
  } else if self.compare(other) >= 0 {
    self
  } else {
    other
  }
}

pub fn BinFloat::clamp(self : BinFloat, min~ : BinFloat, max~ : BinFloat) -> BinFloat {
  guard min.classify() != FpClass::NaN && max.classify() != FpClass::NaN else {
    abort("clamp bounds must be ordered values")
  }
  guard min.compare(max) <= 0 else { abort("min must not exceed max") }
  if self.classify() == FpClass::NaN {
    self
  } else if self.compare(min) < 0 {
    min
  } else if self.compare(max) > 0 {
    max
  } else {
    self
  }
}

pub fn BinFloat::is_zero(self : BinFloat) -> Bool {
  self.class == FpClass::Finite && self.significand.is_zero()
}

pub fn BinFloat::ulp(self : BinFloat) -> BinFloat {
  match self.class {
    FpClass::Finite => {
      if self.significand.is_zero() {
        BinFloat::make(bigint_one(), -(self.precision_ - 1), self.precision_)
      } else {
        let mag_bits = abs_bigint(self.significand).bit_length()
        BinFloat::make(bigint_one(), self.exponent2 + mag_bits - self.precision_, self.precision_)
      }
    }
    _ => BinFloat::nan(precision=self.precision_)
  }
}

fn add_bin_impl(a : BinFloat, b : BinFloat) -> BinFloat {
  let precision = max_precision(a, b)
  match (a.class, b.class) {
    (FpClass::NaN, _) | (_, FpClass::NaN) => BinFloat::nan(precision=precision)
    (FpClass::Infinity, FpClass::Infinity) => {
      if a.sign() == b.sign() { a.with_precision(precision, RoundingMode::ToNearestEven) } else { BinFloat::nan(precision=precision) }
    }
    (FpClass::Infinity, _) => a.with_precision(precision, RoundingMode::ToNearestEven)
    (_, FpClass::Infinity) => b.with_precision(precision, RoundingMode::ToNearestEven)
    (FpClass::Finite, FpClass::Finite) => {
      let target = Int::min(a.exponent2, b.exponent2)
      let sa = a.significand << (a.exponent2 - target)
      let sb = b.significand << (b.exponent2 - target)
      BinFloat::make(sa + sb, target, precision)
    }
  }
}

fn mul_bin_impl(a : BinFloat, b : BinFloat) -> BinFloat {
  let precision = max_precision(a, b)
  match (a.class, b.class) {
    (FpClass::NaN, _) | (_, FpClass::NaN) => BinFloat::nan(precision=precision)
    (FpClass::Infinity, FpClass::Finite) | (FpClass::Finite, FpClass::Infinity) => {
      if a.is_zero() || b.is_zero() {
        BinFloat::nan(precision=precision)
      } else {
        BinFloat::inf(if a.sign() == b.sign() { Sign::Positive } else { Sign::Negative }, precision=precision)
      }
    }
    (FpClass::Infinity, FpClass::Infinity) => {
      BinFloat::inf(if a.sign() == b.sign() { Sign::Positive } else { Sign::Negative }, precision=precision)
    }
    (FpClass::Finite, FpClass::Finite) => {
      BinFloat::make(a.significand * b.significand, a.exponent2 + b.exponent2, precision)
    }
  }
}

fn div_bin_impl(a : BinFloat, b : BinFloat) -> BinFloat {
  let precision = max_precision(a, b)
  match (a.class, b.class) {
    (FpClass::NaN, _) | (_, FpClass::NaN) => BinFloat::nan(precision=precision)
    (_, FpClass::Finite) if b.is_zero() => {
      if a.is_zero() {
        BinFloat::nan(precision=precision)
      } else {
        BinFloat::inf(if a.sign() == b.sign() { Sign::Positive } else { Sign::Negative }, precision=precision)
      }
    }
    (FpClass::Infinity, FpClass::Infinity) => BinFloat::nan(precision=precision)
    (FpClass::Infinity, _) => BinFloat::inf(if a.sign() == b.sign() { Sign::Positive } else { Sign::Negative }, precision=precision)
    (_, FpClass::Infinity) => BinFloat::zero(precision=precision)
    (FpClass::Finite, FpClass::Finite) => {
      let extra = precision + 2
      let numerator = abs_bigint(a.significand) << extra
      let denominator = abs_bigint(b.significand)
      let q = round_positive_div(
        numerator,
        denominator,
        a.sign() != b.sign(),
        RoundingMode::ToNearestEven,
      )
      let sig = if a.sign() == b.sign() { q } else { -q }
      BinFloat::make(sig, a.exponent2 - b.exponent2 - extra, precision)
    }
  }
}

pub fn BinFloat::add(self : BinFloat, other : BinFloat) -> BinFloat {
  add_bin_impl(self, other)
}

pub fn BinFloat::sub(self : BinFloat, other : BinFloat) -> BinFloat {
  add_bin_impl(self, other.neg())
}

pub fn BinFloat::mul(self : BinFloat, other : BinFloat) -> BinFloat {
  mul_bin_impl(self, other)
}

pub fn BinFloat::div(self : BinFloat, other : BinFloat) -> BinFloat {
  div_bin_impl(self, other)
}

pub impl Add for BinFloat with fn add(self, other) {
  add_bin_impl(self, other)
}

pub impl Sub for BinFloat with fn sub(self, other) {
  self.sub(other)
}

pub impl Mul for BinFloat with fn mul(self, other) {
  mul_bin_impl(self, other)
}

pub impl Div for BinFloat with fn div(self, other) {
  div_bin_impl(self, other)
}

pub impl Neg for BinFloat with fn neg(self) {
  self.neg()
}

pub impl Compare for BinFloat with fn compare(self, other) {
  self.compare(other)
}

pub impl @lg.Zero for BinFloat with fn zero() -> BinFloat {
  BinFloat::zero(precision=1)
}

pub impl @lg.One for BinFloat with fn one() -> BinFloat {
  BinFloat::one(precision=1)
}

pub impl @lg.Inverse for BinFloat with fn inv(self) -> BinFloat {
  guard !self.is_zero()
  BinFloat::one(precision=self.precision_) / self
}

pub impl @lg.AddMonoid for BinFloat

pub impl @lg.MulMonoid for BinFloat

pub impl @lg.AddGroup for BinFloat

pub impl @lg.MulGroup for BinFloat

pub impl @lg.Semiring for BinFloat

pub impl @lg.Ring for BinFloat

pub impl @lg.Field for BinFloat

pub impl @lg.Num for BinFloat with fn abs(self) -> BinFloat {
  self.abs()
}

pub impl @lg.Num for BinFloat with fn signum(self) -> BinFloat {
  match self.sign() {
    Sign::Negative => BinFloat::from_int(-1, precision=self.precision_)
    Sign::Zero => BinFloat::zero(precision=self.precision_)
    Sign::Positive => BinFloat::one(precision=self.precision_)
  }
}

pub impl @arith.Sqrt for BinFloat with fn sqrt(self) -> BinFloat {
  sqrt_for_precision(self, self.precision_)
}

pub impl @arith.Cbrt for BinFloat with fn cbrt(self) -> BinFloat {
  cbrt_for_precision(self, self.precision_)
}

pub impl @arith.Radical for BinFloat

pub impl @arith.Exponential for BinFloat with fn exp(self) -> BinFloat {
  exp_for_precision(self, self.precision_)
}

pub impl @arith.Exponential for BinFloat with fn exp2(self) -> BinFloat {
  exp2_for_precision(self, self.precision_)
}

pub impl @arith.Logarithmic for BinFloat with fn ln(self) -> BinFloat {
  ln_for_precision(self, self.precision_)
}

pub impl @arith.Logarithmic for BinFloat with fn log2(self) -> BinFloat {
  log2_for_precision(self, self.precision_)
}

pub impl @arith.Logarithmic for BinFloat with fn log10(self) -> BinFloat {
  log10_for_precision(self, self.precision_)
}

pub impl @arith.Power for BinFloat with fn pow(self, exponent) -> BinFloat {
  pow_for_precision(self, exponent, Int::max(self.precision_, exponent.precision()))
}

pub impl @arith.Trigonometric for BinFloat with fn sin(self) -> BinFloat {
  sin_for_precision(self, self.precision_)
}

pub impl @arith.Trigonometric for BinFloat with fn cos(self) -> BinFloat {
  cos_for_precision(self, self.precision_)
}

pub impl @arith.Trigonometric for BinFloat with fn tan(self) -> BinFloat {
  tan_for_precision(self, self.precision_)
}

pub impl @arith.InverseTrigonometric for BinFloat with fn asin(self) -> BinFloat {
  asin_for_precision(self, self.precision_)
}

pub impl @arith.InverseTrigonometric for BinFloat with fn acos(self) -> BinFloat {
  acos_for_precision(self, self.precision_)
}

pub impl @arith.InverseTrigonometric for BinFloat with fn atan(self) -> BinFloat {
  atan_for_precision(self, self.precision_)
}

pub impl @arith.InverseTrigonometric for BinFloat with fn atan2(self, other) -> BinFloat {
  atan2_for_precision(self, other, Int::max(self.precision_, other.precision()))
}

pub impl @arith.Hyperbolic for BinFloat with fn sinh(self) -> BinFloat {
  sinh_for_precision(self, self.precision_)
}

pub impl @arith.Hyperbolic for BinFloat with fn cosh(self) -> BinFloat {
  cosh_for_precision(self, self.precision_)
}

pub impl @arith.Hyperbolic for BinFloat with fn tanh(self) -> BinFloat {
  tanh_for_precision(self, self.precision_)
}

pub impl @arith.InverseHyperbolic for BinFloat with fn asinh(self) -> BinFloat {
  asinh_for_precision(self, self.precision_)
}

pub impl @arith.InverseHyperbolic for BinFloat with fn acosh(self) -> BinFloat {
  acosh_for_precision(self, self.precision_)
}

pub impl @arith.InverseHyperbolic for BinFloat with fn atanh(self) -> BinFloat {
  atanh_for_precision(self, self.precision_)
}

pub impl @arith.Constants for BinFloat with fn pi() -> BinFloat {
  pi_for_precision(53)
}

pub impl @arith.Constants for BinFloat with fn tau() -> BinFloat {
  tau_for_precision(53)
}

pub impl @arith.Constants for BinFloat with fn e() -> BinFloat {
  e_for_precision(53)
}

pub impl @def.Floating for BinFloat with fn classify(self) {
  self.classify()
}

pub impl @def.Floating for BinFloat with fn sign(self) {
  self.sign()
}

pub impl @def.Floating for BinFloat with fn precision(self) {
  self.precision()
}

pub impl @def.Floating for BinFloat with fn with_precision(self, precision, mode) {
  self.with_precision(precision, mode)
}

pub impl @def.Floating for BinFloat with fn normalized(self) {
  self.normalized()
}

pub impl Show for BinFloat with fn to_string(self) {
  match self.class {
    FpClass::NaN => "nan"
    FpClass::Infinity => if self.sign() == Sign::Negative { "-inf" } else { "inf" }
    FpClass::Finite => {
      if self.significand.is_zero() {
        "0"
      } else {
        self.significand.to_string() + "p" + self.exponent2.to_string()
      }
    }
  }
}
