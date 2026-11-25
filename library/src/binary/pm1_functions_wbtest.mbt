// `exp2m1`, `exp10m1`, `log2p1` and `log10p1` (IEEE 754-2019 9.2, Table 9.1).
//
// Clauses, quoted from the text of IEEE Std 754-2019 (pdftotext of the PDF):
//
//   [9.2.1] "For the operations sin, tan, sinPi, tanPi, asin, atan, asinPi,
//           atanPi, sinh, tanh, asinh, atanh, expm1, exp2m1, exp10m1, logp1,
//           log2p1, and log10p1, f (+0) is +0 and f (−0) is −0 with no
//           exception."
//   [9.2.1] "For the operations expm1, exp2m1, and exp10m1, f (+∞) is +∞ and
//           f (−∞) is −1 with no exception."
//   [9.2.1] "For the operations log, log2, log10, logp1, log2p1, and log10p1,
//           f (+∞) is +∞ with no exception." and "For the operations logp1,
//           log2p1, and log10p1, f (−1) is −∞ and signals the divideByZero
//           exception."
//   [Table 9.1] log2p1, log10p1: domain [−1, +∞], "x = −1: divideByZero; x < −1:
//           invalid operation; underflow"; exp2m1, exp10m1: domain [−∞, +∞],
//           "overflow; underflow".
//   [9.2]   "A conforming operation shall return results correctly rounded for
//           the applicable rounding direction for all operands in its domain."
//   [7.2 a] invalid operation for "any general-computational operation on a
//           signaling NaN (see 6.2)"; 6.2: a quiet NaN result keeps the payload.

///|
fn pm1_run(
  name : String,
  x : Binary,
  ctx : BinaryContext,
) -> (Binary, BinaryFlags) {
  match name {
    "exp2m1" => x.exp2m1_ctx(ctx)
    "exp10m1" => x.exp10m1_ctx(ctx)
    "log2p1" => x.log2p1_ctx(ctx)
    _ => x.log10p1_ctx(ctx)
  }
}

///|
fn pm1_try(
  name : String,
  x : Binary,
  ctx : BinaryContext,
) -> Result[(Binary, BinaryFlags), @def.ArithmeticError] {
  match name {
    "exp2m1" => x.try_exp2m1_ctx(ctx)
    "exp10m1" => x.try_exp10m1_ctx(ctx)
    "log2p1" => x.try_log2p1_ctx(ctx)
    _ => x.try_log10p1_ctx(ctx)
  }
}

///|
fn pm1_contexts() -> Array[BinaryContext] {
  [
    BinaryContext::new(precision=53),
    BinaryContext::new(precision=2),
    BinaryContext::binary64(),
    BinaryContext::new(precision=24, e_max=7),
    BinaryContext::new(
      precision=113,
      rounding=BinaryRoundingMode::RoundTowardZero,
      e_max=16383,
    ),
  ]
}

///|
test "exp2m1 and exp10m1 special values" {
  for name in ["exp2m1", "exp10m1"] {
    for ctx in pm1_contexts() {
      // f(+-0) = +-0 with no exception
      for zero in [Binary::zero(), Binary::negative_zero()] {
        let (value, flags) = pm1_run(name, zero, ctx)
        assert_eq(value.to_string(), zero.to_string())
        assert_eq(flags, BinaryFlags::new())
      }
      // f(+inf) = +inf and f(-inf) = -1 with no exception
      let (value, flags) = pm1_run(name, Binary::inf(), ctx)
      assert_eq(value.to_string(), "inf")
      assert_eq(flags, BinaryFlags::new())
      let (value, flags) = pm1_run(name, Binary::inf(negative=true), ctx)
      assert_eq(value.to_string(), "-1p0")
      assert_eq(flags, BinaryFlags::new())
      // a quiet NaN propagates with its payload, a signaling NaN is invalid
      let qnan = Binary::quiet_nan(
        payload=Coeff::from_uint64(9UL),
        negative=true,
      )
      let (value, flags) = pm1_run(name, qnan, ctx)
      assert_true(value.is_quiet_nan() && value.is_sign_minus())
      assert_eq(
        value.nan_payload().to_string(),
        nan_payload_in(BinCoeff::from_uint64(9UL), ctx.precision()),
      )
      assert_eq(flags, BinaryFlags::new())
      let snan = Binary::signaling_nan(payload=Coeff::from_uint64(5UL))
      let (value, flags) = pm1_run(name, snan, ctx)
      assert_true(value.is_quiet_nan())
      assert_eq(
        value.nan_payload().to_string(),
        nan_payload_in(BinCoeff::from_uint64(5UL), ctx.precision()),
      )
      assert_true(flags.invalid_operation())
    }
  }
}

///|
test "log2p1 and log10p1 special values and domain" {
  for name in ["log2p1", "log10p1"] {
    for ctx in pm1_contexts() {
      for zero in [Binary::zero(), Binary::negative_zero()] {
        let (value, flags) = pm1_run(name, zero, ctx)
        assert_eq(value.to_string(), zero.to_string())
        assert_eq(flags, BinaryFlags::new())
      }
      let (value, flags) = pm1_run(name, Binary::inf(), ctx)
      assert_eq(value.to_string(), "inf")
      assert_eq(flags, BinaryFlags::new())
      // f(-1) = -inf with divideByZero; the try_ form keeps the pole as a value
      let minus_one = Binary::from_int(-1)
      let (value, flags) = pm1_run(name, minus_one, ctx)
      assert_eq(value.to_string(), "-inf")
      assert_true(flags.division_by_zero())
      assert_false(flags.invalid_operation())
      assert_true(pm1_try(name, minus_one, ctx) is Ok(_))
      // x < -1 and -inf are outside the domain: invalid operation
      for
        below in [
          Binary::from_int(-2),
          Binary::make_coeff(Coeff::from_uint64(9UL), -3, 53, negative=true),
          Binary::inf(negative=true),
        ] {
        let (value, flags) = pm1_run(name, below, ctx)
        assert_true(value.is_quiet_nan())
        assert_true(flags.invalid_operation())
        assert_false(flags.division_by_zero())
      }
      // S4: a domain case is a value in the try_ form too, never an `Err`
      match pm1_try(name, Binary::from_int(-2), ctx) {
        Ok((nan, nan_flags)) => {
          assert_true(nan.is_quiet_nan())
          assert_true(nan_flags.invalid_operation())
          assert_false(nan_flags.not_computed())
        }
        Err(_) => abort(name + ": a domain case must not be an Err")
      }
      // NaNs
      let (value, flags) = pm1_run(name, Binary::quiet_nan(), ctx)
      assert_true(value.is_quiet_nan())
      assert_eq(flags, BinaryFlags::new())
      let (value, flags) = pm1_run(name, Binary::signaling_nan(), ctx)
      assert_true(value.is_quiet_nan())
      assert_true(flags.invalid_operation())
    }
  }
}

///|
/// Independent model of `exp2m1(n)`, `log2p1(2^n - 1)` and friends for integer
/// `n`: the exact integer, rounded as a dyadic (no surrogate, no shortcut).
fn pm1_model_exp2m1(n : Int32, ctx : BinaryContext) -> (Binary, BinaryFlags) {
  if n >= 0 {
    binary_round_dyadic(
      false,
      Coeff::one().shift_left(n).sub_checked(Coeff::one()).unwrap(),
      0,
      ctx,
    )
  } else {
    // 2^n - 1 = -(2^k - 1) * 2^-k with k = -n
    binary_round_dyadic(
      true,
      Coeff::one().shift_left(-n).sub_checked(Coeff::one()).unwrap(),
      n,
      ctx,
    )
  }
}

///|
test "exp2m1 of an integer is the correctly rounded 2^n - 1 in every direction" {
  let mut cases = 0
  for p in [2, 3, 24, 53, 113] {
    for mode in e2s_modes() {
      for
        tininess in [
          TininessDetection::AfterRounding,
          TininessDetection::BeforeRounding,
        ] {
        let ctx = BinaryContext::new(precision=p, rounding=mode, tininess~)
        for n in -140..<141 {
          if n != 0 {
            let x = Binary::from_int(n, precision=64)
            let (value, flags) = x.exp2m1_ctx(ctx)
            let (expected, expected_flags) = pm1_model_exp2m1(n, ctx)
            let label = "exp2m1(\{n}) p=\{p} \{e2s_mode_name(mode)}"
            assert_eq(
              "\{label} => \{value} \{e2s_flags(flags)}",
              "\{label} => \{expected} \{e2s_flags(expected_flags)}",
            )
            cases += 1
          }
        }
      }
    }
  }
  assert_eq(cases, 5 * 5 * 2 * 280)
}

///|
test "exp2m1 of a huge integer rounds like the power of two beside it" {
  // 2^n - 1 for n far beyond the precision cannot be formed; the result must
  // still be the neighbour of 2^n chosen by the direction, with overflow where
  // the range ends.
  for n in [1000, 1073741000, 1073741822, 1073741823, 1073741824, 1073741825] {
    let x = Binary::from_int(n, precision=64)
    let up = x.exp2m1_ctx(BinaryContext::new(precision=53))
    let down = x.exp2m1_ctx(
      BinaryContext::new(precision=53, rounding=RoundTowardZero),
    )
    assert_true(up.1.inexact())
    assert_true(down.1.inexact())
    if n <= 1073741823 {
      // nearest: 2^n itself (n <= e_max), toward zero: (2^53 - 1) 2^(n - 53)
      assert_eq(up.0.to_string(), "1p\{n}")
      assert_eq(down.0.to_string(), "9007199254740991p\{n - 53}")
      assert_false(up.1.overflow())
    } else {
      assert_true(up.1.overflow())
      assert_eq(up.0.to_string(), "inf")
    }
  }
  for n in [-1000, -1073741823, -1073741825] {
    let x = Binary::from_int(n, precision=64)
    let nearest = x.exp2m1_ctx(BinaryContext::new(precision=53))
    let toward_zero = x.exp2m1_ctx(
      BinaryContext::new(precision=53, rounding=RoundTowardZero),
    )
    assert_eq(nearest.0.to_string(), "-1p0")
    assert_eq(toward_zero.0.to_string(), "-9007199254740991p-53")
    assert_true(nearest.1.inexact() && toward_zero.1.inexact())
  }
}

///|
test "log2p1 and log10p1 are exact at 2^k - 1 and 10^k - 1" {
  let mut cases = 0
  for ctx in pm1_contexts() {
    for k in [1, 2, 3, 7, 24, 53] {
      // x = 2^k - 1: log2p1 = k
      let x = Binary::make_coeff(
        Coeff::one().shift_left(k).sub_checked(Coeff::one()).unwrap(),
        0,
        64,
      )
      let (value, flags) = x.log2p1_ctx(ctx)
      let (expected, expected_flags) = binary_round_dyadic(
        false,
        Coeff::from_uint64(k.to_uint64()),
        0,
        ctx,
      )
      assert_eq(value.to_string(), expected.to_string())
      assert_eq(e2s_flags(flags), e2s_flags(expected_flags))
      cases += 1
    }
    for k in [1, 2, 3, 10, 22] {
      // x = 2^-k - 1 = -(1 - 2^-k): log2p1 = -k
      let x = Binary::make_coeff(
        Coeff::one().shift_left(k).sub_checked(Coeff::one()).unwrap(),
        -k,
        64,
        negative=true,
      )
      let (value, flags) = x.log2p1_ctx(ctx)
      let (expected, expected_flags) = binary_round_dyadic(
        true,
        Coeff::from_uint64(k.to_uint64()),
        0,
        ctx,
      )
      assert_eq(value.to_string(), expected.to_string())
      assert_eq(e2s_flags(flags), e2s_flags(expected_flags))
      cases += 1
    }
    for k in [1, 2, 3, 9, 15] {
      // x = 10^k - 1: log10p1 = k
      let x = Binary::make_coeff(
        Coeff::from_uint64(10UL)
        .pow_nat(k.reinterpret_as_uint())
        .sub_checked(Coeff::one())
        .unwrap(),
        0,
        64,
      )
      let (value, flags) = x.log10p1_ctx(ctx)
      let (expected, expected_flags) = binary_round_dyadic(
        false,
        Coeff::from_uint64(k.to_uint64()),
        0,
        ctx,
      )
      assert_eq(value.to_string(), expected.to_string())
      assert_eq(e2s_flags(flags), e2s_flags(expected_flags))
      cases += 1
    }
  }
  assert_eq(cases, 5 * 16)
}

///|
test "exp10m1 of a small integer is the correctly rounded 10^n - 1" {
  let mut cases = 0
  for p in [2, 8, 24, 53, 100] {
    for mode in e2s_modes() {
      let ctx = BinaryContext::new(precision=p, rounding=mode)
      for n in 1..<40 {
        let x = Binary::from_int(n, precision=64)
        let (value, flags) = x.exp10m1_ctx(ctx)
        let (expected, expected_flags) = binary_round_dyadic(
          false,
          Coeff::from_uint64(10UL)
          .pow_nat(n.reinterpret_as_uint())
          .sub_checked(Coeff::one())
          .unwrap(),
          0,
          ctx,
        )
        assert_eq(
          "exp10m1(\{n}) p=\{p} \{e2s_mode_name(mode)} => \{value} \{e2s_flags(flags)}",
          "exp10m1(\{n}) p=\{p} \{e2s_mode_name(mode)} => \{expected} \{e2s_flags(expected_flags)}",
        )
        cases += 1
      }
    }
  }
  assert_eq(cases, 5 * 5 * 39)
}

///|
// oracle: A
// source: function_boundary_rows_wbtest.mbt, generated by tools/generate_function_boundary_rows.py; values and flags from GNU MPFR 4.2.2 (tools/generate_mpfr_random_oracle.c eval, mpfr_subnormalize, underflow from IEEE 754-2019 7.5), library-ran: no
// shares: Binary::from_hex_ctx reads operands and expected values exactly (level A through hex_ctx_rows and hex_agree_rows); Display and the flag accessors print the result
test "the four functions decide underflow and overflow like the reference" {
  assert_true(fbr_check_group("pm1_underflow", 810, 0) > 0)
}
