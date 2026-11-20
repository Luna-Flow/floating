///|
// Public constructors and binary/decimal conversion helpers.

///|
/// IEEE 754-2019 5.2: the member of the cohort asked for. A coefficient of at
/// most `precision` digits keeps the exponent given (its cohort is not
/// reduced, S7); a longer one is rounded to exactly `precision` digits. The
/// value must be storable (`decimal_value_e_tiny`, `decimal_value_e_max`),
/// checked after the rounding: `make` aborts otherwise, `try_make` returns the
/// domain error.
pub fn Decimal::make(
  coefficient : BigInt,
  exponent10 : Int32,
  precision : Int32,
  mode~ : DecimalRoundingMode = DecimalRoundingMode::RoundTiesToEven,
) -> Decimal {
  let precision = decimal_check_precision("make", precision)
  match
    Decimal::make_checked(coefficient, exponent10, precision, mode.round()) {
    Ok(value) => value
    Err(message) => abort("Decimal::make: " + message)
  }
}

///|
/// The `Result` form of `make`: the domain error of a value outside the stored
/// range, an `Err` for a precision outside `1..=decimal_precision_max`.
pub fn Decimal::try_make(
  coefficient : BigInt,
  exponent10 : Int32,
  precision : Int32,
  mode~ : DecimalRoundingMode = DecimalRoundingMode::RoundTiesToEven,
) -> Result[Decimal, @def.ArithmeticError] {
  if precision < 1 || precision > decimal_precision_max {
    return Err(
      @def.ArithmeticError::domain_error(
        "Decimal::try_make: precision \{precision} must be within 1..=\{decimal_precision_max}",
      ),
    )
  }
  match
    Decimal::make_checked(coefficient, exponent10, precision, mode.round()) {
    Ok(value) => Ok(value)
    Err(message) =>
      Err(@def.ArithmeticError::domain_error("Decimal::try_make: " + message))
  }
}

///|
fn Decimal::make_checked(
  coefficient : BigInt,
  exponent10 : Int32,
  precision : Int32,
  mode : DecimalRound,
) -> Result[Decimal, String] {
  decimal_round_checked(
    coefficient < bigint_zero(),
    coeff_from_bigint(abs_bigint(coefficient)),
    exponent10.to_int64(),
    precision,
    mode,
  )
}

///|
pub fn Decimal::zero(precision~ : Int32 = 34) -> Decimal {
  let precision = decimal_check_precision("zero", precision)
  Decimal::make(bigint_zero(), 0, precision)
}

///|
pub fn Decimal::negative_zero(precision~ : Int32 = 34) -> Decimal {
  let precision = decimal_check_precision("negative_zero", precision)
  normalize_decimal_parts(
    true,
    bigint_zero(),
    0,
    precision,
    DecimalRound::HalfEven,
  )
}

///|
pub fn Decimal::one(precision~ : Int32 = 34) -> Decimal {
  let precision = decimal_check_precision("one", precision)
  Decimal::make(bigint_one(), 0, precision)
}

///|
pub fn Decimal::inf(
  negative~ : Bool = false,
  precision~ : Int32 = 34,
) -> Decimal {
  let precision = decimal_check_precision("inf", precision)
  make_special(FpClass::Infinity, negative, bigint_zero(), precision, false)
}

///|
pub fn Decimal::nan(precision~ : Int32 = 34) -> Decimal {
  let precision = decimal_check_precision("nan", precision)
  make_special(FpClass::NaN, false, bigint_zero(), precision, false)
}

///|
pub fn Decimal::quiet_nan(
  payload~ : BigInt = bigint_zero(),
  negative~ : Bool = false,
  precision~ : Int32 = 34,
) -> Decimal {
  let precision = decimal_check_precision("quiet_nan", precision)
  decimal_check_payload("quiet_nan", payload, precision)
  make_special(FpClass::NaN, negative, payload, precision, false)
}

///|
pub fn Decimal::signaling_nan(
  payload~ : BigInt = bigint_zero(),
  negative~ : Bool = false,
  precision~ : Int32 = 34,
) -> Decimal {
  let precision = decimal_check_precision("signaling_nan", precision)
  decimal_check_payload("signaling_nan", payload, precision)
  make_special(FpClass::NaN, negative, payload, precision, true)
}

///|
pub fn Decimal::from_int(n : Int32, precision~ : Int32 = 34) -> Decimal {
  let precision = decimal_check_precision("from_int", precision)
  Decimal::from_bigint(BigInt::from_int(n), precision~)
}

///|
pub fn Decimal::from_bigint(n : BigInt, precision~ : Int32 = 34) -> Decimal {
  let precision = decimal_check_precision("from_bigint", precision)
  decimal_from_integer_parts(n, 0, precision)
}

///|
/// IEEE 754-2019 §5.4.1 convertFromInt has preferred exponent 0 and §5.2 an
/// inexact result takes the least possible exponent: an integer of at most
/// `precision` digits keeps `exponent10` (its cohort is not reduced), a longer
/// one is rounded to exactly `precision` digits (a carry into `10^p` leaves
/// `10^(p-1)` at the next exponent).
fn decimal_from_integer_parts(
  value : BigInt,
  exponent10 : Int32,
  precision : Int32,
) -> Decimal {
  let negative = value < bigint_zero()
  let magnitude = coeff_from_bigint(abs_bigint(value))
  if magnitude.is_zero() {
    return finite_with_exponent_repr(negative, magnitude, 0, precision)
  }
  context_free_round_wide(
    negative,
    magnitude,
    exponent10.to_int64(),
    precision,
    round_to_precision=true,
    reduce=false,
    mode=DecimalRound::HalfEven,
  )
}

///|
pub fn Decimal::from_double(x : Double, precision~ : Int32 = 34) -> Decimal {
  let precision = decimal_check_precision("from_double", precision)
  let bits = x.reinterpret_as_uint64()
  let negative = bits >> 63 != 0UL
  let exponent_bits = ((bits >> 52) & 0x7ffUL).to_int()
  let fraction_bits = bits & 0x000f_ffff_ffff_ffffUL
  if exponent_bits == 0x7ff && fraction_bits != 0UL {
    return Decimal::quiet_nan(negative~, precision~)
  }
  if exponent_bits == 0 && fraction_bits == 0UL {
    return if negative {
      Decimal::negative_zero(precision~)
    } else {
      Decimal::zero(precision~)
    }
  }
  let bin = @bin_float.BinFloat::from_double(x, precision=53)
  match bin.classify() {
    FpClass::NaN => Decimal::nan(precision~)
    FpClass::Infinity => Decimal::inf(negative=bin.is_negative(), precision~)
    FpClass::Finite => Decimal::from_bin_float(bin, precision~)
  }
}

///|
pub fn Decimal::from_float(x : Float, precision~ : Int32 = 34) -> Decimal {
  let precision = decimal_check_precision("from_float", precision)
  Decimal::from_double(x.to_double(), precision~)
}

///|
/// `ceil(log2 10 * 10^6)`: `2^(scale * 3.321929) > 10^scale` for `scale >= 1`.
let decimal_log2_10_ceil_ppm : Int64 = 3_321_929L

///|
/// `m 2^k` with `m` of at most `bits` bits, rounded down (or, with `up`, up) from
/// `m 2^k`: one trim step of `decimal_directed_binary_power5`.
fn decimal_binary_directed_trim(
  m : BigInt,
  k : Int32,
  bits : Int32,
  up : Bool,
) -> (BigInt, Int32) {
  let length = m.bit_length()
  if length <= bits {
    return (m, k)
  }
  let drop = length - bits
  let mut q = m >> drop
  if up && q << drop != m {
    q = q + bigint_one()
  }
  (q, k + drop)
}

///|
/// A lower bound (or, with `up`, an upper bound) `m 2^k` of `5^count`, `m` of
/// at most `bits` bits, by binary powering with a directed trim after every
/// product: `O(log count)` products of `bits`-bit numbers. Each trim moves
/// towards the chosen side by less than one unit of the `bits`-th bit (a
/// relative error below `2^(1 - bits)`), and the product of two bounds on the
/// same side is a bound on that side, so the result is a bound with a relative
/// error below `2^(5 - bits)` for `count < 2^30` (at most 30 squarings and 30
/// multiplications by 5, each adding less than `2^(1 - bits)`, doubled by every
/// later squaring: the sum is below `2^(1 - bits) 2^31 / 2^30 * 30` once the
/// later squarings are counted, and `bits >= 64` keeps it below `2^(8 - bits)`).
fn decimal_directed_binary_power5(
  count : Int32,
  bits : Int32,
  up : Bool,
) -> (BigInt, Int32) {
  let mut result = (bigint_one(), 0)
  let mut bit = 30
  while bit >= 0 && count >> bit == 0 {
    bit = bit - 1
  }
  while bit >= 0 {
    result = decimal_binary_directed_trim(
      result.0 * result.0,
      result.1 + result.1,
      bits,
      up,
    )
    if ((count >> bit) & 1) == 1 {
      result = decimal_binary_directed_trim(
        result.0 * BigInt::from_int(5),
        result.1,
        bits,
        up,
      )
    }
    bit = bit - 1
  }
  result
}

///|
/// The exponent from which a conversion uses directed powers of 5 instead of the
/// exact power: the exact `5^e` has `2.32 e` bits and is rebuilt on every call
/// above the cache (4096).
let decimal_directed_conversion_exponent : Int32 = 4096

///|
/// `to_bin_float(mode)` of a finite nonzero `value` with a decimal exponent of
/// magnitude at least `decimal_directed_conversion_exponent`, from bounds of
/// `5^|exponent10|` instead of the exact power: `None` when the two bounds do
/// not give one result (a rounding boundary lies between them, or the value is
/// representable), so that every answer is the exact conversion, bit for bit.
/// Rounding is monotone, so equal roundings of a lower and an upper bound of the
/// value are the rounding of the value.
fn decimal_to_bin_float_directed(
  value : Decimal,
  precision : Int32,
  mode : RoundingMode,
) -> @bin_float.BinFloat? {
  let e = value.exponent10
  let magnitude = if e >= 0 { e } else { -e }
  guard magnitude >= decimal_directed_conversion_exponent else { return None }
  let c = abs_bigint(coeff_bigint(value.coefficient))
  let c_bits = c.bit_length()
  // The bounds must be tight enough that the roundings agree almost always:
  // relative error 2^(8 - bits) against a rounding unit of 2^-precision.
  let bits = precision + c_bits + 80
  let negative = value.sign() == Sign::Negative
  let (lo_m, lo_k) = decimal_directed_binary_power5(magnitude, bits, false)
  let (hi_m, hi_k) = decimal_directed_binary_power5(magnitude, bits, true)
  if e >= 0 {
    let low = @bin_float.BinFloat::make(
      @bin_float.BinCoeff::from_bytes_be((c * lo_m).to_octets()),
      lo_k + e,
      precision,
      negative~,
      mode=bin_mode(mode, negative),
    )
    let high = @bin_float.BinFloat::make(
      @bin_float.BinCoeff::from_bytes_be((c * hi_m).to_octets()),
      hi_k + e,
      precision,
      negative~,
      mode=bin_mode(mode, negative),
    )
    return if low.compare(high) == 0 &&
      low.exponent2() == high.exponent2() &&
      low.coefficient() == high.coefficient() {
      Some(low)
    } else {
      None
    }
  }
  // c / 10^s = c / (5^s 2^s) never has a finite binary expansion here
  // (5^s > c once 2 s > 3.33 digits, checked below), so the quotient is
  // inexact and its sticky bit is set. Quotients of `c 2^u` by the bounds,
  // truncated, give a lower and an upper bound of floor(c 2^u / (5^s 2^k)).
  guard 2 * magnitude > 4 * c_bits else { return None }
  let f = magnitude + Int32::max(hi_k, lo_k) + bits + precision + 4 - c_bits
  let upper_quotient = (c << (f - magnitude - lo_k)) / lo_m
  let lower_quotient = (c << (f - magnitude - hi_k)) / hi_m
  if upper_quotient != lower_quotient {
    return None
  }
  let quotient = lower_quotient | bigint_one()
  Some(
    @bin_float.BinFloat::make(
      @bin_float.BinCoeff::from_bytes_be(quotient.to_octets()),
      -f,
      precision,
      negative~,
      mode=bin_mode(mode, negative),
    ),
  )
}

///|
/// The finite nonzero `self` as `(odd-sticky quotient, binary exponent)`, with
/// `|self| = quotient * 2^exponent` up to the sticky bit: `BinFloat::make`
/// rounds the exact value once from it, in every mode. A positive decimal
/// exponent gives the exact integer `c 5^e` at the binary exponent `e`. A
/// negative one, `c / 10^scale`, is the quotient of `c 2^shift` by `10^scale`
/// truncated and made odd when the division is inexact, with
/// `shift = precision + 3 + ceil(log2 10^scale)`: since `10^scale < 2^(shift -
/// precision - 3)` the quotient keeps at least `precision + 3` bits, which
/// leaves two bits below the target position and a sticky bit. Rounding the
/// quotient in the target mode first would round a value just above a binary
/// midpoint onto it, and ties-to-even would then go the wrong way. One
/// division decides the quotient; the sticky bit comes from multiplying it
/// back, not from a second division.
fn decimal_to_binary_parts(
  value : Decimal,
  precision : Int32,
) -> (BigInt, Int32) {
  if value.exponent10 >= 0 {
    return (
      coeff_bigint(value.coefficient) * pow5(value.exponent10),
      value.exponent10,
    )
  }
  let scale = -value.exponent10
  let log2_ten_scale = (scale.to_int64() * decimal_log2_10_ceil_ppm + 999_999L) /
    1_000_000L
  let binary_shift = precision + 3 + log2_ten_scale.to_int()
  let numerator = abs_bigint(coeff_bigint(value.coefficient)) << binary_shift
  let denominator = pow10(scale)
  let truncated = numerator / denominator
  let quotient = if truncated * denominator == numerator {
    truncated
  } else {
    truncated | bigint_one()
  }
  (quotient, -binary_shift)
}

///|
/// The conversion of a finite non-zero `value` whose adjusted exponent puts it
/// certainly outside the binary implementation range, decided in `Int64`
/// before any power is formed (#447): above `2^(e_max + 2)` it overflows, below
/// `2^(e_min - precision - 4)` it underflows, each as the rounding direction
/// says. `None` for every other value. `10^a >= 2^(3.32 a)` and
/// `10^(a + 1) <= 2^(3.33 (a + 1))`, so the cut-offs below keep a margin.
fn decimal_to_bin_float_out_of_range(
  value : Decimal,
  precision : Int32,
  mode : RoundingMode,
) -> @bin_float.BinFloat? {
  let adjusted = adjusted_exponent64(value)
  let e_max = @bin_float.binary_implementation_e_max.to_int64()
  let e_min = @bin_float.binary_implementation_e_min.to_int64()
  let above = (e_max + 2L) * 30103L / 100000L + 2L
  let below = (e_min - precision.to_int64() - 4L) * 30103L / 100000L - 3L
  let negative = value.negative
  if adjusted > above {
    Some(
      @bin_float.BinFloat::make(
        @bin_float.BinCoeff::one(),
        e_max.to_int() + 4,
        precision,
        negative~,
        mode=bin_mode(mode, negative),
      ),
    )
  } else if adjusted + 1L < below {
    Some(
      @bin_float.BinFloat::make(
        @bin_float.BinCoeff::one(),
        e_min.to_int() - precision - 8,
        precision,
        negative~,
        mode=bin_mode(mode, negative),
      ),
    )
  } else {
    None
  }
}

///|
pub fn Decimal::to_bin_float(
  self : Decimal,
  precision~ : Int32 = self.precision_,
  mode~ : RoundingMode = RoundingMode::ToNearestEven,
) -> @bin_float.BinFloat {
  match self.class {
    FpClass::NaN => @bin_float.BinFloat::nan(precision~)
    FpClass::Infinity => @bin_float.BinFloat::inf(self.sign(), precision~)
    FpClass::Finite => {
      // IEEE 754-2019 §5.4.2 and §6.3: conversions keep the sign of zero.
      if self.coefficient.is_zero() {
        return if self.negative {
          @bin_float.BinFloat::negative_zero(precision~)
        } else {
          @bin_float.BinFloat::zero(precision~)
        }
      }
      match decimal_to_bin_float_out_of_range(self, precision, mode) {
        Some(result) => return result
        None => ()
      }
      match decimal_to_bin_float_directed(self, precision, mode) {
        Some(result) => return result
        None => ()
      }
      let (magnitude, exponent) = decimal_to_binary_parts(self, precision)
      @bin_float.BinFloat::make(
        @bin_float.BinCoeff::from_bytes_be(magnitude.to_octets()),
        exponent,
        precision,
        negative=self.sign() == Sign::Negative,
        mode=bin_mode(mode, self.sign() == Sign::Negative),
      )
    }
  }
}

///|
/// `to_bin_float` in the two directed modes from one conversion: the lower and
/// the upper bound of the value at `precision` bits (equal when it is exact).
fn Decimal::to_bin_float_bounds(
  self : Decimal,
  precision : Int32,
) -> (@bin_float.BinFloat, @bin_float.BinFloat) {
  if self.class != FpClass::Finite || self.coefficient.is_zero() {
    return (
      self.to_bin_float(precision~, mode=RoundingMode::TowardNegative),
      self.to_bin_float(precision~, mode=RoundingMode::TowardPositive),
    )
  }
  match
    (
      decimal_to_bin_float_out_of_range(
        self,
        precision,
        RoundingMode::TowardNegative,
      ),
      decimal_to_bin_float_out_of_range(
        self,
        precision,
        RoundingMode::TowardPositive,
      ),
    ) {
    (Some(lower), Some(upper)) => return (lower, upper)
    _ => ()
  }
  match
    (
      decimal_to_bin_float_directed(
        self,
        precision,
        RoundingMode::TowardNegative,
      ),
      decimal_to_bin_float_directed(
        self,
        precision,
        RoundingMode::TowardPositive,
      ),
    ) {
    (Some(lower), Some(upper)) => return (lower, upper)
    _ => ()
  }
  let (magnitude, exponent) = decimal_to_binary_parts(self, precision)
  let coefficient = @bin_float.BinCoeff::from_bytes_be(magnitude.to_octets())
  let negative = self.sign() == Sign::Negative
  (
    @bin_float.BinFloat::make(
      coefficient,
      exponent,
      precision,
      negative~,
      mode=@bin_float.BinaryRoundingMode::RoundTowardNegative,
    ),
    @bin_float.BinFloat::make(
      coefficient,
      exponent,
      precision,
      negative~,
      mode=@bin_float.BinaryRoundingMode::RoundTowardPositive,
    ),
  )
}

///|
/// The plain `from_bin_float` of a finite non-zero `x` without the exact
/// expansion `c * 5^k` or `c << e2` (the shape that #423 removed from
/// `from_bin_float_ctx`): the digits of the surrogate of
/// `decimal_surrogate_parts` rounded once to `precision` digits, half-even, by
/// the rounding of the plain form. The surrogate keeps the first `precision + 1`
/// digits of `|x|` with a sticky digit and, for an exact value, the member of the
/// cohort closest to exponent 0, so the result is the one of the exact expansion
/// (coefficient, exponent and sign).
fn decimal_from_bin_float_surrogate(
  x : @bin_float.BinFloat,
  precision : Int32,
) -> Decimal {
  let (negative, coefficient, exponent) = decimal_surrogate_parts(x, precision)
  context_free_round_wide(
    negative,
    coefficient,
    exponent.to_int64(),
    precision,
    round_to_precision=true,
    reduce=false,
    mode=DecimalRound::HalfEven,
  )
}

///|
/// Whether the cost of the exact expansion of `x` (it grows with the binary
/// exponent, quadratically for a negative one) is worth avoiding: the exponent
/// is large and the requested precision is small against it (a precision of
/// about the size of the value needs the whole expansion anyway).
fn decimal_from_bin_float_is_bounded(
  x : @bin_float.BinFloat,
  precision : Int32,
) -> Bool {
  let e2 = x.exponent2().to_int64()
  let size = if e2 < 0 { -e2 } else { e2 }
  size > 1024L && precision.to_int64() * 2L <= size
}

///|
pub fn Decimal::from_bin_float(
  x : @bin_float.BinFloat,
  precision~ : Int32 = x.precision(),
) -> Decimal {
  let precision = decimal_check_precision("from_bin_float", precision)
  match x.classify() {
    FpClass::NaN => Decimal::nan(precision~)
    FpClass::Infinity => Decimal::inf(negative=x.is_negative(), precision~)
    FpClass::Finite =>
      // IEEE 754-2019 §5.4.2 and §6.3: conversions keep the sign of zero.
      if x.is_zero() {
        if x.is_negative() {
          Decimal::negative_zero(precision~)
        } else {
          Decimal::zero(precision~)
        }
      } else if decimal_from_bin_float_is_bounded(x, precision) {
        decimal_from_bin_float_surrogate(x, precision)
      } else {
        let coefficient = BigInt::from_octets(x.coefficient().to_bytes_be())
        let signed = if x.is_negative() { -coefficient } else { coefficient }
        if x.exponent2() >= 0 {
          decimal_from_integer_parts(signed << x.exponent2(), 0, precision)
        } else {
          // c * 2^-k = c * 5^k * 10^-k. IEEE 754-2019 §5.4.2: an exact result
          // takes the exponent closest to the preferred exponent 0, so
          // trailing zeros are dropped but never past exponent 0; an inexact
          // one keeps exactly `precision` digits (§5.2).
          let k = -x.exponent2()
          let mut magnitude = coeff_from_bigint(abs_bigint(signed * pow5(k)))
          let mut exponent = -k
          while exponent < 0 {
            let (quotient, remainder) = dec_coeff_div_rem_by_unit_repr(
              magnitude, 10,
            )
            if remainder != 0 {
              break
            }
            magnitude = quotient
            exponent = exponent + 1
          }
          decimal_from_integer_parts(
            if x.is_negative() {
              -coeff_bigint(magnitude)
            } else {
              coeff_bigint(magnitude)
            },
            exponent,
            precision,
          )
        }
      }
  }
}

///|

///|
/// The IEEE 754-2019 attribute of an `@arithmetic` mode for a value of the
/// given sign (`AwayFromZero` is the direction of the sign).
fn bin_mode(
  mode : @def.RoundingMode,
  negative : Bool,
) -> @bin_float.BinaryRoundingMode {
  match mode {
    @def.RoundingMode::ToNearestEven =>
      @bin_float.BinaryRoundingMode::RoundTiesToEven
    @def.RoundingMode::TowardZero =>
      @bin_float.BinaryRoundingMode::RoundTowardZero
    @def.RoundingMode::TowardPositive =>
      @bin_float.BinaryRoundingMode::RoundTowardPositive
    @def.RoundingMode::TowardNegative =>
      @bin_float.BinaryRoundingMode::RoundTowardNegative
    @def.RoundingMode::AwayFromZero =>
      if negative {
        @bin_float.BinaryRoundingMode::RoundTowardNegative
      } else {
        @bin_float.BinaryRoundingMode::RoundTowardPositive
      }
  }
}
