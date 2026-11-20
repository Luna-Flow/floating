///|
// White-box tests of the exponential-type operations at the limits of the
// representable range (issue #363). Clauses are from IEEE Std 754-2019.
//
// Expectation table (b^x with b = e, 2, 10; etiny = e_min - p + 1; the context
// of the issue is p = 51, e_min = -14, e_max = 11, so etiny = -64):
//
// | result                                  | direction                  | delivered result              | flags                         | clause |
// |-----------------------------------------|----------------------------|-------------------------------|-------------------------------|--------|
// | 0 < b^x < half of 10^etiny              | to nearest, toward zero    | +0 (exponent etiny)           | inexact, rounded, underflow,  | 9.2,   |
// |                                         |                            |                               | subnormal (clamped)           | 7.5, 4.3 |
// | 0 < b^x < half of 10^etiny              | toward +inf, away (Up),    | 10^etiny, the least positive  | inexact, rounded, underflow,  | 9.2,   |
// |                                         | ZeroFiveUp                 | subnormal                     | subnormal                     | 7.5, 4.3 |
// | b^x >= 10^(e_max + 1) > largest finite  | to nearest, toward +inf,   | +inf                          | overflow, inexact, rounded    | 7.4 a, d |
// |                                         | away (Up)                  |                               |                               |        |
// | b^x >= 10^(e_max + 1) > largest finite  | toward zero, toward -inf   | the largest finite number     | overflow, inexact, rounded    | 7.4 b, c |
// | just representable results              | all                        | the correctly rounded value   | inexact, rounded (+ subnormal | 9.2, 4.3 |
// | (10^etiny, half of it, largest finite)  |                            | (the table rows below)        | and underflow below 10^e_min) |        |
//
// The generated table `exp_range_rows_wbtest.mbt` holds the rows for the
// narrow context of the issue, decimal32, decimal64, decimal128 and a wide
// context (e_max = 999999), in all eight rounding directions, at results
// just inside and outside the range, at the thresholds `x = +-k (1 - etiny)`,
// `+-k (e_max + 1)` of the coarse decision `+-1`, `+-0.5` and for the
// arguments of the issue. Python decimal (libmpdec) computed them; it only
// cross-checks, the clauses above decide.

///|
fn exp_range_int(text : String) -> Int32 {
  let mut value = 0
  let mut negative = false
  for c in text {
    if c == '-' {
      negative = true
    } else {
      value = value * 10 + (c.to_int() - '0'.to_int())
    }
  }
  if negative {
    -value
  } else {
    value
  }
}

///|
fn exp_range_call(
  op : String,
  x : String,
  y : String,
  ctx : DecimalContext,
) -> String {
  let a = pm1_exact(x)
  let result = match op {
    "exp" => a.try_exp_ctx(ctx)
    "exp2" => a.try_exp2_ctx(ctx)
    "exp10" => a.try_exp10_ctx(ctx)
    "expm1" => a.try_expm1_ctx(ctx)
    "exp2m1" => a.try_exp2m1_ctx(ctx)
    "exp10m1" => a.try_exp10m1_ctx(ctx)
    "log1p" => a.try_log1p_ctx(ctx)
    "rootn" => a.try_rootn_ctx(exp_range_int(y), ctx)
    "sinh" => a.try_sinh_ctx(ctx)
    "cosh" => a.try_cosh_ctx(ctx)
    "pow" => pm1_exact("3").try_pow_ctx(pm1_exact(y), ctx)
    "powr" => pm1_exact("2").try_powr_ctx(pm1_exact(y), ctx)
    "pown" => a.try_pown_ctx(exp_range_int(y), ctx)
    "compound" => a.try_compound_ctx(exp_range_int(y), ctx)
    "rsqrt" => a.try_rsqrt_ctx(ctx)
    _ => abort("unknown operation " + op)
  }
  match result {
    Ok((value, flags)) => "\{value} \{pm1_flags_text(flags)}"
    Err(_) => "certification-failure"
  }
}

///|
test "exp range generated rows: results just inside and outside the range" {
  let failures = StringBuilder()
  let mut count = 0
  let rows = exp_range_rows()
  for row in rows {
    let (op, rounding, precision, e_min, e_max, clamp, x, y, expected, flags) = row
    let ctx = pm1_ctx(precision, rounding, e_min, e_max, clamp, "b")
    let got = exp_range_call(op, x, y, ctx)
    let parts = got.split(" ").map(fn(s) { s.to_owned() }).collect()
    let ok = parts.length() == 2 &&
      pm1_exact(parts[0]).total_order_compare(pm1_exact(expected)) == 0 &&
      parts[1] == flags
    if !ok {
      count += 1
      if count <= 20 {
        failures.write_string(
          "\{op} \{rounding} p=\{precision} [\{e_min},\{e_max}] clamp=\{clamp} x=\{x} y=\{y}: want \{expected} \{flags}, got \{got}\n",
        )
      }
    }
  }
  inspect(failures.to_string(), content="")
  assert_true(rows.length() > 5000)
}

///|
test "exp2 and exp10 of an argument beyond the binary exponent range (#363)" {
  // The issue's table: p = 51, Ceiling, e_min = -14, e_max = 11 (etiny = -64).
  // 9.2: the result is the correctly rounded value, here the least subnormal
  // 1E-64 (below half of it, rounding toward +inf); 7.5: the rounded result is
  // inexact, so underflow and inexact are raised.
  let ctx = pm1_ctx(51, "ceiling", -14, 15, true, "b")
  for op in ["exp", "exp2", "exp10"] {
    for x in ["-1000", "-100000", "-6773329072.88", "-1E+12"] {
      assert_eq(exp_range_call(op, x, "", ctx), "1E-64 xu")
    }
  }
  // Rounding to nearest gives +0 with the same flags (7.5, 9.2).
  let nearest = pm1_ctx(51, "half_even", -14, 15, true, "b")
  for op in ["exp", "exp2", "exp10"] {
    let got = exp_range_call(op, "-6773329072.88", "", nearest)
    assert_true(got.has_prefix("0E-64 x"))
  }
  // 7.4: the symmetric overflow, by rounding direction.
  let down = pm1_ctx(51, "down", -14, 15, true, "b")
  for op in ["exp", "exp2", "exp10"] {
    assert_eq(
      exp_range_call(op, "6773329072.88", "", down),
      "9999999999999999.99999999999999999999999999999999999 xo",
    )
    assert_eq(exp_range_call(op, "6773329072.88", "", ctx), "inf xo")
  }
}

///|
test "rootn exact roots need the exponent to be a multiple of the degree (#376)" {
  // x = c 10^e with c not a multiple of 10: c 10^shift, 0 < shift < n, is an
  // n-th power only if n divides shift (the factors 2 and 5 of 10^shift are the
  // only ones that can raise v2 and v5 to a multiple of n). On both sides:
  // shift 0 gives the exact root, shift 1 or n - 1 does not.
  let ctx = pm1_ctx(34, "half_even", -6143, 6144, true, "b")
  for
    entry in [
      ("1E+6", 3, "100"),
      ("8E+3", 3, "20"),
      ("27E-6", 3, "0.03"),
      ("64E+6", 6, "20"),
      ("1E+0", 1000000, "1"),
      ("1E+999000", 1000, "1E+999"),
    ] {
    let (x, n, want) = entry
    let ctx = if x == "1E+999000" {
      pm1_ctx(34, "half_even", -999998, 999999, true, "b")
    } else {
      ctx
    }
    let got = pm1_exact(x).try_rootn_ctx(n, ctx).unwrap()
    assert_true(got.0.compare(pm1_exact(want)) == 0, msg="\{x} \{n}: \{got.0}")
    assert_true(!got.1.inexact, msg="\{x} \{n}: flags")
  }
  for
    entry in [("1E+7", 3), ("1E+8", 3), ("8E+4", 3), ("27E-5", 3), ("64E+5", 6)] {
    let (x, n) = entry
    let got = pm1_exact(x).try_rootn_ctx(n, ctx).unwrap()
    assert_true(got.1.inexact, msg="\{x} \{n}: should be inexact")
  }
}
