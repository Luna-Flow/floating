///|
#derive(Eq, Debug)
pub struct BinFloat {
  priv class : FpClass
  priv negative : Bool
  priv coefficient_ : Coeff
  priv exponent2 : Int32
  priv precision_ : Int32
  priv signaling_nan : Bool
  priv nan_payload : Coeff
}

///|
fn finite_zero(negative : Bool, precision : Int32) -> BinFloat {
  {
    class: FpClass::Finite,
    negative,
    coefficient_: Coeff::zero(),
    exponent2: 0,
    precision_: Int32::max(1, precision),
    signaling_nan: false,
    nan_payload: Coeff::zero(),
  }
}

///|
fn finite_normalized(
  negative : Bool,
  coefficient : Coeff,
  exponent2 : Int32,
  precision : Int32,
) -> BinFloat {
  {
    class: FpClass::Finite,
    negative,
    coefficient_: coefficient,
    exponent2,
    precision_: Int32::max(1, precision),
    signaling_nan: false,
    nan_payload: Coeff::zero(),
  }
}

///|
fn bin_coeff_round_shift_for_make(
  magnitude : Coeff,
  shift : Int32,
  negative : Bool,
  mode : RoundingMode,
) -> Coeff {
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
    quotient.add(Coeff::one())
  } else {
    quotient
  }
}

///|
fn normalize_finite_odd(
  coefficient : Coeff,
  exponent2 : Int32,
  precision : Int32,
  negative : Bool,
  mode : RoundingMode,
  bits : Int32,
) -> BinFloat {
  // Underflow is decided on the exact value so that precision rounding cannot
  // move a magnitude onto the halfway point of the smallest subnormal.
  let exact_top = exponent2.to_int64() + (bits - 1).to_int64()
  let tiny_top = binary_implementation_e_min.to_int64() -
    (precision - 1).to_int64()
  if exact_top < tiny_top {
    return implementation_underflow(
      negative,
      precision,
      mode,
      exact_top == tiny_top - 1L && bits > 1,
    )
  }
  let (coefficient1, exponent1) = if bits > precision {
    let shift = bits - precision
    (
      bin_coeff_round_shift_for_make(coefficient, shift, negative, mode),
      binary_add_sat(exponent2, shift),
    )
  } else {
    (coefficient, exponent2)
  }
  let final_shift = if coefficient1.is_odd() { 0 } else { coefficient1.ctz() }
  let coefficient2 = if final_shift == 0 {
    coefficient1
  } else {
    coefficient1.shift_right(final_shift)
  }
  let exponent3 = binary_add_sat(exponent1, final_shift)
  // A saturated exponent can only come from a value outside the implementation
  // range, so it is classified here instead of being stored as a wrong finite.
  // Overflow is decided after rounding, as in IEEE 754.
  let top = exponent3.to_int64() + (coefficient2.bit_length() - 1).to_int64()
  if top > binary_implementation_e_max.to_int64() {
    return implementation_overflow(negative, precision, mode)
  }
  finite_normalized(negative, coefficient2, exponent3, precision)
}

///|
fn implementation_overflow(
  negative : Bool,
  precision : Int32,
  mode : RoundingMode,
) -> BinFloat {
  let to_infinity = match mode {
    RoundingMode::ToNearestEven | RoundingMode::AwayFromZero => true
    RoundingMode::TowardZero => false
    RoundingMode::TowardPositive => !negative
    RoundingMode::TowardNegative => negative
  }
  if to_infinity {
    BinFloat::inf(
      if negative {
        Sign::Negative
      } else {
        Sign::Positive
      },
      precision~,
    )
  } else {
    finite_normalized(
      negative,
      Coeff::one().shift_left(precision).sub_checked(Coeff::one()).unwrap(),
      binary_implementation_e_max - (precision - 1),
      precision,
    )
  }
}

///|
/// `above_half` is true when the magnitude lies strictly between half of the
/// smallest subnormal and the smallest subnormal.
fn implementation_underflow(
  negative : Bool,
  precision : Int32,
  mode : RoundingMode,
  above_half : Bool,
) -> BinFloat {
  let to_smallest = match mode {
    RoundingMode::ToNearestEven => above_half
    RoundingMode::AwayFromZero => true
    RoundingMode::TowardZero => false
    RoundingMode::TowardPositive => !negative
    RoundingMode::TowardNegative => negative
  }
  if to_smallest {
    finite_normalized(
      negative,
      Coeff::one(),
      binary_implementation_e_min - (precision - 1),
      precision,
    )
  } else {
    finite_zero(negative, precision)
  }
}

///|
fn normalize_finite(
  coefficient : Coeff,
  exponent2 : Int32,
  precision : Int32,
  negative : Bool,
  mode : RoundingMode,
) -> BinFloat {
  let precision = Int32::max(1, precision)
  if coefficient.is_zero() {
    return finite_zero(negative, precision)
  }
  let initial_shift = if coefficient.is_odd() { 0 } else { coefficient.ctz() }
  let coefficient0 = if initial_shift == 0 {
    coefficient
  } else {
    coefficient.shift_right(initial_shift)
  }
  let exponent0 = binary_add_sat(exponent2, initial_shift)
  normalize_finite_odd(
    coefficient0,
    exponent0,
    precision,
    negative,
    mode,
    coefficient0.bit_length(),
  )
}

///|
fn finite_from_parts(
  negative : Bool,
  magnitude : Coeff,
  exponent2 : Int32,
  precision : Int32,
) -> BinFloat {
  if magnitude.is_zero() {
    return finite_zero(negative, precision)
  }
  let value = normalize_finite(
    magnitude,
    exponent2,
    precision,
    negative,
    RoundingMode::ToNearestEven,
  )
  value
}

///|
fn finite_from_uint64(
  negative : Bool,
  magnitude : UInt64,
  precision : Int32,
) -> BinFloat {
  let precision = Int32::max(1, precision)
  let coefficient = Coeff::from_uint64(magnitude)
  if coefficient.is_zero() {
    return finite_zero(negative, precision)
  }
  let normalization_shift = if coefficient.is_odd() {
    0
  } else {
    coefficient.ctz()
  }
  let coefficient0 = if normalization_shift == 0 {
    coefficient
  } else {
    coefficient.shift_right(normalization_shift)
  }
  let exponent0 = normalization_shift
  let bits = coefficient0.bit_length()
  if bits <= precision {
    return finite_normalized(negative, coefficient0, exponent0, precision)
  }
  normalize_finite_odd(
    coefficient0,
    exponent0,
    precision,
    negative,
    RoundingMode::ToNearestEven,
    bits,
  )
}

///|
fn max_precision(a : BinFloat, b : BinFloat) -> Int32 {
  Int32::max(a.precision_, b.precision_)
}

///|
fn compare_finite(a : BinFloat, b : BinFloat) -> Int32 {
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
    binary_compare_shifted(a.coefficient_, ea, b.coefficient_, eb)
  }
  if a.negative {
    -magnitude_comparison
  } else {
    magnitude_comparison
  }
}

///|
fn add_bin_impl(a : BinFloat, b : BinFloat) -> BinFloat {
  match binary_fast_add(a, b) {
    Some(result) => result
    None =>
      match binary_pair_add(a, b) {
        Some(result) => result
        None =>
          match binary_coeff_fast_add(a, b) {
            Some(result) => result
            None =>
              a.add_ctx(b, BinaryContext::unbounded(max_precision(a, b))).0
          }
      }
  }
}

///|
fn mul_bin_impl(a : BinFloat, b : BinFloat) -> BinFloat {
  match binary_fast_mul(a, b) {
    Some(result) => result
    None =>
      match binary_pair_mul(a, b) {
        Some(result) => result
        None =>
          match binary_coeff_fast_mul(a, b) {
            Some(result) => result
            None =>
              a.mul_ctx(b, BinaryContext::unbounded(max_precision(a, b))).0
          }
      }
  }
}

///|
fn div_bin_impl(a : BinFloat, b : BinFloat) -> BinFloat {
  match binary_fast_div(a, b) {
    Some(result) => result
    None =>
      match binary_coeff_fast_div(a, b) {
        Some(result) => result
        None => a.div_ctx(b, BinaryContext::unbounded(max_precision(a, b))).0
      }
  }
}

///|
fn sqrt_for_precision(
  x : BinFloat,
  precision : Int32,
) -> Result[BinFloat, @def.ArithmeticError] {
  binary_checked_result(
    x.sqrt_ctx(BinaryContext::unbounded(precision)),
    "sqrt requires a non-negative value",
  )
}

///|
/// Maps a contextual result to the checked tier: the invalid operation
/// exception (IEEE 754-2019 section 7.2) becomes `DomainError`, the
/// divideByZero exception (section 7.3) becomes `DivisionByZero`, and every
/// other result, NaN and range exceptions included, is returned in `Ok` (#262).
fn binary_checked_result(
  result : (BinFloat, BinaryFlags),
  invalid_message : String,
  division_by_zero_message~ : String = "division by zero",
) -> Result[BinFloat, @def.ArithmeticError] {
  let (value, flags) = result
  if flags.division_by_zero() {
    Err(@def.ArithmeticError::division_by_zero(division_by_zero_message))
  } else if flags.invalid_operation() {
    Err(@def.ArithmeticError::domain_error(invalid_message))
  } else {
    Ok(value)
  }
}

///|
pub fn BinFloat::make(
  coefficient : BinCoeff,
  exponent2 : Int32,
  precision : Int32,
  negative~ : Bool = false,
  mode~ : RoundingMode = RoundingMode::ToNearestEven,
) -> BinFloat {
  BinFloat::make_coeff(coefficient.0, exponent2, precision, negative~, mode~)
}

///|
fn BinFloat::make_coeff(
  coefficient : Coeff,
  exponent2 : Int32,
  precision : Int32,
  negative~ : Bool = false,
  mode~ : RoundingMode = RoundingMode::ToNearestEven,
) -> BinFloat {
  normalize_finite(coefficient, exponent2, precision, negative, mode)
}

///|
pub fn BinFloat::zero(precision~ : Int32 = 53) -> BinFloat {
  finite_zero(false, precision)
}

///|
pub fn BinFloat::negative_zero(precision~ : Int32 = 53) -> BinFloat {
  finite_zero(true, precision)
}

///|
pub fn BinFloat::one(precision~ : Int32 = 53) -> BinFloat {
  finite_normalized(false, Coeff::one(), 0, precision)
}

///|
pub fn BinFloat::inf(sign : Sign, precision~ : Int32 = 53) -> BinFloat {
  let negative = sign == Sign::Negative
  {
    class: FpClass::Infinity,
    negative,
    coefficient_: Coeff::one(),
    exponent2: 0,
    precision_: Int32::max(1, precision),
    signaling_nan: false,
    nan_payload: Coeff::zero(),
  }
}

///|
pub fn BinFloat::nan(precision~ : Int32 = 53) -> BinFloat {
  BinFloat::quiet_nan(precision~)
}

///|
pub fn BinFloat::quiet_nan(
  payload? : BinCoeff,
  negative~ : Bool = false,
  precision~ : Int32 = 53,
) -> BinFloat {
  let payload : Coeff = match payload {
    Some(value) => value.0
    None => Coeff::zero()
  }
  {
    class: FpClass::NaN,
    negative,
    coefficient_: Coeff::zero(),
    exponent2: 0,
    precision_: Int32::max(1, precision),
    signaling_nan: false,
    nan_payload: payload,
  }
}

///|
pub fn BinFloat::signaling_nan(
  payload? : BinCoeff,
  negative~ : Bool = false,
  precision~ : Int32 = 53,
) -> BinFloat {
  let payload : Coeff = match payload {
    Some(value) => value.0
    None => Coeff::one()
  }
  {
    class: FpClass::NaN,
    negative,
    coefficient_: Coeff::zero(),
    exponent2: 0,
    precision_: Int32::max(1, precision),
    signaling_nan: true,
    nan_payload: if payload.is_zero() {
      Coeff::one()
    } else {
      payload
    },
  }
}

///|
pub fn BinFloat::from_int(n : Int32, precision~ : Int32 = 53) -> BinFloat {
  let negative = n < 0
  let magnitude = if negative {
    (-(n + 1)).to_uint64() + 1UL
  } else {
    n.to_uint64()
  }
  finite_from_uint64(negative, magnitude, precision)
}

///|
pub fn BinFloat::from_coefficient(
  coefficient : BinCoeff,
  precision~ : Int32 = 53,
  negative~ : Bool = false,
) -> BinFloat {
  BinFloat::make_coeff(coefficient.0, 0, precision, negative~)
}

///|
pub fn BinFloat::from_double(x : Double, precision~ : Int32 = 53) -> BinFloat {
  let precision = Int32::max(1, precision)
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
        payload=Coeff::from_uint64(fraction_bits),
        negative~,
        precision~,
      )
    } else {
      BinFloat::quiet_nan(
        payload=Coeff::from_uint64(fraction_bits & (quiet_bit - 1UL)),
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
    return BinFloat::make_coeff(
      Coeff::from_uint64(fraction_bits),
      -1074,
      precision,
      negative~,
    )
  }
  BinFloat::make_coeff(
    Coeff::from_uint64((1UL << 52) | fraction_bits),
    exponent_bits - 1075,
    precision,
    negative~,
  )
}

///|
pub fn BinFloat::from_float(x : Float, precision~ : Int32 = 24) -> BinFloat {
  BinFloat::from_double(x.to_double(), precision~)
}

///|
pub fn BinFloat::classify(self : BinFloat) -> FpClass {
  self.class
}

///|
pub fn BinFloat::is_finite(self : BinFloat) -> Bool {
  self.class == FpClass::Finite
}

///|
pub fn BinFloat::is_infinite(self : BinFloat) -> Bool {
  self.class == FpClass::Infinity
}

///|
pub fn BinFloat::is_nan(self : BinFloat) -> Bool {
  self.class == FpClass::NaN
}

///|
/// True for a nonzero finite value whose leading-bit exponent is below the
/// context's smallest normal exponent (IEEE 754-2019 clause 5.7.2).
pub fn BinFloat::is_subnormal(self : BinFloat, context : BinaryContext) -> Bool {
  self.class == FpClass::Finite &&
  !self.coefficient_.is_zero() &&
  binary_exact_top(self.coefficient_, self.exponent2) < context.range_e_min()
}

///|
/// True for a nonzero finite value that is not subnormal in `context`.
pub fn BinFloat::is_normal(self : BinFloat, context : BinaryContext) -> Bool {
  self.class == FpClass::Finite &&
  !self.coefficient_.is_zero() &&
  binary_exact_top(self.coefficient_, self.exponent2) >= context.range_e_min()
}

///|
/// The ten-valued class of IEEE 754-2019 clause 5.7.2.
pub fn BinFloat::class_of(
  self : BinFloat,
  context : BinaryContext,
) -> IeeeClass {
  match self.class {
    FpClass::NaN => if self.signaling_nan { SignalingNaN } else { QuietNaN }
    FpClass::Infinity =>
      if self.negative {
        NegativeInfinity
      } else {
        PositiveInfinity
      }
    FpClass::Finite =>
      if self.coefficient_.is_zero() {
        if self.negative {
          NegativeZero
        } else {
          PositiveZero
        }
      } else if self.is_subnormal(context) {
        if self.negative {
          NegativeSubnormal
        } else {
          PositiveSubnormal
        }
      } else if self.negative {
        NegativeNormal
      } else {
        PositiveNormal
      }
  }
}

///|
pub fn BinFloat::precision(self : BinFloat) -> Int32 {
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
  BinCoeff(self.nan_payload_coeff())
}

///|
fn BinFloat::nan_payload_coeff(self : BinFloat) -> Coeff {
  if self.class == FpClass::NaN {
    self.nan_payload
  } else {
    Coeff::zero()
  }
}

///|
pub fn BinFloat::coefficient(self : BinFloat) -> BinCoeff {
  BinCoeff(self.coefficient_)
}

///|
pub fn BinFloat::exponent2(self : BinFloat) -> Int32 {
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
  precision : Int32,
  mode : RoundingMode,
) -> BinFloat {
  match self.class {
    FpClass::Finite =>
      if self.is_zero() {
        finite_from_parts(self.negative, Coeff::zero(), 0, precision)
      } else {
        BinFloat::make_coeff(
          self.coefficient_,
          self.exponent2,
          precision,
          negative=self.negative,
          mode~,
        )
      }
    FpClass::Infinity => { ..self, precision_: Int32::max(1, precision), }
    FpClass::NaN => { ..self, precision_: Int32::max(1, precision), }
  }
}

///|
pub fn BinFloat::neg(self : BinFloat) -> BinFloat {
  { ..self, negative: !self.negative, }
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
) -> Result[Int32, @def.ArithmeticError] {
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
/// Numeric three-way comparison with `-0 == +0`. NaN has no numeric order;
/// so that `Compare` stays a total preorder (and sorting never aborts), every
/// NaN compares equal to every other NaN and greater than every non-NaN.
/// Use the quiet/signaling predicates or `compare_checked` for IEEE semantics.
pub fn BinFloat::compare(self : BinFloat, other : BinFloat) -> Int32 {
  match (self.class == FpClass::NaN, other.class == FpClass::NaN) {
    (true, true) => return 0
    (true, false) => return 1
    (false, true) => return -1
    (false, false) => ()
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
        BinFloat::make_coeff(
          Coeff::one(),
          -(self.precision_ - 1),
          self.precision_,
        )
      } else {
        let mag_bits = self.coefficient_.bit_length()
        BinFloat::make_coeff(
          Coeff::one(),
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
  binary_checked_result(
    self.div_ctx(other, BinaryContext::unbounded(max_precision(self, other))),
    "invalid division",
  )
}

///|
pub fn BinFloat::div(self : BinFloat, other : BinFloat) -> BinFloat {
  div_bin_impl(self, other)
}

///|
pub fn BinFloat::sqrt(
  self : BinFloat,
) -> Result[BinFloat, @def.ArithmeticError] {
  match binary_fast_sqrt(self) {
    Some(result) => Ok(result)
    None =>
      match binary_coeff_fast_sqrt(self) {
        Some(result) => Ok(result)
        None => sqrt_for_precision(self, self.precision_)
      }
  }
}

///|
pub fn BinFloat::pow_int(
  self : BinFloat,
  exponent : Int32,
) -> Result[BinFloat, @def.ArithmeticError] {
  binary_checked_result(
    self.pow_int_ctx(exponent, BinaryContext::unbounded(self.precision_)),
    "invalid power",
    division_by_zero_message="negative exponent requires a non-zero base",
  )
}

///|
pub impl @lf_arith.SqrtChecked for BinFloat with fn sqrt_checked(self, ctx) {
  binary_checked_result(
    self.sqrt_ctx(BinaryContext::from_arithmetic_context(ctx)),
    "sqrt requires a non-negative value",
  )
}

///|
pub impl @lf_arith.DivChecked for BinFloat with fn div_checked(self, other, ctx) {
  binary_checked_result(
    self.div_ctx(other, BinaryContext::from_arithmetic_context(ctx)),
    "invalid division",
  )
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
  binary_checked_result(
    self.pow_nat_ctx(exponent, BinaryContext::from_arithmetic_context(ctx)),
    "invalid power",
    division_by_zero_message="negative exponent requires a non-zero base",
  )
}

///|
pub impl @lf_arith.PowIntChecked for BinFloat with fn pow_int_checked(
  self,
  exponent,
  ctx,
) {
  binary_checked_result(
    self.pow_int_ctx(exponent, BinaryContext::from_arithmetic_context(ctx)),
    "invalid power",
    division_by_zero_message="negative exponent requires a non-zero base",
  )
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

///|
pub extend BinFloat with Show::{to_string}

///|
pub extend BinFloat with Eq::{not_equal, equal}

///|
pub extend BinFloat with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BinFloat with @Luna-Flow/arithmetic.SqrtChecked::{sqrt_checked}

///|
pub extend BinFloat with @Luna-Flow/arithmetic.PowNatChecked::{pow_nat_checked}

///|
pub extend BinFloat with @Luna-Flow/arithmetic.PowIntChecked::{pow_int_checked}

///|
pub extend BinFloat with Compare::{op_lt, op_le, op_ge, op_gt}

///|
pub extend BinFloat with Show::{output}
