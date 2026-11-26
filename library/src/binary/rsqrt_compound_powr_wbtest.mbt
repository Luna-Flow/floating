// `rsqrt` (rSqrt), `compound` and `powr` (IEEE 754-2019 9.2, Table 9.1).
//
// Clauses, quoted from the text of IEEE Std 754-2019 (pdftotext of the PDF):
//
//   [9.2.1] "rSqrt(+∞) is +0 with no exception. rSqrt(±0) is ±∞ and signals the
//           divideByZero exception." Table 9.1: rSqrt 1/√x, domain [0, +∞],
//           "x < 0: invalid operation; x is ±0: divideByZero".
//   [9.2.1] compound: "compound (x, 0) is 1 for x ≥ −1 or quiet NaN"; "compound
//           (−1, n) is +∞ and signals the divideByZero exception for n < 0";
//           "compound (−1, n) is +0 for n > 0"; "compound (±0, n) is 1";
//           "compound (+∞, n) is +∞ for n > 0"; "compound (+∞, n) is +0 for
//           n < 0"; "compound (x, n) is qNaN and signals the invalid operation
//           exception for x < −1"; "compound (qNaN, n) is qNaN for n ≠ 0".
//   [9.2.1] powr: "powr (x, ±0) is 1 for finite x > 0"; "powr (±0, y) is +∞ and
//           signals the divideByZero exception for finite y < 0"; "powr (±0,
//           −∞) is +∞"; "powr (±0, y) is +0 for y > 0"; "powr (+1, y) is 1 for
//           finite y"; "powr (x, y) signals the invalid operation exception for
//           x < 0"; "powr (±0, ±0) signals the invalid operation exception";
//           "powr (+∞, ±0) signals the invalid operation exception"; "powr (+1,
//           ±∞) signals the invalid operation exception"; "powr (x, qNaN) is
//           qNaN for x ≥ 0"; "powr (qNaN, y) is qNaN." The unlisted infinite
//           cases follow the definition of 9.2.1, "powr (x, y) is defined by
//           considering exp(y × log(x))" (continuous limits, no exception), so a
//           negative x is invalid for every y, a quiet NaN y included.
//   [9.2]   "A conforming operation shall return results correctly rounded for
//           the applicable rounding direction for all operands in its domain."
//           and the signaling NaN rules of 7.2 a) and 6.2.

///|
fn rcp_contexts() -> Array[BinaryContext] {
  [
    BinaryContext::new(precision=53),
    BinaryContext::new(precision=2),
    BinaryContext::binary64(),
    BinaryContext::new(precision=24, e_max=7),
  ]
}

///|
fn rcp_inf(negative : Bool) -> Binary {
  Binary::inf(negative~)
}

///|
/// Renders a `try_` result as `value flags`: the inexact, underflow and overflow
/// letters of `e2s_flags`, `Z` for divideByZero, `V` for invalid_operation and `N`
/// for not_computed (a case that signals invalid is told apart from a quiet NaN
/// that propagates); an `Err` as `err`.
fn rcp_show(
  result : Result[(Binary, BinaryFlags), @def.ArithmeticError],
) -> String {
  match result {
    Ok((value, flags)) =>
      "\{value} \{e2s_flags(flags)}\{if flags.division_by_zero() { "Z" } else { "" }}\{if flags.invalid_operation() { "V" } else { "" }}\{if flags.not_computed() { "N" } else { "" }}"
    Err(_) => "err"
  }
}

///|
// oracle: A, S
// source: A: written out from the clauses quoted in the header of the file (pdftotext of IEEE Std 754-2019, 9.2.1 and Table 9.1): rSqrt(+inf) = +0 with no exception, rSqrt(+-0) = +-inf with divideByZero, invalid for x < 0 and -inf, quiet NaN propagation, signaling NaN invalid; S: the S4 mapping of the library (invalid is a value in the try_ form, not an Err) is asserted as well
// shares: rcp_inf, Binary::zero, from_int and make build the operands; rsqrt_ctx and try_rsqrt_ctx are the code under test
test "rsqrt special values" {
  for ctx in rcp_contexts() {
    // rSqrt(+0) = +inf and rSqrt(-0) = -inf with divideByZero
    let (value, flags) = Binary::zero().rsqrt_ctx(ctx)
    assert_eq("\{value}", "inf")
    assert_true(flags.division_by_zero() && !flags.invalid_operation())
    let (value, flags) = Binary::negative_zero().rsqrt_ctx(ctx)
    assert_eq("\{value}", "-inf")
    assert_true(flags.division_by_zero() && !flags.invalid_operation())
    // rSqrt(+inf) = +0 with no exception
    let (value, flags) = rcp_inf(false).rsqrt_ctx(ctx)
    assert_eq("\{value}", "0")
    assert_eq(flags, BinaryFlags::new())
    // x < 0, -inf: invalid
    for
      below in [
        Binary::from_int(-4),
        rcp_inf(true),
        Binary::make(BinCoeff::one(), -1000, 53, negative=true),
      ] {
      let (value, flags) = below.rsqrt_ctx(ctx)
      assert_true(value.is_quiet_nan() && flags.invalid_operation())
      // S4: a domain case is a value in the try_ form too
      match below.try_rsqrt_ctx(ctx) {
        Ok((nan, nan_flags)) => {
          assert_true(nan.is_nan())
          assert_true(nan_flags.invalid_operation())
          assert_false(nan_flags.not_computed())
        }
        Err(_) => abort("a domain case must not be an Err")
      }
    }
    // NaNs
    let (value, flags) = Binary::quiet_nan(negative=true).rsqrt_ctx(ctx)
    assert_true(value.is_quiet_nan() && value.is_sign_minus())
    assert_eq(flags, BinaryFlags::new())
    let (value, flags) = Binary::signaling_nan().rsqrt_ctx(ctx)
    assert_true(value.is_quiet_nan() && flags.invalid_operation())
  }
}

///|
// oracle: A
// source: function_boundary_rows_wbtest.mbt, generated by tools/generate_function_boundary_rows.py; values and flags from GNU MPFR 4.2.2 (tools/generate_mpfr_random_oracle.c eval), library-ran: no; the powers of four are written out (1/sqrt(4^k) = 2^-k)
// shares: Binary::make builds the powers of four 4^k (BinCoeff::one with exponent 2k, no rounding involved) and Binary::from_hex_ctx reads operands and expected values exactly (level A through hex_ctx_rows and hex_agree_rows); Display, e2s_flags and the flag accessors print the result
test "rsqrt of a power of four is exact, other values are correctly rounded" {
  let mut cases = 0
  for p in [2, 3, 24, 53] {
    for mode in e2s_modes() {
      let ctx = BinaryContext::new(precision=p, rounding=mode)
      // 4^k: exact 2^-k
      for k in -30..<31 {
        let x = Binary::make(BinCoeff::one(), 2 * k, 64)
        let (value, flags) = x.rsqrt_ctx(ctx)
        assert_eq("\{value} \{e2s_flags(flags)}", "1p\{-k} ---")
        cases += 1
      }
    }
  }
  assert_eq(cases, 4 * 5 * 61)
  // the other values: MPFR rows
  assert_true(fbr_check_group("rsqrt", 520, 0) > 0)
}

///|
// oracle: A, S
// source: A: written out from the clauses quoted in the header of the file (pdftotext of IEEE Std 754-2019, 9.2.1 and Table 9.1): compound(x, 0) = 1 for x >= -1 and a quiet NaN, compound(-1, n) = +inf with divideByZero for n < 0 and +0 for n > 0, compound(+-0, n) = 1, compound(+inf, n) = +inf for n > 0 and +0 for n < 0, invalid for x < -1 and -inf, quiet NaN propagation for n != 0, signaling NaN invalid; S: the S4 mapping of the library (invalid is a value in the try_ form, not an Err) is asserted as well
// shares: rcp_show prints value and flag letters; Binary constructors build the operands; try_compound_ctx and compound_ctx are the code under test
test "compound special values" {
  for ctx in rcp_contexts() {
    let one = "1p0 ---"
    let render = fn(x : Binary, n : Int32) {
      rcp_show(x.try_compound_ctx(n, ctx))
    }
    // compound(x, 0) = 1 for x >= -1 and for a quiet NaN
    for
      x in [
        Binary::from_int(-1),
        Binary::zero(),
        Binary::from_int(3),
        rcp_inf(false),
        Binary::quiet_nan(),
      ] {
      assert_eq(render(x, 0), one)
    }
    // compound(-1, n): +inf with divideByZero for n < 0, +0 for n > 0
    assert_eq(render(Binary::from_int(-1), -3), "inf ---Z")
    assert_eq(render(Binary::from_int(-1), 3), "0 ---")
    // compound(+-0, n) = 1
    for zero in [Binary::zero(), Binary::negative_zero()] {
      for n in [-5, 1, 7] {
        assert_eq(render(zero, n), one)
      }
    }
    // compound(+inf, n)
    assert_eq(render(rcp_inf(false), 4), "inf ---")
    assert_eq(render(rcp_inf(false), -4), "0 ---")
    // x < -1 (and -inf): invalid
    for
      below in [
        Binary::from_int(-2),
        Binary::make(BinCoeff::from_uint64(9UL), -3, 53, negative=true),
        rcp_inf(true),
      ] {
      for n in [-3, 0, 3] {
        assert_eq(render(below, n), "nan ---V")
        let (value, flags) = below.compound_ctx(n, ctx)
        assert_true(value.is_quiet_nan() && flags.invalid_operation())
      }
    }
    // compound(qNaN, n) = qNaN for n != 0; a signaling NaN is invalid
    let (value, flags) = Binary::quiet_nan().compound_ctx(5, ctx)
    assert_true(value.is_quiet_nan())
    assert_eq(flags, BinaryFlags::new())
    for n in [0, 5] {
      let (value, flags) = Binary::signaling_nan().compound_ctx(n, ctx)
      assert_true(value.is_quiet_nan() && flags.invalid_operation())
    }
  }
}

///|
// oracle: A
// source: function_boundary_rows_wbtest.mbt, generated by tools/generate_function_boundary_rows.py; values and flags from GNU MPFR 4.2.2 (tools/generate_mpfr_random_oracle.c eval, mpfr_subnormalize, underflow from IEEE 754-2019 7.5), library-ran: no; the compound rows are corrected by the evaluator with exact rational arithmetic where mpfr_compound_si is not correctly rounded
// shares: Binary::from_hex_ctx reads operands and expected values exactly (level A through hex_ctx_rows and hex_agree_rows); Display and the flag accessors print the result
test "compound is the correctly rounded (1 + x)^n" {
  assert_true(fbr_check_group("compound", 1280, 0) > 0)
}

///|
// oracle: A
// source: written out: (1 + x)^n = 1 + n x for x = +-2^-400 and n = 3 and 1000000, far below a quarter of the spacing at 1 (precision 24), so the correctly rounded result is 1 or its neighbour on the side of the sign of n x chosen by the direction: 1 + 2^-23 = 8388609p-23 above (toward positive infinity only, for a positive x) and 1 - 2^-24 = 16777215p-24 below (toward zero and toward negative infinity, for a negative x), with inexact and no underflow (IEEE Std 754-2019 4.3, 7.6)
// shares: Binary::make and neg build the operands; compound_ctx is the code under test; to_string prints the result
test "compound of a tiny x is the neighbour of 1 chosen by the direction" {
  // (1 + x)^n = 1 + n x with |n x| far below a quarter of the spacing at 1
  for mode in e2s_modes() {
    let ctx = BinaryContext::new(precision=24, rounding=mode)
    let tiny = Binary::make(BinCoeff::one(), -400, 64)
    for n in [3, 1000000] {
      for negative in [false, true] {
        let x = if negative { tiny.neg() } else { tiny }
        let (value, flags) = x.compound_ctx(n, ctx)
        let positive_delta = !negative
        let up = match mode {
          RoundTowardPositive => true
          _ => false
        }
        let expected = if positive_delta && up {
          "8388609p-23"
        } else if !positive_delta &&
          (mode == RoundTowardZero || mode == RoundTowardNegative) {
          "16777215p-24"
        } else {
          "1p0"
        }
        assert_eq(value.to_string(), expected)
        assert_true(flags.inexact() && !flags.underflow())
      }
    }
  }
}

///|
// oracle: A, S
// source: A: written out from the clauses quoted in the header of the file (pdftotext of IEEE Std 754-2019, 9.2.1 and Table 9.1): powr(x, +-0) = 1 for finite x > 0, powr(+-0, y) = +inf with divideByZero for finite y < 0, +inf for y = -inf and +0 for y > 0, powr(+1, y) = 1 for finite y, invalid for powr(+1, +-inf), powr(+-0, +-0), powr(+inf, +-0) and x < 0, quiet NaN propagation and the signaling NaN; S: the S4 mapping of the library (invalid is a value in the try_ form, not an Err) is asserted as well
// shares: rcp_show prints value and flag letters; Binary constructors build the operands; try_powr_ctx and powr_ctx are the code under test
test "powr special values" {
  for ctx in rcp_contexts() {
    let render = fn(x : Binary, y : Binary) { rcp_show(x.try_powr_ctx(y, ctx)) }
    let two = Binary::from_int(2)
    let zero = Binary::zero()
    let minus_zero = Binary::negative_zero()
    let one = Binary::one()
    let inf = rcp_inf(false)
    // powr(x, +-0) = 1 for finite x > 0
    assert_eq(render(two, zero), "1p0 ---")
    assert_eq(render(two, minus_zero), "1p0 ---")
    // powr(+-0, y): divideByZero for finite y < 0, -inf gives +inf with no
    // exception, y > 0 (and +inf) gives +0
    for z in [zero, minus_zero] {
      assert_eq(render(z, Binary::from_int(-3)), "inf ---Z")
      assert_eq(render(z, rcp_inf(true)), "inf ---")
      assert_eq(render(z, Binary::from_int(3)), "0 ---")
      assert_eq(render(z, inf), "0 ---")
      assert_eq(render(z, zero), "nan ---V")
      assert_eq(render(z, minus_zero), "nan ---V")
    }
    // powr(+1, y) = 1 for finite y; powr(+1, +-inf) is invalid
    assert_eq(render(one, Binary::from_int(-7)), "1p0 ---")
    assert_eq(render(one, Binary::quiet_nan()), "nan ---")
    assert_eq(render(one, inf), "nan ---V")
    assert_eq(render(one, rcp_inf(true)), "nan ---V")
    // x < 0 (and -inf) is invalid, whatever y
    for below in [Binary::from_int(-2), rcp_inf(true)] {
      for y in [two, zero, inf, Binary::quiet_nan()] {
        assert_eq(render(below, y), "nan ---V")
      }
    }
    // powr(+inf, y)
    assert_eq(render(inf, zero), "nan ---V")
    assert_eq(render(inf, two), "inf ---")
    assert_eq(render(inf, Binary::from_int(-2)), "0 ---")
    // quiet NaNs: powr(x, qNaN) and powr(qNaN, y) are qNaN, no exception
    assert_eq(render(two, Binary::quiet_nan()), "nan ---")
    assert_eq(render(Binary::quiet_nan(), two), "nan ---")
    assert_eq(render(Binary::quiet_nan(), zero), "nan ---")
    // signaling NaNs are invalid
    for snan in [Binary::signaling_nan()] {
      assert_true(snan.powr_ctx(two, ctx).1.invalid_operation())
      assert_true(two.powr_ctx(snan, ctx).1.invalid_operation())
      assert_true(one.powr_ctx(snan, ctx).1.invalid_operation())
      assert_true(snan.powr_ctx(zero, ctx).1.invalid_operation())
    }
  }
}

///|
// oracle: A
// source: function_boundary_rows_wbtest.mbt, generated by tools/generate_function_boundary_rows.py; values and flags from GNU MPFR 4.2.2 (tools/generate_mpfr_random_oracle.c eval, mpfr_subnormalize, underflow from IEEE 754-2019 7.5), library-ran: no
// shares: Binary::from_hex_ctx reads operands and expected values exactly (level A through hex_ctx_rows and hex_agree_rows); Display and the flag accessors print the result
test "powr of a positive x is pow, exact and correctly rounded" {
  assert_true(fbr_check_group("powr", 240, 0) > 0)
}
