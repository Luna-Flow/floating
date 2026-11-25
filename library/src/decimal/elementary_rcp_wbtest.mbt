///|
// White-box tests of rsqrt, compound and powr (issue #236, PR 2). The clause
// quotes are from IEEE Std 754-2019; the generated table
// `elementary_rcp_rows_wbtest.mbt` holds the exact and certified rows.

///|
fn rcp_try(
  op : String,
  x : String,
  y : String,
  n : Int32,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  let a = pm1_exact(x)
  match op {
    "rsqrt" => a.try_rsqrt_ctx(ctx)
    "compound" => a.try_compound_ctx(n, ctx)
    "powr" => a.try_powr_ctx(pm1_exact(y), ctx)
    _ => abort("unknown operation " + op)
  }
}

///|
fn rcp_call(
  op : String,
  x : String,
  y : String,
  n : Int32,
  ctx : DecimalContext,
) -> String {
  match rcp_try(op, x, y, n, ctx) {
    Ok((value, flags)) => "\{value} \{pm1_flags_text(flags)}"
    Err(_) => "certification-failure"
  }
}

///|
test "rcp generated rows: exact and certified results, cohort and flags" {
  let failures = StringBuilder()
  let mut count = 0
  let rows = rcp_rows()
  for row in rows {
    let (
      op,
      rounding,
      precision,
      e_min,
      e_max,
      clamp,
      tininess,
      x,
      y,
      n,
      expected,
      flags,
    ) = row
    let ctx = pm1_ctx_cached(precision, rounding, e_min, e_max, clamp, tininess)
    // Value (cohort included) and flags are compared directly; the result is
    // formatted only to describe a failure.
    let ok = match rcp_try(op, x, y, n, ctx) {
      Ok((value, actual_flags)) =>
        value.total_order_compare(pm1_exact(expected)) == 0 &&
        pm1_flags_text(actual_flags) == flags
      Err(_) => false
    }
    if !ok {
      count += 1
      if count <= 20 {
        failures.write_string(
          "\{op} \{rounding} p=\{precision} [\{e_min},\{e_max}] clamp=\{clamp} \{tininess} x=\{x} y=\{y} n=\{n}: want \{expected} \{flags}, got \{rcp_call(op, x, y, n, ctx)}\n",
        )
      }
    }
  }
  inspect(failures.to_string(), content="")
  assert_true(rows.length() > 5000)
}

///|
test "rsqrt special values (9.2.1, Table 9.1)" {
  // Table 9.1: rSqrt has domain [0, +inf]; "x < 0: invalid operation; x is
  // +-0: divideByZero". 9.2.1: "rSqrt(+inf) is +0 with no exception.
  // rSqrt(+-0) is +-inf and signals the divideByZero exception."
  let outputs : Array[String] = []
  for mode in pm1_modes {
    let ctx = pm1_ctx(16, mode, -383, 384, true, "b")
    let out = StringBuilder()
    for
      x in [
        "0", "-0", "0E-9", "-0E+5", "Infinity", "-Infinity", "-1", "-1E-400", "NaN12",
        "-sNaN3",
      ] {
      out.write_string("\{x} -> \{rcp_call("rsqrt", x, "", 0, ctx)}\n")
    }
    outputs.push(out.to_string())
  }
  // The same in every mode.
  for text in outputs {
    assert_eq(text, outputs[0])
  }
  inspect(
    outputs[0],
    content=(
      #|0 -> inf z
      #|-0 -> -inf z
      #|0E-9 -> inf z
      #|-0E+5 -> -inf z
      #|Infinity -> 0 -
      #|-Infinity -> nan v
      #|-1 -> nan v
      #|-1E-400 -> nan v
      #|NaN12 -> nan12 -
      #|-sNaN3 -> -nan3 v
      #|
    ),
  )
}

///|
test "rsqrt exact results take the preferred exponent -floor(Q(x)/2) (9.2.2)" {
  // 9.2.2: "Q(rSqrt(x)) is -floor(Q(x)/2)"; 5.2: an exact result takes the
  // member of its cohort with the exponent closest to the preferred one.
  let ctx = DecimalContext::decimal64()
  let out = StringBuilder()
  for
    x in [
      "4", "4.00", "400E-2", "0.04", "1E+2", "1.00E+2", "100", "1E+3", "1E-6", "6.25",
      "0.0016", "390625", "1E-400", "1E+380", "4E+384",
    ] {
    out.write_string("rsqrt(\{x}) = \{rcp_call("rsqrt", x, "", 0, ctx)}\n")
  }
  inspect(
    out.to_string(),
    content=(
      #|rsqrt(4) = 0.5 -
      #|rsqrt(4.00) = 0.5 -
      #|rsqrt(400E-2) = 0.5 -
      #|rsqrt(0.04) = 5 -
      #|rsqrt(1E+2) = 0.1 -
      #|rsqrt(1.00E+2) = 0.1 -
      #|rsqrt(100) = 0.1 -
      #|rsqrt(1E+3) = 0.03162277660168379 x
      #|rsqrt(1E-6) = 1E+3 -
      #|rsqrt(6.25) = 0.4 -
      #|rsqrt(0.0016) = 25 -
      #|rsqrt(390625) = 0.0016 -
      #|rsqrt(1E-400) = 1E+200 -
      #|rsqrt(1E+380) = 1E-190 -
      #|rsqrt(4E+384) = 5E-193 -
      #|
    ),
  )
}

///|
// oracle: S
// source: equivalence of the scaled loop with the plain certified loop (decimal_certified_unary_result with the interval sqrt then recip), the general route that decimal_certified_scaled_result replaces; value, cohort and flags compared, no expected value written out. The level A table of elementary_rcp_rows_wbtest.mbt (fractions.Fraction exact results and MPFR 4.2.2 enclosures, tools/generate_decimal_rcp_rows.py) covers rsqrt, but the operands of this block are not all rows of it
// shares: decimal_certified_unary_result and the interval sqrt and recip (both sides use them)
test "rsqrt by the scaled loop equals the plain certified loop" {
  // `decimal_certified_scaled_result` encloses 1/sqrt(x 10^-2k) and shifts
  // the endpoints by 10^-k; on operands the plain loop handles cheaply the
  // two must agree in value, cohort and flags.
  let eval = fn(input : @interval.Interval) { Ok(input.sqrt().recip()) }
  for mode in pm1_modes {
    for
      spec in [
        (7, -95, 96, true),
        (16, -383, 384, true),
        (34, -6143, 6144, true),
        (5, -8, 9, true),
      ] {
      let (precision, e_min, e_max, clamp) = spec
      for tininess in ["b"] {
        let ctx = pm1_ctx(precision, mode, e_min, e_max, clamp, tininess)
        for
          x in [
            "2", "3.5E+7", "7E-11", "1.2345678E+150", "9.87E-160", "5E+18", "2E-19",
            "3E+190", "1.1E-200",
          ] {
          let value = pm1_exact(x)
          let plain = decimal_certified_unary_result(value, ctx, "rsqrt", eval)
          let fast = value.try_rsqrt_ctx(ctx)
          match (plain, fast) {
            (Ok(a), Ok(b)) => {
              assert_eq(a.0.total_order_compare(b.0), 0, msg="\{x} \{mode}")
              assert_eq(
                pm1_flags_text(a.1),
                pm1_flags_text(b.1),
                msg="\{x} \{mode}",
              )
            }
            _ => fail("certification failure \{x} \{mode}")
          }
        }
      }
    }
  }
}

///|
test "compound special values (9.2.1)" {
  // 9.2.1: "compound(x, 0) is 1 for x >= -1 or quiet NaN";
  // "compound(-1, n) is +inf and signals the divideByZero exception for
  // n < 0"; "compound(-1, n) is +0 for n > 0"; "compound(+-0, n) is 1";
  // "compound(+inf, n) is +inf for n > 0"; "compound(+inf, n) is +0 for
  // n < 0"; "compound(x, n) is qNaN and signals the invalid operation
  // exception for x < -1"; "compound(qNaN, n) is qNaN for n != 0". Table
  // 9.1: the domain is [-1, +inf] x Z, so x < -1 is invalid also for n = 0.
  // 9.2.2: "Q(compound(x, n)) is floor(n * min(0, Q(x)))".
  let ctx = DecimalContext::decimal64()
  let out = StringBuilder()
  for
    pair in [
      ("2", 0),
      ("-1", 0),
      ("-1.00", 0),
      ("Infinity", 0),
      ("NaN7", 0),
      ("sNaN7", 0),
      ("-1.5", 0),
      ("-Infinity", 0),
      ("-1", -3),
      ("-1", 3),
      ("-1.0", 2),
      ("0", 5),
      ("-0", -5),
      ("0.00", 3),
      ("0.00", -3),
      ("Infinity", 2),
      ("Infinity", -2),
      ("-1.5", 3),
      ("-Infinity", 3),
      ("NaN7", 4),
      ("-NaN", -4),
      ("sNaN8", 4),
    ] {
    let (x, n) = pair
    out.write_string(
      "compound(\{x}, \{n}) = \{rcp_call("compound", x, "", n, ctx)}\n",
    )
  }
  inspect(
    out.to_string(),
    content=(
      #|compound(2, 0) = 1 -
      #|compound(-1, 0) = 1 -
      #|compound(-1.00, 0) = 1 -
      #|compound(Infinity, 0) = 1 -
      #|compound(NaN7, 0) = 1 -
      #|compound(sNaN7, 0) = nan7 v
      #|compound(-1.5, 0) = nan v
      #|compound(-Infinity, 0) = nan v
      #|compound(-1, -3) = inf z
      #|compound(-1, 3) = 0 -
      #|compound(-1.0, 2) = 0 -
      #|compound(0, 5) = 1 -
      #|compound(-0, -5) = 1 -
      #|compound(0.00, 3) = 1.000000 -
      #|compound(0.00, -3) = 1 -
      #|compound(Infinity, 2) = inf -
      #|compound(Infinity, -2) = 0 -
      #|compound(-1.5, 3) = nan v
      #|compound(-Infinity, 3) = nan v
      #|compound(NaN7, 4) = nan7 -
      #|compound(-NaN, -4) = -nan -
      #|compound(sNaN8, 4) = nan8 v
      #|
    ),
  )
}

///|
test "compound at Int32.min_value" {
  // n = -2^31 has no Int32 magnitude; the values below are exp(n log1p(x))
  // computed with Python decimal at 80 digits (far from any rounding
  // boundary): (1 + 1E-30)^(-2^31) = 0.99999999999999999999785..., so
  // Floor gives 0.9999999999999999 and the nearest modes 1.000000000000000.
  let out = StringBuilder()
  for mode in ["half_even", "floor", "ceiling"] {
    let ctx = pm1_ctx(16, mode, -383, 384, true, "b")
    for x in ["1E-30", "1E-7", "-1E-20", "-0.5", "3"] {
      out.write_string(
        "\{mode} \{x} \{rcp_call("compound", x, "", -2147483647 - 1, ctx)}\n",
      )
    }
  }
  inspect(
    out.to_string(),
    content=(
      #|half_even 1E-30 1.000000000000000 x
      #|half_even 1E-7 5.444711000534668E-94 x
      #|half_even -1E-20 1.000000000021475 x
      #|half_even -0.5 inf xo
      #|half_even 3 0E-398 xu
      #|floor 1E-30 0.9999999999999999 x
      #|floor 1E-7 5.444711000534667E-94 x
      #|floor -1E-20 1.000000000021474 x
      #|floor -0.5 9.999999999999999E+384 xo
      #|floor 3 0E-398 xu
      #|ceiling 1E-30 1.000000000000000 x
      #|ceiling 1E-7 5.444711000534668E-94 x
      #|ceiling -1E-20 1.000000000021475 x
      #|ceiling -0.5 inf xo
      #|ceiling 3 1E-398 xu
      #|
    ),
  )
}

///|
// oracle: S
// source: equivalence of the anchored result of try_compound_ctx with decimal_compound_certified (the certified loop through exp(n log1p(x))), the general route it replaces; value and flags compared, no expected value written out. Compound is level A in the table of elementary_rcp_rows_wbtest.mbt (exact rationals by fractions.Fraction and brackets of the rational (1 + x)^n, tools/generate_decimal_rcp_rows.py, never MPFR's compound), but the tiny operands and the n at the Int32 ends of this block are not all rows of it
// shares: decimal_compound_certified and the interval functions (both sides use them)
test "compound of a tiny x is anchored and agrees with the certified loop" {
  // (1 + x)^n - 1 has the sign of n x and magnitude below 10^(adj(x) + 12),
  // so a tiny x gives a one-sided neighbour of 1; the anchored result must be
  // the one exp(n log1p(x)) certifies.
  for mode in pm1_modes {
    for precision in [1, 7, 16, 34] {
      let ctx = pm1_ctx(precision, mode, -6143, 6144, true, "b")
      for x in ["1E-60", "-3.7E-55", "9.99E-70"] {
        for n in [1, -1, 13, -2147483647, 2147483647, -2147483647 - 1] {
          let value = pm1_exact(x)
          let anchored = value.try_compound_ctx(n, ctx).unwrap()
          let certified = decimal_compound_certified(value, n, ctx).unwrap()
          assert_eq(
            anchored.0.total_order_compare(certified.0),
            0,
            msg="\{x} \{n} \{mode}",
          )
          assert_eq(pm1_flags_text(anchored.1), pm1_flags_text(certified.1))
        }
      }
    }
  }
}

///|
test "powr special values (9.2.1) and the pow agreement" {
  // 9.2.1 for powr: "powr(x, +-0) is 1 for finite x > 0"; "powr(+-0, y) is
  // +inf and signals the divideByZero exception for finite y < 0";
  // "powr(+-0, -inf) is +inf"; "powr(+-0, y) is +0 for y > 0"; "powr(+1, y)
  // is 1 for finite y"; "powr(x, y) signals the invalid operation exception
  // for x < 0"; "powr(+-0, +-0) signals the invalid operation exception";
  // "powr(+inf, +-0) signals the invalid operation exception"; "powr(+1,
  // +-inf) signals the invalid operation exception"; "powr(x, qNaN) is qNaN
  // for x >= 0"; "powr(qNaN, y) is qNaN". [ambiguous, #236 design note]
  // x < 0 with y = qNaN is the invalid row; +inf^y (y != 0) and x^+-inf
  // (x not in {0, 1}) follow exp(y log x).
  let ctx = DecimalContext::decimal64()
  let out = StringBuilder()
  for
    pair in [
      ("2", "0"),
      ("2", "-0.00"),
      ("0", "-3"),
      ("-0", "-3"),
      ("-0", "-2.5"),
      ("0", "-Infinity"),
      ("-0", "-Infinity"),
      ("0", "3"),
      ("-0", "3"),
      ("-0", "Infinity"),
      ("1", "123.5"),
      ("1.00", "2"),
      ("-2", "2"),
      ("-2", "0"),
      ("-Infinity", "2"),
      ("-1E-5", "NaN"),
      ("0", "0"),
      ("-0", "-0"),
      ("Infinity", "0"),
      ("Infinity", "-0"),
      ("1", "Infinity"),
      ("1", "-Infinity"),
      ("2", "NaN4"),
      ("0", "NaN"),
      ("NaN5", "0"),
      ("NaN5", "2"),
      ("1", "NaN"),
      ("2", "sNaN6"),
      ("-2", "sNaN6"),
      ("Infinity", "2"),
      ("Infinity", "-2"),
      ("Infinity", "Infinity"),
      ("Infinity", "-Infinity"),
      ("0.5", "Infinity"),
      ("0.5", "-Infinity"),
      ("2", "Infinity"),
      ("2", "-Infinity"),
      ("4", "0.5"),
      ("4.00", "1.5"),
      ("10", "1.5"),
    ] {
    let (x, y) = pair
    out.write_string("powr(\{x}, \{y}) = \{rcp_call("powr", x, y, 0, ctx)}\n")
  }
  inspect(
    out.to_string(),
    content=(
      #|powr(2, 0) = 1 -
      #|powr(2, -0.00) = 1 -
      #|powr(0, -3) = inf z
      #|powr(-0, -3) = inf z
      #|powr(-0, -2.5) = inf z
      #|powr(0, -Infinity) = inf -
      #|powr(-0, -Infinity) = inf -
      #|powr(0, 3) = 0 -
      #|powr(-0, 3) = 0 -
      #|powr(-0, Infinity) = 0 -
      #|powr(1, 123.5) = 1 -
      #|powr(1.00, 2) = 1.0000 -
      #|powr(-2, 2) = nan v
      #|powr(-2, 0) = nan v
      #|powr(-Infinity, 2) = nan v
      #|powr(-1E-5, NaN) = nan v
      #|powr(0, 0) = nan v
      #|powr(-0, -0) = nan v
      #|powr(Infinity, 0) = nan v
      #|powr(Infinity, -0) = nan v
      #|powr(1, Infinity) = nan v
      #|powr(1, -Infinity) = nan v
      #|powr(2, NaN4) = nan4 -
      #|powr(0, NaN) = nan -
      #|powr(NaN5, 0) = nan5 -
      #|powr(NaN5, 2) = nan5 -
      #|powr(1, NaN) = nan -
      #|powr(2, sNaN6) = nan6 v
      #|powr(-2, sNaN6) = nan6 v
      #|powr(Infinity, 2) = inf -
      #|powr(Infinity, -2) = 0 -
      #|powr(Infinity, Infinity) = inf -
      #|powr(Infinity, -Infinity) = 0 -
      #|powr(0.5, Infinity) = 0 -
      #|powr(0.5, -Infinity) = inf -
      #|powr(2, Infinity) = inf -
      #|powr(2, -Infinity) = 0 -
      #|powr(4, 0.5) = 2 -
      #|powr(4.00, 1.5) = 8.000 -
      #|powr(10, 1.5) = 31.62277660168379 x
      #|
    ),
  )
}
