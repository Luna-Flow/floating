// floating#377: sinpi, cospi and tanpi of a huge integer, cospi next to zero and
// sin of an argument beyond the old cutoff. Expected values:
// testdata/decimal/ieee/rows/huge_trig.txt (the full gate runs all 84 rows;
// the `1E+300000` to `1E+999999` operands of sin, cos and tan are in
// huge_trig_extreme.txt, run on demand).

///|
fn huge_trig_show(
  f : (Decimal, DecimalContext) -> Result[
    (Decimal, DecimalFlags),
    @def.ArithmeticError,
  ],
  x : String,
  ctx : DecimalContext,
) -> String {
  match f(Decimal::from_string(x).unwrap(), ctx) {
    Ok((value, flags)) =>
      value.to_string() +
      (if flags.inexact { " x" } else { "" }) +
      (if flags.division_by_zero { " z" } else { "" })
    Err(e) => "Err " + e.message
  }
}

///|
test "sinpi, cospi, tanpi of a huge even integer are exact without expanding it" {
  let ctx = DecimalContext::decimal64()
  for x in ["1E+20000", "1E+999999", "7.5E+400000"] {
    inspect(
      huge_trig_show(fn(v, c) { v.try_sinpi_ctx(c) }, x, ctx),
      content="0",
    )
    inspect(
      huge_trig_show(fn(v, c) { v.try_cospi_ctx(c) }, x, ctx),
      content="1",
    )
    inspect(
      huge_trig_show(fn(v, c) { v.try_tanpi_ctx(c) }, x, ctx),
      content="0",
    )
  }
  for x in ["-1E+300000", "-5E+999998"] {
    inspect(
      huge_trig_show(fn(v, c) { v.try_sinpi_ctx(c) }, x, ctx),
      content="-0",
    )
    inspect(
      huge_trig_show(fn(v, c) { v.try_cospi_ctx(c) }, x, ctx),
      content="1",
    )
    inspect(
      huge_trig_show(fn(v, c) { v.try_tanpi_ctx(c) }, x, ctx),
      content="-0",
    )
  }
  // The boundary of the rule: 1E+1 and 1E+0 take the expanded path.
  inspect(
    huge_trig_show(fn(v, c) { v.try_cospi_ctx(c) }, "10", ctx),
    content="1",
  )
  inspect(
    huge_trig_show(fn(v, c) { v.try_cospi_ctx(c) }, "3", ctx),
    content="-1",
  )
  inspect(
    huge_trig_show(fn(v, c) { v.try_sinpi_ctx(c) }, "-3", ctx),
    content="-0",
  )
  inspect(
    huge_trig_show(fn(v, c) { v.try_tanpi_ctx(c) }, "3", ctx),
    content="-0",
  )
}

///|
test "cospi next to zero is decided before the loop in every direction" {
  let rows : Array[(DecimalRoundingMode, String)] = [
    (DecimalRoundingMode::HalfEven, "1.000000000000000 x"),
    (DecimalRoundingMode::Floor, "0.9999999999999999 x"),
    (DecimalRoundingMode::Down, "0.9999999999999999 x"),
    (DecimalRoundingMode::Ceiling, "1.000000000000000 x"),
    (DecimalRoundingMode::Up, "1.000000000000000 x"),
  ]
  for x in ["1E-999999", "-3E-999999", "1E-1999996", "9E-1999997"] {
    for row in rows {
      let ctx = DecimalContext::new(
        precision=16,
        decimal_rounding=row.0,
        e_min=-383,
        e_max=384,
      )
      assert_eq(
        "cospi(\{x}): " +
        huge_trig_show(fn(v, c) { v.try_cospi_ctx(c) }, x, ctx),
        "cospi(\{x}): \{row.1}",
      )
    }
  }
}

///|
test "sin of 1E+20000 beyond the old cutoff" {
  // huge_trig-00000: MPFR 4.2.2 at the exact operand rounds to this.
  inspect(
    huge_trig_show(
      fn(v, c) { v.try_sin_ctx(c) },
      "1E+20000",
      DecimalContext::decimal64(),
    ),
    content="0.3438070363959716 x",
  )
}
