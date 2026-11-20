///|
// White-box tests of asinPi, acosPi, atanPi and atan2Pi (issue #236, PR 3).
// The clause quotes are from IEEE Std 754-2019; the generated table
// `elementary_pi_inverse_rows_wbtest.mbt` holds the exact and MPFR-certified
// rows.

///|
fn pii_try(
  op : String,
  x : String,
  y : String,
  ctx : DecimalContext,
) -> Result[(Decimal, DecimalFlags), @def.ArithmeticError] {
  let a = pm1_exact(x)
  match op {
    "asinpi" => a.try_asinpi_ctx(ctx)
    "acospi" => a.try_acospi_ctx(ctx)
    "atanpi" => a.try_atanpi_ctx(ctx)
    "atan2pi" => a.try_atan2pi_ctx(pm1_exact(y), ctx)
    _ => abort("unknown operation " + op)
  }
}

///|
fn pii_call(
  op : String,
  x : String,
  y : String,
  ctx : DecimalContext,
) -> String {
  match pii_try(op, x, y, ctx) {
    Ok((value, flags)) => "\{value} \{pm1_flags_text(flags)}"
    Err(_) => "certification-failure"
  }
}

///|
test "pi inverse generated rows: exact and certified results, cohort and flags" {
  let failures = StringBuilder()
  let mut count = 0
  let rows = pii_rows()
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
      expected,
      flags,
    ) = row
    let ctx = pm1_ctx_cached(precision, rounding, e_min, e_max, clamp, tininess)
    // Value (cohort included) and flags are compared directly; the result is
    // formatted only to describe a failure.
    let ok = match pii_try(op, x, y, ctx) {
      Ok((value, actual_flags)) =>
        value.compare_total(pm1_exact(expected)) == 0 &&
        pm1_flags_text(actual_flags) == flags
      Err(_) => false
    }
    if !ok {
      count += 1
      if count <= 20 {
        failures.write_string(
          "\{op} \{rounding} p=\{precision} [\{e_min},\{e_max}] clamp=\{clamp} \{tininess} x=\{x} y=\{y}: want \{expected} \{flags}, got \{pii_call(op, x, y, ctx)}\n",
        )
      }
    }
  }
  inspect(failures.to_string(), content="")
  assert_true(rows.length() > 3000)
}

///|
fn pii_all_modes(op : String, x : String, y : String) -> String raise {
  // The same text in every rounding mode (exact constants, domain errors).
  let outputs : Array[String] = []
  for mode in pm1_modes {
    let ctx = pm1_ctx(16, mode, -383, 384, true, "b")
    outputs.push(pii_call(op, x, y, ctx))
  }
  for text in outputs {
    assert_eq(text, outputs[0], msg="\{op}(\{x}, \{y})")
  }
  outputs[0]
}

///|
test "asinPi special values (9.2.1, Table 9.1)" {
  // 9.2.1: "f(+0) is +0 and f(-0) is -0 with no exception" for asinPi.
  // Table 9.1: "|x| > 1: invalid operation". asinPi(+-1) = +-1/2 (Niven).
  let out = StringBuilder()
  for
    x in [
      "0", "-0", "0E-9", "-0E+5", "1", "-1", "1.000", "-1E+0", "2", "-1.0000001",
      "Infinity", "-Infinity", "NaN12", "-sNaN3",
    ] {
    out.write_string("asinpi(\{x}) = \{pii_all_modes("asinpi", x, "")}\n")
  }
  inspect(
    out.to_string(),
    content=(
      #|asinpi(0) = 0 -
      #|asinpi(-0) = -0 -
      #|asinpi(0E-9) = 0 -
      #|asinpi(-0E+5) = -0 -
      #|asinpi(1) = 0.5 -
      #|asinpi(-1) = -0.5 -
      #|asinpi(1.000) = 0.5 -
      #|asinpi(-1E+0) = -0.5 -
      #|asinpi(2) = nan v
      #|asinpi(-1.0000001) = nan v
      #|asinpi(Infinity) = nan v
      #|asinpi(-Infinity) = nan v
      #|asinpi(NaN12) = nan12 -
      #|asinpi(-sNaN3) = -nan3 v
      #|
    ),
  )
}

///|
test "acosPi special values (9.2.1, Table 9.1)" {
  // 9.2.1: "acos(1), acosPi(1), and acosh(1) are +0." acosPi(-1) = 1 and
  // acosPi(+-0) = 1/2 are exact; |x| > 1 is invalid.
  let out = StringBuilder()
  for
    x in [
      "0", "-0", "0E-9", "1", "1.000", "-1", "-1E+0", "2", "-1.0000001", "Infinity",
      "-Infinity", "NaN12", "-sNaN3",
    ] {
    out.write_string("acospi(\{x}) = \{pii_all_modes("acospi", x, "")}\n")
  }
  inspect(
    out.to_string(),
    content=(
      #|acospi(0) = 0.5 -
      #|acospi(-0) = 0.5 -
      #|acospi(0E-9) = 0.5 -
      #|acospi(1) = 0 -
      #|acospi(1.000) = 0 -
      #|acospi(-1) = 1 -
      #|acospi(-1E+0) = 1 -
      #|acospi(2) = nan v
      #|acospi(-1.0000001) = nan v
      #|acospi(Infinity) = nan v
      #|acospi(-Infinity) = nan v
      #|acospi(NaN12) = nan12 -
      #|acospi(-sNaN3) = -nan3 v
      #|
    ),
  )
}

///|
test "atanPi special values (9.2.1)" {
  // 9.2.1: "atanPi(+-inf) is +-1/2 with no exception"; f(+-0) = +-0;
  // atanPi(+-1) = +-1/4 (Niven).
  let out = StringBuilder()
  for
    x in [
      "0", "-0", "0E-9", "1", "-1", "1.000", "-1E+0", "Infinity", "-Infinity", "NaN12",
      "-sNaN3",
    ] {
    out.write_string("atanpi(\{x}) = \{pii_all_modes("atanpi", x, "")}\n")
  }
  inspect(
    out.to_string(),
    content=(
      #|atanpi(0) = 0 -
      #|atanpi(-0) = -0 -
      #|atanpi(0E-9) = 0 -
      #|atanpi(1) = 0.25 -
      #|atanpi(-1) = -0.25 -
      #|atanpi(1.000) = 0.25 -
      #|atanpi(-1E+0) = -0.25 -
      #|atanpi(Infinity) = 0.5 -
      #|atanpi(-Infinity) = -0.5 -
      #|atanpi(NaN12) = nan12 -
      #|atanpi(-sNaN3) = -nan3 v
      #|
    ),
  )
}

///|
test "atan2Pi: the special cases of 9.2.1" {
  // "atan2Pi(+-0, -0) is +-1; atan2Pi(+-0, +0) is +-0; atan2Pi(+-0, x) is +-1
  // for x < 0; atan2Pi(+-0, x) is +-0 for x > 0; atan2Pi(y, +-0) is -1/2 for
  // y < 0; atan2Pi(y, +-0) is +1/2 for y > 0; atan2Pi(+-y, -inf) is +-1 for
  // finite y > 0; atan2Pi(+-y, +inf) is +-0 for finite y > 0; atan2Pi(+-inf, x)
  // is +-1/2 for finite x; atan2Pi(+-inf, -inf) is +-3/4; atan2Pi(+-inf,
  // +inf) is +-1/4." No exception is signaled.
  let out = StringBuilder()
  for
    pair in [
      ("0", "-0"),
      ("-0", "-0"),
      ("0", "0"),
      ("-0", "0"),
      ("0", "-5"),
      ("-0", "-5"),
      ("0", "5"),
      ("-0", "5"),
      ("-3", "0"),
      ("-3", "-0"),
      ("3", "0"),
      ("3", "-0"),
      ("3", "-Infinity"),
      ("-3", "-Infinity"),
      ("3", "Infinity"),
      ("-3", "Infinity"),
      ("Infinity", "7"),
      ("-Infinity", "7"),
      ("Infinity", "-7"),
      ("-Infinity", "-7"),
      ("Infinity", "0"),
      ("-Infinity", "-0"),
      ("Infinity", "-Infinity"),
      ("-Infinity", "-Infinity"),
      ("Infinity", "Infinity"),
      ("-Infinity", "Infinity"),
    ] {
    let (y, x) = pair
    out.write_string(
      "atan2pi(\{y}, \{x}) = \{pii_all_modes("atan2pi", y, x)}\n",
    )
  }
  inspect(
    out.to_string(),
    content=(
      #|atan2pi(0, -0) = 1 -
      #|atan2pi(-0, -0) = -1 -
      #|atan2pi(0, 0) = 0 -
      #|atan2pi(-0, 0) = -0 -
      #|atan2pi(0, -5) = 1 -
      #|atan2pi(-0, -5) = -1 -
      #|atan2pi(0, 5) = 0 -
      #|atan2pi(-0, 5) = -0 -
      #|atan2pi(-3, 0) = -0.5 -
      #|atan2pi(-3, -0) = -0.5 -
      #|atan2pi(3, 0) = 0.5 -
      #|atan2pi(3, -0) = 0.5 -
      #|atan2pi(3, -Infinity) = 1 -
      #|atan2pi(-3, -Infinity) = -1 -
      #|atan2pi(3, Infinity) = 0 -
      #|atan2pi(-3, Infinity) = -0 -
      #|atan2pi(Infinity, 7) = 0.5 -
      #|atan2pi(-Infinity, 7) = -0.5 -
      #|atan2pi(Infinity, -7) = 0.5 -
      #|atan2pi(-Infinity, -7) = -0.5 -
      #|atan2pi(Infinity, 0) = 0.5 -
      #|atan2pi(-Infinity, -0) = -0.5 -
      #|atan2pi(Infinity, -Infinity) = 0.75 -
      #|atan2pi(-Infinity, -Infinity) = -0.75 -
      #|atan2pi(Infinity, Infinity) = 0.25 -
      #|atan2pi(-Infinity, Infinity) = -0.25 -
      #|
    ),
  )
}

///|
test "atan2Pi: quiet and signaling NaN operands" {
  let out = StringBuilder()
  for
    pair in [
      ("NaN5", "1"),
      ("1", "NaN6"),
      ("NaN5", "NaN6"),
      ("-sNaN3", "2"),
      ("2", "sNaN4"),
      ("NaN7", "Infinity"),
      ("0", "NaN8"),
    ] {
    let (y, x) = pair
    out.write_string(
      "atan2pi(\{y}, \{x}) = \{pii_all_modes("atan2pi", y, x)}\n",
    )
  }
  inspect(
    out.to_string(),
    content=(
      #|atan2pi(NaN5, 1) = nan5 -
      #|atan2pi(1, NaN6) = nan6 -
      #|atan2pi(NaN5, NaN6) = nan5 -
      #|atan2pi(-sNaN3, 2) = -nan3 v
      #|atan2pi(2, sNaN4) = nan4 v
      #|atan2pi(NaN7, Infinity) = nan7 -
      #|atan2pi(0, NaN8) = nan8 -
      #|
    ),
  )
}

///|
test "atan2Pi: |y| = |x| is exactly +-1/4 or +-3/4 (Niven)" {
  let out = StringBuilder()
  for
    pair in [
      ("1", "1"),
      ("-1", "1"),
      ("1", "-1"),
      ("-1", "-1"),
      ("2.50", "2.5"),
      ("-7E+100", "-7000E+97"),
      ("3E-300", "-30E-301"),
      ("9.99", "-9.990000"),
    ] {
    let (y, x) = pair
    out.write_string(
      "atan2pi(\{y}, \{x}) = \{pii_all_modes("atan2pi", y, x)}\n",
    )
  }
  inspect(
    out.to_string(),
    content=(
      #|atan2pi(1, 1) = 0.25 -
      #|atan2pi(-1, 1) = -0.25 -
      #|atan2pi(1, -1) = 0.75 -
      #|atan2pi(-1, -1) = -0.75 -
      #|atan2pi(2.50, 2.5) = 0.25 -
      #|atan2pi(-7E+100, -7000E+97) = -0.75 -
      #|atan2pi(3E-300, -30E-301) = 0.75 -
      #|atan2pi(9.99, -9.990000) = 0.75 -
      #|
    ),
  )
}

///|
test "exact results are at the preferred exponent 0 (9.2.2)" {
  // 9.2.2: "the preferred exponent for asinPi, ... is 0 (Q(f(x)) = 0)": 1/2 is
  // 5E-1, 1/4 is 25E-2, 3/4 is 75E-2 and 1 is 1, never a shorter or longer
  // cohort member; a context too narrow for them rounds (with Inexact).
  let wide = DecimalContext::decimal128()
  let out = StringBuilder()
  out.write_string("asinpi(1) = \{pii_call("asinpi", "1", "", wide)}\n")
  out.write_string("acospi(0) = \{pii_call("acospi", "0", "", wide)}\n")
  out.write_string("acospi(-1) = \{pii_call("acospi", "-1", "", wide)}\n")
  out.write_string("atanpi(1) = \{pii_call("atanpi", "1", "", wide)}\n")
  out.write_string("atan2pi(1, -1) = \{pii_call("atan2pi", "1", "-1", wide)}\n")
  for precision in [1, 2] {
    let ctx = pm1_ctx(precision, "half_even", -383, 384, true, "b")
    out.write_string(
      "p=\{precision} atan2pi(1, -1) = \{pii_call("atan2pi", "1", "-1", ctx)}\n",
    )
    out.write_string(
      "p=\{precision} atanpi(1) = \{pii_call("atanpi", "1", "", ctx)}\n",
    )
  }
  inspect(
    out.to_string(),
    content=(
      #|asinpi(1) = 0.5 -
      #|acospi(0) = 0.5 -
      #|acospi(-1) = 1 -
      #|atanpi(1) = 0.25 -
      #|atan2pi(1, -1) = 0.75 -
      #|p=1 atan2pi(1, -1) = 0.8 xr
      #|p=1 atanpi(1) = 0.2 xr
      #|p=2 atan2pi(1, -1) = 0.75 -
      #|p=2 atanpi(1) = 0.25 -
      #|
    ),
  )
}

///|
fn pii_anchor_cases() -> Array[(String, String, String)] {
  // (op, x, y): one result next to each anchor class.
  [
    ("atanpi", "1E+40", ""),
    ("atanpi", "-1E+40", ""),
    ("atanpi", "-7.3E+25", ""),
    ("acospi", "1E-40", ""),
    ("acospi", "-1E-40", ""),
    ("acospi", "3.5E-30", ""),
    ("atan2pi", "1E+40", "1"),
    ("atan2pi", "-1E+40", "1"),
    ("atan2pi", "1E+40", "-1"),
    ("atan2pi", "-1E+40", "-3"),
    ("atan2pi", "1", "1E+40"),
    ("atan2pi", "-1", "1E+40"),
    ("atan2pi", "1", "-1E+40"),
    ("atan2pi", "-1", "-1E+40"),
    ("atan2pi", "3E-60", "-2E+60"),
    ("atan2pi", "-3E-60", "-2E+60"),
    ("atan2pi", "3E+60", "-2E-60"),
    ("atan2pi", "-3E+60", "2E-60"),
  ]
}

///|
test "anchored results agree with the certified loop in all modes and ranges" {
  // The anchor paths of atanPi (large |x|), acosPi (tiny |x|) and atan2Pi
  // (extreme ratios) are one-sided neighbours of 1/2 or 1. In every mode, on
  // both sides, they must equal what the plain Ziv loop certifies.
  let mut checked = 0
  for mode in pm1_modes {
    for precision in [1, 16] {
      for tininess in ["b"] {
        let ctx = pm1_ctx(precision, mode, -6143, 6144, false, tininess)
        for case_ in pii_anchor_cases() {
          let (op, x, y) = case_
          let value = pm1_exact(x)
          let plain = match op {
            "atanpi" =>
              decimal_certified_unary_result(value, ctx, op, fn(i) {
                Ok(i.atan_interval().div(decimal_pi_ball(i.precision())))
              })
            "acospi" =>
              decimal_certified_unary_result(value, ctx, op, fn(i) {
                Ok(i.acos_interval().div(decimal_pi_ball(i.precision())))
              })
            _ =>
              decimal_certified_binary_result(value, pm1_exact(y), ctx, op, fn(
                a,
                b,
              ) {
                a
                .try_atan2_interval(b)
                .map(fn(t) { t.div(decimal_pi_ball(t.precision())) })
              })
          }
          let fast = match op {
            "atanpi" => value.try_atanpi_ctx(ctx)
            "acospi" => value.try_acospi_ctx(ctx)
            _ => value.try_atan2pi_ctx(pm1_exact(y), ctx)
          }
          match (plain, fast) {
            (Ok(a), Ok(b)) => {
              assert_eq(
                a.0.compare_total(b.0),
                0,
                msg="\{op} \{x} \{y} p=\{precision} \{mode}: \{a.0} vs \{b.0}",
              )
              assert_eq(
                pm1_flags_text(a.1),
                pm1_flags_text(b.1),
                msg="\{op} \{x} \{y} p=\{precision} \{mode}",
              )
              checked += 1
            }
            _ => fail("certification failure \{op} \{x} \{y} \{mode}")
          }
        }
      }
    }
  }
  assert_eq(checked, 8 * 2 * 18)
}

///|
test "anchors: both sides in all eight modes (precision 16)" {
  // atanPi(1E+40) = 1/2 - 3.18E-41: below 1/2, so the directed modes that
  // round down give 0.4999999999999999 and the ones that round up give 0.5;
  // the mirror image for x < 0, and the acosPi and atan2Pi clusters.
  let out = StringBuilder()
  for mode in pm1_modes {
    let ctx = pm1_ctx(16, mode, -383, 384, true, "b")
    out.write_string(
      "\{mode}: atanpi(1E+40)=\{pii_call("atanpi", "1E+40", "", ctx)} atanpi(-1E+40)=\{pii_call("atanpi", "-1E+40", "", ctx)} acospi(1E-40)=\{pii_call("acospi", "1E-40", "", ctx)} acospi(-1E-40)=\{pii_call("acospi", "-1E-40", "", ctx)}\n",
    )
    out.write_string(
      "  atan2pi(1E+40,1)=\{pii_call("atan2pi", "1E+40", "1", ctx)} atan2pi(1E+40,-1)=\{pii_call("atan2pi", "1E+40", "-1", ctx)} atan2pi(-1E+40,-1)=\{pii_call("atan2pi", "-1E+40", "-1", ctx)} atan2pi(1,-1E+40)=\{pii_call("atan2pi", "1", "-1E+40", ctx)} atan2pi(-1,-1E+40)=\{pii_call("atan2pi", "-1", "-1E+40", ctx)} atan2pi(1,1E+40)=\{pii_call("atan2pi", "1", "1E+40", ctx)}\n",
    )
  }
  inspect(
    out.to_string(),
    content=(
      #|half_even: atanpi(1E+40)=0.5000000000000000 xr atanpi(-1E+40)=-0.5000000000000000 xr acospi(1E-40)=0.5000000000000000 xr acospi(-1E-40)=0.5000000000000000 xr
      #|  atan2pi(1E+40,1)=0.5000000000000000 xr atan2pi(1E+40,-1)=0.5000000000000000 xr atan2pi(-1E+40,-1)=-0.5000000000000000 xr atan2pi(1,-1E+40)=1.000000000000000 xr atan2pi(-1,-1E+40)=-1.000000000000000 xr atan2pi(1,1E+40)=3.183098861837907E-41 xr
      #|half_up: atanpi(1E+40)=0.5000000000000000 xr atanpi(-1E+40)=-0.5000000000000000 xr acospi(1E-40)=0.5000000000000000 xr acospi(-1E-40)=0.5000000000000000 xr
      #|  atan2pi(1E+40,1)=0.5000000000000000 xr atan2pi(1E+40,-1)=0.5000000000000000 xr atan2pi(-1E+40,-1)=-0.5000000000000000 xr atan2pi(1,-1E+40)=1.000000000000000 xr atan2pi(-1,-1E+40)=-1.000000000000000 xr atan2pi(1,1E+40)=3.183098861837907E-41 xr
      #|half_down: atanpi(1E+40)=0.5000000000000000 xr atanpi(-1E+40)=-0.5000000000000000 xr acospi(1E-40)=0.5000000000000000 xr acospi(-1E-40)=0.5000000000000000 xr
      #|  atan2pi(1E+40,1)=0.5000000000000000 xr atan2pi(1E+40,-1)=0.5000000000000000 xr atan2pi(-1E+40,-1)=-0.5000000000000000 xr atan2pi(1,-1E+40)=1.000000000000000 xr atan2pi(-1,-1E+40)=-1.000000000000000 xr atan2pi(1,1E+40)=3.183098861837907E-41 xr
      #|down: atanpi(1E+40)=0.4999999999999999 xr atanpi(-1E+40)=-0.4999999999999999 xr acospi(1E-40)=0.4999999999999999 xr acospi(-1E-40)=0.5000000000000000 xr
      #|  atan2pi(1E+40,1)=0.4999999999999999 xr atan2pi(1E+40,-1)=0.5000000000000000 xr atan2pi(-1E+40,-1)=-0.5000000000000000 xr atan2pi(1,-1E+40)=0.9999999999999999 xr atan2pi(-1,-1E+40)=-0.9999999999999999 xr atan2pi(1,1E+40)=3.183098861837906E-41 xr
      #|ceiling: atanpi(1E+40)=0.5000000000000000 xr atanpi(-1E+40)=-0.4999999999999999 xr acospi(1E-40)=0.5000000000000000 xr acospi(-1E-40)=0.5000000000000001 xr
      #|  atan2pi(1E+40,1)=0.5000000000000000 xr atan2pi(1E+40,-1)=0.5000000000000001 xr atan2pi(-1E+40,-1)=-0.5000000000000000 xr atan2pi(1,-1E+40)=1.000000000000000 xr atan2pi(-1,-1E+40)=-0.9999999999999999 xr atan2pi(1,1E+40)=3.183098861837907E-41 xr
      #|floor: atanpi(1E+40)=0.4999999999999999 xr atanpi(-1E+40)=-0.5000000000000000 xr acospi(1E-40)=0.4999999999999999 xr acospi(-1E-40)=0.5000000000000000 xr
      #|  atan2pi(1E+40,1)=0.4999999999999999 xr atan2pi(1E+40,-1)=0.5000000000000000 xr atan2pi(-1E+40,-1)=-0.5000000000000001 xr atan2pi(1,-1E+40)=0.9999999999999999 xr atan2pi(-1,-1E+40)=-1.000000000000000 xr atan2pi(1,1E+40)=3.183098861837906E-41 xr
      #|up: atanpi(1E+40)=0.5000000000000000 xr atanpi(-1E+40)=-0.5000000000000000 xr acospi(1E-40)=0.5000000000000000 xr acospi(-1E-40)=0.5000000000000001 xr
      #|  atan2pi(1E+40,1)=0.5000000000000000 xr atan2pi(1E+40,-1)=0.5000000000000001 xr atan2pi(-1E+40,-1)=-0.5000000000000001 xr atan2pi(1,-1E+40)=1.000000000000000 xr atan2pi(-1,-1E+40)=-1.000000000000000 xr atan2pi(1,1E+40)=3.183098861837907E-41 xr
      #|05up: atanpi(1E+40)=0.4999999999999999 xr atanpi(-1E+40)=-0.4999999999999999 xr acospi(1E-40)=0.4999999999999999 xr acospi(-1E-40)=0.5000000000000001 xr
      #|  atan2pi(1E+40,1)=0.4999999999999999 xr atan2pi(1E+40,-1)=0.5000000000000001 xr atan2pi(-1E+40,-1)=-0.5000000000000001 xr atan2pi(1,-1E+40)=0.9999999999999999 xr atan2pi(-1,-1E+40)=-0.9999999999999999 xr atan2pi(1,1E+40)=3.183098861837906E-41 xr
      #|
    ),
  )
}

///|
test "tiny and huge operands: relative width of the enclosure" {
  // asinPi and atanPi of a tiny x are x/pi (1 - O(x^2)): the result must
  // carry its full precision for the least legal operands, which the digit
  // count of the working precision does not cover by itself.
  let ctx = pm1_ctx(34, "half_even", -6143, 6144, true, "b")
  let out = StringBuilder()
  for x in ["1E-1999996", "-3E-1000000", "7E-9999", "1E-30"] {
    let wide = DecimalContext::new(precision=34, e_min=-999999, e_max=999999).unwrap()
    out.write_string("asinpi(\{x}) = \{pii_call("asinpi", x, "", wide)}\n")
    out.write_string("atanpi(\{x}) = \{pii_call("atanpi", x, "", wide)}\n")
    out.write_string("acospi(\{x}) = \{pii_call("acospi", x, "", ctx)}\n")
  }
  inspect(
    out.to_string(),
    content=(
      #|asinpi(1E-1999996) = 0E-1000032 xrsuc
      #|atanpi(1E-1999996) = 0E-1000032 xrsuc
      #|acospi(1E-1999996) = 0.5000000000000000000000000000000000 xr
      #|asinpi(-3E-1000000) = -9.5492965855137201461330258023509E-1000001 xrsu
      #|atanpi(-3E-1000000) = -9.5492965855137201461330258023509E-1000001 xrsu
      #|acospi(-3E-1000000) = 0.5000000000000000000000000000000000 xr
      #|asinpi(7E-9999) = 2.228169203286534700764372687215201E-9999 xr
      #|atanpi(7E-9999) = 2.228169203286534700764372687215201E-9999 xr
      #|acospi(7E-9999) = 0.5000000000000000000000000000000000 xr
      #|asinpi(1E-30) = 3.183098861837906715377675267450287E-31 xr
      #|atanpi(1E-30) = 3.183098861837906715377675267450287E-31 xr
      #|acospi(1E-30) = 0.4999999999999999999999999999996817 xr
      #|
    ),
  )
}

///|
test "tiny operands: the scaled evaluation equals the plain certified loop" {
  // For a tiny x the loop encloses (s / pi) (1 +- x^2) and shifts it by 10^adj;
  // the result, cohort and flags must be those of the unscaled enclosure.
  let mut checked = 0
  for mode in pm1_modes {
    for precision in [1, 16] {
      let ctx = pm1_ctx(precision, mode, -6143, 6144, true, "b")
      for x in ["1E-120", "-3.7E-150"] {
        let value = pm1_exact(x)
        let one = pm1_exact("1")
        let cases : Array[
          (
            String,
            Result[(Decimal, DecimalFlags), @def.ArithmeticError],
            Result[(Decimal, DecimalFlags), @def.ArithmeticError],
          ),
        ] = [
          (
            "asinpi",
            decimal_certified_unary_result(value, ctx, "asinpi", fn(i) {
              Ok(i.asin_interval().div(decimal_pi_ball(i.precision())))
            }),
            value.try_asinpi_ctx(ctx),
          ),
          (
            "atanpi",
            decimal_certified_unary_result(value, ctx, "atanpi", fn(i) {
              Ok(i.atan_interval().div(decimal_pi_ball(i.precision())))
            }),
            value.try_atanpi_ctx(ctx),
          ),
          (
            "atan2pi",
            decimal_certified_binary_result(value, one, ctx, "atan2pi", fn(
              a,
              b,
            ) {
              a
              .try_atan2_interval(b)
              .map(fn(t) { t.div(decimal_pi_ball(t.precision())) })
            }),
            value.try_atan2pi_ctx(one, ctx),
          ),
        ]
        for case_ in cases {
          match (case_.1, case_.2) {
            (Ok(a), Ok(b)) => {
              assert_eq(
                a.0.compare_total(b.0),
                0,
                msg="\{case_.0} \{x} p=\{precision} \{mode}: \{a.0} vs \{b.0}",
              )
              assert_eq(pm1_flags_text(a.1), pm1_flags_text(b.1))
              checked += 1
            }
            _ => fail("certification failure \{case_.0} \{x} \{mode}")
          }
        }
      }
    }
  }
  assert_eq(checked, 8 * 2 * 2 * 3)
}

///|
test "underflow of the Pi functions follows the context (Table 9.1)" {
  // asinPi, atanPi and atan2Pi may underflow: x/pi for a tiny x is rounded by
  // the context like any inexact result.
  let out = StringBuilder()
  for mode in pm1_modes {
    let ctx = pm1_ctx(7, mode, -95, 96, true, "b")
    out.write_string(
      "\{mode}: \{pii_call("asinpi", "3E-101", "", ctx)} \{pii_call("asinpi", "-3E-101", "", ctx)} \{pii_call("atanpi", "3E-101", "", ctx)} \{pii_call("atan2pi", "-3E-101", "1", ctx)} \{pii_call("atan2pi", "1E-300", "1E+300", ctx)} \{pii_call("atan2pi", "-1E-300", "1E+300", ctx)}\n",
    )
  }
  inspect(
    out.to_string(),
    content=(
      #|half_even: 1E-101 xrsu -1E-101 xrsu 1E-101 xrsu -1E-101 xrsu 0E-101 xrsuc -0E-101 xrsuc
      #|half_up: 1E-101 xrsu -1E-101 xrsu 1E-101 xrsu -1E-101 xrsu 0E-101 xrsuc -0E-101 xrsuc
      #|half_down: 1E-101 xrsu -1E-101 xrsu 1E-101 xrsu -1E-101 xrsu 0E-101 xrsuc -0E-101 xrsuc
      #|down: 0E-101 xrsuc -0E-101 xrsuc 0E-101 xrsuc -0E-101 xrsuc 0E-101 xrsuc -0E-101 xrsuc
      #|ceiling: 1E-101 xrsu -0E-101 xrsuc 1E-101 xrsu -0E-101 xrsuc 1E-101 xrsu -0E-101 xrsuc
      #|floor: 0E-101 xrsuc -1E-101 xrsu 0E-101 xrsuc -1E-101 xrsu 0E-101 xrsuc -1E-101 xrsu
      #|up: 1E-101 xrsu -1E-101 xrsu 1E-101 xrsu -1E-101 xrsu 1E-101 xrsu -1E-101 xrsu
      #|05up: 1E-101 xrsu -1E-101 xrsu 1E-101 xrsu -1E-101 xrsu 1E-101 xrsu -1E-101 xrsu
      #|
    ),
  )
}

///|
test "checked tier methods" {
  let ctx = DecimalContext::decimal64()
  let a = pm1_exact("0.5")
  let (value, flags) = a.asinpi_ctx(ctx)
  assert_eq(pm1_flags_text(flags), "xr")
  assert_eq(value.to_string(), "0.1666666666666667")
  let (value, _) = a.acospi_ctx(ctx)
  assert_eq(value.to_string(), "0.3333333333333333")
  let (value, _) = pm1_exact("1").atanpi_ctx(ctx)
  assert_eq(value.to_string(), "0.25")
  let (value, _) = pm1_exact("-1").atan2pi_ctx(pm1_exact("-1"), ctx)
  assert_eq(value.to_string(), "-0.75")
}
