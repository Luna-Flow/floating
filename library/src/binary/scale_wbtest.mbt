///|
fn scale_show(result : (Binary, BinaryFlags)) -> String {
  "\{result.0} flags=\{result.1.to_testfloat_bits()}"
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 5.3.3 (scaleB(x, N) = x * 2^N rounded once, scaleB(+-0, N) = +-0), 7.4 and 7.5 in binary64: 3 * 2^10 exact, 3 * 2^1023 overflows (inf, flags 5), 3 * 2^-1074 is exact (3 units of the smallest subnormal), 3 * 2^-1076 rounds to 2^-1074 with underflow and inexact (flags 3), the counts +-2^31 overflow and underflow to -0 with flags 5 and 3
// shares: scale_show prints value and flag bits; Binary::from_int and negative_zero build the operands; scaleb_ctx is the code under test
test "scaleB rounds once with range handling" {
  let context = BinaryContext::binary64()
  let three = Binary::from_int(3)
  inspect(
    scale_show(three.scaleb_ctx(Binary::from_int(10), context)),
    content=(
      #|3p10 flags=0
    ),
  )
  inspect(
    scale_show(three.scaleb_ctx(Binary::from_int(1023), context)),
    content=(
      #|inf flags=5
    ),
  )
  inspect(
    scale_show(three.scaleb_ctx(Binary::from_int(-1074), context)),
    content=(
      #|3p-1074 flags=0
    ),
  )
  inspect(
    scale_show(three.scaleb_ctx(Binary::from_int(-1076), context)),
    content=(
      #|1p-1074 flags=3
    ),
  )
  inspect(
    scale_show(three.scaleb_ctx(Binary::from_int(2147483647), context)),
    content=(
      #|inf flags=5
    ),
  )
  inspect(
    scale_show(
      three.neg().scaleb_ctx(Binary::from_int(-2147483647 - 1), context),
    ),
    content=(
      #|-0 flags=3
    ),
  )
  inspect(
    scale_show(Binary::negative_zero().scaleb_ctx(Binary::from_int(5), context)),
    content=(
      #|-0 flags=0
    ),
  )
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 5.3.3 (logB(x) is the exponent of x, logB(1) = +0, logB(+-inf) = +inf, logB(0) = -inf with divideByZero when the result is a floating-point format): logB(10) = 3, logB(0.75) = -1, logB(-1) = 0, logB(2^-1074) = -1074 (printed -537p1), logB(0) = -inf with flags 8, logB(-inf) = +inf
// shares: scale_show prints value and flag bits; Binary::from_double, make, zero and inf build the operands; logb_ctx is the code under test
test "logB returns the leading-bit exponent" {
  let context = BinaryContext::binary64()
  inspect(
    scale_show(Binary::from_double(10.0).logb_ctx(context)),
    content=(
      #|3p0 flags=0
    ),
  )
  inspect(
    scale_show(Binary::from_double(0.75).logb_ctx(context)),
    content=(
      #|-1p0 flags=0
    ),
  )
  inspect(
    scale_show(Binary::from_double(-1.0).logb_ctx(context)),
    content=(
      #|0 flags=0
    ),
  )
  inspect(
    scale_show(Binary::make(BinCoeff::one(), -1074, 53).logb_ctx(context)),
    content=(
      #|-537p1 flags=0
    ),
  )
  inspect(
    scale_show(Binary::zero().logb_ctx(context)),
    content=(
      #|-inf flags=8
    ),
  )
  inspect(
    scale_show(Binary::inf(negative=true).logb_ctx(context)),
    content=(
      #|inf flags=0
    ),
  )
}

///|
/// The count is a floating-point integer: a NaN propagates, an infinite or
/// non-integer count is an invalid operation, a huge integer count overflows or
/// underflows like the largest count would.

///|
// oracle: A, S
// source: A: written out from IEEE Std 754-2019 5.3.3 and 7.2: scaleB of a NaN count is a quiet NaN, a signaling NaN count is invalid, scaleB(+-inf, N) = +-inf, an overflowing or underflowing integer count gives inf (flags 5) and 0 (flags 3); S: the standard leaves the behaviour for a non-integral second operand language-defined (5.3.3), and the library makes an infinite or non-integer count an invalid operation, as asserted
// shares: scale_show prints value and flag bits; Binary::from_int, inf, nan and signaling_nan build the operands; scaleb_ctx is the code under test
test "scaleB takes its count as a floating-point integer" {
  let context = BinaryContext::binary64()
  let three = Binary::from_int(3)
  let half = Binary::from_int(1).scaleb_ctx(Binary::from_int(-1), context).0
  inspect(half.to_string(), content="1p-1")
  inspect(
    scale_show(three.scaleb_ctx(Binary::from_int(4), context)),
    content=(
      #|3p4 flags=0
    ),
  )
  // NaN count: quiet NaN, no flag; signaling NaN count: invalid operation
  let (quiet, quiet_flags) = three.scaleb_ctx(Binary::quiet_nan(), context)
  assert_true(quiet.is_quiet_nan())
  assert_eq(quiet_flags.to_testfloat_bits(), 0)
  let (signaled, signaled_flags) = three.scaleb_ctx(
    Binary::signaling_nan(),
    context,
  )
  assert_true(signaled.is_quiet_nan())
  assert_eq(signaled_flags.to_testfloat_bits(), 16)
  // an infinite or a non-integer count is invalid, for a zero receiver too
  for count in [Binary::inf(), Binary::inf(negative=true), half] {
    for receiver in [three, Binary::zero()] {
      let (nan, flags) = receiver.scaleb_ctx(count, context)
      assert_true(nan.is_nan())
      assert_eq(flags.to_testfloat_bits(), 16)
    }
  }
  // a count beyond the Int32 range behaves as the clamped count
  let wide = BinaryContext::new(precision=200)
  let huge = Binary::from_int(1).scaleb_ctx(Binary::from_int(100), wide).0
  assert_true(huge.is_finite())
  inspect(scale_show(three.scaleb_ctx(huge, context)), content="inf flags=5")
  inspect(
    scale_show(three.scaleb_ctx(huge.neg(), context)),
    content="0 flags=3",
  )
  // an infinite receiver and a finite count: the infinity itself
  inspect(
    scale_show(Binary::inf().scaleb_ctx(Binary::from_int(7), context)),
    content="inf flags=0",
  )
}
