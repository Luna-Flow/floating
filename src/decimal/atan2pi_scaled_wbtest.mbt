///|
// atan2Pi with operands of extreme exponents (#378): the result depends on the
// ratio only, and for a ratio below 10^(D+1), D <= -77 for precision 7, it is
// the enclosure of (sy / sx pi)(1 - e) shifted by D (0 <= e <= r^2). The tests
// compare the scaled path with `atanpi` of the exact ratio (a separate
// certified implementation) on both sides of the threshold and with the same
// ratio at moderate exponents, in all eight rounding directions.

///|
fn atan2pi_scaled_same(
  a : String,
  b : String,
  ctx : DecimalContext,
) -> Unit raise {
  assert_eq(a, b, msg="\{ctx.precision()}")
}

///|
test "atan2pi tiny ratio equals atanpi of the ratio on both sides of the threshold" {
  for mode in pm1_modes {
    for p in [7, 16, 34] {
      let ctx = pm1_ctx(p, mode, -383, 384, false, "b")
      // 2 D + 2 <= -t where 3 t >= 8 p + 400; D runs through the threshold.
      let threshold = -((8 * p + 400 + 2) / 6 + 1)
      for
        d in [
          threshold - 40,
          threshold - 3,
          threshold - 1,
          threshold,
          threshold + 1,
          threshold + 3,
          threshold + 40,
        ] {
        let y = "3E\{d}"
        let direct = pii_call("atan2pi", y, "1", ctx)
        let via_atanpi = pii_call("atanpi", y, "", ctx)
        atan2pi_scaled_same(direct, via_atanpi, ctx)
        // The same ratio from a longer abscissa: y / x = 3E<d> / 1.
        let scaled = pii_call("atan2pi", "6E\{d}", "2", ctx)
        atan2pi_scaled_same(scaled, via_atanpi, ctx)
      }
    }
  }
}

///|
test "atan2pi with both operands of extreme exponent equals the moderate ratio" {
  for mode in pm1_modes {
    let ctx = pm1_ctx(16, mode, -383, 384, false, "b")
    for e in ["1999996", "5000", "300"] {
      for pair in [("3", "2"), ("7", "9"), ("1.5", "4")] {
        let moderate = pii_call("atan2pi", pair.0, pair.1, ctx)
        let extreme = pii_call(
          "atan2pi",
          pair.0 + "E-" + e,
          pair.1 + "E-" + e,
          ctx,
        )
        atan2pi_scaled_same(extreme, moderate, ctx)
        let negative_x = pii_call(
          "atan2pi",
          pair.0 + "E-" + e,
          "-" + pair.1 + "E-" + e,
          ctx,
        )
        let negative_x_moderate = pii_call("atan2pi", pair.0, "-" + pair.1, ctx)
        atan2pi_scaled_same(negative_x, negative_x_moderate, ctx)
      }
    }
  }
}

///|
test "atan2pi of a tiny ordinate and abscissa 1 underflows (#378)" {
  // 1E-1999996 / pi is below half of the smallest subnormal: 0 or the least
  // subnormal by direction (IEEE 754-2019 7.5, 9.2), with the sign of y.
  let ctx = pm1_ctx(7, "half_even", -95, 96, true, "b")
  assert_eq(pii_call("atan2pi", "1E-1999996", "1", ctx), "0E-101 xrsuc")
  assert_eq(pii_call("atan2pi", "-1E-1999996", "1", ctx), "-0E-101 xrsuc")
  let up = pm1_ctx(7, "up", -95, 96, true, "b")
  assert_eq(pii_call("atan2pi", "1E-1999996", "1", up), "1E-101 xrsu")
}

///|
test "atan2pi generated rows: both sides of the scaled condition, all signs and directions" {
  // Expected values are independent of the library (Python decimal at 450
  // digits, tools/generate_decimal_atan2pi_scaled_rows.py); the clause is
  // IEEE 754-2019 9.2 (correct rounding) with 7.5 (underflow) for the tiny
  // results and the sign of the ordinate (9.2.1, atan2Pi).
  let failures = StringBuilder()
  let mut count = 0
  let rows = atan2pi_scaled_rows()
  for row in rows {
    let (op, rounding, precision, e_min, e_max, clamp, y, x, expected, flags) = row
    let ctx = pm1_ctx(precision, rounding, e_min, e_max, clamp, "b")
    let got = if op == "atan2" {
      match pm1_exact(y).try_atan2_ctx(pm1_exact(x), ctx) {
        Ok((value, f)) => "\{value} \{pm1_flags_text(f)}"
        Err(_) => "certification-failure"
      }
    } else {
      pii_call("atan2pi", y, x, ctx)
    }
    let parts = got.split(" ").map(fn(s) { s.to_owned() }).collect()
    let ok = parts.length() == 2 &&
      pm1_exact(parts[0]).compare_total(pm1_exact(expected)) == 0 &&
      parts[1] == flags
    if !ok {
      count += 1
      if count <= 20 {
        failures.write_string(
          "\{op} \{rounding} p=\{precision} [\{e_min},\{e_max}] clamp=\{clamp} y=\{y} x=\{x}: want \{expected} \{flags}, got \{got}\n",
        )
      }
    }
  }
  inspect(failures.to_string(), content="")
  assert_true(rows.length() > 7000)
}
