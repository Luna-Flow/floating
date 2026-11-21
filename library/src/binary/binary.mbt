///|
/// A binary floating-point datum. The representation (`@binary_kernel.BinRepr`) is
/// internal and read only through the accessors of `bin_repr_nonjs.mbt` and
/// `bin_repr_js.mbt`; the newtype costs nothing: a value is one heap object.
#derive(Debug)
pub struct Binary(@binary_kernel.BinRepr)

///|
fn finite_zero(negative : Bool, precision : Int32) -> Binary {
  bin_repr_zero(negative, Int32::max(1, precision))
}

///|
fn finite_normalized(
  negative : Bool,
  coefficient : Coeff,
  exponent2 : Int32,
  precision : Int32,
) -> Binary {
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
) -> Binary {
  // Underflow is decided on the exact value so that precision rounding cannot
  // move a magnitude onto the halfway point of the smallest subnormal.
  let exact_top = exponent2.to_int64() + (bits - 1).to_int64()
  let tiny_top = binary_value_e_min.to_int64() - (precision - 1).to_int64()
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
  if top > binary_value_e_max.to_int64() {
    return implementation_overflow(negative, precision, mode)
  }
  finite_normalized(negative, coefficient2, exponent3, precision)
}

///|
fn implementation_overflow(
  negative : Bool,
  precision : Int32,
  mode : BinaryRoundingMode,
) -> Binary {
  let to_infinity = match mode {
    BinaryRoundingMode::RoundTiesToEven | BinaryRoundingMode::RoundTiesToAway =>
      true
    BinaryRoundingMode::RoundTowardZero => false
    BinaryRoundingMode::RoundTowardPositive => !negative
    BinaryRoundingMode::RoundTowardNegative => negative
  }
  if to_infinity {
    Binary::inf_raw(
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
      binary_value_e_max - (precision - 1),
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
) -> Binary {
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
      binary_value_e_min - (precision - 1),
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
) -> Binary {
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
) -> Binary {
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
) -> Binary {
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
/// Exponent of the leading bit of a finite non-zero value (`binary_exact_top` of
/// its coefficient and exponent) without building the coefficient.
fn Binary::exact_top(self : Binary) -> Int32 {
  binary_add_sat(self.coefficient_bits() - 1, self.exponent2_())
}

///|
fn max_precision(a : Binary, b : Binary) -> Int32 {
  Int32::max(a.precision_(), b.precision_())
}

///|
/// Order of the magnitudes of two finite values (zero included): the words of
/// values of at most 128 coefficient bits are compared without building a
/// coefficient (`binary_compare_pair_magnitude`), anything wider through the
/// coefficients.
fn binary_compare_magnitude(left : Binary, right : Binary) -> Int32 {
  if left.coefficient_is_zero() || right.coefficient_is_zero() {
    return if left.coefficient_is_zero() {
      if right.coefficient_is_zero() {
        0
      } else {
        -1
      }
    } else {
      1
    }
  }
  let words = binary_compare_pair_magnitude(left, right)
  if words != 2 {
    return words
  }
  binary_compare_shifted(
    left.coefficient_(),
    left.exponent2_(),
    right.coefficient_(),
    right.exponent2_(),
  )
}

///|
fn compare_finite(a : Binary, b : Binary) -> Int32 {
  if a.coefficient_is_zero() && b.coefficient_is_zero() {
    return 0
  }
  if a.negative() != b.negative() {
    return if a.negative() { -1 } else { 1 }
  }
  let magnitude_comparison = binary_compare_magnitude(a, b)
  if a.negative() {
    -magnitude_comparison
  } else {
    magnitude_comparison
  }
}

///|
fn add_bin_impl(a : Binary, b : Binary) -> Binary {
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
fn add_signed_impl(a : Binary, b : Binary, flip : Bool) -> Binary {
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
fn mul_bin_impl(a : Binary, b : Binary) -> Binary {
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
fn div_bin_impl(a : Binary, b : Binary) -> Binary {
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
fn sqrt_for_precision(x : Binary, precision : Int32) -> Binary {
  x.sqrt_ctx(binary_working_context(precision)).0
}

///|
/// Maps a contextual result to the checked tier: the invalid operation
/// exception (IEEE 754-2019 section 7.2) becomes `DomainError`, the
/// divideByZero exception (section 7.3) becomes `DivisionByZero`, and every
/// other result, NaN and range exceptions included, is returned in `Ok` (#262).
fn binary_checked_result(
  result : (Binary, BinaryFlags),
  invalid_message : String,
  division_by_zero_message~ : String = "division by zero",
) -> Result[Binary, @def.ArithmeticError] {
  let (value, flags) = result
  if flags.division_by_zero() {
    Err(@def.ArithmeticError::division_by_zero(division_by_zero_message))
  } else if flags.not_computed() {
    Err(binary_not_computed_error("binary operation"))
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
) -> Binary {
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
) -> Binary {
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
pub fn Binary::make(
  coefficient : BinCoeff,
  exponent2 : Int32,
  precision : Int32,
  negative~ : Bool = false,
  mode~ : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
) -> Binary {
  binary_check_precision("Binary::make", precision)
  Binary::make_coeff(coefficient.0, exponent2, precision, negative~, mode~)
}

///|
fn Binary::make_coeff(
  coefficient : Coeff,
  exponent2 : Int32,
  precision : Int32,
  negative~ : Bool = false,
  mode~ : BinaryRoundingMode = BinaryRoundingMode::RoundTiesToEven,
) -> Binary {
  normalize_finite(coefficient, exponent2, precision, negative, mode)
}

///|
pub fn Binary::zero(precision~ : Int32 = 53) -> Binary {
  binary_check_precision("Binary::zero", precision)
  Binary::zero_raw(precision~)
}

///|
fn Binary::zero_raw(precision~ : Int32 = 53) -> Binary {
  finite_zero(false, precision)
}

///|
pub fn Binary::negative_zero(precision~ : Int32 = 53) -> Binary {
  binary_check_precision("Binary::negative_zero", precision)
  Binary::negative_zero_raw(precision~)
}

///|
fn Binary::negative_zero_raw(precision~ : Int32 = 53) -> Binary {
  finite_zero(true, precision)
}

///|
pub fn Binary::one(precision~ : Int32 = 53) -> Binary {
  binary_check_precision("Binary::one", precision)
  Binary::one_raw(precision~)
}

///|
fn Binary::one_raw(precision~ : Int32 = 53) -> Binary {
  finite_normalized(false, Coeff::one(), 0, precision)
}

///|
pub fn Binary::inf(negative~ : Bool = false, precision~ : Int32 = 53) -> Binary {
  binary_check_precision("Binary::inf", precision)
  bin_repr_inf(negative, precision)
}

///|
fn Binary::inf_raw(sign : Sign, precision~ : Int32 = 53) -> Binary {
  bin_repr_inf(sign == Sign::Negative, precision)
}

///|
pub fn Binary::nan(precision~ : Int32 = 53) -> Binary {
  binary_check_precision("Binary::nan", precision)
  Binary::nan_raw(precision~)
}

///|
fn Binary::nan_raw(precision~ : Int32 = 53) -> Binary {
  binary_nan_raw(false, false, Coeff::zero(), precision)
}

///|
/// A quiet NaN. The payload must fit the `precision - 2` bits that a NaN of
/// that precision has (IEEE 754-2019 6.2.1); a wider payload aborts.
pub fn Binary::quiet_nan(
  payload? : BinCoeff,
  negative~ : Bool = false,
  precision~ : Int32 = 53,
) -> Binary {
  binary_check_precision("Binary::quiet_nan", precision)
  let payload : Coeff = match payload {
    Some(value) => value.0
    None => Coeff::zero()
  }
  binary_check_payload("Binary::quiet_nan", payload, precision)
  binary_nan_raw(negative, false, payload, precision)
}

///|
/// A signaling NaN. Its payload is non-zero (a zero payload is replaced by 1,
/// because a signaling NaN with payload 0 is the encoding of infinity) and
/// fits `precision - 2` bits, so the precision is at least 3; otherwise this
/// aborts (IEEE 754-2019 6.2.1).
pub fn Binary::signaling_nan(
  payload? : BinCoeff,
  negative~ : Bool = false,
  precision~ : Int32 = 53,
) -> Binary {
  binary_check_precision("Binary::signaling_nan", precision)
  let payload : Coeff = match payload {
    Some(value) => value.0
    None => Coeff::one()
  }
  let payload = if payload.is_zero() { Coeff::one() } else { payload }
  if precision < 3 {
    abort(
      "Binary::signaling_nan: a signaling NaN needs a precision of at least 3 (got \{precision})",
    )
  }
  binary_check_payload("Binary::signaling_nan", payload, precision)
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
pub fn Binary::from_int(n : Int32, precision~ : Int32 = 53) -> Binary {
  binary_check_precision("Binary::from_int", precision)
  Binary::from_int_raw(n, precision~)
}

///|
fn Binary::from_int_raw(n : Int32, precision~ : Int32 = 53) -> Binary {
  let negative = n < 0
  let magnitude = if negative {
    (-(n + 1)).to_uint64() + 1UL
  } else {
    n.to_uint64()
  }
  finite_from_uint64(negative, magnitude, precision)
}

///|
pub fn Binary::from_coefficient(
  coefficient : BinCoeff,
  precision~ : Int32 = 53,
  negative~ : Bool = false,
) -> Binary {
  binary_check_precision("Binary::from_coefficient", precision)
  Binary::from_coefficient_raw(coefficient, precision~, negative~)
}

///|
fn Binary::from_coefficient_raw(
  coefficient : BinCoeff,
  precision~ : Int32 = 53,
  negative~ : Bool = false,
) -> Binary {
  Binary::make_coeff(coefficient.0, 0, precision, negative~)
}

///|
pub fn Binary::from_double(x : Double, precision~ : Int32 = 53) -> Binary {
  binary_check_precision("Binary::from_double", precision)
  let bits = x.reinterpret_as_uint64()
  let negative = bits >> 63 != 0UL
  let exponent_bits = ((bits >> 52) & 0x7ffUL).to_int()
  let fraction_bits = bits & 0x000f_ffff_ffff_ffffUL
  let quiet_bit = 1UL << 51
  if exponent_bits == 0x7ff {
    if fraction_bits == 0UL {
      return Binary::inf_raw(
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
        Binary::negative_zero_raw(precision~)
      } else {
        Binary::zero_raw(precision~)
      }
    }
    return Binary::make_coeff(
      Coeff::from_uint64(fraction_bits),
      -1074,
      precision,
      negative~,
    )
  }
  Binary::make_coeff(
    Coeff::from_uint64((1UL << 52) | fraction_bits),
    exponent_bits - 1075,
    precision,
    negative~,
  )
}

///|
pub fn Binary::from_float(x : Float, precision~ : Int32 = 24) -> Binary {
  Binary::from_double(x.to_double(), precision~)
}

///|
pub fn Binary::classify(self : Binary) -> FpClass {
  self.class()
}

///|
pub fn Binary::is_finite(self : Binary) -> Bool {
  self.class() == FpClass::Finite
}

///|
pub fn Binary::is_infinite(self : Binary) -> Bool {
  self.class() == FpClass::Infinity
}

///|
pub fn Binary::is_nan(self : Binary) -> Bool {
  self.class() == FpClass::NaN
}

///|
/// True for a nonzero finite value whose leading-bit exponent is below the
/// context's smallest normal exponent (IEEE 754-2019 clause 5.7.2).
pub fn Binary::is_subnormal(self : Binary, context : BinaryContext) -> Bool {
  self.class() == FpClass::Finite &&
  !self.coefficient_is_zero() &&
  self.exact_top() < context.range_e_min()
}

///|
/// True for a nonzero finite value that is not subnormal in `context`.
pub fn Binary::is_normal(self : Binary, context : BinaryContext) -> Bool {
  self.class() == FpClass::Finite &&
  !self.coefficient_is_zero() &&
  self.exact_top() >= context.range_e_min()
}

///|
/// The ten-valued class of IEEE 754-2019 clause 5.7.2.
pub fn Binary::class_of(self : Binary, context : BinaryContext) -> IeeeClass {
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
pub fn Binary::precision(self : Binary) -> Int32 {
  self.precision_()
}

///|
pub fn Binary::signum(self : Binary) -> Sign {
  self.sign_()
}

///|
pub fn Binary::is_sign_minus(self : Binary) -> Bool {
  self.negative()
}

///|
pub fn Binary::is_negative_zero(self : Binary) -> Bool {
  self.is_zero() && self.negative()
}

///|
pub fn Binary::is_quiet_nan(self : Binary) -> Bool {
  self.class() == FpClass::NaN && !self.signaling()
}

///|
pub fn Binary::is_signaling_nan(self : Binary) -> Bool {
  self.class() == FpClass::NaN && self.signaling()
}

///|
pub fn Binary::nan_payload(self : Binary) -> BinCoeff {
  BinCoeff(self.nan_payload_coeff())
}

///|
fn Binary::nan_payload_coeff(self : Binary) -> Coeff {
  if self.class() == FpClass::NaN {
    self.payload_()
  } else {
    Coeff::zero()
  }
}

///|
pub fn Binary::coefficient(self : Binary) -> BinCoeff {
  BinCoeff(self.coefficient_())
}

///|
pub fn Binary::exponent2(self : Binary) -> Int32 {
  self.exponent2_()
}

///|
/// The exponent of the leading bit of a finite non-zero value: the `e` with
/// `2^e <= |x| < 2^(e+1)`, that is `floor(log2 |x|)`; `ilogb(1)` is `Some(0)`.
///
/// This is `logB` of IEEE 754-2019 5.3.3 with an integral `logBFormat`.
/// The standard defines `logB(x)` as the exponent of `x` "determined as
/// though x were represented with infinite range and minimum exponent", so a
/// subnormal value gives the exponent of its leading bit, and not the minimum
/// exponent of the format (the leading bit of the subnormal `3 * 2^(e_min -
/// p + 1)` is `e_min - p + 2`). For `logB(NaN)`, `logB(infinity)` and `logB(0)`
/// with an integer `logBFormat` the standard returns language-defined values
/// outside `+-2 * (e_max + p - 1)` and signals the invalid operation exception
/// (5.3.3, 7.2 l); this interface renders those three cases as `None` and
/// raises no flag. With a floating-point `logBFormat` the results are a NaN,
/// `+infinity` and `-infinity` (with divideByZero), which `logb_ctx` returns.
///
/// It is read from the value without building its coefficient, and is
/// `exponent2() + coefficient().bit_length() - 1`.
pub fn Binary::ilogb(self : Binary) -> Int32? {
  match self.class() {
    FpClass::Finite =>
      if self.coefficient_is_zero() {
        None
      } else {
        Some(self.exact_top())
      }
    FpClass::Infinity | FpClass::NaN => None
  }
}

///|
pub fn Binary::normalized(self : Binary) -> Binary {
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
pub fn Binary::with_precision(
  self : Binary,
  precision : Int32,
  mode : BinaryRoundingMode,
) -> Binary {
  binary_check_precision("Binary::with_precision", precision)
  Binary::with_precision_raw(self, precision, mode)
}

///|
fn Binary::with_precision_raw(
  self : Binary,
  precision : Int32,
  mode : BinaryRoundingMode,
) -> Binary {
  match self.class() {
    FpClass::Finite =>
      if self.is_zero() {
        finite_from_parts(self.negative(), Coeff::zero(), 0, precision)
      } else {
        Binary::make_coeff(
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
pub fn Binary::neg(self : Binary) -> Binary {
  self.with_negative(!self.negative())
}

///|
pub fn Binary::abs(self : Binary) -> Binary {
  if self.negative() {
    self.neg()
  } else {
    self
  }
}

///|
pub fn Binary::is_zero(self : Binary) -> Bool {
  self.class() == FpClass::Finite && self.coefficient_is_zero()
}

///|
pub fn Binary::compare_checked(
  self : Binary,
  other : Binary,
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
        if self.signum() == Sign::Negative {
          -1
        } else {
          1
        }
      (_, FpClass::Infinity) =>
        if other.signum() == Sign::Negative {
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
pub fn Binary::compare(self : Binary, other : Binary) -> Int32 {
  let words = binary_compare_pair(self, other)
  if words != 2 {
    return words
  }
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
    (FpClass::Infinity, _) =>
      if self.signum() == Sign::Negative {
        -1
      } else {
        1
      }
    (_, FpClass::Infinity) =>
      if other.signum() == Sign::Negative {
        1
      } else {
        -1
      }
    (FpClass::Finite, FpClass::Finite) => compare_finite(self, other)
    _ => 0
  }
}

///|
pub fn Binary::min_num(self : Binary, other : Binary) -> Binary {
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
pub fn Binary::max_num(self : Binary, other : Binary) -> Binary {
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
pub fn Binary::clamp(self : Binary, min~ : Binary, max~ : Binary) -> Binary {
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
pub fn Binary::clamp_checked(
  self : Binary,
  min~ : Binary,
  max~ : Binary,
) -> Result[Binary, @def.ArithmeticError] {
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
pub fn Binary::ulp(self : Binary) -> Binary {
  match self.class() {
    FpClass::Finite =>
      if self.coefficient_is_zero() {
        Binary::make_coeff(
          Coeff::one(),
          -(self.precision_() - 1),
          self.precision_(),
        )
      } else {
        let mag_bits = self.coefficient_bits()
        Binary::make_coeff(
          Coeff::one(),
          self.exponent2_() + mag_bits - self.precision_(),
          self.precision_(),
        )
      }
    _ => Binary::nan_raw(precision=self.precision_())
  }
}

///|
pub fn Binary::add(self : Binary, other : Binary) -> Binary {
  add_bin_impl(self, other)
}

///|
pub fn Binary::sub(self : Binary, other : Binary) -> Binary {
  add_signed_impl(self, other, true)
}

///|
pub fn Binary::mul(self : Binary, other : Binary) -> Binary {
  mul_bin_impl(self, other)
}

///|
pub fn Binary::div(self : Binary, other : Binary) -> Binary {
  div_bin_impl(self, other)
}

///|
/// IEEE 754-2019 squareRoot at the precision of `self`: `sqrt_ctx` under the
/// working context, a NaN (7.2 invalid operation) for a negative operand, `-0` for
/// `-0`. It never aborts and has no `Result`: the flag is read through `sqrt_ctx`.
pub fn Binary::sqrt(self : Binary) -> Binary {
  match binary_fast_sqrt(self) {
    Some(result) => result
    None =>
      match binary_coeff_fast_sqrt(self) {
        Some(result) => result
        None => sqrt_for_precision(self, self.precision_())
      }
  }
}

///|
/// `pown_ctx` under the working context at the precision of `self`: a NaN for an
/// invalid case (7.2), an infinity for `0^negative` (7.3), never an abort; the
/// flags are read through `pown_ctx`.
pub fn Binary::pown(self : Binary, exponent : Int32) -> Binary {
  self.pown_ctx(exponent, binary_working_context(self.precision_())).0
}

///|
pub impl @lf_arith.SqrtChecked for Binary with fn sqrt_checked(self, ctx) {
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
pub impl @lf_arith.DivChecked for Binary with fn div_checked(self, other, ctx) {
  match BinaryContext::from_arithmetic_context(ctx) {
    Err(error) => Err(error)
    Ok(bctx) =>
      binary_checked_result(self.div_ctx(other, bctx), "invalid division")
  }
}

///|
pub impl @lf_arith.CompareChecked for Binary with fn compare_checked(
  self,
  other,
) {
  self.compare_checked(other)
}

///|
pub impl @lf_arith.PowNatChecked for Binary with fn pow_nat_checked(
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
pub impl @lf_arith.PowIntChecked for Binary with fn pow_int_checked(
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
pub impl Add for Binary with fn add(self, other) {
  add_bin_impl(self, other)
}

///|
pub impl Sub for Binary with fn sub(self, other) {
  self.sub(other)
}

///|
pub impl Mul for Binary with fn mul(self, other) {
  mul_bin_impl(self, other)
}

///|
pub impl Div for Binary with fn div(self, other) {
  div_bin_impl(self, other)
}

///|
pub impl Neg for Binary with fn neg(self) {
  self.neg()
}

///|
/// `==` agrees with `compare`: `a == b` exactly when `a.compare(b) == 0`, so the two
/// numbers are equal whatever their precisions (`-0 == +0`,
/// `one(precision=53) == one(precision=24)`) and every NaN equals every other NaN,
/// the order in which `<`, `<=` and sorting work (a total preorder: every NaN equal to
/// every NaN and above every number). It is not IEEE equality: use
/// `compare_quiet_equal` (IEEE Std 754-2019 5.6.1, 5.11) when a NaN must be unordered,
/// and `identical` for the structural question (sign of zero, kind and payload of a NaN,
/// the precision). `Decimal` (`decimal` and `decimal_gda`) follows the same rule.
pub impl Eq for Binary with fn equal(self, other) {
  self.compare(other) == 0
}

///|
/// The structural equality: the same class, sign (the sign of a zero included),
/// coefficient, exponent, precision, and for a NaN the same kind and payload. It
/// distinguishes `-0` from `+0` and a value of precision 53 from the same value of
/// precision 24, and a NaN is identical to an identical NaN; use `==` for the
/// numerical question.
pub fn Binary::identical(self : Binary, other : Binary) -> Bool {
  self.0 == other.0
}

///|
pub impl Compare for Binary with fn compare(self, other) {
  self.compare(other)
}

///|
pub impl @def.Floating for Binary with fn classify(self) {
  self.classify()
}

///|
pub impl @def.Floating for Binary with fn signum(self) {
  self.signum()
}

///|
pub impl @def.Floating for Binary with fn precision(self) {
  self.precision()
}

///|
pub impl @def.Floating for Binary with fn with_precision(self, precision) {
  Binary::with_precision(self, precision, BinaryRoundingMode::RoundTiesToEven)
}

///|
pub impl @def.Floating for Binary with fn normalized(self) {
  self.normalized()
}

///|
pub impl Show for Binary with fn to_string(self) {
  match self.class() {
    FpClass::NaN => "nan"
    FpClass::Infinity =>
      if self.signum() == Sign::Negative {
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
pub extend Binary with Show::{to_string}

///|
pub extend Binary with Eq::{not_equal, equal}

///|
pub extend Binary with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Binary with @Luna-Flow/arithmetic.SqrtChecked::{sqrt_checked}

///|
pub extend Binary with @Luna-Flow/arithmetic.PowNatChecked::{pow_nat_checked}

///|
pub extend Binary with @Luna-Flow/arithmetic.PowIntChecked::{pow_int_checked}

///|
pub extend Binary with Compare::{op_lt, op_le, op_ge, op_gt}

///|
pub extend Binary with Show::{output}
