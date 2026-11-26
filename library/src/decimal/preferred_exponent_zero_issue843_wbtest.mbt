///|
fn issue843_flags(flags : DecimalFlags) -> String {
  (if flags.inexact { "x" } else { "." }) +
  (if flags.underflow { "u" } else { "." }) +
  (if flags.overflow { "o" } else { "." }) +
  (if flags.division_by_zero { "z" } else { "." }) +
  (if flags.invalid_operation { "i" } else { "." })
}

///|
fn issue843_int(text : String) -> Int32 {
  let mut value = 0
  let mut negative = false
  for ch in text {
    if ch == '-' {
      negative = true
    } else {
      value = value * 10 + (ch.to_int() - '0'.to_int())
    }
  }
  if negative {
    -value
  } else {
    value
  }
}

///|
fn issue843_context(name : String) -> DecimalContext {
  match name {
    "d64" => DecimalContext::decimal64()
    "d32" => DecimalContext::decimal32()
    _ => { ..DecimalContext::decimal32(), clamp: false, }
  }
}

///|
// oracle: A
// source: expected strings written out by hand from IEEE 754-2019 9.2.2, which gives Q(compound(x, n)) = floor(n * min(0, Q(x))), Q(pow(x, y)) = Q(powr(x, y)) = floor(y * Q(x)), Q(pown(x, n)) = floor(n * Q(x)), Q(rootn(x, n)) = floor(Q(x) / n), Q(hypot(x, y)) = min(Q(x), Q(y)); each row's exponent is that formula evaluated with Q(x) read from the operand text, then held to the exponents of the format (Etiny, and Etop when the context clamps, else e_max) as 5.2 selects the member closest to the preferred exponent. The values are zero or the other operand, exact in every row, so no flag is raised.
// shares: Decimal::from_string (builds the operands from their text, so the cohort of each operand is the one its text gives), issue843_int and issue843_flags (convert the count and print the flags) and Decimal::to_string (prints the result, whose exponent is what is compared); compound_ctx, pown_ctx, rootn_ctx, pow_ctx, powr_ctx and hypot_ctx are the code under test
test "an exact zero result takes the preferred exponent of 9.2.2 (#843)" {
  // (operation, context, x, y or n, expected); no flag in any row.
  let rows : Array[(String, String, String, String, String)] = [
    // compound(-1, n) = +0 for n > 0: Q = floor(n * min(0, Q(x)))
    ("compound", "d64", "-1.0", "2", "0.00"),
    ("compound", "d64", "-1.0", "3", "0.000"),
    ("compound", "d64", "-1.00", "2", "0.0000"),
    ("compound", "d64", "-1.0", "1", "0.0"),
    ("compound", "d64", "-1", "2", "0"),
    ("compound", "d64", "-1.0", "2147483647", "0E-398"),
    ("compound", "d32", "-1.0", "1000", "0E-101"),
    // pow(+-0, y) for y > 0: Q = floor(y * Q(x))
    ("pow", "d64", "0.00", "2", "0.0000"),
    ("pow", "d64", "0.0", "3", "0.000"),
    ("pow", "d64", "0E-3", "2", "0.000000"),
    ("pow", "d64", "0", "2", "0"),
    ("pow", "d64", "-0.0", "3", "-0.000"),
    ("pow", "d64", "-0.0", "2", "0.00"),
    ("pow", "d64", "0.00", "1.5", "0.000"),
    ("pow", "d64", "0.00", "2.5", "0.00000"),
    ("pow", "d64", "0.0", "0.25", "0.0"),
    ("pow", "d64", "0E+3", "2", "0E+6"),
    ("pow", "d64", "0E+3", "1.5", "0E+4"),
    ("pow", "d64", "0.00", "0.5", "0.0"),
    // pown(+-0, n) for n > 0: Q = floor(n * Q(x))
    ("pown", "d64", "0.00", "3", "0.000000"),
    ("pown", "d64", "0.0", "2", "0.00"),
    ("pown", "d64", "-0.00", "3", "-0.000000"),
    ("pown", "d64", "0E+2", "2", "0E+4"),
    ("pown", "d64", "0.00", "1", "0.00"),
    ("pown", "d64", "0.00", "0", "1"),
    // powr(+0, y) for y > 0: Q = floor(y * Q(x))
    ("powr", "d64", "0.00", "2", "0.0000"),
    ("powr", "d64", "0.0", "1.5", "0.00"),
    ("powr", "d64", "0E+2", "3", "0E+6"),
    // rootn(+-0, n) for n > 0: Q = floor(Q(x) / n)
    ("rootn", "d64", "0.00", "3", "0.0"),
    ("rootn", "d64", "0.0", "2", "0.0"),
    ("rootn", "d64", "0.00", "2", "0.0"),
    ("rootn", "d64", "0E+4", "2", "0E+2"),
    ("rootn", "d64", "0E+3", "3", "0E+1"),
    ("rootn", "d64", "0E-5", "2", "0.000"),
    ("rootn", "d64", "-0.00", "3", "-0.0"),
    ("rootn", "d64", "-0.00", "2", "0.0"),
    // hypot: Q = min(Q(x), Q(y)); a zero operand leaves the other operand
    ("hypot", "d64", "0.00", "0.0", "0.00"),
    ("hypot", "d64", "0E+2", "0E-3", "0.000"),
    ("hypot", "d64", "-0.0", "-0.00", "0.00"),
    ("hypot", "d64", "0.00", "3.0", "3.00"),
    ("hypot", "d64", "3.0", "0.00", "3.00"),
    ("hypot", "d64", "0E-3", "3.0", "3.000"),
    ("hypot", "d64", "0E+2", "3", "3"),
    ("hypot", "d64", "3.0", "4.00", "5.00"),
    // the exponent is held to the format: Etiny = -101 and Etop = 90 in
    // decimal32 (p = 7, e_max = 96); without clamp the top is e_max = 96
    ("pown", "d32", "0E-60", "3", "0E-101"),
    ("pown", "d32", "0E+60", "3", "0E+90"),
    ("pown", "d32 unclamped", "0E+60", "3", "0E+96"),
    ("hypot", "d32", "0E+95", "0E+94", "0E+90"),
  ]
  for row in rows {
    let (op, ctx_name, operand, count, expected) = row
    let ctx = issue843_context(ctx_name)
    let base = Decimal::from_string(operand).unwrap()
    let (value, flags) = match op {
      "compound" => base.compound_ctx(issue843_int(count), ctx)
      "pown" => base.pown_ctx(issue843_int(count), ctx)
      "rootn" => base.rootn_ctx(issue843_int(count), ctx)
      "pow" => base.pow_ctx(Decimal::from_string(count).unwrap(), ctx)
      "powr" => base.powr_ctx(Decimal::from_string(count).unwrap(), ctx)
      _ => base.hypot_ctx(Decimal::from_string(count).unwrap(), ctx)
    }
    assert_eq(
      (op, ctx_name, operand, count, value.to_string(), issue843_flags(flags)),
      (op, ctx_name, operand, count, expected, "....."),
    )
  }
}
