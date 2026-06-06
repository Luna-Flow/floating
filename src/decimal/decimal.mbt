pub struct Decimal {
  priv class : FpClass
  priv coefficient : BigInt
  priv exponent10 : Int
  priv precision_ : Int
} derive(Eq)

fn normalize_decimal(
  coefficient : BigInt,
  exponent10 : Int,
  precision : Int,
  mode : RoundingMode,
) -> Decimal {
  let precision = Int::max(1, precision)
  if coefficient.is_zero() {
    return { class: FpClass::Finite, coefficient, exponent10: 0, precision_: precision }
  }
  let (coeff0, exp0) = remove_factor10(coefficient, exponent10)
  let negative = coeff0 < bigint_zero()
  let magnitude0 = abs_bigint(coeff0)
  let digits = digits10(magnitude0)
  let (magnitude1, exp1) = if digits > precision {
    let shift = digits - precision
    let divisor = pow10(shift)
    (round_positive_div(magnitude0, divisor, negative, mode), exp0 + shift)
  } else {
    (magnitude0, exp0)
  }
  let coeff1 = if negative { -magnitude1 } else { magnitude1 }
  let (coeff2, exp2) = remove_factor10(coeff1, exp1)
  { class: FpClass::Finite, coefficient: coeff2, exponent10: exp2, precision_: precision }
}

pub fn Decimal::make(
  coefficient : BigInt,
  exponent10 : Int,
  precision : Int,
  mode? : RoundingMode = RoundingMode::ToNearestEven,
) -> Decimal {
  normalize_decimal(coefficient, exponent10, precision, mode)
}

pub fn Decimal::zero(precision? : Int = 34) -> Decimal {
  Decimal::make(bigint_zero(), 0, precision)
}

pub fn Decimal::one(precision? : Int = 34) -> Decimal {
  Decimal::make(bigint_one(), 0, precision)
}

pub fn Decimal::inf(sign : Sign, precision? : Int = 34) -> Decimal {
  let coeff = match sign {
    Sign::Negative => -bigint_one()
    Sign::Positive => bigint_one()
    Sign::Zero => bigint_one()
  }
  { class: FpClass::Infinity, coefficient: coeff, exponent10: 0, precision_: Int::max(1, precision) }
}

pub fn Decimal::nan(precision? : Int = 34) -> Decimal {
  { class: FpClass::NaN, coefficient: bigint_zero(), exponent10: 0, precision_: Int::max(1, precision) }
}

pub fn Decimal::from_int(n : Int, precision? : Int = 34) -> Decimal {
  Decimal::make(BigInt::from_int(n), 0, precision)
}

pub fn Decimal::from_bigint(n : BigInt, precision? : Int = 34) -> Decimal {
  Decimal::make(n, 0, precision)
}

pub fn Decimal::from_string(src : String, precision? : Int = 34) -> Decimal? {
  match split_decimal_string(src) {
    Some((negative, digits, exponent10)) => {
      let coeff = BigInt::from_string(digits)
      let signed = if negative { -coeff } else { coeff }
      Some(Decimal::make(signed, exponent10, precision))
    }
    None => None
  }
}

pub fn Decimal::classify(self : Decimal) -> FpClass {
  self.class
}

pub fn Decimal::precision(self : Decimal) -> Int {
  self.precision_
}

pub fn Decimal::sign(self : Decimal) -> Sign {
  match self.class {
    FpClass::NaN => Sign::Zero
    _ => sign_of_bigint(self.coefficient)
  }
}

pub fn Decimal::coefficient(self : Decimal) -> BigInt {
  self.coefficient
}

pub fn Decimal::exponent10(self : Decimal) -> Int {
  self.exponent10
}

pub fn Decimal::is_zero(self : Decimal) -> Bool {
  self.class == FpClass::Finite && self.coefficient.is_zero()
}

pub fn Decimal::normalized(self : Decimal) -> Decimal {
  match self.class {
    FpClass::Finite => Decimal::make(self.coefficient, self.exponent10, self.precision_, mode=RoundingMode::ToNearestEven)
    _ => self
  }
}

pub fn Decimal::with_precision(
  self : Decimal,
  precision : Int,
  mode : RoundingMode,
) -> Decimal {
  match self.class {
    FpClass::Finite => Decimal::make(self.coefficient, self.exponent10, precision, mode=mode)
    FpClass::Infinity => { ..self, precision_: Int::max(1, precision) }
    FpClass::NaN => { ..self, precision_: Int::max(1, precision) }
  }
}

pub fn Decimal::neg(self : Decimal) -> Decimal {
  match self.class {
    FpClass::NaN => self
    _ => { ..self, coefficient: -self.coefficient }
  }
}

pub fn Decimal::abs(self : Decimal) -> Decimal {
  if self.sign() == Sign::Negative { self.neg() } else { self }
}

fn max_precision(a : Decimal, b : Decimal) -> Int {
  Int::max(a.precision_, b.precision_)
}

fn zeros(n : Int) -> String {
  let b = StringBuilder::new()
  for _ in 0..<n {
    b.write_char('0')
  }
  b.to_string()
}

fn add_decimal_impl(a : Decimal, b : Decimal) -> Decimal {
  let precision = max_precision(a, b)
  match (a.class, b.class) {
    (FpClass::NaN, _) | (_, FpClass::NaN) => Decimal::nan(precision=precision)
    (FpClass::Infinity, FpClass::Infinity) => {
      if a.sign() == b.sign() { a.with_precision(precision, RoundingMode::ToNearestEven) } else { Decimal::nan(precision=precision) }
    }
    (FpClass::Infinity, _) => a.with_precision(precision, RoundingMode::ToNearestEven)
    (_, FpClass::Infinity) => b.with_precision(precision, RoundingMode::ToNearestEven)
    (FpClass::Finite, FpClass::Finite) => {
      let target = Int::min(a.exponent10, b.exponent10)
      let ca = a.coefficient * pow10(a.exponent10 - target)
      let cb = b.coefficient * pow10(b.exponent10 - target)
      Decimal::make(ca + cb, target, precision)
    }
  }
}

fn mul_decimal_impl(a : Decimal, b : Decimal) -> Decimal {
  let precision = max_precision(a, b)
  match (a.class, b.class) {
    (FpClass::NaN, _) | (_, FpClass::NaN) => Decimal::nan(precision=precision)
    (FpClass::Infinity, FpClass::Finite) | (FpClass::Finite, FpClass::Infinity) => {
      if a.is_zero() || b.is_zero() {
        Decimal::nan(precision=precision)
      } else {
        Decimal::inf(if a.sign() == b.sign() { Sign::Positive } else { Sign::Negative }, precision=precision)
      }
    }
    (FpClass::Infinity, FpClass::Infinity) => Decimal::inf(if a.sign() == b.sign() { Sign::Positive } else { Sign::Negative }, precision=precision)
    (FpClass::Finite, FpClass::Finite) => Decimal::make(a.coefficient * b.coefficient, a.exponent10 + b.exponent10, precision)
  }
}

fn div_decimal_impl(a : Decimal, b : Decimal) -> Decimal {
  let precision = max_precision(a, b)
  match (a.class, b.class) {
    (FpClass::NaN, _) | (_, FpClass::NaN) => Decimal::nan(precision=precision)
    (_, FpClass::Finite) if b.is_zero() => {
      if a.is_zero() {
        Decimal::nan(precision=precision)
      } else {
        Decimal::inf(if a.sign() == b.sign() { Sign::Positive } else { Sign::Negative }, precision=precision)
      }
    }
    (FpClass::Infinity, FpClass::Infinity) => Decimal::nan(precision=precision)
    (FpClass::Infinity, _) => Decimal::inf(if a.sign() == b.sign() { Sign::Positive } else { Sign::Negative }, precision=precision)
    (_, FpClass::Infinity) => Decimal::zero(precision=precision)
    (FpClass::Finite, FpClass::Finite) => {
      let extra = precision + 2
      let numerator = abs_bigint(a.coefficient) * pow10(extra)
      let denominator = abs_bigint(b.coefficient)
      let q = round_positive_div(
        numerator,
        denominator,
        a.sign() != b.sign(),
        RoundingMode::ToNearestEven,
      )
      let coeff = if a.sign() == b.sign() { q } else { -q }
      Decimal::make(coeff, a.exponent10 - b.exponent10 - extra, precision)
    }
  }
}

pub fn Decimal::add(self : Decimal, other : Decimal) -> Decimal {
  add_decimal_impl(self, other)
}

pub fn Decimal::sub(self : Decimal, other : Decimal) -> Decimal {
  add_decimal_impl(self, other.neg())
}

pub fn Decimal::mul(self : Decimal, other : Decimal) -> Decimal {
  mul_decimal_impl(self, other)
}

pub fn Decimal::div(self : Decimal, other : Decimal) -> Decimal {
  div_decimal_impl(self, other)
}

pub fn Decimal::to_bin_float(
  self : Decimal,
  precision? : Int = self.precision_,
  mode? : RoundingMode = RoundingMode::ToNearestEven,
) -> @bin_float.BinFloat {
  match self.class {
    FpClass::NaN => @bin_float.BinFloat::nan(precision=precision)
    FpClass::Infinity => @bin_float.BinFloat::inf(self.sign(), precision=precision)
    FpClass::Finite => {
      if self.coefficient.is_zero() {
        return @bin_float.BinFloat::zero(precision=precision)
      }
      if self.exponent10 >= 0 {
        return @bin_float.BinFloat::make(
          self.coefficient * pow5(self.exponent10),
          self.exponent10,
          precision,
          mode=mode,
        )
      }
      let scale = -self.exponent10
      let numerator = abs_bigint(self.coefficient) << (precision + scale)
      let denominator = pow10(scale)
      let q = round_positive_div(numerator, denominator, self.sign() == Sign::Negative, mode)
      let sig = if self.sign() == Sign::Negative { -q } else { q }
      @bin_float.BinFloat::make(sig, -(precision + scale), precision, mode=mode)
    }
  }
}

pub fn Decimal::from_bin_float(
  x : @bin_float.BinFloat,
  precision? : Int = x.precision(),
) -> Decimal {
  match x.classify() {
    FpClass::NaN => Decimal::nan(precision=precision)
    FpClass::Infinity => Decimal::inf(x.sign(), precision=precision)
    FpClass::Finite => {
      if x.is_zero() {
        Decimal::zero(precision=precision)
      } else if x.exponent2() >= 0 {
        Decimal::make(x.significand() << x.exponent2(), 0, precision)
      } else {
        let k = -x.exponent2()
        Decimal::make(x.significand() * pow5(k), -k, precision)
      }
    }
  }
}

pub impl Add for Decimal with fn add(self, other) {
  add_decimal_impl(self, other)
}

pub impl Sub for Decimal with fn sub(self, other) {
  self.sub(other)
}

pub impl Mul for Decimal with fn mul(self, other) {
  mul_decimal_impl(self, other)
}

pub impl Div for Decimal with fn div(self, other) {
  div_decimal_impl(self, other)
}

pub impl Neg for Decimal with fn neg(self) {
  self.neg()
}

pub impl @def.Floating for Decimal with fn classify(self) {
  self.classify()
}

pub impl @def.Floating for Decimal with fn sign(self) {
  self.sign()
}

pub impl @def.Floating for Decimal with fn precision(self) {
  self.precision()
}

pub impl @def.Floating for Decimal with fn with_precision(self, precision, mode) {
  self.with_precision(precision, mode)
}

pub impl @def.Floating for Decimal with fn normalized(self) {
  self.normalized()
}

pub impl Show for Decimal with fn to_string(self) {
  match self.class {
    FpClass::NaN => "nan"
    FpClass::Infinity => if self.sign() == Sign::Negative { "-inf" } else { "inf" }
    FpClass::Finite => {
      if self.coefficient.is_zero() {
        return "0"
      }
      let negative = self.coefficient < bigint_zero()
      let digits = abs_bigint(self.coefficient).to_string()
      let prefix = if negative { "-" } else { "" }
      if self.exponent10 >= 0 {
        prefix + digits + zeros(self.exponent10)
      } else {
        let split = digits.length() + self.exponent10
        if split > 0 {
          prefix + digits[:split].to_owned() + "." + digits[split:].to_owned()
        } else {
          prefix + "0." + zeros(-split) + digits
        }
      }
    }
  }
}
