///|
// Public constructors and binary/decimal conversion helpers.

///|
/// The precision a value may carry: GDA 1.70 puts no limit on the length of a
/// coefficient (page 9); the package adopts the decNumber limit, the same as
/// for a context.
let decimal_value_precision_limit : Int32 = 999_999_999

///|
/// The precision of a value made by a constructor, checked where the value is
/// made. A precision outside `1..=999_999_999` aborts and names the function and
/// the argument; there is no silent replacement.
fn decimal_checked_precision(precision : Int32, who : String) -> Int32 {
  guard precision >= 1 && precision <= decimal_value_precision_limit else {
    abort(
      who +
      ": precision must be within 1..=999999999, got " +
      precision.to_string(),
    )
  }
  precision
}

///|
/// GDA 1.70 (page 11): the payload of a NaN is zero or a positive integer no
/// larger than the coefficient can represent less one digit, so at most
/// `precision - 1` digits. A negative payload or one that is too wide aborts.
fn decimal_checked_payload(
  payload : BigInt,
  precision : Int32,
  who : String,
) -> BigInt {
  guard payload >= bigint_zero() else {
    abort(who + ": the NaN payload must not be negative")
  }
  let digits = coeff_from_bigint(payload).digits10()
  guard payload.is_zero() || digits <= precision - 1 else {
    abort(
      who +
      ": the NaN payload has " +
      digits.to_string() +
      " digits, at most precision - 1 = " +
      (precision - 1).to_string() +
      " fit (GDA 1.70, page 11)",
    )
  }
  payload
}

///|
pub fn Decimal::zero(precision~ : Int32 = 34) -> Decimal {
  Decimal::zero_raw(
    precision=decimal_checked_precision(precision, "Decimal::zero"),
  )
}

///|
pub fn Decimal::negative_zero(precision~ : Int32 = 34) -> Decimal {
  Decimal::negative_zero_raw(
    precision=decimal_checked_precision(precision, "Decimal::negative_zero"),
  )
}

///|
pub fn Decimal::one(precision~ : Int32 = 34) -> Decimal {
  Decimal::one_raw(
    precision=decimal_checked_precision(precision, "Decimal::one"),
  )
}

///|
pub fn Decimal::inf(
  negative~ : Bool = false,
  precision~ : Int32 = 34,
) -> Decimal {
  Decimal::inf_with_sign(
    if negative {
      Sign::Negative
    } else {
      Sign::Positive
    },
    precision=decimal_checked_precision(precision, "Decimal::inf"),
  )
}

///|
pub fn Decimal::nan(precision~ : Int32 = 34) -> Decimal {
  Decimal::nan_raw(
    precision=decimal_checked_precision(precision, "Decimal::nan"),
  )
}

///|
pub fn Decimal::quiet_nan(
  payload~ : BigInt = bigint_zero(),
  negative~ : Bool = false,
  precision~ : Int32 = 34,
) -> Decimal {
  let precision = decimal_checked_precision(precision, "Decimal::quiet_nan")
  Decimal::quiet_nan_raw(
    payload=decimal_checked_payload(payload, precision, "Decimal::quiet_nan"),
    negative~,
    precision~,
  )
}

///|
pub fn Decimal::signaling_nan(
  payload~ : BigInt = bigint_zero(),
  negative~ : Bool = false,
  precision~ : Int32 = 34,
) -> Decimal {
  let precision = decimal_checked_precision(precision, "Decimal::signaling_nan")
  Decimal::signaling_nan_raw(
    payload=decimal_checked_payload(
      payload, precision, "Decimal::signaling_nan",
    ),
    negative~,
    precision~,
  )
}

///|
pub fn Decimal::from_int(n : Int32, precision~ : Int32 = 34) -> Decimal {
  Decimal::from_int_raw(
    n,
    precision=decimal_checked_precision(precision, "Decimal::from_int"),
  )
}

///|
pub fn Decimal::from_bigint(n : BigInt, precision~ : Int32 = 34) -> Decimal {
  Decimal::from_bigint_raw(
    n,
    precision=decimal_checked_precision(precision, "Decimal::from_bigint"),
  )
}

///|
/// The decimal value of the binary64 `x`: the exact binary value rounded once,
/// half to even, to `precision` digits (default 34). A value that fits keeps the
/// exponent closest to 0. NaN gives the quiet NaN, an infinity and a zero keep
/// their sign.
pub fn Decimal::from_double(x : Double, precision~ : Int32 = 34) -> Decimal {
  Decimal::from_double_raw(
    x,
    precision=decimal_checked_precision(precision, "Decimal::from_double"),
  )
}

///|
pub fn Decimal::from_float(x : Float, precision~ : Int32 = 34) -> Decimal {
  Decimal::from_float_raw(
    x,
    precision=decimal_checked_precision(precision, "Decimal::from_float"),
  )
}

///|
/// `coefficient * 10^exponent10` as a value of `precision` digits (GDA 1.70
/// to-number, page 21): the exponent is kept when the coefficient has at most
/// `precision` digits, so `make(1200, 0, 34)` is `1200` and `make(0, 5, 5)` is
/// `0E+5`; a longer coefficient is rounded once, in `mode`, to `precision`
/// digits (`make(1000000, 0, 3)` is `1.00E+6`) and the rounded coefficient is not
/// reduced. `reduce`, `trim` and `Decimal::normalized` strip trailing zeros.
pub fn Decimal::make(
  coefficient : BigInt,
  exponent10 : Int32,
  precision : Int32,
  mode~ : GdaRoundingMode = GdaRoundingMode::HalfEven,
) -> Decimal {
  let precision = decimal_checked_precision(precision, "Decimal::make")
  let magnitude = coeff_from_bigint(abs_bigint(coefficient))
  if magnitude.is_zero() {
    return finite_with_exponent_repr(false, magnitude, exponent10, precision)
  }
  context_free_round_wide(
    coefficient < bigint_zero(),
    magnitude,
    exponent10.to_int64(),
    precision,
    round_to_precision=true,
    reduce=false,
    mode=decimal_rounding(mode),
  )
}

///|
/// The value with `precision` digits of coefficient, rounded in `mode`.
pub fn Decimal::with_precision(
  self : Decimal,
  precision : Int32,
  mode : GdaRoundingMode,
) -> Decimal {
  self.with_precision_decimal_mode(
    decimal_checked_precision(precision, "Decimal::with_precision"),
    decimal_rounding(mode),
  )
}

///|
/// The binary value nearest to `self` in `mode` (IEEE 754-2019 4.3.1, the rounding
/// attributes of the radix of the result), with `precision` bits. The precision
/// is required and counts bits, from 1 to `@bin_float.binary_precision_max`;
/// outside that range the call aborts.
pub fn Decimal::to_bin_float(
  self : Decimal,
  precision~ : Int32,
  mode~ : @bin_float.BinaryRoundingMode = @bin_float.BinaryRoundingMode::RoundTiesToEven,
) -> @bin_float.BinFloat {
  guard precision >= 1 && precision <= @bin_float.binary_precision_max else {
    abort(
      "Decimal::to_bin_float: precision must be within 1.." +
      @bin_float.binary_precision_max.to_string() +
      " bits, got " +
      precision.to_string(),
    )
  }
  self.to_bin_float_raw(precision~, mode~)
}

///|
/// The decimal value of a binary one, rounded to `precision` decimal digits in
/// `mode`. The precision is required and counts digits.
pub fn Decimal::from_bin_float(
  x : @bin_float.BinFloat,
  precision~ : Int32,
  mode~ : GdaRoundingMode = GdaRoundingMode::HalfEven,
) -> Decimal {
  Decimal::from_bin_float_raw(
    x,
    precision=decimal_checked_precision(precision, "Decimal::from_bin_float"),
    mode=decimal_rounding(mode),
  )
}

///|
fn Decimal::zero_raw(precision~ : Int32 = 34) -> Decimal {
  finite_with_exponent_repr(
    false,
    dec_coeff_zero(),
    0,
    Int32::max(1, precision),
  )
}

///|
fn Decimal::negative_zero_raw(precision~ : Int32 = 34) -> Decimal {
  finite_with_exponent_repr(true, dec_coeff_zero(), 0, Int32::max(1, precision))
}

///|
fn Decimal::one_raw(precision~ : Int32 = 34) -> Decimal {
  finite_with_exponent_repr(
    false,
    dec_coeff_from_int(1),
    0,
    Int32::max(1, precision),
  )
}

///|
fn Decimal::inf_with_sign(sign : Sign, precision~ : Int32 = 34) -> Decimal {
  make_special_repr(
    FpClass::Infinity,
    sign == Sign::Negative,
    dec_coeff_zero(),
    precision,
    false,
  )
}

///|
fn Decimal::nan_raw(precision~ : Int32 = 34) -> Decimal {
  make_special_repr(FpClass::NaN, false, dec_coeff_zero(), precision, false)
}

///|
fn Decimal::quiet_nan_raw(
  payload~ : BigInt = bigint_zero(),
  negative~ : Bool = false,
  precision~ : Int32 = 34,
) -> Decimal {
  make_special(FpClass::NaN, negative, payload, precision, false)
}

///|
fn Decimal::signaling_nan_raw(
  payload~ : BigInt = bigint_zero(),
  negative~ : Bool = false,
  precision~ : Int32 = 34,
) -> Decimal {
  make_special(FpClass::NaN, negative, payload, precision, true)
}

///|
fn Decimal::from_int_raw(n : Int32, precision~ : Int32 = 34) -> Decimal {
  Decimal::from_bigint_raw(BigInt::from_int(n), precision~)
}

///|
fn Decimal::from_bigint_raw(n : BigInt, precision~ : Int32 = 34) -> Decimal {
  decimal_from_integer_parts(n, 0, precision)
}

///|
/// An integer of at most `precision` digits keeps `exponent10` (its cohort is
/// not reduced, as in the General Decimal Arithmetic to-number conversion); a
/// longer one is rounded half-even to exactly `precision` digits, and a carry
/// into `10^p` leaves `10^(p-1)` at the next exponent.
fn decimal_from_integer_parts(
  value : BigInt,
  exponent10 : Int32,
  precision : Int32,
  mode~ : DecimalRoundingMode = DecimalRoundingMode::HalfEven,
) -> Decimal {
  let negative = value < bigint_zero()
  let magnitude = coeff_from_bigint(abs_bigint(value))
  let precision = Int32::max(1, precision)
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
    mode~,
  )
}

///|
fn Decimal::from_double_raw(x : Double, precision~ : Int32 = 34) -> Decimal {
  let precision = Int32::max(1, precision)
  let bits = x.reinterpret_as_uint64()
  let negative = bits >> 63 != 0UL
  let exponent_bits = ((bits >> 52) & 0x7ffUL).to_int()
  let fraction_bits = bits & 0x000f_ffff_ffff_ffffUL
  if exponent_bits == 0x7ff && fraction_bits != 0UL {
    return Decimal::quiet_nan_raw(negative~, precision~)
  }
  if exponent_bits == 0 && fraction_bits == 0UL {
    return if negative {
      Decimal::negative_zero_raw(precision~)
    } else {
      Decimal::zero_raw(precision~)
    }
  }
  let bin = @bin_float.BinFloat::from_double(x, precision=53)
  match bin.classify() {
    FpClass::NaN => Decimal::nan_raw(precision~)
    FpClass::Infinity => Decimal::inf_with_sign(bin.sign(), precision~)
    FpClass::Finite => Decimal::from_bin_float_raw(bin, precision~)
  }
}

///|
fn Decimal::from_float_raw(x : Float, precision~ : Int32 = 34) -> Decimal {
  Decimal::from_double_raw(x.to_double(), precision~)
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
  binary_mode : @bin_float.BinaryRoundingMode,
) -> @bin_float.BinFloat? {
  // ties-to-away rounds like ties-to-even where nothing but the direction of
  // an overflow or underflow is decided
  let mode = binary_mode.to_arithmetic().unwrap_or(RoundingMode::ToNearestEven)
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
/// The exponent magnitude from which `to_bin_float` converts through the exact
/// decimal parser of `bin_float` instead of forming `5^e` or `10^scale` (#468).
let decimal_parser_conversion_exponent : Int32 = 4096

///|
/// `to_bin_float` of a finite non-zero `value` through `BinFloat::from_string_ctx`,
/// the exact decimal conversion of `bin_float` (correctly rounded for any precision
/// and exponent, checked against MPFR), whose cost does not grow with the decimal
/// exponent. `None` when the precision is outside the binary range (the caller
/// then takes the expansion, which reports it as before).
fn decimal_to_bin_float_through_parser(
  value : Decimal,
  precision : Int32,
  mode : @bin_float.BinaryRoundingMode,
) -> @bin_float.BinFloat? {
  guard precision > 0 && precision <= @bin_float.binary_precision_max else {
    return None
  }
  let text = (if value.negative { "-" } else { "" }) +
    coeff_bigint(value.coefficient).to_string() +
    "E" +
    value.exponent10.to_string()
  match
    @bin_float.BinFloat::from_string_ctx(
      text,
      @bin_float.BinaryContext::new(precision~, rounding=mode),
    ) {
    Ok((result, _)) => Some(result)
    Err(_) => None
  }
}

///|
/// `BinFloat::make` in a rounding mode of IEEE 754-2019 4.3.
fn decimal_bin_float_make(
  coefficient : @bin_float.BinCoeff,
  exponent2 : Int32,
  precision : Int32,
  negative : Bool,
  mode : @bin_float.BinaryRoundingMode,
) -> @bin_float.BinFloat {
  @bin_float.BinFloat::make(coefficient, exponent2, precision, negative~, mode~)
}

///|
fn Decimal::to_bin_float_raw(
  self : Decimal,
  precision~ : Int32 = self.precision_,
  mode~ : @bin_float.BinaryRoundingMode = @bin_float.BinaryRoundingMode::RoundTiesToEven,
) -> @bin_float.BinFloat {
  match self.class {
    FpClass::NaN => @bin_float.BinFloat::nan(precision~)
    FpClass::Infinity => @bin_float.BinFloat::inf(self.sign(), precision~)
    FpClass::Finite => {
      if self.coefficient.is_zero() {
        return @bin_float.BinFloat::zero(precision~)
      }
      match decimal_to_bin_float_out_of_range(self, precision, mode) {
        Some(result) => return result
        None => ()
      }
      if self.exponent10 >= decimal_parser_conversion_exponent ||
        self.exponent10 <= -decimal_parser_conversion_exponent {
        match decimal_to_bin_float_through_parser(self, precision, mode) {
          Some(result) => return result
          None => ()
        }
      }
      if self.exponent10 >= 0 {
        let magnitude = coeff_bigint(self.coefficient) * pow5(self.exponent10)
        return decimal_bin_float_make(
          @bin_float.BinCoeff::from_bytes_be(magnitude.to_octets()),
          self.exponent10,
          precision,
          self.negative,
          mode,
        )
      }
      let scale = -self.exponent10
      // 10^scale < 2^(4 * scale), so the quotient keeps at least precision + 3
      // bits. Truncating it and setting its last bit when the division is
      // inexact (round to odd) leaves two bits below the target position and a
      // sticky bit, so BinFloat::make rounds the exact value once, in every
      // mode; rounding the quotient in the target mode first would round a
      // value just above a binary midpoint onto it, and ties-to-even would
      // then go the wrong way.
      let binary_shift = precision + scale * 4 + 2
      let numerator = abs_bigint(coeff_bigint(self.coefficient)) << binary_shift
      let denominator = pow10(scale)
      let truncated = numerator / denominator
      let q = if (numerator % denominator).is_zero() {
        truncated
      } else {
        truncated | bigint_one()
      }
      decimal_bin_float_make(
        @bin_float.BinCoeff::from_bytes_be(q.to_octets()),
        -binary_shift,
        precision,
        self.sign() == Sign::Negative,
        mode,
      )
    }
  }
}

///|
/// The sign, coefficient and exponent of the surrogate of a finite non-zero `x`
/// at a precision of `precision` digits: the first `precision + 1` correctly
/// rounded (truncated) digits of `|x|` from `BinFloat::to_decimal_string_ctx`,
/// with a sticky digit `1` appended when digits were dropped; for an exact value
/// the trailing zeros are dropped and the member of the cohort closest to
/// exponent 0 is kept. A private copy of `decimal_surrogate_parts` of `decimal`
/// (the two packages share no code outside the internal kernel).
fn decimal_surrogate_parts(
  x : @bin_float.BinFloat,
  precision : Int32,
) -> (Bool, DecCoeff, Int32) {
  let digits = precision + 1
  let (text, flags) = x.to_decimal_string_ctx(
    digits,
    @bin_float.BinaryContext::new(
      precision=53,
      rounding=@bin_float.BinaryRoundingMode::RoundTowardZero,
    ),
  )
  let sticky = flags.inexact()
  let negative = text[0] == '-'
  let body = if negative { text[1:].to_owned() } else { text }
  // d.ddd...e+x
  let split = body.find("e").unwrap()
  let mantissa = body[0:split].to_owned()
  let exponent_text = body[split + 1:].to_owned()
  let magnitude = @string.parse_int(exponent_text[1:]) catch {
    _ => abort("unexpected decimal exponent text \{exponent_text}")
  }
  let leading = if exponent_text[0] == '-' { -magnitude } else { magnitude }
  let mut coefficient = mantissa.replace(old=".", new="")
  let mut exponent = leading - digits + 1
  if sticky {
    coefficient = coefficient + "1"
    exponent = exponent - 1
  } else {
    // exact: drop the trailing zeros, then prefer the exponent 0
    let mut end = coefficient.length()
    while end > 1 && coefficient[end - 1] == '0' {
      end = end - 1
    }
    exponent = exponent + (coefficient.length() - end)
    coefficient = coefficient[0:end].to_owned()
    if exponent > 0 {
      // The member closest to the preferred exponent 0 (IEEE 754-2019 §5.2):
      // exponent 0 when the value fits in `precision` digits. Otherwise zeros
      // are appended up to `precision + 1` digits, and the one `apply_ctx`
      // rounds away is a zero: the `precision`-digit member with the exponent
      // closest to 0, flagged rounded, with no second rounding.
      let pad = Int32::min(exponent, precision + 1 - coefficient.length())
      if pad > 0 {
        coefficient = coefficient + "0".repeat(pad)
        exponent = exponent - pad
      }
    }
  }
  (negative, coeff_from_bigint(bigint_from_text(coefficient)), exponent)
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
  mode : DecimalRoundingMode,
) -> Decimal {
  let (negative, coefficient, exponent) = decimal_surrogate_parts(
    x,
    Int32::max(1, precision),
  )
  context_free_round_wide(
    negative,
    coefficient,
    exponent.to_int64(),
    precision,
    round_to_precision=true,
    reduce=false,
    mode~,
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
  size > 1024L && Int32::max(1, precision).to_int64() * 2L <= size
}

///|
fn Decimal::from_bin_float_raw(
  x : @bin_float.BinFloat,
  precision~ : Int32 = x.precision(),
  mode~ : DecimalRoundingMode = DecimalRoundingMode::HalfEven,
) -> Decimal {
  match x.classify() {
    FpClass::NaN => Decimal::nan_raw(precision~)
    FpClass::Infinity => Decimal::inf_with_sign(x.sign(), precision~)
    FpClass::Finite =>
      if x.is_zero() {
        Decimal::zero_raw(precision~)
      } else if decimal_from_bin_float_is_bounded(x, precision) {
        decimal_from_bin_float_surrogate(x, precision, mode)
      } else {
        let coefficient = BigInt::from_octets(x.coefficient().to_bytes_be())
        let signed = if x.is_negative() { -coefficient } else { coefficient }
        if x.exponent2() >= 0 {
          decimal_from_integer_parts(
            signed << x.exponent2(),
            0,
            precision,
            mode~,
          )
        } else {
          // c * 2^-k = c * 5^k * 10^-k; an exact result takes the exponent
          // closest to 0, so trailing zeros go but never past exponent 0.
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
            mode~,
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
