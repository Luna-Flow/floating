///|
pub struct BinFloat {
  priv class : FpClass
  priv significand : BigInt
  priv exponent2 : Int
  priv precision_ : Int
} derive(Eq)

///|
fn normalize_finite(
  significand : BigInt,
  exponent2 : Int,
  precision : Int,
  mode : RoundingMode,
) -> BinFloat {
  let precision = Int::max(1, precision)
  if significand.is_zero() {
    return {
      class: FpClass::Finite,
      significand,
      exponent2: 0,
      precision_: precision,
    }
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
  {
    class: FpClass::Finite,
    significand: sig2,
    exponent2: exp2,
    precision_: precision,
  }
}

///|
fn max_precision(a : BinFloat, b : BinFloat) -> Int {
  Int::max(a.precision_, b.precision_)
}

///|
fn exact_make(significand : BigInt, exponent2 : Int) -> BinFloat {
  BinFloat::make(
    significand,
    exponent2,
    Int::max(1, abs_bigint(significand).bit_length()),
  )
}

///|
fn exact_add(a : BinFloat, b : BinFloat) -> BinFloat {
  let target = Int::min(a.exponent2(), b.exponent2())
  let sa = a.significand() << (a.exponent2() - target)
  let sb = b.significand() << (b.exponent2() - target)
  exact_make(sa + sb, target)
}

///|
fn exact_half(x : BinFloat) -> BinFloat {
  exact_make(x.significand(), x.exponent2() - 1)
}

///|
fn integer_sqrt_floor(n : BigInt) -> BigInt {
  if n <= 1N {
    return n
  }
  let mut x = 1N << ((n.bit_length() + 1) / 2)
  let mut y = (x + n / x) / 2N
  while y < x {
    x = y
    y = (x + n / x) / 2N
  }
  x
}

///|
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

///|
fn pow_nat(base : BinFloat, exponent : Int, precision : Int) -> BinFloat {
  let mut n = exponent
  let mut result = BinFloat::one(precision~)
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
fn add_bin_impl(a : BinFloat, b : BinFloat) -> BinFloat {
  let precision = max_precision(a, b)
  match (a.class, b.class) {
    (FpClass::NaN, _) | (_, FpClass::NaN) => BinFloat::nan(precision~)
    (FpClass::Infinity, FpClass::Infinity) =>
      if a.sign() == b.sign() {
        a.with_precision(precision, RoundingMode::ToNearestEven)
      } else {
        BinFloat::nan(precision~)
      }
    (FpClass::Infinity, _) =>
      a.with_precision(precision, RoundingMode::ToNearestEven)
    (_, FpClass::Infinity) =>
      b.with_precision(precision, RoundingMode::ToNearestEven)
    (FpClass::Finite, FpClass::Finite) => {
      let target = Int::min(a.exponent2, b.exponent2)
      let sa = a.significand << (a.exponent2 - target)
      let sb = b.significand << (b.exponent2 - target)
      BinFloat::make(sa + sb, target, precision)
    }
  }
}

///|
fn mul_bin_impl(a : BinFloat, b : BinFloat) -> BinFloat {
  let precision = max_precision(a, b)
  match (a.class, b.class) {
    (FpClass::NaN, _) | (_, FpClass::NaN) => BinFloat::nan(precision~)
    (FpClass::Infinity, FpClass::Finite)
    | (FpClass::Finite, FpClass::Infinity) =>
      if a.is_zero() || b.is_zero() {
        BinFloat::nan(precision~)
      } else {
        BinFloat::inf(
          if a.sign() == b.sign() {
            Sign::Positive
          } else {
            Sign::Negative
          },
          precision~,
        )
      }
    (FpClass::Infinity, FpClass::Infinity) =>
      BinFloat::inf(
        if a.sign() == b.sign() {
          Sign::Positive
        } else {
          Sign::Negative
        },
        precision~,
      )
    (FpClass::Finite, FpClass::Finite) =>
      BinFloat::make(
        a.significand * b.significand,
        a.exponent2 + b.exponent2,
        precision,
      )
  }
}

///|
fn div_bin_impl(a : BinFloat, b : BinFloat) -> BinFloat {
  let precision = max_precision(a, b)
  match (a.class, b.class) {
    (FpClass::NaN, _) | (_, FpClass::NaN) => BinFloat::nan(precision~)
    (_, FpClass::Finite) if b.is_zero() =>
      if a.is_zero() {
        BinFloat::nan(precision~)
      } else {
        BinFloat::inf(
          if a.sign() == b.sign() {
            Sign::Positive
          } else {
            Sign::Negative
          },
          precision~,
        )
      }
    (FpClass::Infinity, FpClass::Infinity) => BinFloat::nan(precision~)
    (FpClass::Infinity, _) =>
      BinFloat::inf(
        if a.sign() == b.sign() {
          Sign::Positive
        } else {
          Sign::Negative
        },
        precision~,
      )
    (_, FpClass::Infinity) => BinFloat::zero(precision~)
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

///|
pub fn sqrt_bounds_for_precision(
  x : BinFloat,
  precision : Int,
) -> Result[(BinFloat, BinFloat), @def.ArithmeticError] {
  guard x.classify() == FpClass::Finite else {
    return Err(
      @def.ArithmeticError::unsupported("sqrt bounds require a finite value"),
    )
  }
  guard x.sign() != Sign::Negative else {
    return Err(
      @def.ArithmeticError::domain_error("sqrt requires a non-negative value"),
    )
  }
  if x.is_zero() {
    let z = BinFloat::zero(precision~)
    return Ok((z, z))
  }
  let e = x.exponent2()
  let extra = if e < 0 { (-e + 1) / 2 } else { 0 }
  let work_bits = Int::max(1, precision) + extra + 6
  let shift = e + 2 * work_bits
  let n = x.significand() << shift
  let q = integer_sqrt_floor(n)
  let lower0 = BinFloat::make(q, -work_bits, Int::max(1, q.bit_length()))
  let lower = lower0.with_precision(precision, RoundingMode::TowardNegative)
  if q * q == n {
    return Ok((lower, lower))
  }
  let upper0 = BinFloat::make(
    q + 1N,
    -work_bits,
    Int::max(1, (q + 1N).bit_length()),
  )
  let upper = upper0.with_precision(precision, RoundingMode::TowardPositive)
  Ok((lower, upper))
}

///|
pub fn sqrt_for_precision(
  x : BinFloat,
  precision : Int,
) -> Result[BinFloat, @def.ArithmeticError] {
  match x.classify() {
    FpClass::NaN => Ok(BinFloat::nan(precision~))
    FpClass::Infinity =>
      if x.sign() == Sign::Negative {
        Err(
          @def.ArithmeticError::domain_error(
            "sqrt requires a non-negative value",
          ),
        )
      } else {
        Ok(BinFloat::inf(Sign::Positive, precision~))
      }
    FpClass::Finite =>
      match sqrt_bounds_for_precision(x, precision) {
        Ok((lo, hi)) =>
          Ok(
            exact_half(exact_add(lo, hi)).with_precision(
              precision,
              RoundingMode::ToNearestEven,
            ),
          )
        Err(err) => Err(err)
      }
  }
}

///|
pub fn BinFloat::make(
  significand : BigInt,
  exponent2 : Int,
  precision : Int,
  mode? : RoundingMode = RoundingMode::ToNearestEven,
) -> BinFloat {
  normalize_finite(significand, exponent2, precision, mode)
}

///|
pub fn BinFloat::zero(precision? : Int = 53) -> BinFloat {
  BinFloat::make(bigint_zero(), 0, precision)
}

///|
pub fn BinFloat::one(precision? : Int = 53) -> BinFloat {
  BinFloat::make(bigint_one(), 0, precision)
}

///|
pub fn BinFloat::inf(sign : Sign, precision? : Int = 53) -> BinFloat {
  let sig = match sign {
    Sign::Negative => -bigint_one()
    Sign::Positive => bigint_one()
    Sign::Zero => bigint_one()
  }
  {
    class: FpClass::Infinity,
    significand: sig,
    exponent2: 0,
    precision_: Int::max(1, precision),
  }
}

///|
pub fn BinFloat::nan(precision? : Int = 53) -> BinFloat {
  {
    class: FpClass::NaN,
    significand: bigint_zero(),
    exponent2: 0,
    precision_: Int::max(1, precision),
  }
}

///|
pub fn BinFloat::from_int(n : Int, precision? : Int = 53) -> BinFloat {
  BinFloat::make(BigInt::from_int(n), 0, precision)
}

///|
pub fn BinFloat::from_bigint(n : BigInt, precision? : Int = 53) -> BinFloat {
  BinFloat::make(n, 0, precision)
}

///|
pub fn BinFloat::from_double(x : Double, precision? : Int = 53) -> BinFloat {
  let precision = Int::max(1, precision)
  if x.is_nan() {
    return BinFloat::nan(precision~)
  }
  if x.is_pos_inf() {
    return BinFloat::inf(Sign::Positive, precision~)
  }
  if x.is_neg_inf() {
    return BinFloat::inf(Sign::Negative, precision~)
  }
  let bits = x.reinterpret_as_uint64()
  let negative = bits >> 63 != 0UL
  let exponent_bits = ((bits >> 52) & 0x7ffUL).to_int()
  let fraction_bits = bits & 0x000f_ffff_ffff_ffffUL
  if exponent_bits == 0 {
    if fraction_bits == 0UL {
      return BinFloat::zero(precision~)
    }
    let sig = BigInt::from_uint64(fraction_bits)
    let signed = if negative { -sig } else { sig }
    return BinFloat::make(signed, -1074, precision)
  }
  let significand = BigInt::from_uint64((1UL << 52) | fraction_bits)
  let signed = if negative { -significand } else { significand }
  BinFloat::make(signed, exponent_bits - 1075, precision)
}

///|
pub fn BinFloat::from_float(x : Float, precision? : Int = 24) -> BinFloat {
  BinFloat::from_double(x.to_double(), precision~)
}

///|
pub fn BinFloat::classify(self : BinFloat) -> FpClass {
  self.class
}

///|
pub fn BinFloat::precision(self : BinFloat) -> Int {
  self.precision_
}

///|
pub fn BinFloat::sign(self : BinFloat) -> Sign {
  match self.class {
    FpClass::NaN => Sign::Zero
    _ => sign_of_bigint(self.significand)
  }
}

///|
pub fn BinFloat::significand(self : BinFloat) -> BigInt {
  self.significand
}

///|
pub fn BinFloat::exponent2(self : BinFloat) -> Int {
  self.exponent2
}

///|
pub fn BinFloat::normalized(self : BinFloat) -> BinFloat {
  match self.class {
    FpClass::Finite =>
      normalize_finite(
        self.significand,
        self.exponent2,
        self.precision_,
        RoundingMode::ToNearestEven,
      )
    _ => self
  }
}

///|
pub fn BinFloat::with_precision(
  self : BinFloat,
  precision : Int,
  mode : RoundingMode,
) -> BinFloat {
  match self.class {
    FpClass::Finite =>
      BinFloat::make(self.significand, self.exponent2, precision, mode~)
    FpClass::Infinity => { ..self, precision_: Int::max(1, precision) }
    FpClass::NaN => { ..self, precision_: Int::max(1, precision) }
  }
}

///|
pub fn BinFloat::neg(self : BinFloat) -> BinFloat {
  match self.class {
    FpClass::NaN => self
    _ => { ..self, significand: -self.significand }
  }
}

///|
pub fn BinFloat::abs(self : BinFloat) -> BinFloat {
  if self.sign() == Sign::Negative {
    self.neg()
  } else {
    self
  }
}

///|
pub fn BinFloat::is_zero(self : BinFloat) -> Bool {
  self.class == FpClass::Finite && self.significand.is_zero()
}

///|
pub fn BinFloat::compare_checked(
  self : BinFloat,
  other : BinFloat,
) -> Result[Int, @def.ArithmeticError] {
  guard self.class != FpClass::NaN && other.class != FpClass::NaN else {
    return Err(@def.ArithmeticError::unordered_comparison("NaN is unordered"))
  }
  Ok(
    match (self.class, other.class) {
      (FpClass::Infinity, FpClass::Infinity) =>
        self.significand.compare(other.significand)
      (FpClass::Infinity, _) =>
        if self.sign() == Sign::Negative {
          -1
        } else {
          1
        }
      (_, FpClass::Infinity) =>
        if other.sign() == Sign::Negative {
          1
        } else {
          -1
        }
      (FpClass::Finite, FpClass::Finite) => compare_finite(self, other)
      _ => 0
    },
  )
}

///|
pub fn BinFloat::compare(self : BinFloat, other : BinFloat) -> Int {
  guard self.class != FpClass::NaN && other.class != FpClass::NaN else {
    abort("NaN is unordered")
  }
  match (self.class, other.class) {
    (FpClass::Infinity, FpClass::Infinity) =>
      self.significand.compare(other.significand)
    (FpClass::Infinity, _) => if self.sign() == Sign::Negative { -1 } else { 1 }
    (_, FpClass::Infinity) =>
      if other.sign() == Sign::Negative {
        1
      } else {
        -1
      }
    (FpClass::Finite, FpClass::Finite) => compare_finite(self, other)
    _ => 0
  }
}

///|
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

///|
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

///|
pub fn BinFloat::clamp(
  self : BinFloat,
  min~ : BinFloat,
  max~ : BinFloat,
) -> BinFloat {
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

///|
pub fn BinFloat::ulp(self : BinFloat) -> BinFloat {
  match self.class {
    FpClass::Finite =>
      if self.significand.is_zero() {
        BinFloat::make(bigint_one(), -(self.precision_ - 1), self.precision_)
      } else {
        let mag_bits = abs_bigint(self.significand).bit_length()
        BinFloat::make(
          bigint_one(),
          self.exponent2 + mag_bits - self.precision_,
          self.precision_,
        )
      }
    _ => BinFloat::nan(precision=self.precision_)
  }
}

///|
pub fn BinFloat::add(self : BinFloat, other : BinFloat) -> BinFloat {
  add_bin_impl(self, other)
}

///|
pub fn BinFloat::sub(self : BinFloat, other : BinFloat) -> BinFloat {
  add_bin_impl(self, other.neg())
}

///|
pub fn BinFloat::mul(self : BinFloat, other : BinFloat) -> BinFloat {
  mul_bin_impl(self, other)
}

///|
pub fn BinFloat::div_checked(
  self : BinFloat,
  other : BinFloat,
) -> Result[BinFloat, @def.ArithmeticError] {
  guard !(other.classify() == FpClass::Finite && other.is_zero()) else {
    return Err(@def.ArithmeticError::division_by_zero("division by zero"))
  }
  Ok(div_bin_impl(self, other))
}

///|
pub fn BinFloat::div(self : BinFloat, other : BinFloat) -> BinFloat {
  div_bin_impl(self, other)
}

///|
pub fn BinFloat::sqrt(
  self : BinFloat,
) -> Result[BinFloat, @def.ArithmeticError] {
  sqrt_for_precision(self, self.precision_)
}

///|
pub fn BinFloat::pow_int(
  self : BinFloat,
  exponent : Int,
) -> Result[BinFloat, @def.ArithmeticError] {
  if exponent == 0 {
    return Ok(BinFloat::one(precision=self.precision_))
  }
  if exponent < 0 {
    guard !self.is_zero() else {
      return Err(
        @def.ArithmeticError::division_by_zero(
          "negative exponent requires a non-zero base",
        ),
      )
    }
    let positive = pow_nat(self, -exponent, self.precision_)
    return BinFloat::one(precision=self.precision_).div_checked(positive)
  }
  Ok(pow_nat(self, exponent, self.precision_))
}

///|
pub impl @arithmetic.SqrtChecked for BinFloat with fn sqrt_checked(self, ctx) {
  match self.with_precision(ctx.precision, ctx.rounding).sqrt() {
    Ok(value) => Ok(value.with_precision(ctx.precision, ctx.rounding))
    Err(err) => Err(err)
  }
}

///|
pub impl @arithmetic.DivChecked for BinFloat with fn div_checked(
  self,
  other,
  ctx,
) {
  let lhs = self.with_precision(ctx.precision, ctx.rounding)
  let rhs = other.with_precision(ctx.precision, ctx.rounding)
  match lhs.div_checked(rhs) {
    Ok(value) => Ok(value.with_precision(ctx.precision, ctx.rounding))
    Err(err) => Err(err)
  }
}

///|
pub impl @arithmetic.CompareChecked for BinFloat with fn compare_checked(
  self,
  other,
) {
  self.compare_checked(other)
}

///|
pub impl @arithmetic.PowNatChecked for BinFloat with fn pow_nat_checked(
  self,
  exponent,
  ctx,
) {
  let base = self.with_precision(ctx.precision, ctx.rounding)
  Ok(
    pow_nat(base, exponent.reinterpret_as_int(), ctx.precision).with_precision(
      ctx.precision,
      ctx.rounding,
    ),
  )
}

///|
pub impl @arithmetic.PowIntChecked for BinFloat with fn pow_int_checked(
  self,
  exponent,
  ctx,
) {
  match self.with_precision(ctx.precision, ctx.rounding).pow_int(exponent) {
    Ok(value) => Ok(value.with_precision(ctx.precision, ctx.rounding))
    Err(err) => Err(err)
  }
}

///|
pub impl Add for BinFloat with fn add(self, other) {
  add_bin_impl(self, other)
}

///|
pub impl Sub for BinFloat with fn sub(self, other) {
  self.sub(other)
}

///|
pub impl Mul for BinFloat with fn mul(self, other) {
  mul_bin_impl(self, other)
}

///|
pub impl Div for BinFloat with fn div(self, other) {
  div_bin_impl(self, other)
}

///|
pub impl Neg for BinFloat with fn neg(self) {
  self.neg()
}

///|
pub impl Compare for BinFloat with fn compare(self, other) {
  self.compare(other)
}

///|
pub impl @def.Floating for BinFloat with fn classify(self) {
  self.classify()
}

///|
pub impl @def.Floating for BinFloat with fn sign(self) {
  self.sign()
}

///|
pub impl @def.Floating for BinFloat with fn precision(self) {
  self.precision()
}

///|
pub impl @def.Floating for BinFloat with fn with_precision(
  self,
  precision,
  mode,
) {
  self.with_precision(precision, mode)
}

///|
pub impl @def.Floating for BinFloat with fn normalized(self) {
  self.normalized()
}

///|
pub impl Show for BinFloat with fn to_string(self) {
  match self.class {
    FpClass::NaN => "nan"
    FpClass::Infinity =>
      if self.sign() == Sign::Negative {
        "-inf"
      } else {
        "inf"
      }
    FpClass::Finite =>
      if self.significand.is_zero() {
        "0"
      } else {
        self.significand.to_string() + "p" + self.exponent2.to_string()
      }
  }
}
