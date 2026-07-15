///|
pub struct BinFloat {
  priv class : FpClass
  priv negative : Bool
  priv coefficient_ : BinCoeff
  priv exponent2 : Int
  priv precision_ : Int
  priv signaling_nan : Bool
  priv nan_payload : BinCoeff
} derive(Eq, Debug)

///|
fn bin_coeff_round_shift_for_make(
  magnitude : BinCoeff,
  shift : Int,
  negative : Bool,
  mode : RoundingMode,
) -> BinCoeff {
  if shift <= 0 || magnitude.is_zero() {
    return magnitude
  }
  let quotient = magnitude.shift_right(shift)
  let trailing_zeros = magnitude.ctz()
  if trailing_zeros >= shift {
    return quotient
  }
  let round_bit = magnitude.test_bit(shift - 1)
  let sticky = trailing_zeros < shift - 1
  let increment = match mode {
    RoundingMode::TowardZero => false
    RoundingMode::TowardPositive => !negative
    RoundingMode::TowardNegative => negative
    RoundingMode::AwayFromZero => true
    RoundingMode::ToNearestEven => round_bit && (sticky || quotient.test_bit(0))
  }
  if increment {
    quotient.add(BinCoeff::one())
  } else {
    quotient
  }
}

///|
fn normalize_finite(
  coefficient : BinCoeff,
  exponent2 : Int,
  precision : Int,
  negative : Bool,
  mode : RoundingMode,
) -> BinFloat {
  let precision = Int::max(1, precision)
  if coefficient.is_zero() {
    return {
      class: FpClass::Finite,
      negative,
      coefficient_: coefficient,
      exponent2: 0,
      precision_: precision,
      signaling_nan: false,
      nan_payload: BinCoeff::zero(),
    }
  }
  let initial_shift = coefficient.ctz()
  let coefficient0 = coefficient.shift_right(initial_shift)
  let exponent0 = binary_add_sat(exponent2, initial_shift)
  let bits = coefficient0.bit_length()
  let (coefficient1, exponent1) = if bits > precision {
    let shift = bits - precision
    (
      bin_coeff_round_shift_for_make(coefficient0, shift, negative, mode),
      binary_add_sat(exponent0, shift),
    )
  } else {
    (coefficient0, exponent0)
  }
  let final_shift = coefficient1.ctz()
  {
    class: FpClass::Finite,
    negative,
    coefficient_: coefficient1.shift_right(final_shift),
    exponent2: binary_add_sat(exponent1, final_shift),
    precision_: precision,
    signaling_nan: false,
    nan_payload: BinCoeff::zero(),
  }
}

///|
fn finite_from_parts(
  negative : Bool,
  magnitude : BinCoeff,
  exponent2 : Int,
  precision : Int,
) -> BinFloat {
  let value = normalize_finite(
    magnitude,
    exponent2,
    precision,
    negative,
    RoundingMode::ToNearestEven,
  )
  if magnitude.is_zero() {
    { ..value, negative, }
  } else {
    value
  }
}

///|
fn max_precision(a : BinFloat, b : BinFloat) -> Int {
  Int::max(a.precision_, b.precision_)
}

///|
fn compare_finite(a : BinFloat, b : BinFloat) -> Int {
  if a.coefficient_.is_zero() && b.coefficient_.is_zero() {
    return 0
  }
  if a.negative != b.negative {
    return if a.negative { -1 } else { 1 }
  }
  let ea = a.exponent2
  let eb = b.exponent2
  let magnitude_comparison = if ea == eb {
    a.coefficient_.compare(b.coefficient_)
  } else {
    let target = Int::min(ea, eb)
    let left = a.coefficient_.shift_left(ea - target)
    let right = b.coefficient_.shift_left(eb - target)
    left.compare(right)
  }
  if a.negative {
    -magnitude_comparison
  } else {
    magnitude_comparison
  }
}

///|
fn add_bin_impl(a : BinFloat, b : BinFloat) -> BinFloat {
  a.add_ctx(b, BinaryContext::unbounded(max_precision(a, b))).0
}

///|
fn mul_bin_impl(a : BinFloat, b : BinFloat) -> BinFloat {
  a.mul_ctx(b, BinaryContext::unbounded(max_precision(a, b))).0
}

///|
fn div_bin_impl(a : BinFloat, b : BinFloat) -> BinFloat {
  a.div_ctx(b, BinaryContext::unbounded(max_precision(a, b))).0
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
    let z = if x.is_negative_zero() {
      BinFloat::negative_zero(precision~)
    } else {
      BinFloat::zero(precision~)
    }
    return Ok((z, z))
  }
  let lower = x.sqrt_ctx(
      BinaryContext::unbounded(
        precision,
        rounding=BinaryRoundingMode::RoundTowardNegative,
      ),
    ).0
  let upper = x.sqrt_ctx(
      BinaryContext::unbounded(
        precision,
        rounding=BinaryRoundingMode::RoundTowardPositive,
      ),
    ).0
  Ok((lower, upper))
}

///|
pub fn sqrt_for_precision(
  x : BinFloat,
  precision : Int,
) -> Result[BinFloat, @def.ArithmeticError] {
  guard !(x.is_negative() && !x.is_zero()) else {
    return Err(
      @def.ArithmeticError::domain_error("sqrt requires a non-negative value"),
    )
  }
  Ok(x.sqrt_ctx(BinaryContext::unbounded(precision)).0)
}

///|
pub fn BinFloat::make(
  coefficient : BinCoeff,
  exponent2 : Int,
  precision : Int,
  negative? : Bool = false,
  mode? : RoundingMode = RoundingMode::ToNearestEven,
) -> BinFloat {
  normalize_finite(coefficient, exponent2, precision, negative, mode)
}

///|
pub fn BinFloat::zero(precision? : Int = 53) -> BinFloat {
  BinFloat::make(BinCoeff::zero(), 0, precision)
}

///|
pub fn BinFloat::negative_zero(precision? : Int = 53) -> BinFloat {
  finite_from_parts(true, BinCoeff::zero(), 0, precision)
}

///|
pub fn BinFloat::one(precision? : Int = 53) -> BinFloat {
  BinFloat::make(BinCoeff::one(), 0, precision)
}

///|
pub fn BinFloat::inf(sign : Sign, precision? : Int = 53) -> BinFloat {
  let negative = sign == Sign::Negative
  {
    class: FpClass::Infinity,
    negative,
    coefficient_: BinCoeff::one(),
    exponent2: 0,
    precision_: Int::max(1, precision),
    signaling_nan: false,
    nan_payload: BinCoeff::zero(),
  }
}

///|
pub fn BinFloat::nan(precision? : Int = 53) -> BinFloat {
  BinFloat::quiet_nan(precision~)
}

///|
pub fn BinFloat::quiet_nan(
  payload? : BinCoeff = BinCoeff::zero(),
  negative? : Bool = false,
  precision? : Int = 53,
) -> BinFloat {
  {
    class: FpClass::NaN,
    negative,
    coefficient_: BinCoeff::zero(),
    exponent2: 0,
    precision_: Int::max(1, precision),
    signaling_nan: false,
    nan_payload: payload,
  }
}

///|
pub fn BinFloat::signaling_nan(
  payload? : BinCoeff = BinCoeff::one(),
  negative? : Bool = false,
  precision? : Int = 53,
) -> BinFloat {
  {
    class: FpClass::NaN,
    negative,
    coefficient_: BinCoeff::zero(),
    exponent2: 0,
    precision_: Int::max(1, precision),
    signaling_nan: true,
    nan_payload: if payload.is_zero() {
      BinCoeff::one()
    } else {
      payload
    },
  }
}

///|
pub fn BinFloat::from_int(n : Int, precision? : Int = 53) -> BinFloat {
  let negative = n < 0
  let magnitude = if negative {
    (-(n + 1)).to_uint64() + 1UL
  } else {
    n.to_uint64()
  }
  BinFloat::make(BinCoeff::from_uint64(magnitude), 0, precision, negative~)
}

///|
pub fn BinFloat::from_coefficient(
  coefficient : BinCoeff,
  precision? : Int = 53,
  negative? : Bool = false,
) -> BinFloat {
  BinFloat::make(coefficient, 0, precision, negative~)
}

///|
pub fn BinFloat::from_double(x : Double, precision? : Int = 53) -> BinFloat {
  let precision = Int::max(1, precision)
  let bits = x.reinterpret_as_uint64()
  let negative = bits >> 63 != 0UL
  let exponent_bits = ((bits >> 52) & 0x7ffUL).to_int()
  let fraction_bits = bits & 0x000f_ffff_ffff_ffffUL
  let quiet_bit = 1UL << 51
  if exponent_bits == 0x7ff {
    if fraction_bits == 0UL {
      return BinFloat::inf(
        if negative {
          Sign::Negative
        } else {
          Sign::Positive
        },
        precision~,
      )
    }
    return if (fraction_bits & quiet_bit) == 0UL {
      BinFloat::signaling_nan(
        payload=BinCoeff::from_uint64(fraction_bits),
        negative~,
        precision~,
      )
    } else {
      BinFloat::quiet_nan(
        payload=BinCoeff::from_uint64(fraction_bits & (quiet_bit - 1UL)),
        negative~,
        precision~,
      )
    }
  }
  if exponent_bits == 0 {
    if fraction_bits == 0UL {
      return if negative {
        BinFloat::negative_zero(precision~)
      } else {
        BinFloat::zero(precision~)
      }
    }
    return BinFloat::make(
      BinCoeff::from_uint64(fraction_bits),
      -1074,
      precision,
      negative~,
    )
  }
  BinFloat::make(
    BinCoeff::from_uint64((1UL << 52) | fraction_bits),
    exponent_bits - 1075,
    precision,
    negative~,
  )
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
    FpClass::Finite if self.coefficient_.is_zero() => Sign::Zero
    _ => if self.negative { Sign::Negative } else { Sign::Positive }
  }
}

///|
pub fn BinFloat::is_negative(self : BinFloat) -> Bool {
  self.negative
}

///|
pub fn BinFloat::is_negative_zero(self : BinFloat) -> Bool {
  self.is_zero() && self.negative
}

///|
pub fn BinFloat::is_quiet_nan(self : BinFloat) -> Bool {
  self.class == FpClass::NaN && !self.signaling_nan
}

///|
pub fn BinFloat::is_signaling_nan(self : BinFloat) -> Bool {
  self.class == FpClass::NaN && self.signaling_nan
}

///|
pub fn BinFloat::nan_payload(self : BinFloat) -> BinCoeff {
  if self.class == FpClass::NaN {
    self.nan_payload
  } else {
    BinCoeff::zero()
  }
}

///|
pub fn BinFloat::coefficient(self : BinFloat) -> BinCoeff {
  self.coefficient_
}

///|
pub fn BinFloat::exponent2(self : BinFloat) -> Int {
  self.exponent2
}

///|
pub fn BinFloat::normalized(self : BinFloat) -> BinFloat {
  match self.class {
    FpClass::Finite =>
      finite_from_parts(
        self.negative,
        self.coefficient_,
        self.exponent2,
        self.precision_,
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
      if self.is_zero() {
        finite_from_parts(self.negative, BinCoeff::zero(), 0, precision)
      } else {
        BinFloat::make(
          self.coefficient_,
          self.exponent2,
          precision,
          negative=self.negative,
          mode~,
        )
      }
    FpClass::Infinity => { ..self, precision_: Int::max(1, precision) }
    FpClass::NaN => { ..self, precision_: Int::max(1, precision) }
  }
}

///|
pub fn BinFloat::neg(self : BinFloat) -> BinFloat {
  { ..self, negative: !self.negative }
}

///|
pub fn BinFloat::abs(self : BinFloat) -> BinFloat {
  if self.negative {
    self.neg()
  } else {
    self
  }
}

///|
pub fn BinFloat::is_zero(self : BinFloat) -> Bool {
  self.class == FpClass::Finite && self.coefficient_.is_zero()
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
        if self.negative == other.negative {
          0
        } else if self.negative {
          -1
        } else {
          1
        }
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
      if self.negative == other.negative {
        0
      } else if self.negative {
        -1
      } else {
        1
      }
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
pub fn BinFloat::clamp_checked(
  self : BinFloat,
  min~ : BinFloat,
  max~ : BinFloat,
) -> Result[BinFloat, @def.ArithmeticError] {
  guard min.classify() != FpClass::NaN && max.classify() != FpClass::NaN else {
    return Err(
      @def.ArithmeticError::domain_error("clamp bounds must be ordered values"),
    )
  }
  guard min.compare(max) <= 0 else {
    return Err(@def.ArithmeticError::domain_error("min must not exceed max"))
  }
  Ok(self.clamp(min~, max~))
}

///|
pub fn BinFloat::ulp(self : BinFloat) -> BinFloat {
  match self.class {
    FpClass::Finite =>
      if self.coefficient_.is_zero() {
        BinFloat::make(BinCoeff::one(), -(self.precision_ - 1), self.precision_)
      } else {
        let mag_bits = self.coefficient_.bit_length()
        BinFloat::make(
          BinCoeff::one(),
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
  guard !(exponent < 0 && self.is_zero()) else {
    return Err(
      @def.ArithmeticError::division_by_zero(
        "negative exponent requires a non-zero base",
      ),
    )
  }
  Ok(self.pow_int_ctx(exponent, BinaryContext::unbounded(self.precision_)).0)
}

///|
pub impl @lf_arith.SqrtChecked for BinFloat with fn sqrt_checked(self, ctx) {
  guard !(self.is_negative() && !self.is_zero()) else {
    return Err(
      @def.ArithmeticError::domain_error("sqrt requires a non-negative value"),
    )
  }
  Ok(self.sqrt_ctx(BinaryContext::from_arithmetic_context(ctx)).0)
}

///|
pub impl @lf_arith.DivChecked for BinFloat with fn div_checked(self, other, ctx) {
  guard !(other.classify() == FpClass::Finite && other.is_zero()) else {
    return Err(@def.ArithmeticError::division_by_zero("division by zero"))
  }
  Ok(self.div_ctx(other, BinaryContext::from_arithmetic_context(ctx)).0)
}

///|
pub impl @lf_arith.CompareChecked for BinFloat with fn compare_checked(
  self,
  other,
) {
  self.compare_checked(other)
}

///|
pub impl @lf_arith.PowNatChecked for BinFloat with fn pow_nat_checked(
  self,
  exponent,
  ctx,
) {
  Ok(self.pow_nat_ctx(exponent, BinaryContext::from_arithmetic_context(ctx)).0)
}

///|
pub impl @lf_arith.PowIntChecked for BinFloat with fn pow_int_checked(
  self,
  exponent,
  ctx,
) {
  guard !(exponent < 0 && self.is_zero()) else {
    return Err(
      @def.ArithmeticError::division_by_zero(
        "negative exponent requires a non-zero base",
      ),
    )
  }
  Ok(self.pow_int_ctx(exponent, BinaryContext::from_arithmetic_context(ctx)).0)
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
      if self.coefficient_.is_zero() {
        if self.negative {
          "-0"
        } else {
          "0"
        }
      } else {
        (if self.negative { "-" } else { "" }) +
        self.coefficient_.to_string() +
        "p" +
        self.exponent2.to_string()
      }
  }
}
