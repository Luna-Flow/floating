///|
/// The correctly rounded value of a result just above (`above`) or just below
/// the representable `anchor`.
fn tiny_expected(
  anchor : Binary,
  above : Bool,
  context : BinaryContext,
) -> Binary {
  let toward_anchor = match context.rounding() {
    RoundTiesToEven | RoundTiesToAway => true
    RoundTowardPositive => !above
    RoundTowardNegative => above
    RoundTowardZero => above != anchor.is_sign_minus()
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
fn tiny_contexts(precision : Int32) -> Array[BinaryContext] {
  [RoundTiesToEven, RoundTowardNegative, RoundTowardPositive, RoundTowardZero].map(fn(
      mode,
    ) {
      BinaryContext::new(precision~, rounding=mode)
    },
  )
}

///|
// oracle: B, S
// source: B: the model of the file, written from the series (sin x = x - x^3/6, tan x = x + x^3/3, atan, asin, sinh, tanh, asinh, atanh, expm1 = x + x^2/2, log1p = x - x^2/2, atan2(x, 1), exp, exp2, exp10, cos, cosh near 1): for |x| = 2^-6000 and 2^-20000 the exact result lies just above or just below the anchor (x or 1), and the direction rule of tiny_expected: a result just above or just below a representable anchor is the anchor in nearest, toward the anchor otherwise as the direction decides, and the next neighbour of the anchor on the other side, with inexact; S: the neighbour is made with next_up_ctx and next_down_ctx, whose level A walk (next_wbtest.mbt) covers the binary64 grid and a binary32 operand, not the precision 113 of the closing binary128 sin(2^-8000) check
// shares: Binary::make_coeff and one build the operands; tiny_expected builds the expected values with next_up_ctx and next_down_ctx; the try_*_ctx functions are the code under test
// primitives: Binary::next_up_ctx and next_down_ctx (level A through next_wbtest.mbt for the binary64 grid; precision 113 is not covered), Binary::make_coeff
test "Binary elementary functions certify tiny arguments" {
  let one = Binary::one()
  for exponent in [-6000, -20000] {
    for negative in [false, true] {
      let magnitude = Binary::make_coeff(Coeff::one(), exponent, 53)
      let x = if negative { magnitude.neg() } else { magnitude }
      let positive = !negative
      // (name, function, anchor, result above the anchor)
      let cases : Array[
        (
          String,
          (Binary, BinaryContext) -> Result[
            (Binary, BinaryFlags),
            @def.ArithmeticError,
          ],
          Binary,
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
          assert_identical(
            value,
            tiny_expected(anchor, above, context),
            msg=label,
          )
          assert_eq(flags.to_testfloat_bits(), 1, msg=label)
        }
      }
    }
  }
  // A normal binary128 argument far below 2^-113.
  let x = Binary::make_coeff(Coeff::one(), -8000, 113)
  for mode in [RoundTiesToEven, RoundTowardNegative, RoundTowardPositive] {
    let context = BinaryContext::binary128(rounding=mode)
    guard x.try_sin_ctx(context) is Ok((value, flags)) else {
      fail("binary128 sin(2^-8000) failed to certify")
    }
    assert_identical(value, tiny_expected(x, false, context))
    assert_true(flags.inexact())
  }
}

///|
// oracle: B
// source: the model of the file: hypot(L, s) with a negligible s is L (1 + s^2 / (2 L^2)), just above L, so the direction rule of tiny_expected: a result just above or just below a representable anchor is the anchor in nearest, toward the anchor otherwise as the direction decides, and the next neighbour of the anchor on the other side, with inexact; s = 2^-600000 and the thresholds 5 * 2^-70 and 2^-40 against L = 1 and 3 * 2^100, precision 53, four directions
// shares: Binary::make_coeff, one and neg build the operands; tiny_expected builds the expected values with next_up_ctx; try_hypot_ctx and hypot_ctx are the code under test
// primitives: Binary::next_up_ctx (level A through next_wbtest.mbt, the binary64 grid; the contexts here have precision 53), Binary::make_coeff
test "Binary hypot ignores the exponent gap of a negligible operand" {
  let tiny = Binary::make_coeff(Coeff::one(), -600000, 53)
  let three_large = Binary::make_coeff(Coeff::from_uint64(3UL), 100, 53)
  for context in tiny_contexts(53) {
    for
      case in [
        (Binary::one(), tiny),
        (tiny.neg(), Binary::one()),
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
      assert_identical(value, tiny_expected(large, true, context))
      assert_eq(flags.to_testfloat_bits(), 1)
    }
  }
  // Just past the threshold (5 * 2^-70) and just before it (2^-40, the exact
  // sum of squares) the results agree.
  for context in tiny_contexts(53) {
    for
      small in [
        Binary::make_coeff(Coeff::from_uint64(5UL), -70, 53),
        Binary::make_coeff(Coeff::one(), -40, 53),
      ] {
      let (value, flags) = Binary::one().hypot_ctx(small, context)
      assert_identical(value, tiny_expected(Binary::one(), true, context))
      assert_true(flags.inexact())
    }
  }
}

///|
// oracle: S
// source: the written identity 10^5000 = 5^5000 * 2^5000 and log10(10^5000) = 5000, exact with no flag at precision 12000; the coefficient 5^5000 is built with Coeff::pow_nat, which the code under test may use as well, so no independent value is stated and the level is S
// shares: Coeff::pow_nat, Binary::make_coeff and from_int on the reference side; exp10_ctx and log10_ctx are the code under test
test "Binary exp10 and log10 stay exact past 10^4096" {
  let context = BinaryContext::new(precision=12000)
  let (power, power_flags) = Binary::from_int(5000).exp10_ctx(context)
  let expected = Binary::make_coeff(
    Coeff::from_uint64(5UL).pow_nat(5000U),
    5000,
    12000,
  )
  assert_identical(power, expected)
  assert_eq(power_flags, BinaryFlags::new())
  let (logarithm, logarithm_flags) = expected.log10_ctx(context)
  assert_identical(logarithm, Binary::from_int(5000, precision=12000))
  assert_eq(logarithm_flags, BinaryFlags::new())
}

///|
// oracle: B, S
// source: B: x^e for e = 2^-16000 and 3 * 2^-20000 (and the negatives) is 1 + e ln x, just above 1 for x > 1 and e > 0 and just below it for x = 1/2: the direction rule of tiny_expected: a result just above or just below a representable anchor is the anchor in nearest, toward the anchor otherwise as the direction decides, and the next neighbour of the anchor on the other side, with inexact; S: the neighbour is made with next_up_ctx and next_down_ctx, whose level A walk covers the binary64 grid, not the precision 113 of the binary128 contexts used here
// shares: Binary::make_coeff, from_int and one build the operands; tiny_expected builds the expected values; try_pow_ctx is the code under test
// primitives: Binary::next_up_ctx and next_down_ctx (level A through next_wbtest.mbt for the binary64 grid; precision 113 is not covered), Binary::make_coeff
test "Binary pow certifies tiny exponents" {
  let tiny = Binary::make_coeff(Coeff::one(), -16000, 53)
  let three_tiny = Binary::make_coeff(Coeff::from_uint64(3UL), -20000, 53)
  let half = Binary::make_coeff(Coeff::one(), -1, 53)
  // (base, exponent, result above 1)
  let cases = [
    (Binary::from_int(2), tiny, true),
    (Binary::from_int(2), tiny.neg(), false),
    (half, tiny, false),
    (Binary::from_int(3), three_tiny, true),
    (Binary::from_int(3), three_tiny.neg(), false),
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
      let one = Binary::one(precision=context.precision)
      assert_identical(value, tiny_expected(one, above, context), msg=label)
      assert_eq(flags.to_testfloat_bits(), 1, msg=label)
    }
  }
}
