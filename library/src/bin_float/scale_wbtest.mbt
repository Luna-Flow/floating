///|
fn scale_show(result : (BinFloat, BinaryFlags)) -> String {
  "\{result.0} flags=\{result.1.to_testfloat_bits()}"
}

///|
test "scaleB rounds once with range handling" {
  let context = BinaryContext::binary64()
  let three = BinFloat::from_int(3)
  inspect(
    scale_show(three.scaleb_ctx(BinFloat::from_int(10), context)),
    content=(
      #|3p10 flags=0
    ),
  )
  inspect(
    scale_show(three.scaleb_ctx(BinFloat::from_int(1023), context)),
    content=(
      #|inf flags=5
    ),
  )
  inspect(
    scale_show(three.scaleb_ctx(BinFloat::from_int(-1074), context)),
    content=(
      #|3p-1074 flags=0
    ),
  )
  inspect(
    scale_show(three.scaleb_ctx(BinFloat::from_int(-1076), context)),
    content=(
      #|1p-1074 flags=3
    ),
  )
  inspect(
    scale_show(three.scaleb_ctx(BinFloat::from_int(2147483647), context)),
    content=(
      #|inf flags=5
    ),
  )
  inspect(
    scale_show(
      three.neg().scaleb_ctx(BinFloat::from_int(-2147483647 - 1), context),
    ),
    content=(
      #|-0 flags=3
    ),
  )
  inspect(
    scale_show(
      BinFloat::negative_zero().scaleb_ctx(BinFloat::from_int(5), context),
    ),
    content=(
      #|-0 flags=0
    ),
  )
}

///|
test "logB returns the leading-bit exponent" {
  let context = BinaryContext::binary64()
  inspect(
    scale_show(BinFloat::from_double(10.0).logb_ctx(context)),
    content=(
      #|3p0 flags=0
    ),
  )
  inspect(
    scale_show(BinFloat::from_double(0.75).logb_ctx(context)),
    content=(
      #|-1p0 flags=0
    ),
  )
  inspect(
    scale_show(BinFloat::from_double(-1.0).logb_ctx(context)),
    content=(
      #|0 flags=0
    ),
  )
  inspect(
    scale_show(BinFloat::make(BinCoeff::one(), -1074, 53).logb_ctx(context)),
    content=(
      #|-537p1 flags=0
    ),
  )
  inspect(
    scale_show(BinFloat::zero().logb_ctx(context)),
    content=(
      #|-inf flags=8
    ),
  )
  inspect(
    scale_show(BinFloat::inf(Sign::Negative).logb_ctx(context)),
    content=(
      #|inf flags=0
    ),
  )
}

///|
/// The count is a floating-point integer: a NaN propagates, an infinite or
/// non-integer count is an invalid operation, a huge integer count overflows or
/// underflows like the largest count would.
test "scaleB takes its count as a floating-point integer" {
  let context = BinaryContext::binary64()
  let three = BinFloat::from_int(3)
  let half = BinFloat::from_int(1).scaleb_ctx(BinFloat::from_int(-1), context).0
  inspect(half.to_string(), content="1p-1")
  inspect(
    scale_show(three.scaleb_ctx(BinFloat::from_int(4), context)),
    content=(
      #|3p4 flags=0
    ),
  )
  // NaN count: quiet NaN, no flag; signaling NaN count: invalid operation
  let (quiet, quiet_flags) = three.scaleb_ctx(BinFloat::quiet_nan(), context)
  assert_true(quiet.is_quiet_nan())
  assert_eq(quiet_flags.to_testfloat_bits(), 0)
  let (signaled, signaled_flags) = three.scaleb_ctx(
    BinFloat::signaling_nan(),
    context,
  )
  assert_true(signaled.is_quiet_nan())
  assert_eq(signaled_flags.to_testfloat_bits(), 16)
  // an infinite or a non-integer count is invalid, for a zero receiver too
  for
    count in [
      BinFloat::inf(Sign::Positive),
      BinFloat::inf(Sign::Negative),
      half,
    ] {
    for receiver in [three, BinFloat::zero()] {
      let (nan, flags) = receiver.scaleb_ctx(count, context)
      assert_true(nan.is_nan())
      assert_eq(flags.to_testfloat_bits(), 16)
    }
  }
  // a count beyond the Int32 range behaves as the clamped count
  let wide = BinaryContext::new(precision=200)
  let huge = BinFloat::from_int(1).scaleb_ctx(BinFloat::from_int(100), wide).0
  assert_true(huge.is_finite())
  inspect(scale_show(three.scaleb_ctx(huge, context)), content="inf flags=5")
  inspect(
    scale_show(three.scaleb_ctx(huge.neg(), context)),
    content="0 flags=3",
  )
  // an infinite receiver and a finite count: the infinity itself
  inspect(
    scale_show(
      BinFloat::inf(Sign::Positive).scaleb_ctx(BinFloat::from_int(7), context),
    ),
    content="inf flags=0",
  )
}
