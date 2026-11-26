// `asinpi`, `acospi`, `atanpi` and `atan2pi` (IEEE 754-2019 9.2, Table 9.1).
//
// Clauses, quoted from the text of IEEE Std 754-2019 (pdftotext of the PDF):
//
//   [Table 9.1] "asinPi asin(x)/π [−1, +1] |x| > 1: invalid operation;
//           underflow", "acosPi acos(x)/π [−1, +1] |x| > 1: invalid operation",
//           "atanPi atan(x)/π [−∞, +∞] underflow", "atan2Pi(y, x) ... underflow".
//   [9.2.1] "For the operations sin, tan, sinPi, tanPi, asin, atan, asinPi,
//           atanPi, ... f (+0) is +0 and f (−0) is −0 with no exception."
//           "acos(1), acosPi(1), and acosh(1) are +0." "atanPi(±∞) is ±½ with
//           no exception." "The range of atan2Pi is [−1, +1]."
//   [9.2.1] "atan2Pi(y, x) for finite x > 0 is atan(|y/x|)/π, which could
//           signal the underflow exception; atan2Pi(y, x) for finite x < 0 is
//           1 − atan(|y/x|)/π." "The special cases of atan2Pi(y, x) involving 0
//           and ∞ are exact constants that signal no exception:
//           atan2Pi(±0, −0) is ±1; atan2Pi(±0, +0) is ±0; atan2Pi(±0, x) is ±1
//           for x < 0; atan2Pi(±0, x) is ±0 for x > 0; atan2Pi(y, ±0) is −½ for
//           y < 0; atan2Pi(y, ±0) is +½ for y > 0; atan2Pi(±y, −∞) is ±1 for
//           finite y > 0; atan2Pi(±y, +∞) is ±0 for finite y > 0;
//           atan2Pi(±∞, x) is ±½ for finite x; atan2Pi(±∞, −∞) is ±¾;
//           atan2Pi(±∞, +∞) is ±¼."
//   [9.2]   "A conforming operation shall return results correctly rounded for
//           the applicable rounding direction for all operands in its domain."
//   [7.5], [7.6] tininess (both detection rules) and inexact.
//
// Models, independent of the implementation. (1) Exact values: by Niven's
// theorem the only rational angles are those of the tables. (2) Near an anchor
// A (±1/2, ±1) the result is A ∓ δ with 0 < δ far below the spacing, so the
// rounding direction alone decides between A and its neighbour on that side
// (`pi_expected_near`). (3) For |x| below 2^-200, asin(x)/π = (x/π)(1 + x²/6 ...)
// and atan(x)/π = (x/π)(1 - x²/3 ...), within 2^-300 of x/π, which is rounded by
// `binary_round_dyadic` from a 450-bit π: no breakpoint lies that close. (4) At
// moderate arguments the result at precision p must equal the result at
// precision p + 150, rounded to p.

///|
fn pi_x(
  numerator : Int32,
  exponent : Int32,
  negative~ : Bool = false,
) -> Binary {
  Binary::make_coeff(
    Coeff::from_uint64(numerator.to_uint64()),
    exponent,
    64,
    negative~,
  )
}

///|
fn pi_inf(negative : Bool) -> Binary {
  Binary::inf(negative~)
}

///|
/// `value flags` (with `V` for invalid_operation and `N` for not_computed, so that a
/// case that signals invalid is told apart from a quiet NaN that propagates), or
/// `err` for an `Err`.
fn pi_show(
  result : Result[(Binary, BinaryFlags), @def.ArithmeticError],
) -> String {
  match result {
    Ok((value, flags)) =>
      "\{value} \{e2s_flags(flags)}\{if flags.invalid_operation() { "V" } else { "" }}\{if flags.not_computed() { "N" } else { "" }}"
    Err(_) => "err"
  }
}

///|
fn pi_contexts() -> Array[BinaryContext] {
  [
    BinaryContext::new(precision=53),
    BinaryContext::new(precision=2),
    BinaryContext::binary64(),
    BinaryContext::new(precision=24, e_max=7),
  ]
}

///|
/// The result next to an anchor of magnitude `anchor` (`1/2` as `(1, -1)`,
/// `1` as `(1, 0)`) of the given sign: the anchor itself, or its neighbour on
/// the side of the exact value (`above` in magnitude), chosen by direction.
fn pi_expected_near(
  anchor_is_half : Bool,
  negative : Bool,
  above : Bool,
  mode : BinaryRoundingMode,
  p : Int32,
) -> String {
  let toward_zero = match mode {
    RoundTowardZero => true
    RoundTowardPositive => negative
    RoundTowardNegative => !negative
    _ => false
  }
  let away = match mode {
    RoundTowardPositive => !negative
    RoundTowardNegative => negative
    _ => false
  }
  let sign = if negative { "-" } else { "" }
  // Below the anchor the neighbour is (2^p - 1) 2^-(p + 1) next to 1/2 and
  // (2^p - 1) 2^-p next to 1; above 1/2 it is (2^(p - 1) + 1) 2^-p.
  if above {
    if away {
      "\{sign}\{(1L << (p - 1)) + 1L}p-\{p}"
    } else if anchor_is_half {
      "\{sign}1p-1"
    } else {
      "\{sign}1p0"
    }
  } else if toward_zero {
    if anchor_is_half {
      "\{sign}\{(1L << p) - 1L}p-\{p + 1}"
    } else {
      "\{sign}\{(1L << p) - 1L}p-\{p}"
    }
  } else if anchor_is_half {
    "\{sign}1p-1"
  } else {
    "\{sign}1p0"
  }
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 9.2.1 and Table 9.1 (the clauses are quoted in the header of this file and were checked against the pdftotext of the PDF): f(+0) = +0 and f(-0) = -0 for asinPi and atanPi, acosPi(1) = +0, acosPi(-1) = 1, acosPi(+-0) = 1/2, asinPi(+-1) = +-1/2 and atanPi(+-1) = +-1/4 (Niven's theorem: the only rational angles), atanPi(+-inf) = +-1/2 without exception, invalid operation for |x| > 1 and for infinities in asinPi and acosPi, NaN propagation and the signaling NaN
// shares: pi_show and e2s_flags print the result (Display of Binary and the flag accessors); Binary::zero, from_int, inf and make_coeff build the operands; the try_ and the plain forms are the code under test
test "asinpi, acospi and atanpi special values" {
  for ctx in pi_contexts() {
    let render = fn(
      f : (Binary) -> Result[(Binary, BinaryFlags), @def.ArithmeticError],
    ) {
      fn(x : Binary) { pi_show(f(x)) }
    }
    let asinpi = render(fn(x) { x.try_asinpi_ctx(ctx) })
    let acospi = render(fn(x) { x.try_acospi_ctx(ctx) })
    let atanpi = render(fn(x) { x.try_atanpi_ctx(ctx) })
    // f(+0) = +0 and f(-0) = -0 with no exception
    assert_eq(asinpi(Binary::zero()), "0 ---")
    assert_eq(asinpi(Binary::negative_zero()), "-0 ---")
    assert_eq(atanpi(Binary::zero()), "0 ---")
    assert_eq(atanpi(Binary::negative_zero()), "-0 ---")
    // asinPi(±1) = ±1/2, exact
    assert_eq(asinpi(Binary::from_int(1)), "1p-1 ---")
    assert_eq(asinpi(Binary::from_int(-1)), "-1p-1 ---")
    // acosPi(1) = +0, acosPi(-1) = 1, acosPi(±0) = 1/2
    assert_eq(acospi(Binary::from_int(1)), "0 ---")
    assert_eq(acospi(Binary::from_int(-1)), "1p0 ---")
    assert_eq(acospi(Binary::zero()), "1p-1 ---")
    assert_eq(acospi(Binary::negative_zero()), "1p-1 ---")
    // atanPi(±inf) = ±1/2 with no exception, atanPi(±1) = ±1/4
    assert_eq(atanpi(pi_inf(false)), "1p-1 ---")
    assert_eq(atanpi(pi_inf(true)), "-1p-1 ---")
    assert_eq(atanpi(Binary::from_int(1)), "1p-2 ---")
    assert_eq(atanpi(Binary::from_int(-1)), "-1p-2 ---")
    // |x| > 1 and infinities are invalid for asinPi and acosPi
    for
      bad in [
        Binary::from_int(2),
        pi_x(5, -2, negative=true),
        pi_inf(false),
        pi_inf(true),
      ] {
      // S4: a domain case is a value in the try_ form (the NaN with invalid_operation)
      assert_eq(asinpi(bad), "nan ---V")
      assert_eq(acospi(bad), "nan ---V")
      let (value, flags) = bad.asinpi_ctx(ctx)
      assert_true(value.is_quiet_nan() && flags.invalid_operation())
      let (value, flags) = bad.acospi_ctx(ctx)
      assert_true(value.is_quiet_nan() && flags.invalid_operation())
    }
    // NaNs: a quiet NaN propagates, a signaling NaN is invalid
    for f in [asinpi, acospi, atanpi] {
      assert_eq(f(Binary::quiet_nan()), "nan ---")
    }
    for pair in [Binary::signaling_nan()] {
      assert_true(pair.asinpi_ctx(ctx).1.invalid_operation())
      assert_true(pair.acospi_ctx(ctx).1.invalid_operation())
      assert_true(pair.atanpi_ctx(ctx).1.invalid_operation())
    }
  }
}

///|
// oracle: A
// source: written out from IEEE Std 754-2019 9.2.1 and Table 9.1 (the clauses are quoted in the header of this file and were checked against the pdftotext of the PDF): atan2Pi(+-0, -0) = +-1, (+-0, +0) = +-0, (+-0, x) = +-1 for x < 0 and +-0 for x > 0, (y, +-0) = +-1/2, (+-y, -inf) = +-1, (+-y, +inf) = +-0, (+-inf, x) = +-1/2, (+-inf, -inf) = +-3/4, (+-inf, +inf) = +-1/4, and |y| = |x| gives the exact angles +-1/4 and +-3/4; NaN propagation
// shares: pi_show and e2s_flags print the result; Binary::zero, negative_zero, from_int, inf and pi_x build the operands; try_atan2pi_ctx is the code under test
test "atan2pi special values" {
  for ctx in pi_contexts() {
    let atan2pi = fn(y : Binary, x : Binary) {
      pi_show(y.try_atan2pi_ctx(x, ctx))
    }
    let zero = Binary::zero()
    let minus_zero = Binary::negative_zero()
    let two = Binary::from_int(2)
    let minus_two = Binary::from_int(-2)
    // atan2Pi(±0, -0) = ±1, (±0, +0) = ±0, (±0, x) = ±1 for x < 0 and ±0 for x > 0
    assert_eq(atan2pi(zero, minus_zero), "1p0 ---")
    assert_eq(atan2pi(minus_zero, minus_zero), "-1p0 ---")
    assert_eq(atan2pi(zero, zero), "0 ---")
    assert_eq(atan2pi(minus_zero, zero), "-0 ---")
    assert_eq(atan2pi(zero, minus_two), "1p0 ---")
    assert_eq(atan2pi(minus_zero, minus_two), "-1p0 ---")
    assert_eq(atan2pi(zero, two), "0 ---")
    assert_eq(atan2pi(minus_zero, two), "-0 ---")
    // atan2Pi(y, ±0) = -1/2 for y < 0 and +1/2 for y > 0
    assert_eq(atan2pi(two, zero), "1p-1 ---")
    assert_eq(atan2pi(two, minus_zero), "1p-1 ---")
    assert_eq(atan2pi(minus_two, zero), "-1p-1 ---")
    assert_eq(atan2pi(minus_two, minus_zero), "-1p-1 ---")
    // atan2Pi(±y, -inf) = ±1 and atan2Pi(±y, +inf) = ±0 for finite y > 0
    assert_eq(atan2pi(two, pi_inf(true)), "1p0 ---")
    assert_eq(atan2pi(minus_two, pi_inf(true)), "-1p0 ---")
    assert_eq(atan2pi(two, pi_inf(false)), "0 ---")
    assert_eq(atan2pi(minus_two, pi_inf(false)), "-0 ---")
    // atan2Pi(±inf, x) = ±1/2 for finite x, (±inf, -inf) = ±3/4, (±inf, +inf) = ±1/4
    assert_eq(atan2pi(pi_inf(false), two), "1p-1 ---")
    assert_eq(atan2pi(pi_inf(true), minus_two), "-1p-1 ---")
    assert_eq(atan2pi(pi_inf(false), zero), "1p-1 ---")
    assert_eq(atan2pi(pi_inf(false), pi_inf(true)), "3p-2 ---")
    assert_eq(atan2pi(pi_inf(true), pi_inf(true)), "-3p-2 ---")
    assert_eq(atan2pi(pi_inf(false), pi_inf(false)), "1p-2 ---")
    assert_eq(atan2pi(pi_inf(true), pi_inf(false)), "-1p-2 ---")
    // |y| = |x|: the exact angles ±1/4 and ±3/4
    assert_eq(atan2pi(pi_x(3, -7), pi_x(3, -7)), "1p-2 ---")
    assert_eq(atan2pi(pi_x(3, -7, negative=true), pi_x(3, -7)), "-1p-2 ---")
    assert_eq(atan2pi(pi_x(3, 40), pi_x(3, 40, negative=true)), "3p-2 ---")
    assert_eq(
      atan2pi(pi_x(3, 40, negative=true), pi_x(3, 40, negative=true)),
      "-3p-2 ---",
    )
    // NaNs
    assert_eq(atan2pi(Binary::quiet_nan(), two), "nan ---")
    assert_eq(atan2pi(two, Binary::quiet_nan()), "nan ---")
    assert_true(
      Binary::signaling_nan().atan2pi_ctx(two, ctx).1.invalid_operation(),
    )
    assert_true(
      two.atan2pi_ctx(Binary::signaling_nan(), ctx).1.invalid_operation(),
    )
  }
}

///|
// oracle: B
// source: asinPi(1/2) = 1/6, acosPi(1/2) = 1/3, acosPi(-1/2) = 2/3 and asinPi(-1/2) = -1/6 (the exact rational angles, Niven's theorem), rounded by dividing the exact small integers with Binary::div_ctx at the same context, precisions 2, 3, 11, 24 and 53 in all five directions, with the inexact flag asserted
// shares: pi_x builds +-1/2; e2s_modes and e2s_flags select the directions and print the flags; Binary::from_int and div_ctx on the reference side
// primitives: Binary::div_ctx and Binary::from_int (level A through arith_rows_wbtest.mbt: precisions from 2 to 4097, five directions, exact and inexact quotients)
test "the rational but non-dyadic angles are correctly rounded" {
  // asinPi(1/2) = 1/6, acosPi(1/2) = 1/3, acosPi(-1/2) = 2/3: rational, not
  // dyadic, so inexact in every mode, never a tie. The reference divides the
  // exact integers.
  let half = pi_x(1, -1)
  let minus_half = pi_x(1, -1, negative=true)
  let mut cases = 0
  for p in [2, 3, 11, 24, 53] {
    for mode in e2s_modes() {
      let ctx = BinaryContext::new(precision=p, rounding=mode)
      let quotient = fn(numerator : Int32, denominator : Int32) {
        Binary::from_int(numerator, precision=p + 100).div_ctx(
          Binary::from_int(denominator, precision=p + 100),
          ctx,
        )
      }
      for
        (value, expected) in [
          (half.asinpi_ctx(ctx), quotient(1, 6)),
          (half.acospi_ctx(ctx), quotient(1, 3)),
          (minus_half.acospi_ctx(ctx), quotient(2, 3)),
          (minus_half.asinpi_ctx(ctx), quotient(-1, 6)),
        ] {
        assert_eq(
          "\{value.0} \{e2s_flags(value.1)}",
          "\{expected.0} \{e2s_flags(expected.1)}",
        )
        assert_true(value.1.inexact())
        cases += 1
      }
    }
  }
  assert_eq(cases, 5 * 5 * 4)
}

///|
// oracle: A
// source: a closed-form model written out in this file, with no library function: atanPi(x) = 1/2 - delta with 0 < delta < 2^-t for |x| = 1.5 * 2^t (t from p + 4 to the implementation limit); the correctly rounded result is then the anchor or its neighbour on the side of the exact value chosen by the direction, which pi_expected_near writes as integer shifts ((2^p - 1) 2^-(p + 1) below 1/2, (2^p - 1) 2^-p below 1, (2^(p - 1) + 1) 2^-p above 1/2); the model is the header's items (1) and (2), checked at precisions 2, 3, 8, 24 and 53 in five directions
// shares: pi_expected_near builds the strings; pi_x, e2s_modes and e2s_flags build the operands and print the result; the asinpi, acospi, atanpi and atan2pi functions are the code under test
test "atanpi of a huge argument sits next to the anchor 1/2" {
  let mut cases = 0
  for p in [2, 3, 8, 24, 53] {
    for mode in e2s_modes() {
      let ctx = BinaryContext::new(precision=p, rounding=mode)
      // |x| = 1.5 * 2^t: atanPi = 1/2 - delta, 0 < delta < 2^-t, from t = p + 4
      // (decided by the Ziv loop) through t = p + 8 (the anchor rule) up to the
      // implementation limit.
      for t in [p + 4, p + 6, p + 7, p + 8, p + 9, p + 30, 1000000, 1073741820] {
        for negative in [false, true] {
          let x = pi_x(3, t - 1, negative~)
          let (value, flags) = x.atanpi_ctx(ctx)
          assert_eq(
            "\{value} \{e2s_flags(flags)}",
            "\{pi_expected_near(true, negative, false, mode, p)} I--",
          )
          cases += 1
        }
      }
    }
  }
  assert_eq(cases, 5 * 5 * 8 * 2)
}

///|
// oracle: A
// source: a closed-form model written out in this file, with no library function: acosPi(x) = 1/2 - asin(x)/pi with 0 < asin(x)/pi < |x|/2, below 1/2 for x > 0 and above it for x < 0; the correctly rounded result is then the anchor or its neighbour on the side of the exact value chosen by the direction, which pi_expected_near writes as integer shifts ((2^p - 1) 2^-(p + 1) below 1/2, (2^p - 1) 2^-p below 1, (2^(p - 1) + 1) 2^-p above 1/2); the model is the header's items (1) and (2), checked at precisions 2, 3, 8, 24 and 53 in five directions
// shares: pi_expected_near builds the strings; pi_x, e2s_modes and e2s_flags build the operands and print the result; the asinpi, acospi, atanpi and atan2pi functions are the code under test
test "acospi of a tiny argument clusters at 1/2" {
  let mut cases = 0
  for p in [2, 3, 8, 24, 53] {
    for mode in e2s_modes() {
      let ctx = BinaryContext::new(precision=p, rounding=mode)
      // acosPi(x) = 1/2 - asin(x)/π with 0 < asin(x)/π < |x|/2: below 1/2 for
      // x > 0 and above it for x < 0.
      for t in [p + 3, p + 4, p + 5, p + 8, 2 * p + 20, 5000, 1073741000] {
        for negative in [false, true] {
          let x = pi_x(3, -t, negative~)
          let (value, flags) = x.acospi_ctx(ctx)
          assert_eq(
            "\{value} \{e2s_flags(flags)}",
            "\{pi_expected_near(true, false, negative, mode, p)} I--",
          )
          cases += 1
        }
      }
    }
  }
  assert_eq(cases, 5 * 5 * 7 * 2)
}

///|
// oracle: A
// source: a closed-form model written out in this file, with no library function: atan2Pi = 1/2 - delta (x > 0) or 1/2 + delta (x < 0) with 0 < delta < 2^-D for a ratio of exponents D >= p + 4, and 1 - delta next to the anchor 1 for the reciprocal ratio with a negative abscissa; the correctly rounded result is then the anchor or its neighbour on the side of the exact value chosen by the direction, which pi_expected_near writes as integer shifts ((2^p - 1) 2^-(p + 1) below 1/2, (2^p - 1) 2^-p below 1, (2^(p - 1) + 1) 2^-p above 1/2); the model is the header's items (1) and (2), checked at precisions 2, 3, 8, 24 and 53 in five directions
// shares: pi_expected_near builds the strings; pi_x, e2s_modes and e2s_flags build the operands and print the result; the asinpi, acospi, atanpi and atan2pi functions are the code under test
test "atan2pi of an extreme ratio sits next to the anchors" {
  let mut cases = 0
  for p in [2, 3, 8, 24, 53] {
    for mode in e2s_modes() {
      let ctx = BinaryContext::new(precision=p, rounding=mode)
      // D = top(y) - top(x) >= p + 4: atan2Pi = 1/2 - delta (x > 0) or 1/2 + delta
      // (x < 0), delta < 2^-D, the sign of y mirrors it. The reciprocal ratio
      // with a negative abscissa gives 1 - delta, delta < 2^-D, next to the
      // anchor 1. The exponents reach the limits of the implementation, where
      // the ratio itself is not representable.
      for
        d in [
          p + 4,
          p + 6,
          p + 8,
          p + 9,
          p + 40,
          100000,
          1073741000,
          2147483000,
        ] {
        for x_negative in [false, true] {
          for y_negative in [false, true] {
            // y = 1.5 * 2^a, x = 1.25 * 2^b with a - b = d, both in range
            let a = d / 2
            let b = a - d
            let y = pi_x(3, a - 1, negative=y_negative)
            let x = pi_x(5, b - 2, negative=x_negative)
            let (value, flags) = y.atan2pi_ctx(x, ctx)
            assert_eq(
              "\{value} \{e2s_flags(flags)}",
              "\{pi_expected_near(true, y_negative, x_negative, mode, p)} I--",
            )
            cases += 1
            // swapped: ordinate x, abscissa y; a negative abscissa gives
            // +-(1 - delta) with the sign of the ordinate
            if y_negative {
              let (swapped, swapped_flags) = x.atan2pi_ctx(y, ctx)
              assert_eq(
                "\{swapped} \{e2s_flags(swapped_flags)}",
                "\{pi_expected_near(false, x_negative, false, mode, p)} I--",
              )
              cases += 1
            }
          }
        }
      }
    }
  }
  assert_true(cases > 500)
}

///|
// oracle: S
// source: atanpi_ctx of the exact quotient (x = 1 or powers of two), the same function in another form; agreement of atan2pi with atanpi
// shares: atanpi_ctx (the code under test, as the reference) and pi_x
test "atan2pi with an exact quotient is atanpi of it" {
  // For x = 1 the quotient y / x is exact, and for y = 2^a, x = 2^b it is the
  // exact power 2^(a - b): atan2Pi(y, x) = atanPi(y / x) for x > 0. The ratios
  // reach the implementation limits.
  let mut cases = 0
  for p in [2, 11, 53] {
    for mode in e2s_modes() {
      let ctx = BinaryContext::new(precision=p, rounding=mode)
      for
        e in [
          -30, -3, 0, 3, 30, 200, 1000000, 1073741000, -1073741000, -1073741800,
        ] {
        for numerator in [3, 5, 7] {
          let y = pi_x(numerator, e)
          let (left, left_flags) = y.atan2pi_ctx(Binary::one(), ctx)
          let (right, right_flags) = y.atanpi_ctx(ctx)
          assert_eq(
            "\{left} \{e2s_flags(left_flags)}",
            "\{right} \{e2s_flags(right_flags)}",
          )
          cases += 1
        }
      }
      for a in [-1073741000, -5, 0, 7, 1073741000] {
        for b in [-1073741000, -9, 0, 11, 1073741000] {
          let y = pi_x(1, a)
          let x = pi_x(1, b)
          let (left, left_flags) = y.atan2pi_ctx(x, ctx)
          let ratio = a - b
          // 2^(a - b) is representable only for |a - b| < 2^30
          if ratio.abs() <= 1073741000 && ratio != 0 {
            let (right, right_flags) = pi_x(1, ratio).atanpi_ctx(ctx)
            assert_eq(
              "\{left} \{e2s_flags(left_flags)}",
              "\{right} \{e2s_flags(right_flags)}",
            )
            cases += 1
          }
        }
      }
    }
  }
  assert_true(cases > 600)
}

///|
/// The correctly rounded value of asin(x)/π (`is_asin`) or atan(x)/π for a tiny
/// x as the rounding by `binary_round_dyadic` of x/π (1 +- 2^-300): above for
/// asin, below for atan. Valid for |x| < 2^-150.
fn pi_inverse_tiny_model(
  x : Binary,
  is_asin : Bool,
  ctx : BinaryContext,
) -> (Binary, BinaryFlags) {
  let base = Coeff::one().shift_left(300)
  let factor = if is_asin {
    base.add(Coeff::one())
  } else {
    base.sub_checked(Coeff::one()).unwrap()
  }
  // pi from the MPFR rows (acos(-1) rounded toward negative infinity at 512 bits)
  let pi = mpfr_enclosure("acos", Binary::from_int(-1), 512).0
  let reciprocal = Binary::one(precision=450).div_ctx(
      pi,
      BinaryContext::new(precision=450),
    ).0
  let product = x.abs().mul_ctx(reciprocal, BinaryContext::new(precision=900)).0
  binary_round_dyadic(
    x.is_sign_minus(),
    product.coefficient_().mul(factor),
    product.exponent2() - 300,
    ctx,
  )
}

///|
// oracle: A
// source: function_boundary_rows_wbtest.mbt, generated by tools/generate_function_boundary_rows.py; values and flags from GNU MPFR 4.2.2 (tools/generate_mpfr_random_oracle.c eval, mpfr_subnormalize, underflow from IEEE 754-2019 7.5), library-ran: no
// shares: Binary::from_hex_ctx reads operands and expected values exactly (level A through hex_ctx_rows and hex_agree_rows); Display and the flag accessors print the result
test "asinpi and atanpi of tiny arguments round as x / pi, also at the subnormal limit" {
  assert_true(fbr_check_group("pi_inverse_tiny", 916, 236) > 0)
}

///|
// oracle: B
// source: pi_inverse_tiny_model: for a tiny x, atan(x)/pi = (x/pi)(1 - x^2/3 ...) and the product is rounded once by binary_round_dyadic from x/pi times (1 - 2^-300) (the header's item 3: no breakpoint lies that close), with pi from the MPFR rows (acos(-1) rounded toward negative infinity at 512 bits, enclosure_rows_wbtest.mbt, GNU MPFR 4.2.2) and 1/pi by Binary::div_ctx; the same class of inputs (tiny arguments to the subnormal limit) is level A in the block `asinpi and atanpi of tiny arguments round as x / pi, also at the subnormal limit`
// shares: Binary::mul_ctx, div_ctx and binary_round_dyadic in the model; pi_x builds the operands; e2s_modes and e2s_flags print the result; atan2pi_ctx is the code under test
// primitives: Binary::mul_ctx and Binary::div_ctx (level A through arith_rows_wbtest.mbt), binary_round_dyadic (level A through round_rows_wbtest.mbt, magnitudes at e_min and e_max, five directions, both tininess rules), the MPFR pi (level A)
test "atan2pi with a tiny ratio rounds as y / (pi x)" {
  // x = 1: atan2Pi(y, 1) = atanPi(y), tiny and within the subnormal range of
  // binary64 or below it. Also with an exact power-of-two abscissa.
  let mut cases = 0
  for p in [2, 11, 24, 53] {
    for mode in e2s_modes() {
      let ctx = BinaryContext::new(precision=p, rounding=mode, e_max=1023)
      for e in [-1100, -1080, -1074, -1070, -1030, -1000, -500, -160] {
        for negative in [false, true] {
          let y = pi_x(3, e, negative~)
          let (left, left_flags) = y.atan2pi_ctx(Binary::one(), ctx)
          let (expected, expected_flags) = pi_inverse_tiny_model(y, false, ctx)
          assert_eq(
            "\{left} \{e2s_flags(left_flags)}",
            "\{expected} \{e2s_flags(expected_flags)}",
          )
          // the same ratio with an abscissa 2^40
          let (scaled, scaled_flags) = pi_x(3, e + 40, negative~).atan2pi_ctx(
            pi_x(1, 40),
            ctx,
          )
          assert_eq(
            "\{scaled} \{e2s_flags(scaled_flags)}",
            "\{expected} \{e2s_flags(expected_flags)}",
          )
          cases += 2
        }
      }
    }
  }
  assert_true(cases > 100)
}

///|
// oracle: A
// source: function_boundary_rows_wbtest.mbt, generated by tools/generate_function_boundary_rows.py; values and flags from GNU MPFR 4.2.2 (tools/generate_mpfr_random_oracle.c eval, mpfr_subnormalize, underflow from IEEE 754-2019 7.5), library-ran: no
// shares: Binary::from_hex_ctx reads operands and expected values exactly (level A through hex_ctx_rows and hex_agree_rows); Display and the flag accessors print the result
test "asinpi, acospi and atanpi of moderate arguments are correctly rounded in every direction" {
  assert_true(fbr_check_group("pi_inverse_moderate", 540, 0) > 0)
}
