///|
/// A binary floating-point datum. The representation (`@bin_kernel.BinRepr`) is
/// internal and read only through the accessors of `bin_repr_nonjs.mbt` and
/// `bin_repr_js.mbt`; the newtype costs nothing: a value is one heap object.
#derive(Eq, Debug)
pub struct BinFloat(@bin_kernel.BinRepr)

///|
fn finite_zero(negative : Bool, precision : Int32) -> BinFloat {
  bin_repr_zero(negative, Int32::max(1, precision))
}

///|
fn finite_normalized(
  negative : Bool,
  coefficient : Coeff,
  exponent2 : Int32,
  precision : Int32,
) -> BinFloat {
  bin_repr_finite(negative, coefficient, exponent2, Int32::max(1, precision))
}

///|
fn bin_coeff_round_shift_for_make(
  magnitude : Coeff,
  shift : Int32,
  negative : Bool,
  mode : BinaryRoundingMode,
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
    BinaryRoundingMode::RoundTowardZero => false
    BinaryRoundingMode::RoundTowardPositive => !negative
    BinaryRoundingMode::RoundTowardNegative => negative
    BinaryRoundingMode::RoundTiesToAway => round_bit
    BinaryRoundingMode::RoundTiesToEven =>
      round_bit && (sticky || quotient.test_bit(0))
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
  mode : BinaryRoundingMode,
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
      exact_top == tiny_top - 1L && bits == 1,
    )
  }
  // The kept bits are bounded by the precision and by the range together: at
  // or above 2^e_min the grid has `precision` bits, below it the grid is the
  // fixed smallest quantum 2^tiny_top, so a leading bit at `exact_top` leaves
  // only `exact_top - tiny_top + 1` bits (at least 1 here).
  let kept = Int64::min(precision.to_int64(), exact_top - tiny_top + 1L).to_int()
  let (coefficient1, exponent1) = if bits > kept {
    let shift = bits - kept
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
  mode : BinaryRoundingMode,
) -> BinFloat {
  let to_infinity = match mode {
    BinaryRoundingMode::RoundTiesToEven | BinaryRoundingMode::RoundTiesToAway =>
      true
    BinaryRoundingMode::RoundTowardZero => false
    BinaryRoundingMode::RoundTowardPositive => !negative
    BinaryRoundingMode::RoundTowardNegative => negative
  }
  if to_infinity {
    BinFloat::inf_raw(
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
/// smallest subnormal and the smallest subnormal, `at_half` when it is exactly
/// half of it.
fn implementation_underflow(
  negative : Bool,
  precision : Int32,
  mode : BinaryRoundingMode,
  above_half : Bool,
  at_half : Bool,
) -> BinFloat {
  let to_smallest = match mode {
    BinaryRoundingMode::RoundTiesToEven => above_half
    BinaryRoundingMode::RoundTiesToAway => above_half || at_half
    BinaryRoundingMode::RoundTowardZero => false
    BinaryRoundingMode::RoundTowardPositive => !negative
    BinaryRoundingMode::RoundTowardNegative => negative
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
  mode : BinaryRoundingMode,
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
    BinaryRoundingMode::RoundTiesToEven,
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
    BinaryRoundingMode::RoundTiesToEven,
    bits,
  )
}

///|
fn max_precision(a : BinFloat, b : BinFloat) -> Int32 {
  Int32::max(a.precision_(), b.precision_())
}

///|
fn compare_finite(a : BinFloat, b : BinFloat) -> Int32 {
  if a.coefficient_is_zero() && b.coefficient_is_zero() {
    return 0
  }
  if a.negative() != b.negative() {
    return if a.negative() { -1 } else { 1 }
  }
  let ea = a.exponent2_()
  let eb = b.exponent2_()
  let magnitude_comparison = if ea == eb {
    a.coefficient_().compare(b.coefficient_())
  } else {
    binary_compare_shifted(a.coefficient_(), ea, b.coefficient_(), eb)
  }
  if a.negative() {
    -magnitude_comparison
  } else {
    magnitude_comparison
  }
}

///|
fn add_bin_impl(a : BinFloat, b : BinFloat) -> BinFloat {
  add_signed_impl(a, b, false)
}

///|
/// Largest precision of the one-word fast paths (`binary_fast_*`); the two-word
/// paths go to `binary_pair_precision_limit`. The precision is read once here, so
/// a wide operation does not read it again in the entry of every path it skips.
let binary_word_precision_limit : Int32 = 62

///|
/// `a + b`, or `a - b` when `flip`: the fast paths read the sign of `b`
/// flipped, so a subtraction does not allocate the negated `b`.
fn add_signed_impl(a : BinFloat, b : BinFloat, flip : Bool) -> BinFloat {
  let precision = max_precision(a, b)
  if precision <= binary_word_precision_limit {
    match binary_fast_add_signed(a, b, flip) {
      Some(result) => return result
      None => ()
    }
  }
  if precision <= binary_pair_precision_limit {
    match binary_pair_add_signed(a, b, flip) {
      Some(result) => return result
      None => ()
    }
  }
  match binary_coeff_fast_add_signed(a, b, flip) {
    Some(result) => result
    None => {
      let addend = if flip { b.neg() } else { b }
      a.add_ctx(addend, binary_working_context(precision)).0
    }
  }
}

///|
fn mul_bin_impl(a : BinFloat, b : BinFloat) -> BinFloat {
  let precision = max_precision(a, b)
  if precision <= binary_word_precision_limit {
    match binary_fast_mul(a, b) {
      Some(result) => return result
      None => ()
    }
  }
  if precision <= binary_pair_precision_limit {
    match binary_pair_mul(a, b) {
      Some(result) => return result
      None => ()
    }
  }
  match binary_coeff_fast_mul(a, b) {
    Some(result) => result
    None => a.mul_ctx(b, binary_working_context(precision)).0
  }
}

///|
fn div_bin_impl(a : BinFloat, b : BinFloat) -> BinFloat {
  let precision = max_precision(a, b)
  if precision <= binary_word_precision_limit {
    match binary_fast_div(a, b) {
      Some(result) => return result
      None => ()
    }
  }
  if precision <= binary_pair_precision_limit {
    match binary_pair_div(a, b) {
      Some(result) => return result
      None => ()
    }
  }
  match binary_coeff_fast_div(a, b) {
    Some(result) => result
    None => a.div_ctx(b, binary_working_context(precision)).0
  }
}

///|
fn sqrt_for_precision(
  x : BinFloat,
  precision : Int32,
) -> Result[BinFloat, @def.ArithmeticError] {
  binary_checked_result(
    x.sqrt_ctx(binary_working_context(precision)),
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
fn binary_precision_error(
  operation : String,
  precision : Int32,
) -> @def.ArithmeticError {
  @def.ArithmeticError::domain_error(
    "\{operation}: precision must be within 1..=\{binary_precision_max} (got \{precision})",
  )
}

///|
/// Aborts unless `1 <= precision <= binary_precision_max`: the precision of a
/// value is checked where the value is made, so that no later operation can
/// abort because of it.
fn binary_check_precision(operation : String, precision : Int32) -> Unit {
  if precision < 1 || precision > binary_precision_max {
    abort(
      "\{operation}: precision must be within 1..=\{binary_precision_max} (got \{precision})",
    )
  }
}

///|
/// The number of payload bits of a NaN of precision `precision` (IEEE 754-2019
/// 6.2.1: the trailing significand field has `precision - 1` bits and the
/// first of them is the quiet bit).
fn binary_nan_payload_bits(precision : Int32) -> Int32 {
  Int32::max(precision - 2, 0)
}

///|
fn binary_nan_raw(
  negative : Bool,
  signaling : Bool,
  payload : Coeff,
  precision : Int32,
) -> BinFloat {
  bin_repr_nan(negative, signaling, payload, precision)
}

///|
/// A NaN as a conversion delivers it (IEEE 754-2019 6.2.3): the payload is
/// kept in its low `precision - 2` bits, and a signaling NaN whose payload
/// does not survive (or whose format has no room for one) is quiet.
fn binary_convert_nan(
  negative : Bool,
  signaling : Bool,
  payload : Coeff,
  precision : Int32,
) -> BinFloat {
  let bits = binary_nan_payload_bits(precision)
  let kept = if payload.bit_length() <= bits {
    payload
  } else if bits == 0 {
    Coeff::zero()
  } else {
    payload.bit_and(
      Coeff::one().shift_left(bits).sub_checked(Coeff::one()).unwrap(),
    )
  }
  binary_nan_raw(negative, signaling && !kept.is_zero(), kept, precision)
}

///|
pub fn BinFloat::make(
  coefficient : BinCoeff,
  exponent2 : Int32,
  precision : Int32,
  negative~ : Bool = false,
  mode~ : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
) -> BinFloat {
  binary_check_precision("BinFloat::make", precision)
  BinFloat::make_coeff(coefficient.0, exponent2, precision, negative~, mode~)
}

///|
fn BinFloat::make_coeff(
  coefficient : Coeff,
  exponent2 : Int32,
  precision : Int32,
  negative~ : Bool = false,
  mode~ : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
) -> BinFloat {
  normalize_finite(coefficient, exponent2, precision, negative, mode)
}

///|
pub fn BinFloat::zero(precision~ : Int32 = 53) -> BinFloat {
  binary_check_precision("BinFloat::zero", precision)
  BinFloat::zero_raw(precision~)
}

///|
fn BinFloat::zero_raw(precision~ : Int32 = 53) -> BinFloat {
  finite_zero(false, precision)
}

///|
pub fn BinFloat::negative_zero(precision~ : Int32 = 53) -> BinFloat {
  binary_check_precision("BinFloat::negative_zero", precision)
  BinFloat::negative_zero_raw(precision~)
}

///|
fn BinFloat::negative_zero_raw(precision~ : Int32 = 53) -> BinFloat {
  finite_zero(true, precision)
}

///|
pub fn BinFloat::one(precision~ : Int32 = 53) -> BinFloat {
  binary_check_precision("BinFloat::one", precision)
  BinFloat::one_raw(precision~)
}

///|
fn BinFloat::one_raw(precision~ : Int32 = 53) -> BinFloat {
  finite_normalized(false, Coeff::one(), 0, precision)
}

///|
pub fn BinFloat::inf(sign : Sign, precision~ : Int32 = 53) -> BinFloat {
  binary_check_precision("BinFloat::inf", precision)
  BinFloat::inf_raw(sign, precision~)
}

///|
fn BinFloat::inf_raw(sign : Sign, precision~ : Int32 = 53) -> BinFloat {
  bin_repr_inf(sign == Sign::Negative, precision)
}

///|
pub fn BinFloat::nan(precision~ : Int32 = 53) -> BinFloat {
  binary_check_precision("BinFloat::nan", precision)
  BinFloat::nan_raw(precision~)
}

///|
fn BinFloat::nan_raw(precision~ : Int32 = 53) -> BinFloat {
  binary_nan_raw(false, false, Coeff::zero(), precision)
}

///|
/// A quiet NaN. The payload must fit the `precision - 2` bits that a NaN of
/// that precision has (IEEE 754-2019 6.2.1); a wider payload aborts.
pub fn BinFloat::quiet_nan(
  payload? : BinCoeff,
  negative~ : Bool = false,
  precision~ : Int32 = 53,
) -> BinFloat {
  binary_check_precision("BinFloat::quiet_nan", precision)
  let payload : Coeff = match payload {
    Some(value) => value.0
    None => Coeff::zero()
  }
  binary_check_payload("BinFloat::quiet_nan", payload, precision)
  binary_nan_raw(negative, false, payload, precision)
}

///|
/// A signaling NaN. Its payload is non-zero (a zero payload is replaced by 1,
/// because a signaling NaN with payload 0 is the encoding of infinity) and
/// fits `precision - 2` bits, so the precision is at least 3; otherwise this
/// aborts (IEEE 754-2019 6.2.1).
pub fn BinFloat::signaling_nan(
  payload? : BinCoeff,
  negative~ : Bool = false,
  precision~ : Int32 = 53,
) -> BinFloat {
  binary_check_precision("BinFloat::signaling_nan", precision)
  let payload : Coeff = match payload {
    Some(value) => value.0
    None => Coeff::one()
  }
  let payload = if payload.is_zero() { Coeff::one() } else { payload }
  if precision < 3 {
    abort(
      "BinFloat::signaling_nan: a signaling NaN needs a precision of at least 3 (got \{precision})",
    )
  }
  binary_check_payload("BinFloat::signaling_nan", payload, precision)
  binary_nan_raw(negative, true, payload, precision)
}

///|
fn binary_check_payload(
  operation : String,
  payload : Coeff,
  precision : Int32,
) -> Unit {
  let bits = binary_nan_payload_bits(precision)
  if payload.bit_length() > bits {
    abort(
      "\{operation}: the payload needs \{payload.bit_length()} bits, a NaN of precision \{precision} has \{bits}",
    )
  }
}

///|
pub fn BinFloat::from_int(n : Int32, precision~ : Int32 = 53) -> BinFloat {
  binary_check_precision("BinFloat::from_int", precision)
  BinFloat::from_int_raw(n, precision~)
}

///|
fn BinFloat::from_int_raw(n : Int32, precision~ : Int32 = 53) -> BinFloat {
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
  binary_check_precision("BinFloat::from_coefficient", precision)
  BinFloat::from_coefficient_raw(coefficient, precision~, negative~)
}

///|
fn BinFloat::from_coefficient_raw(
  coefficient : BinCoeff,
  precision~ : Int32 = 53,
  negative~ : Bool = false,
) -> BinFloat {
  BinFloat::make_coeff(coefficient.0, 0, precision, negative~)
}

///|
pub fn BinFloat::from_double(x : Double, precision~ : Int32 = 53) -> BinFloat {
  binary_check_precision("BinFloat::from_double", precision)
  let bits = x.reinterpret_as_uint64()
  let negative = bits >> 63 != 0UL
  let exponent_bits = ((bits >> 52) & 0x7ffUL).to_int()
  let fraction_bits = bits & 0x000f_ffff_ffff_ffffUL
  let quiet_bit = 1UL << 51
  if exponent_bits == 0x7ff {
    if fraction_bits == 0UL {
      return BinFloat::inf_raw(
        if negative {
          Sign::Negative
        } else {
          Sign::Positive
        },
        precision~,
      )
    }
    // A NaN of another precision keeps the low `precision - 2` bits of its
    // payload (IEEE 754-2019 6.2.3); a signaling NaN that cannot keep a
    // non-zero payload becomes quiet.
    return binary_convert_nan(
      negative,
      (fraction_bits & quiet_bit) == 0UL,
      Coeff::from_uint64(fraction_bits & (quiet_bit - 1UL)),
      precision,
    )
  }
  if exponent_bits == 0 {
    if fraction_bits == 0UL {
      return if negative {
        BinFloat::negative_zero_raw(precision~)
      } else {
        BinFloat::zero_raw(precision~)
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
  self.class()
}

///|
pub fn BinFloat::is_finite(self : BinFloat) -> Bool {
  self.class() == FpClass::Finite
}

///|
pub fn BinFloat::is_infinite(self : BinFloat) -> Bool {
  self.class() == FpClass::Infinity
}

///|
pub fn BinFloat::is_nan(self : BinFloat) -> Bool {
  self.class() == FpClass::NaN
}

///|
/// True for a nonzero finite value whose leading-bit exponent is below the
/// context's smallest normal exponent (IEEE 754-2019 clause 5.7.2).
pub fn BinFloat::is_subnormal(self : BinFloat, context : BinaryContext) -> Bool {
  self.class() == FpClass::Finite &&
  !self.coefficient_is_zero() &&
  binary_exact_top(self.coefficient_(), self.exponent2_()) <
  context.range_e_min()
}

///|
/// True for a nonzero finite value that is not subnormal in `context`.
pub fn BinFloat::is_normal(self : BinFloat, context : BinaryContext) -> Bool {
  self.class() == FpClass::Finite &&
  !self.coefficient_is_zero() &&
  binary_exact_top(self.coefficient_(), self.exponent2_()) >=
  context.range_e_min()
}

///|
/// The ten-valued class of IEEE 754-2019 clause 5.7.2.
pub fn BinFloat::class_of(
  self : BinFloat,
  context : BinaryContext,
) -> IeeeClass {
  match self.class() {
    FpClass::NaN => if self.signaling() { SignalingNaN } else { QuietNaN }
    FpClass::Infinity =>
      if self.negative() {
        NegativeInfinity
      } else {
        PositiveInfinity
      }
    FpClass::Finite =>
      if self.coefficient_is_zero() {
        if self.negative() {
          NegativeZero
        } else {
          PositiveZero
        }
      } else if self.is_subnormal(context) {
        if self.negative() {
          NegativeSubnormal
        } else {
          PositiveSubnormal
        }
      } else if self.negative() {
        NegativeNormal
      } else {
        PositiveNormal
      }
  }
}

///|
pub fn BinFloat::precision(self : BinFloat) -> Int32 {
  self.precision_()
}

///|
pub fn BinFloat::sign(self : BinFloat) -> Sign {
  match self.class() {
    FpClass::NaN => Sign::Zero
    FpClass::Finite if self.coefficient_is_zero() => Sign::Zero
    _ => if self.negative() { Sign::Negative } else { Sign::Positive }
  }
}

///|
pub fn BinFloat::is_negative(self : BinFloat) -> Bool {
  self.negative()
}

///|
pub fn BinFloat::is_negative_zero(self : BinFloat) -> Bool {
  self.is_zero() && self.negative()
}

///|
pub fn BinFloat::is_quiet_nan(self : BinFloat) -> Bool {
  self.class() == FpClass::NaN && !self.signaling()
}

///|
pub fn BinFloat::is_signaling_nan(self : BinFloat) -> Bool {
  self.class() == FpClass::NaN && self.signaling()
}

///|
pub fn BinFloat::nan_payload(self : BinFloat) -> BinCoeff {
  BinCoeff(self.nan_payload_coeff())
}

///|
fn BinFloat::nan_payload_coeff(self : BinFloat) -> Coeff {
  if self.class() == FpClass::NaN {
    self.payload_()
  } else {
    Coeff::zero()
  }
}

///|
pub fn BinFloat::coefficient(self : BinFloat) -> BinCoeff {
  BinCoeff(self.coefficient_())
}

///|
pub fn BinFloat::exponent2(self : BinFloat) -> Int32 {
  self.exponent2_()
}

///|
pub fn BinFloat::normalized(self : BinFloat) -> BinFloat {
  match self.class() {
    FpClass::Finite =>
      finite_from_parts(
        self.negative(),
        self.coefficient_(),
        self.exponent2_(),
        self.precision_(),
      )
    _ => self
  }
}

///|
pub fn BinFloat::with_precision(
  self : BinFloat,
  precision : Int32,
  mode : BinaryRoundingMode,
) -> BinFloat {
  binary_check_precision("BinFloat::with_precision", precision)
  BinFloat::with_precision_raw(self, precision, mode)
}

///|
fn BinFloat::with_precision_raw(
  self : BinFloat,
  precision : Int32,
  mode : BinaryRoundingMode,
) -> BinFloat {
  match self.class() {
    FpClass::Finite =>
      if self.is_zero() {
        finite_from_parts(self.negative(), Coeff::zero(), 0, precision)
      } else {
        BinFloat::make_coeff(
          self.coefficient_(),
          self.exponent2_(),
          precision,
          negative=self.negative(),
          mode~,
        )
      }
    FpClass::Infinity => bin_repr_inf(self.negative(), precision)
    FpClass::NaN =>
      binary_convert_nan(
        self.negative(),
        self.signaling(),
        self.payload_(),
        precision,
      )
  }
}

///|
pub fn BinFloat::neg(self : BinFloat) -> BinFloat {
  self.with_negative(!self.negative())
}

///|
pub fn BinFloat::abs(self : BinFloat) -> BinFloat {
  if self.negative() {
    self.neg()
  } else {
    self
  }
}

///|
pub fn BinFloat::is_zero(self : BinFloat) -> Bool {
  self.class() == FpClass::Finite && self.coefficient_is_zero()
}

///|
pub fn BinFloat::compare_checked(
  self : BinFloat,
  other : BinFloat,
) -> Result[Int32, @def.ArithmeticError] {
  guard self.class() != FpClass::NaN && other.class() != FpClass::NaN else {
    return Err(@def.ArithmeticError::unordered_comparison("NaN is unordered"))
  }
  Ok(
    match (self.class(), other.class()) {
      (FpClass::Infinity, FpClass::Infinity) =>
        if self.negative() == other.negative() {
          0
        } else if self.negative() {
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
  match (self.class() == FpClass::NaN, other.class() == FpClass::NaN) {
    (true, true) => return 0
    (true, false) => return 1
    (false, true) => return -1
    (false, false) => ()
  }
  match (self.class(), other.class()) {
    (FpClass::Infinity, FpClass::Infinity) =>
      if self.negative() == other.negative() {
        0
      } else if self.negative() {
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
  match self.class() {
    FpClass::Finite =>
      if self.coefficient_is_zero() {
        BinFloat::make_coeff(
          Coeff::one(),
          -(self.precision_() - 1),
          self.precision_(),
        )
      } else {
        let mag_bits = self.coefficient_bits()
        BinFloat::make_coeff(
          Coeff::one(),
          self.exponent2_() + mag_bits - self.precision_(),
          self.precision_(),
        )
      }
    _ => BinFloat::nan_raw(precision=self.precision_())
  }
}

///|
pub fn BinFloat::add(self : BinFloat, other : BinFloat) -> BinFloat {
  add_bin_impl(self, other)
}

///|
pub fn BinFloat::sub(self : BinFloat, other : BinFloat) -> BinFloat {
  add_signed_impl(self, other, true)
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
    self.div_ctx(other, binary_working_context(max_precision(self, other))),
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
        None => sqrt_for_precision(self, self.precision_())
      }
  }
}

///|
pub fn BinFloat::pown(
  self : BinFloat,
  exponent : Int32,
) -> Result[BinFloat, @def.ArithmeticError] {
  binary_checked_result(
    self.pown_ctx(exponent, binary_working_context(self.precision_())),
    "invalid power",
    division_by_zero_message="negative exponent requires a non-zero base",
  )
}

///|
pub impl @lf_arith.SqrtChecked for BinFloat with fn sqrt_checked(self, ctx) {
  match BinaryContext::from_arithmetic_context(ctx) {
    Err(error) => Err(error)
    Ok(bctx) =>
      binary_checked_result(
        self.sqrt_ctx(bctx),
        "sqrt requires a non-negative value",
      )
  }
}

///|
pub impl @lf_arith.DivChecked for BinFloat with fn div_checked(self, other, ctx) {
  match BinaryContext::from_arithmetic_context(ctx) {
    Err(error) => Err(error)
    Ok(bctx) =>
      binary_checked_result(self.div_ctx(other, bctx), "invalid division")
  }
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
  match BinaryContext::from_arithmetic_context(ctx) {
    Err(error) => Err(error)
    Ok(bctx) =>
      binary_checked_result(
        self.pow_nat_ctx(exponent, bctx),
        "invalid power",
        division_by_zero_message="negative exponent requires a non-zero base",
      )
  }
}

///|
pub impl @lf_arith.PowIntChecked for BinFloat with fn pow_int_checked(
  self,
  exponent,
  ctx,
) {
  match BinaryContext::from_arithmetic_context(ctx) {
    Err(error) => Err(error)
    Ok(bctx) =>
      binary_checked_result(
        self.pown_ctx(exponent, bctx),
        "invalid power",
        division_by_zero_message="negative exponent requires a non-zero base",
      )
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
pub impl @def.Floating for BinFloat with fn with_precision(self, precision) {
  BinFloat::with_precision(self, precision, BinaryRoundingMode::RoundTiesToEven)
}

///|
pub impl @def.Floating for BinFloat with fn normalized(self) {
  self.normalized()
}

///|
pub impl Show for BinFloat with fn to_string(self) {
  match self.class() {
    FpClass::NaN => "nan"
    FpClass::Infinity =>
      if self.sign() == Sign::Negative {
        "-inf"
      } else {
        "inf"
      }
    FpClass::Finite =>
      if self.coefficient_is_zero() {
        if self.negative() {
          "-0"
        } else {
          "0"
        }
      } else {
        (if self.negative() { "-" } else { "" }) +
        self.coefficient_().to_string() +
        "p" +
        self.exponent2_().to_string()
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
