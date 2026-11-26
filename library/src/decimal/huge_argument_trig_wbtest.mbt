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
// oracle: A
// source: IEEE 754-2019 9.2.1 (sinPi, cosPi and tanPi lists, read from the PDF text): sinPi(+n) is +0 and sinPi(-n) is -0 for an integer n, cosPi of an even integer is 1, tanPi(2n) is +0 and tanPi(-2n) is -0, cosPi(3) is -1, sinPi(-3) is -0 and tanPi(2n + 1) is -0; the operands 1E+20000, 1E+999999 and 7.5E+400000 are even integers; written out
// shares: huge_trig_show (prints value and flags through to_string), Decimal::from_string, try_sinpi_ctx, try_cospi_ctx, try_tanpi_ctx and try_sin_ctx (the code under test)
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
// oracle: A
// source: mathematics and IEEE 754-2019 4.3: cosPi(x) = 1 - pi^2 x^2 / 2 + ... is just below 1 for tiny x (the deficit is far below one unit at 16 digits), so toward negative and toward zero give 0.9999999999999999 and to nearest, toward positive and away give 1.000000000000000, all inexact; written out
// shares: huge_trig_show (prints value and flags through to_string), Decimal::from_string, try_sinpi_ctx, try_cospi_ctx, try_tanpi_ctx and try_sin_ctx (the code under test)
test "cospi next to zero is decided before the loop in every direction" {
  let rows : Array[(DecimalRound, String)] = [
    (DecimalRound::HalfEven, "1.000000000000000 x"),
    (DecimalRound::Floor, "0.9999999999999999 x"),
    (DecimalRound::Down, "0.9999999999999999 x"),
    (DecimalRound::Ceiling, "1.000000000000000 x"),
    (DecimalRound::Up, "1.000000000000000 x"),
  ]
  for x in ["1E-999999", "-3E-999999", "1E-1999996", "9E-1999997"] {
    for row in rows {
      let ctx = DecimalContext::new(precision=16, e_max=384).with_round(row.0)
      assert_eq(
        "cospi(\{x}): " +
        huge_trig_show(fn(v, c) { v.try_cospi_ctx(c) }, x, ctx),
        "cospi(\{x}): \{row.1}",
      )
    }
  }
}

///|
// oracle: A
// source: row huge_trig-00000 of testdata/decimal/ieee/rows/huge_trig.txt (MPFR 4.2.2 at the exact operand, rounded by libmpdec; generator tools/generate_decimal_huge_trig_rows.py): sin(1E+20000) at 16 digits is 0.3438070363959716, inexact; note: the generator's --check reports the binary table library/src/binary/huge_argument_trig_wbtest.mbt stale, not this row file
// shares: huge_trig_show (prints value and flags through to_string), Decimal::from_string, try_sinpi_ctx, try_cospi_ctx, try_tanpi_ctx and try_sin_ctx (the code under test)
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
