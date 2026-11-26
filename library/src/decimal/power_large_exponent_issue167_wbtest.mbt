///|
fn power_issue167_case(result : (Decimal, DecimalFlags)) -> String {
  let (value, flags) = result
  let mut text = value.to_string()
  if flags.inexact {
    text = text + " inexact"
  }
  if flags.underflow {
    text = text + " underflow"
  }
  if flags.overflow {
    text = text + " overflow"
  }
  if flags.division_by_zero {
    text = text + " division_by_zero"
  }
  if flags.invalid_operation {
    text = text + " invalid_operation"
  }
  text
}

///|
/// IEEE 754-2019 §9.2.1 defines integral powers independently of the
/// implementation's bounded integer-power loop.
// oracle: A
// source: IEEE 754-2019 9.2.1 (pow and pown lists, read from the PDF text), 7.4 and 7.5 and CPython decimal at 120 to 200 digits, rounded once to the context (the digits after the kept ones are not borderline): (-2)^(1E+30) overflows to +inf (even exponent), (-0.5)^(+-1E+30) underflows to 0E-398 or overflows to +inf, (-1.000000000000001)^12345678901234567 = -229964.1948529869 and its reciprocal power = -0.000004348503038219871 (odd exponent, negative), (-0)^(-12345678901234567) is -inf with divideByZero; written out
// shares: Decimal::from_string (the local d: builds the operands), to_string and power_issue167_case (print value and flags), pow_ctx, pown_ctx, exp2_ctx and exp10_ctx (the code under test)
test "decimal power handles integral exponents beyond the bounded count" {
  let ctx = DecimalContext::decimal64()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  inspect(
    power_issue167_case(d("-2").pow_ctx(d("1E+30"), ctx)),
    content=(
      #|inf inexact overflow
    ),
  )
  inspect(
    power_issue167_case(d("-0.5").pow_ctx(d("1E+30"), ctx)),
    content=(
      #|0E-398 inexact underflow
    ),
  )
  inspect(
    power_issue167_case(d("-0.5").pow_ctx(d("-1E+30"), ctx)),
    content=(
      #|inf inexact overflow
    ),
  )
  inspect(
    power_issue167_case(
      d("-1.000000000000001").pow_ctx(d("12345678901234567"), ctx),
    ),
    content=(
      #|-229964.1948529869 inexact
    ),
  )
  inspect(
    power_issue167_case(d("-0").pow_ctx(d("-12345678901234567"), ctx)),
    content=(
      #|-inf division_by_zero
    ),
  )
  inspect(
    power_issue167_case(
      d("-1.000000000000001").pow_ctx(d("-12345678901234567"), ctx),
    ),
    content=(
      #|-0.000004348503038219871 inexact
    ),
  )
}

///|
/// IEEE 754-2019 §9.2.1 also defines zero and infinite bases for arbitrary
/// integral exponents, including the limits of the Int representation.
// oracle: A
// source: IEEE 754-2019 9.2.1 (pow and pown lists, read from the PDF text), 7.4 and 7.5: pow(+-0, y) for large integral y, pow(+-inf, y) and pown(+-0 or +-inf, n) at the Int32 limits follow the sign rules of odd and even exponents (+0, -0, +inf, -inf, +inf with divideByZero for -0 to a negative even power); the 1E+30 and 12345678901234567 exponents are even and odd respectively; written out
// shares: Decimal::from_string (the local d: builds the operands), to_string and power_issue167_case (print value and flags), pow_ctx, pown_ctx, exp2_ctx and exp10_ctx (the code under test)
test "decimal power handles zero and infinity at large integer exponents" {
  let ctx = DecimalContext::decimal64()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  inspect(
    power_issue167_case(d("0").pow_ctx(d("1E+30"), ctx)),
    content=(
      #|0
    ),
  )
  inspect(
    power_issue167_case(d("Inf").pow_ctx(d("1E+30"), ctx)),
    content=(
      #|inf
    ),
  )
  inspect(
    power_issue167_case(d("-0").pow_ctx(d("12345678901234567"), ctx)),
    content=(
      #|-0
    ),
  )
  inspect(
    power_issue167_case(d("-0").pow_ctx(d("-1E+30"), ctx)),
    content=(
      #|inf division_by_zero
    ),
  )
  inspect(
    power_issue167_case(d("-Inf").pow_ctx(d("12345678901234567"), ctx)),
    content=(
      #|-inf
    ),
  )
  inspect(
    power_issue167_case(d("-Inf").pow_ctx(d("-12345678901234567"), ctx)),
    content=(
      #|-0
    ),
  )
  inspect(
    power_issue167_case(d("0").pown_ctx(2147483647, ctx)),
    content=(
      #|0
    ),
  )
  inspect(
    power_issue167_case(d("-0").pown_ctx(2147483647, ctx)),
    content=(
      #|-0
    ),
  )
  inspect(
    power_issue167_case(d("Inf").pown_ctx(2147483647, ctx)),
    content=(
      #|inf
    ),
  )
  inspect(
    power_issue167_case(d("-Inf").pown_ctx(2147483647, ctx)),
    content=(
      #|-inf
    ),
  )
  inspect(
    power_issue167_case(d("Inf").pown_ctx(-2147483648, ctx)),
    content=(
      #|0
    ),
  )
  inspect(
    power_issue167_case(d("-Inf").pown_ctx(-2147483648, ctx)),
    content=(
      #|0
    ),
  )
}

///|
/// A zero base has a defined result for a tiny positive non-integral exponent;
/// operand range checks must not turn this domain case into Invalid operation.
// oracle: A
// source: IEEE 754-2019 9.2.1 (pow and pown lists, read from the PDF text), 7.4 and 7.5: pow(+-0, y) is +0 for finite y > 0 that is not an odd integer and +inf with divideByZero for finite y < 0 that is not an odd integer, for the tiny exponents +-1E-2000000 as for any other; written out
// shares: Decimal::from_string (the local d: builds the operands), to_string and power_issue167_case (print value and flags), pow_ctx, pown_ctx, exp2_ctx and exp10_ctx (the code under test)
test "decimal power keeps zero defined for tiny nonintegral exponents" {
  let ctx = DecimalContext::decimal64()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  inspect(
    power_issue167_case(d("0").pow_ctx(d("1E-2000000"), ctx)),
    content=(
      #|0
    ),
  )
  inspect(
    power_issue167_case(d("-0").pow_ctx(d("1E-2000000"), ctx)),
    content=(
      #|0
    ),
  )
  inspect(
    power_issue167_case(d("0").pow_ctx(d("-1E-2000000"), ctx)),
    content=(
      #|inf division_by_zero
    ),
  )
  inspect(
    power_issue167_case(d("-0").pow_ctx(d("-1E-2000000"), ctx)),
    content=(
      #|inf division_by_zero
    ),
  )
}

///|
/// Negating a positive result must reverse directed rounding, so negative-base
/// odd powers use the mirrored magnitude context before certification.
// oracle: S
// source: odd symmetry of the power, (-x)^n = -(x^n) with the directed rounding mirrored (ceiling for floor); the positive-base power is the oracle, the same function in the mirrored mode, and no value is written out
// shares: Decimal::from_string, pow_ctx, neg and with_rounding (the code under test on both sides)
test "decimal large negative-base powers mirror directed rounding" {
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  let base = d("-1.000000000000001")
  let exponent = d("12345678901234567")
  let down = DecimalContext::decimal64().with_rounding(
    DecimalRoundingMode::RoundTowardNegative,
  )
  let up = DecimalContext::decimal64().with_rounding(
    DecimalRoundingMode::RoundTowardPositive,
  )
  assert_eq(
    base.pow_ctx(exponent, up).0.to_string(),
    d("1.000000000000001").pow_ctx(exponent, down).0.neg().to_string(),
  )
  assert_eq(
    base.pow_ctx(exponent, down).0.to_string(),
    d("1.000000000000001").pow_ctx(exponent, up).0.neg().to_string(),
  )
}

///|
/// The ordinary context has the full representation exponent range. An
/// integer power remains defined there even when its count exceeds the
/// bounded square-and-multiply helper.
// oracle: A
// source: CPython decimal at 120 to 200 digits, rounded once to the context (the digits after the kept ones are not borderline) (Context(prec=34, Emax=999999999)): 1.0000000000001^(1E+11), 0.999999^1000000001, (-1.000001)^1000000001, 2^(1E+9) and 1.01^(1E+10) as written out, all inexact and with no overflow, underflow or invalid flag; the digits after the 34th are 8578, 8510, 7307, 0187 and 7435 (not at a rounding boundary)
// shares: Decimal::from_string (the local d: builds the operands), to_string and power_issue167_case (print value and flags), pow_ctx, pown_ctx, exp2_ctx and exp10_ctx (the code under test)
test "decimal large integer powers work in the default context" {
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  let context = DecimalContext::new(e_max=999_999_999)
  let cases = [
    ("1.0000000000001", "1E+11", "1.010050167084167552517081914852626"),
    ("0.999999", "1000000001", "5.073416477377115719975853397616633E-435"),
    ("-1.000001", "1000000001", "-1.969088294420576654510139814956395E+434"),
    ("2", "1E+9", "4.612976001169069393116119221037316E+301029995"),
    ("1.01", "1E+10", "6.705416252570703534199491376911599E+43213737"),
  ]
  for (base, exponent, expected) in cases {
    let (value, flags) = d(base).pow_ctx(d(exponent), context)
    assert_eq(value.to_string(), expected)
    assert_true(flags.inexact)
    assert_false(flags.invalid_operation)
    assert_false(flags.division_by_zero)
    assert_false(flags.overflow)
    assert_false(flags.underflow)
  }
}

///|
/// Exponents whose exact coefficient exceeds the bounded materialization
/// budget are never expanded: the magnitude of `y ln|x|` decides overflow or
/// underflow directly (#196), so `2^(1E+9999999)` overflows instead of
/// returning invalid_context, with no expansion of millions of decimal limbs
/// and no unbounded certification loop.
// oracle: A, S
// source: arithmetic and IEEE 754-2019 7.4, 7.5: 2^(1E+9999999) exceeds any decimal range (log10 is about 3E+9999998) and overflows to infinity with overflow and inexact, 0.5^(1E+9999999) underflows to zero with underflow and inexact; exp2 and exp10 of 1E+9999999 are not computed (a design limit of those functions, level S: NaN with not_computed and no invalid operation)
// shares: Decimal::from_string (the local d: builds the operands), to_string and power_issue167_case (print value and flags), pow_ctx, pown_ctx, exp2_ctx and exp10_ctx (the code under test)
test "decimal large integer powers enforce the expansion budget" {
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  let context = DecimalContext::new(e_max=999_999_999)
  let (value, flags) = d("2").pow_ctx(d("1E+9999999"), context)
  assert_true(value.is_infinite())
  assert_true(flags.overflow && flags.inexact)
  let (exp2, exp2_flags) = d("1E+9999999").exp2_ctx(context)
  let (exp10, exp10_flags) = d("1E+9999999").exp10_ctx(context)
  // `exp2` and `exp10` reject such arguments before they reach `power_ctx`.
  assert_true(exp2.is_nan())
  assert_true(exp2_flags.not_computed && !exp2_flags.invalid_operation)
  assert_true(exp10.is_nan())
  assert_true(exp10_flags.not_computed && !exp10_flags.invalid_operation)
  let (small, small_flags) = d("0.5").pow_ctx(d("1E+9999999"), context)
  assert_true(small.is_zero())
  assert_true(small_flags.underflow && small_flags.inexact)
}

///|
/// The expected strings below were generated independently with Python's
/// `decimal` module at precision 34 and the same exponent bounds.  Directed
/// rounding must survive the large integer route, including sign reversal.
// oracle: A
// source: CPython decimal at 120 to 200 digits, rounded once to the context (the digits after the kept ones are not borderline): 2^(1E+9) = 4.612976001169069393116119221037316|0187... E+301029995, so nearest, toward zero and toward negative give ...316 and away, toward positive give ...317; (-1.000001)^1000000001 = -1.969088294420576654510139814956394|7... E+434, so toward positive gives ...394 and toward negative ...395 (the sign reverses the direction); the values are written out
// shares: Decimal::from_string (the local d: builds the operands), to_string and power_issue167_case (print value and flags), pow_ctx, pown_ctx, exp2_ctx and exp10_ctx (the code under test)
test "decimal large integer powers honor all rounding modes" {
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  let context = DecimalContext::new(e_max=999_999_999)
  let modes = [
    (
      RoundingMode::ToNearestEven,
      "4.612976001169069393116119221037316E+301029995",
    ),
    (
      RoundingMode::AwayFromZero,
      "4.612976001169069393116119221037317E+301029995",
    ),
    (RoundingMode::TowardZero, "4.612976001169069393116119221037316E+301029995"),
    (
      RoundingMode::TowardPositive,
      "4.612976001169069393116119221037317E+301029995",
    ),
    (
      RoundingMode::TowardNegative,
      "4.612976001169069393116119221037316E+301029995",
    ),
  ]
  for (mode, expected) in modes {
    let (value, flags) = d("2").pow_ctx(
      d("1E+9"),
      context.with_round(DecimalRound::from_arithmetic(mode)),
    )
    assert_eq(value.to_string(), expected)
    assert_true(flags.inexact)
  }
  let (ceiling, _) = d("-1.000001").pow_ctx(
    d("1000000001"),
    context.with_rounding(DecimalRoundingMode::RoundTowardPositive),
  )
  let (floor, _) = d("-1.000001").pow_ctx(
    d("1000000001"),
    context.with_rounding(DecimalRoundingMode::RoundTowardNegative),
  )
  assert_eq(ceiling.to_string(), "-1.969088294420576654510139814956394E+434")
  assert_eq(floor.to_string(), "-1.969088294420576654510139814956395E+434")
}

///|
/// Mirror the independent Python 34-digit oracle for an odd negative-base
/// exponent. These absolute expected values kill a lost-parity or rounding
/// direction regression without comparing the implementation to itself.
// oracle: A
// source: CPython decimal at 120 to 200 digits, rounded once to the context (the digits after the kept ones are not borderline): (-1.000001)^1000000001 at 34 digits is -1.969088294420576654510139814956394E+434 toward positive and ...395 toward negative, both inexact; written out
// shares: Decimal::from_string (the local d: builds the operands), to_string and power_issue167_case (print value and flags), pow_ctx, pown_ctx, exp2_ctx and exp10_ctx (the code under test)
test "decimal large integer negative powers match directed oracle values" {
  let base = Decimal::from_string("-1.000001").unwrap()
  let exponent = Decimal::from_string("1000000001").unwrap()
  let context = DecimalContext::new(e_max=999_999_999)
  let (ceiling, ceiling_flags) = base.pow_ctx(
    exponent,
    context.with_rounding(DecimalRoundingMode::RoundTowardPositive),
  )
  let (floor, floor_flags) = base.pow_ctx(
    exponent,
    context.with_rounding(DecimalRoundingMode::RoundTowardNegative),
  )
  assert_eq(ceiling.to_string(), "-1.969088294420576654510139814956394E+434")
  assert_eq(floor.to_string(), "-1.969088294420576654510139814956395E+434")
  assert_true(ceiling_flags.inexact)
  assert_true(floor_flags.inexact)
}

///|
/// Python decimal p=9 oracle strings for the default exponent limits.
// oracle: A
// source: CPython decimal at 120 to 200 digits, rounded once to the context (the digits after the kept ones are not borderline) (Context(prec=9, Emax=999999999)): the five bases and exponents of the default-context block rounded to nine digits as written out, all inexact
// shares: Decimal::from_string (the local d: builds the operands), to_string and power_issue167_case (print value and flags), pow_ctx, pown_ctx, exp2_ctx and exp10_ctx (the code under test)
test "decimal large integer powers work at precision nine" {
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  let context = DecimalContext::new(precision=9, e_max=999_999_999)
  let cases = [
    ("1.0000000000001", "1E+11", "1.01005017"),
    ("0.999999", "1000000001", "5.07341648E-435"),
    ("-1.000001", "1000000001", "-1.96908829E+434"),
    ("2", "1E+9", "4.61297600E+301029995"),
    ("1.01", "1E+10", "6.70541625E+43213737"),
  ]
  for (base, exponent, expected) in cases {
    let (value, flags) = d(base).pow_ctx(d(exponent), context)
    assert_eq(value.to_string(), expected)
    assert_true(flags.inexact)
  }
}

///|
/// Decimal spellings with trailing zeros must share the same parity and
/// bounded power path as their canonical coefficient form.
// oracle: A
// source: IEEE 754-2019 9.2.1 (pow and pown lists, read from the PDF text), 7.4 and 7.5 and CPython decimal at 120 to 200 digits, rounded once to the context (the digits after the kept ones are not borderline): 1.0E+30, 10E+29 and 100E+28 are the same even integer, so (-2)^n overflows to +inf; (-1.000000000000001)^12345678901234567 = -229964.1948529869209840694937236457 at 34 digits; (-1.000001)^(even 1234567890123456789012345678900) is +inf and the odd exponent ...901 gives -inf, both overflow and inexact; written out
// shares: Decimal::from_string (the local d: builds the operands), to_string and power_issue167_case (print value and flags), pow_ctx, pown_ctx, exp2_ctx and exp10_ctx (the code under test)
test "decimal large integer exponent spellings preserve parity" {
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  let context = DecimalContext::new(e_max=999_999_999)
  for exponent in ["1.0E+30", "10E+29", "100E+28"] {
    let (value, flags) = d("-2").pow_ctx(d(exponent), context)
    assert_eq(value.to_string(), "inf")
    assert_true(flags.overflow)
  }
  let (value, flags) = d("-1.000000000000001").pow_ctx(
    d("12345678901234567E+0"),
    context,
  )
  assert_eq(value.to_string(), "-229964.1948529869209840694937236457")
  assert_true(flags.inexact)
  let (even, even_flags) = d("-1.000001").pow_ctx(
    d("1234567890123456789012345678900"),
    context,
  )
  let (odd, odd_flags) = d("-1.000001").pow_ctx(
    d("1234567890123456789012345678901"),
    context,
  )
  assert_eq(even.to_string(), "inf")
  assert_eq(odd.to_string(), "-inf")
  assert_true(even_flags.overflow)
  assert_true(odd_flags.overflow)
  assert_true(even_flags.inexact)
  assert_true(odd_flags.inexact)
}

///|
/// IEEE special values remain exact even when the exponent itself is beyond
/// the bounded coefficient materialization budget.
// oracle: A
// source: IEEE 754-2019 9.2.1 (pow and pown lists, read from the PDF text), 7.4 and 7.5: (-0)^(1E+9999999) is +0 (even exponent) and (-inf)^(12345678901234567) is -inf (odd exponent), exact; written out
// shares: Decimal::from_string (the local d: builds the operands), to_string and power_issue167_case (print value and flags), pow_ctx, pown_ctx, exp2_ctx and exp10_ctx (the code under test)
test "decimal large integer powers keep signed zero and infinity" {
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  let context = DecimalContext::new(e_max=999_999_999)
  let (zero, _) = d("-0").pow_ctx(d("1E+9999999"), context)
  let (infinity, _) = d("-Inf").pow_ctx(d("12345678901234567E+0"), context)
  assert_eq(zero.to_string(), "0")
  assert_eq(infinity.to_string(), "-inf")
}

///|
/// A subset context still returns the correct finite result when its exponent
/// range admits it; a smaller range uses the IEEE overflow result.
// oracle: A
// source: CPython decimal at 120 to 200 digits, rounded once to the context (the digits after the kept ones are not borderline) and 7.4: 2^(1E+9) = 4.612976001169069393116119221037316E+301029995 in the context with e_max 999999999, and overflow to infinity in decimal128-precision with e_max 384; written out
// shares: Decimal::from_string (the local d: builds the operands), to_string and power_issue167_case (print value and flags), pow_ctx, pown_ctx, exp2_ctx and exp10_ctx (the code under test)
test "decimal large integer powers support extended and subset contexts" {
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  let extended = DecimalContext::new(e_max=999_999_999)
  let subset = DecimalContext::new(precision=34, e_max=384)
  let (wide, _) = d("2").pow_ctx(d("1E+9"), extended)
  let (narrow, narrow_flags) = d("2").pow_ctx(d("1E+9"), subset)
  assert_eq(wide.to_string(), "4.612976001169069393116119221037316E+301029995")
  assert_eq(narrow.to_string(), "inf")
  assert_true(narrow_flags.overflow)
}
