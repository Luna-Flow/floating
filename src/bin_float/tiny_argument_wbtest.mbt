///|
/// The correctly rounded value of a result just above (`above`) or just below
/// the representable `anchor`.
fn tiny_expected(
  anchor : BinFloat,
  above : Bool,
  context : BinaryContext,
) -> BinFloat {
  let toward_anchor = match context.rounding() {
    RoundTiesToEven | RoundTiesToAway => true
    RoundTowardPositive => !above
    RoundTowardNegative => above
    RoundTowardZero => above != anchor.is_negative()
    RoundAwayFromZero => above == anchor.is_negative()
  }
  if toward_anchor {
    anchor
  } else if above {
    anchor.next_up_ctx(context).0
  } else {
    anchor.next_down_ctx(context).0
  }
}

///|
fn tiny_contexts(precision : Int) -> Array[BinaryContext] {
  [RoundTiesToEven, RoundTowardNegative, RoundTowardPositive, RoundTowardZero].map(fn(
      mode,
    ) {
      BinaryContext::unbounded(precision, rounding=mode)
    },
  )
}

///|
test "BinFloat elementary functions certify tiny arguments" {
  let one = BinFloat::one()
  for exponent in [-6000, -20000] {
    for negative in [false, true] {
      let magnitude = BinFloat::make(BinCoeff::one(), exponent, 53)
      let x = if negative { magnitude.neg() } else { magnitude }
      let positive = !negative
      // (name, function, anchor, result above the anchor)
      let cases : Array[
        (
          String,
          (BinFloat, BinaryContext) -> Result[
            (BinFloat, BinaryFlags),
            @def.ArithmeticError,
          ],
          BinFloat,
          Bool,
        ),
      ] = [
        ("sin", fn(a, c) { a.try_sin_ctx(c) }, x, negative),
        ("tan", fn(a, c) { a.try_tan_ctx(c) }, x, positive),
        ("atan", fn(a, c) { a.try_atan_ctx(c) }, x, negative),
        ("asin", fn(a, c) { a.try_asin_ctx(c) }, x, positive),
        ("sinh", fn(a, c) { a.try_sinh_ctx(c) }, x, positive),
        ("tanh", fn(a, c) { a.try_tanh_ctx(c) }, x, negative),
        ("asinh", fn(a, c) { a.try_asinh_ctx(c) }, x, negative),
        ("atanh", fn(a, c) { a.try_atanh_ctx(c) }, x, positive),
        ("expm1", fn(a, c) { a.try_expm1_ctx(c) }, x, true),
        ("log1p", fn(a, c) { a.try_log1p_ctx(c) }, x, false),
        ("atan2", fn(a, c) { a.try_atan2_ctx(one, c) }, x, negative),
        ("exp", fn(a, c) { a.try_exp_ctx(c) }, one, positive),
        ("exp2", fn(a, c) { a.try_exp2_ctx(c) }, one, positive),
        ("exp10", fn(a, c) { a.try_exp10_ctx(c) }, one, positive),
        ("cos", fn(a, c) { a.try_cos_ctx(c) }, one, false),
        ("cosh", fn(a, c) { a.try_cosh_ctx(c) }, one, true),
      ]
      for context in tiny_contexts(53) {
        for case in cases {
          let (name, function, anchor, above) = case
          let label = name + "(" + x.to_hex() + ")"
          guard function(x, context) is Ok((value, flags)) else {
            fail(label + " failed to certify")
          }
          assert_eq(value, tiny_expected(anchor, above, context), msg=label)
          assert_eq(flags.to_testfloat_bits(), 1, msg=label)
        }
      }
    }
  }
  // A normal binary128 argument far below 2^-113.
  let x = BinFloat::make(BinCoeff::one(), -8000, 113)
  for mode in [RoundTiesToEven, RoundTowardNegative, RoundTowardPositive] {
    let context = BinaryContext::binary128(rounding=mode)
    guard x.try_sin_ctx(context) is Ok((value, flags)) else {
      fail("binary128 sin(2^-8000) failed to certify")
    }
    assert_eq(value, tiny_expected(x, false, context))
    assert_true(flags.inexact())
  }
}

///|
test "BinFloat hypot ignores the exponent gap of a negligible operand" {
  let tiny = BinFloat::make(BinCoeff::one(), -600000, 53)
  let three_large = BinFloat::make(BinCoeff::from_uint64(3UL), 100, 53)
  for context in tiny_contexts(53) {
    for
      case in [
        (BinFloat::one(), tiny),
        (tiny.neg(), BinFloat::one()),
        (three_large.neg(), tiny),
      ] {
      let (left, right) = case
      let large = if left.abs() > right.abs() {
        left.abs()
      } else {
        right.abs()
      }
      guard left.try_hypot_ctx(right, context) is Ok((value, flags)) else {
        fail("hypot(" + left.to_hex() + ", " + right.to_hex() + ") failed")
      }
      assert_eq(value, tiny_expected(large, true, context))
      assert_eq(flags.to_testfloat_bits(), 1)
    }
  }
  // Just past the threshold (5 * 2^-70) and just before it (2^-40, the exact
  // sum of squares) the results agree.
  for context in tiny_contexts(53) {
    for
      small in [
        BinFloat::make(BinCoeff::from_uint64(5UL), -70, 53),
        BinFloat::make(BinCoeff::one(), -40, 53),
      ] {
      let (value, flags) = BinFloat::one().hypot_ctx(small, context)
      assert_eq(value, tiny_expected(BinFloat::one(), true, context))
      assert_true(flags.inexact())
    }
  }
}

///|
test "BinFloat exp10 and log10 stay exact past 10^4096" {
  let context = BinaryContext::unbounded(12000)
  let (power, power_flags) = BinFloat::from_int(5000).exp10_ctx(context)
  let expected = BinFloat::make(
    BinCoeff::from_uint64(5UL).pow_nat(5000U),
    5000,
    12000,
  )
  assert_eq(power, expected)
  assert_eq(power_flags, BinaryFlags::new())
  let (logarithm, logarithm_flags) = expected.log10_ctx(context)
  assert_eq(logarithm, BinFloat::from_int(5000, precision=12000))
  assert_eq(logarithm_flags, BinaryFlags::new())
}

///|
test "BinFloat pow certifies tiny exponents" {
  let tiny = BinFloat::make(BinCoeff::one(), -16000, 53)
  let three_tiny = BinFloat::make(BinCoeff::from_uint64(3UL), -20000, 53)
  let half = BinFloat::make(BinCoeff::one(), -1, 53)
  // (base, exponent, result above 1)
  let cases = [
    (BinFloat::from_int(2), tiny, true),
    (BinFloat::from_int(2), tiny.neg(), false),
    (half, tiny, false),
    (BinFloat::from_int(3), three_tiny, true),
    (BinFloat::from_int(3), three_tiny.neg(), false),
  ]
  let contexts = tiny_contexts(53)
  for
    mode in [
      RoundTiesToEven,
      RoundTowardNegative,
      RoundTowardPositive,
      RoundTowardZero,
    ] {
    contexts.push(BinaryContext::binary128(rounding=mode))
  }
  for context in contexts {
    for case in cases {
      let (base, exponent, above) = case
      let label = "pow(" + base.to_hex() + ", " + exponent.to_hex() + ")"
      guard base.try_pow_ctx(exponent, context) is Ok((value, flags)) else {
        fail(label + " failed to certify")
      }
      let one = BinFloat::one(precision=context.precision)
      assert_eq(value, tiny_expected(one, above, context), msg=label)
      assert_eq(flags.to_testfloat_bits(), 1, msg=label)
    }
  }
}
