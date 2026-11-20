///|
/// IEEE 754-2019 §5.4.2 convertFormat between decimal interchange formats:
/// "For conversions between decimal formats, the preferred exponent is
/// Q(source)." The value is rounded once, in the rounding direction of the
/// destination context, to the precision and the exponent range of `format`
/// (decimal32, decimal64 or decimal128 of the interchange formats), with the
/// flags of that rounding: a conversion to a wider format is exact and keeps
/// the quantum of the source (a cohort member is not renormalized), a narrower
/// one is rounded, can overflow, underflow and fold the exponent down
/// (`clamped`). A signaling NaN gives a quiet NaN and the invalid operation
/// exception; the payload of a NaN is kept when the destination holds it
/// (at most `p - 1` digits, §6.2.3) and reduced to its low digits otherwise,
/// the rule of the interchange encoders; the sign of a NaN is kept.
pub fn Decimal::convert_format(
  self : Decimal,
  format : DecimalInterchangeFormat,
) -> (Decimal, DecimalFlags) {
  self.apply_ctx(format.context())
}

///|
/// The number of decimal digits in the adjusted exponent estimate of a binary
/// value `c * 2^e`, from below and above: `floor(log10(2) * bits)` within one.
/// Used only to take a value out of the way of the exponent range, where the
/// result does not depend on the digits.
fn binary_decimal_magnitude(bits : Int64) -> Int64 {
  bits * 30103L / 100000L
}

///|
/// The exact decimal value of a finite nonzero binary float `c * 2^e` with the
/// exponent closest to the preferred exponent 0 (IEEE 754-2019 §5.4.2: "For
/// exact conversions from binary to decimal formats, the preferred exponent is
/// 0"). With `c` odd, `c * 2^-k = c * 5^k * 10^-k` has no trailing zero, and an
/// integer keeps exponent 0.
fn decimal_exact_from_bin_float(x : @bin_float.BinFloat) -> Decimal {
  let mut coefficient = BigInt::from_octets(x.coefficient().to_bytes_be())
  let mut exponent = x.exponent2()
  let zeros = x.coefficient().ctz()
  if zeros > 0 {
    coefficient = coefficient >> zeros
    exponent = exponent + zeros
  }
  let signed = if x.is_negative() { -coefficient } else { coefficient }
  if exponent >= 0 {
    let integer = signed << exponent
    decimal_from_integer_parts(
      integer,
      0,
      abs_bigint(integer).to_string().length(),
    )
  } else {
    let k = -exponent
    decimal_from_integer_parts(
      signed * pow5(k),
      -k,
      (abs_bigint(signed) * pow5(k)).to_string().length(),
    )
  }
}

///|
/// IEEE 754-2019 §5.4.2 convertFormat from a binary format to a decimal
/// format: "If the conversion is to a format in a different radix ... the
/// result shall be rounded as specified in Clause 4"; "For inexact conversions
/// from binary to decimal formats, the preferred exponent is the least
/// possible. For exact conversions from binary to decimal formats, the
/// preferred exponent is 0." The exact value `c * 2^e` is formed as a decimal
/// and rounded once by the context (precision, exponent range, direction),
/// with the flags of that rounding; an exact result keeps the exponent closest
/// to 0 (`0.5` is `5E-1`, `96` is `96`), an inexact one has `p` digits. A value
/// beyond the exponent range, or far below it, overflows or underflows without
/// the digits being formed. The sign of a zero and of a NaN is kept; a
/// signaling NaN gives a quiet NaN and the invalid operation exception; the
/// payload is kept when the destination holds it (§6.2.3). A binary exponent
/// beyond 2^22 in magnitude with a context that does not take the value out of
/// range by itself is outside the work bound of the exact expansion and gives
/// NaN with `invalid_context`.
pub fn Decimal::from_bin_float_ctx(
  x : @bin_float.BinFloat,
  ctx : DecimalContext,
) -> (Decimal, DecimalFlags) {
  match x.classify() {
    FpClass::NaN => {
      let payload = BigInt::from_octets(x.nan_payload().to_bytes_be())
      let value = if x.is_signaling_nan() {
        Decimal::signaling_nan(
          payload~,
          negative=x.is_negative(),
          precision=ctx.precision,
        )
      } else {
        Decimal::quiet_nan(
          payload~,
          negative=x.is_negative(),
          precision=ctx.precision,
        )
      }
      value.apply_ctx(ctx)
    }
    FpClass::Infinity =>
      Decimal::inf(x.sign(), precision=ctx.precision).apply_ctx(ctx)
    FpClass::Finite =>
      if x.is_zero() {
        (if x.is_negative() {
          Decimal::negative_zero(precision=ctx.precision)
        } else {
          Decimal::zero(precision=ctx.precision)
        }).apply_ctx(ctx)
      } else {
        let bits = x.coefficient().bit_length().to_int64() +
          x.exponent2().to_int64()
        let estimate = binary_decimal_magnitude(bits)
        if estimate > ctx.e_max.to_int64() + 2L {
          return decimal_range_marker(x.is_negative(), ctx.e_max + 3).apply_ctx(
            ctx,
          )
        }
        if estimate < etiny(ctx).to_int64() - 3L {
          return decimal_range_marker(x.is_negative(), etiny(ctx) - 3).apply_ctx(
            ctx,
          )
        }
        let exponent = x.exponent2().to_int64()
        if exponent > 4_194_304L || exponent < -4_194_304L {
          return (
            Decimal::nan(precision=ctx.precision),
            invalid_context_flags(),
          )
        }
        decimal_exact_from_bin_float(x).apply_ctx(ctx)
      }
  }
}

///|
/// `+-1E<exponent>`: a value standing for every value beyond the range.
fn decimal_range_marker(negative : Bool, exponent : Int32) -> Decimal {
  finite_with_exponent_repr(negative, dec_coeff_from_int(1), exponent, 1)
}

///|
/// IEEE 754-2019 §5.4.2 convertFormat from a decimal format to a binary
/// format: the exact value `c * 10^q` is rounded once under `context`
/// (precision, exponent range, direction and tininess detection) with the
/// flags of that rounding (inexact, overflow, underflow). A zero keeps its sign
/// and an infinity converts to the infinity. A signaling NaN gives a quiet NaN
/// and the invalid operation exception; the payload of a NaN is kept when the
/// destination holds it (a binary NaN holds `p - 2` bits, §6.2.3) and reduced
/// to its low bits otherwise; the sign of a NaN is kept. The conversion is the
/// one of `BinFloat::from_string_ctx`, which is correctly rounded for any
/// precision and exponent and is checked against MPFR (`mpfr_strtofr`).
pub fn Decimal::to_bin_float_ctx(
  self : Decimal,
  context : @bin_float.BinaryContext,
) -> (@bin_float.BinFloat, @bin_float.BinaryFlags) {
  match self.class {
    FpClass::NaN => {
      let capacity = Int32::max(0, context.precision() - 2)
      let payload = coeff_bigint(self.coefficient)
      let modulus = BigInt::from_int(1) << capacity
      let kept = payload % modulus
      let payload = @bin_float.BinCoeff::from_bytes_be(kept.to_octets())
      let value = if self.signaling_nan {
        @bin_float.BinFloat::signaling_nan(
          payload~,
          negative=self.negative,
          precision=context.precision(),
        )
      } else {
        @bin_float.BinFloat::quiet_nan(
          payload~,
          negative=self.negative,
          precision=context.precision(),
        )
      }
      value.round_ctx(context)
    }
    FpClass::Infinity =>
      (
        @bin_float.BinFloat::inf(self.sign(), precision=context.precision()),
        @bin_float.BinaryFlags::new(),
      )
    FpClass::Finite =>
      if self.coefficient.is_zero() {
        (
          if self.negative {
            @bin_float.BinFloat::negative_zero(precision=context.precision())
          } else {
            @bin_float.BinFloat::zero(precision=context.precision())
          },
          @bin_float.BinaryFlags::new(),
        )
      } else {
        let text = (if self.negative { "-" } else { "" }) +
          coeff_bigint(self.coefficient).to_string() +
          "E" +
          self.exponent10.to_string()
        match @bin_float.BinFloat::from_string_ctx(text, context) {
          Ok(result) => result
          Err(_) =>
            (
              @bin_float.BinFloat::nan(precision=context.precision()),
              @bin_float.BinFloat::signaling_nan(precision=context.precision()).round_ctx(
                context,
              ).1,
            )
        }
      }
  }
}
