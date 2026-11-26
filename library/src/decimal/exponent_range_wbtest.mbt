///|
fn exponent_range_show(result : (Decimal, DecimalFlags)) -> String {
  let (value, flags) = result
  let names = []
  if flags.overflow {
    names.push("overflow")
  }
  if flags.underflow {
    names.push("underflow")
  }
  if flags.inexact {
    names.push("inexact")
  }
  value.to_string() + " [" + names.join(",") + "]"
}

///|
// oracle: A, S
// source: arithmetic: 1e1600000000 is the exponent 1600000000 exactly (not saturated at the context range); a context with e_max 2000000000 is refused, which is the library's limit on e_max (level S)
// shares: Decimal::from_string, DecimalContext::try_new and the plain and _ctx operators (the code under test), exponent_range_show and inspect (print value and flags); also read through to_string and inspect (print the result) (they read the operands and results, not the code under test)
test "literal exponents beyond 1.5e9 are not saturated" {
  inspect(
    Decimal::from_string("1e1600000000").unwrap().to_string(),
    content="1E+1600000000",
  )
  assert_true(DecimalContext::try_new(e_max=2_000_000_000) is Err(_))
}

///|
// oracle: A, S
// source: arithmetic and IEEE 754-2019 4.3: the literals are checked against the library's stored range after the rounding to the precision (level S): 1249e-2147483646 at three digits is 1.25E-2147483643, 12501e-2147483647 the same; the refusals are the literals whose rounded exponent or adjusted exponent is outside the range
// shares: Decimal::from_string, DecimalContext::try_new and the plain and _ctx operators (the code under test), exponent_range_show and inspect (print value and flags); also read through to_string and inspect (print the result) (they read the operands and results, not the code under test)
test "context-free literals outside the stored range are refused, not replaced" {
  // A literal whose value, after the rounding to the precision, has an
  // adjusted exponent above `decimal_value_e_max` or an exponent below
  // `decimal_value_e_tiny` is an error: `from_string` returns the
  // domain error. `from_string_ctx` reads a text with a context when a rounded
  // value is wanted.
  for
    text in [
      "1e3000000000", "-1e3000000000", "12e2147483647", "1e2147483647", "1e99999999999999999999999999",
      "1e-3000000000", "-1e-3000000000", "123e-2147483650", "15e-2147483649", "25e-2147483649",
      "5e-2147483649", "10e-2147483649", "1e-2147483646", "0e2147483647", "0e-2147483646",
      "-0e-3000000000",
    ] {
    assert_true(Decimal::from_string(text) is Err(_), msg=text)
  }
  // The rounding to the precision comes first: the exponent is checked after it.
  inspect(
    Decimal::from_string("1249e-2147483646", precision=3).unwrap(),
    content=(
      #|1.25E-2147483643
    ),
  )
  inspect(
    Decimal::from_string("12501e-2147483647", precision=3).unwrap(),
    content=(
      #|1.25E-2147483643
    ),
  )
  assert_true(Decimal::from_string("1249e-2147483646", precision=3) is Ok(_))
  assert_true(Decimal::from_string("1249e-2147483647", precision=3) is Err(_))
  assert_true(
    Decimal::from_string("2500000001e-2147483657", precision=3) is Err(_),
  )
}

///|
// oracle: A, S
// source: CPython decimal (Context with Emax = e_max, Emin = 1 - e_max, clamp = 1; run 2026-11-26) for the rows with e_max 999999999 (1E+1500000000 squared and divided by 1E-1500000000 overflow, 1E-1500000000 squared rounds up to 1E-1000000031 with underflow, divided by 1E+1500000000 gives 0E-1000000031 with underflow, fma with 1 under Up gives 1.000000000000000000000000000000001 inexact); the rows of the plain operators beyond that context follow the library's working range (largest adjusted exponent 2147483646, smallest exponent -2147483645, level S) and IEEE 754-2019 4.3, 7.4
// shares: Decimal::from_string, DecimalContext::try_new and the plain and _ctx operators (the code under test), exponent_range_show and inspect (print value and flags); also read through neg and unary minus, to_string and inspect (print the result) (they read the operands and results, not the code under test)
test "products and quotients of extreme exponents do not wrap" {
  let big = Decimal::from_string("1E+1500000000").unwrap()
  let small = Decimal::from_string("1E-1500000000").unwrap()
  let ctx = DecimalContext::new(e_max=999_999_999)
  let up = DecimalContext::new(e_max=999_999_999).with_round(DecimalRound::Up)
  inspect(
    exponent_range_show(big.mul_ctx(big, ctx)),
    content=(
      #|inf [overflow,inexact]
    ),
  )
  inspect(
    exponent_range_show(small.mul_ctx(small, up)),
    content=(
      #|1E-1000000031 [underflow,inexact]
    ),
  )
  inspect(
    exponent_range_show(big.div_ctx(small, ctx)),
    content=(
      #|inf [overflow,inexact]
    ),
  )
  inspect(
    exponent_range_show(small.div_ctx(big, ctx)),
    content=(
      #|0E-1000000031 [underflow,inexact]
    ),
  )
  inspect(
    exponent_range_show(big.fma_ctx(big, Decimal::one(), ctx)),
    content=(
      #|inf [overflow,inexact]
    ),
  )
  inspect(
    exponent_range_show(small.fma_ctx(small, Decimal::one(), up)),
    content=(
      #|1.000000000000000000000000000000001 [inexact]
    ),
  )
  inspect(big * big, content="inf")
  inspect(-big * big, content="-inf")
  inspect(small * small, content="0E-2147483645")
  inspect(-small * small, content="-0E-2147483645")
  inspect(big / small, content="inf")
  inspect(small / big, content="0E-2147483645")
  inspect(big * small, content="1")
  // Below the range of the working context of the plain operators (smallest
  // exponent -2147483645) the result is rounded half-even to that exponent,
  // here to a zero: the plain operator is the `_ctx` operation in that context.
  let d = fn(s : String) { Decimal::from_string(s).unwrap() }
  inspect(
    d("123E-2147483640") * d("1E-10"),
    content=(
      #|0E-2147483645
    ),
  )
  inspect(
    d("10E-2147483640") * d("1E-9"),
    content=(
      #|0E-2147483645
    ),
  )
  inspect(
    d("3E-2147483640") / d("2E+8"),
    content=(
      #|0E-2147483645
    ),
  )
  inspect(
    d("1E-2147483640") / d("3E+7"),
    content=(
      #|0E-2147483645
    ),
  )
  inspect(
    d("-1E-2147483640") / d("3E+9"),
    content=(
      #|-0E-2147483645
    ),
  )
  // A sum that rounds up past the largest adjusted exponent (2147483646) overflows.
  let nines = d("9999999999999999999999999999999999E+2147483613")
  inspect(nines + d("5E+2147483612"), content="inf")
  inspect(-nines - d("5E+2147483612"), content="-inf")
  inspect(
    nines + d("4E+2147483612"),
    content="9.999999999999999999999999999999999E+2147483646",
  )
  // Rounding at the top of the range overflows according to the mode.
  let top = d("9999E+2147483643")
  inspect(top.with_precision_round(2, DecimalRound::Up), content="inf")
  inspect(
    top.with_precision(2, DecimalRoundingMode::RoundTowardZero),
    content="9.9E+2147483646",
  )
}
