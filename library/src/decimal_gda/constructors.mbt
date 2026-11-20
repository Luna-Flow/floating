///|
// Public constructors and binary/decimal conversion helpers.

pub fn Decimal::make(
  coefficient : BigInt,
  exponent10 : Int32,
  precision : Int32,
  mode~ : RoundingMode = RoundingMode::ToNearestEven,
) -> Decimal {
  normalize_decimal(coefficient, exponent10, precision, mode)
}

///|
pub fn Decimal::zero(precision~ : Int32 = 34) -> Decimal {
  finite_with_exponent_repr(
    false,
    dec_coeff_zero(),
    0,
    Int32::max(1, precision),
  )
}

///|
pub fn Decimal::negative_zero(precision~ : Int32 = 34) -> Decimal {
  finite_with_exponent_repr(true, dec_coeff_zero(), 0, Int32::max(1, precision))
}

///|
pub fn Decimal::one(precision~ : Int32 = 34) -> Decimal {
  finite_with_exponent_repr(
    false,
    dec_coeff_from_int(1),
    0,
    Int32::max(1, precision),
  )
}

///|
pub fn Decimal::inf(sign : Sign, precision~ : Int32 = 34) -> Decimal {
  make_special_repr(
    FpClass::Infinity,
    sign == Sign::Negative,
    dec_coeff_zero(),
    precision,
    false,
  )
}

///|
pub fn Decimal::nan(precision~ : Int32 = 34) -> Decimal {
  make_special_repr(FpClass::NaN, false, dec_coeff_zero(), precision, false)
}

///|
pub fn Decimal::quiet_nan(
  payload~ : BigInt = bigint_zero(),
  negative~ : Bool = false,
  precision~ : Int32 = 34,
) -> Decimal {
  make_special(FpClass::NaN, negative, payload, precision, false)
}

///|
pub fn Decimal::signaling_nan(
  payload~ : BigInt = bigint_zero(),
  negative~ : Bool = false,
  precision~ : Int32 = 34,
) -> Decimal {
  make_special(FpClass::NaN, negative, payload, precision, true)
}

///|
pub fn Decimal::from_int(n : Int32, precision~ : Int32 = 34) -> Decimal {
  Decimal::from_bigint(BigInt::from_int(n), precision~)
}

///|
pub fn Decimal::from_bigint(n : BigInt, precision~ : Int32 = 34) -> Decimal {
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
    mode=DecimalRoundingMode::HalfEven,
  )
}

///|
pub fn Decimal::from_double(x : Double, precision~ : Int32 = 34) -> Decimal {
  let precision = Int32::max(1, precision)
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
    FpClass::Infinity => Decimal::inf(bin.sign(), precision~)
    FpClass::Finite => Decimal::from_bin_float(bin, precision~)
  }
}

///|
pub fn Decimal::from_float(x : Float, precision~ : Int32 = 34) -> Decimal {
  Decimal::from_double(x.to_double(), precision~)
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
        mode~,
      ),
    )
  } else if adjusted + 1L < below {
    Some(
      @bin_float.BinFloat::make(
        @bin_float.BinCoeff::one(),
        e_min.to_int() - precision - 8,
        precision,
        negative~,
        mode~,
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
  mode : RoundingMode,
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
      @bin_float.BinaryContext::unbounded(
        precision,
        rounding=@bin_float.BinaryRoundingMode::from_arithmetic(mode),
      ),
    ) {
    Ok((result, _)) => Some(result)
    Err(_) => None
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
        return @bin_float.BinFloat::make(
          @bin_float.BinCoeff::from_bytes_be(magnitude.to_octets()),
          self.exponent10,
          precision,
          negative=self.negative,
          mode~,
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
      @bin_float.BinFloat::make(
        @bin_float.BinCoeff::from_bytes_be(q.to_octets()),
        -binary_shift,
        precision,
        negative=self.sign() == Sign::Negative,
        mode~,
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
    @bin_float.BinaryContext::unbounded(
      53,
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
    mode=DecimalRoundingMode::HalfEven,
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
pub fn Decimal::from_bin_float(
  x : @bin_float.BinFloat,
  precision~ : Int32 = x.precision(),
) -> Decimal {
  match x.classify() {
    FpClass::NaN => Decimal::nan(precision~)
    FpClass::Infinity => Decimal::inf(x.sign(), precision~)
    FpClass::Finite =>
      if x.is_zero() {
        Decimal::zero(precision~)
      } else if decimal_from_bin_float_is_bounded(x, precision) {
        decimal_from_bin_float_surrogate(x, precision)
      } else {
        let coefficient = BigInt::from_octets(x.coefficient().to_bytes_be())
        let signed = if x.is_negative() { -coefficient } else { coefficient }
        if x.exponent2() >= 0 {
          decimal_from_integer_parts(signed << x.exponent2(), 0, precision)
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
          )
        }
      }
  }
}

///|
