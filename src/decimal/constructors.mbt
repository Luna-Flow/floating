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
  Decimal::make(bigint_zero(), 0, precision)
}

///|
pub fn Decimal::negative_zero(precision~ : Int32 = 34) -> Decimal {
  normalize_decimal_parts(
    true,
    bigint_zero(),
    0,
    precision,
    RoundingMode::ToNearestEven,
  )
}

///|
pub fn Decimal::one(precision~ : Int32 = 34) -> Decimal {
  Decimal::make(bigint_one(), 0, precision)
}

///|
pub fn Decimal::inf(sign : Sign, precision~ : Int32 = 34) -> Decimal {
  make_special(
    FpClass::Infinity,
    sign == Sign::Negative,
    bigint_zero(),
    precision,
    false,
  )
}

///|
pub fn Decimal::nan(precision~ : Int32 = 34) -> Decimal {
  make_special(FpClass::NaN, false, bigint_zero(), precision, false)
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
/// `ceil(log2 10 * 10^6)`: `2^(scale * 3.321929) > 10^scale` for `scale >= 1`.
let decimal_log2_10_ceil_ppm : Int64 = 3_321_929L

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
      let (magnitude, exponent) = decimal_to_binary_parts(self, precision)
      @bin_float.BinFloat::make(
        @bin_float.BinCoeff::from_bytes_be(magnitude.to_octets()),
        exponent,
        precision,
        negative=self.sign() == Sign::Negative,
        mode~,
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
  let (magnitude, exponent) = decimal_to_binary_parts(self, precision)
  let coefficient = @bin_float.BinCoeff::from_bytes_be(magnitude.to_octets())
  let negative = self.sign() == Sign::Negative
  (
    @bin_float.BinFloat::make(
      coefficient,
      exponent,
      precision,
      negative~,
      mode=RoundingMode::TowardNegative,
    ),
    @bin_float.BinFloat::make(
      coefficient,
      exponent,
      precision,
      negative~,
      mode=RoundingMode::TowardPositive,
    ),
  )
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
      // IEEE 754-2019 §5.4.2 and §6.3: conversions keep the sign of zero.
      if x.is_zero() {
        if x.is_negative() {
          Decimal::negative_zero(precision~)
        } else {
          Decimal::zero(precision~)
        }
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
