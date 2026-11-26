///|
fn power_case(result : (Decimal, DecimalFlags)) -> String {
  let (value, flags) = result
  let mut text = value.to_string()
  if flags.inexact {
    text = text + " inexact"
  }
  if flags.invalid_operation {
    text = text + " invalid"
  }
  text
}

///|
/// Integer powers must be rounded once from the exact power. The GDA scheme
/// (p + digits(n) + 2 working digits, rounding after every multiplication)
/// can land on the wrong side of a midpoint: 3.339434^3 is exactly
/// 37.240765000..., and 4.329438^5 is 1521.09949940...
// oracle: A
// source: CPython decimal at 120 to 200 digits, rounded once to the context (the digits after the kept ones are not borderline): 3.339434^3 = 37.240765000... and 4.329438^5 = 1521.09949940... at 7 digits give 37.24077 and 1521.099, 1.0000001^999999 = 1.105170802032713 and 3.7^-200 = 2.289049512326577E-114 at 16 digits; 1.5^2 = 2.25 and 2^-3 = 0.125 are exact (no inexact flag)
// shares: Decimal::from_string (the local d: builds the operands), to_string and power_case (print value and flags), pow_ctx, pown_ctx, rootn_ctx and hypot_ctx (the code under test)
test "decimal integer powers are correctly rounded" {
  let c32 = DecimalContext::decimal32()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  assert_eq(power_case(d("3.339434").pow_ctx(d("3"), c32)), "37.24077 inexact")
  assert_eq(power_case(d("4.329438").pown_ctx(5, c32)), "1521.099 inexact")
  // Bounds path: the exact power is far longer than the precision.
  assert_eq(
    power_case(d("1.0000001").pown_ctx(999999, DecimalContext::decimal64())),
    "1.105170802032713 inexact",
  )
  assert_eq(
    power_case(d("3.7").pown_ctx(-200, DecimalContext::decimal64())),
    "2.289049512326577E-114 inexact",
  )
  // Exact powers keep their exactness and cohort.
  assert_eq(power_case(d("1.5").pown_ctx(2, c32)), "2.25")
  assert_eq(power_case(d("2").pown_ctx(-3, c32)), "0.125")
}

///|
/// pown_ctx built its exponent at the context precision, so an exponent
/// longer than the precision was rounded and could change parity (#51).
// oracle: A
// source: IEEE 754-2019 9.2.1: (-1)^12345679 = -1 (odd exponent), exact, also through pow; (-0.02)^115 at two digits is -4.2E-196 (CPython decimal at 200 digits), inexact
// shares: Decimal::from_string (the local d: builds the operands), to_string and power_case (print value and flags), pow_ctx, pown_ctx, rootn_ctx and hypot_ctx (the code under test)
test "decimal pown keeps the integer exponent exact" {
  let ctx = DecimalContext::new(precision=7)
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  assert_eq(power_case(d("-1").pown_ctx(12345679, ctx)), "-1")
  assert_eq(
    power_case(d("-1").pow_ctx(d("12345679"), ctx)),
    power_case(d("-1").pown_ctx(12345679, ctx)),
  )
  assert_eq(
    power_case(d("-0.02").pown_ctx(115, DecimalContext::new(precision=2))),
    "-4.2E-196 inexact",
  )
}

///|
/// Exactly representable roots and norms used to come back from the
/// certified evaluation with `inexact` in the half modes and failed
/// certification in the directed modes.
// oracle: A
// source: arithmetic: hypot(0.3, 0.4) = 0.5, hypot(-7.5, 0) = 7.5, hypot(5E+300, 1.2E+301) = 1.3E+301, rootn(0.008, 3) = 0.2, rootn(16E-8, 4) = 0.02, rootn(-0.008, -3) = -5, exact in nearest, toward-zero and toward-positive (IEEE 754-2019 7.6: no inexact for an exact result); hypot(1, 1) = 1.414213562373095 and rootn(2, 3) = 1.259921049894873 at 16 digits, inexact (CPython decimal)
// shares: Decimal::from_string (the local d: builds the operands), to_string and power_case (print value and flags), pow_ctx, pown_ctx, rootn_ctx and hypot_ctx (the code under test)
test "decimal rootn and hypot return exact results exactly" {
  let c64 = DecimalContext::decimal64()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  for mode in [RoundingMode::ToNearestEven, TowardZero, TowardPositive] {
    let ctx = c64.with_round(DecimalRound::from_arithmetic(mode))
    assert_eq(power_case(d("0.3").hypot_ctx(d("0.4"), ctx)), "0.5")
    assert_eq(power_case(d("-7.5").hypot_ctx(d("0"), ctx)), "7.5")
    assert_eq(power_case(d("5E+300").hypot_ctx(d("1.2E+301"), ctx)), "1.3E+301")
    assert_eq(power_case(d("0.008").rootn_ctx(3, ctx)), "0.2")
    assert_eq(power_case(d("16E-8").rootn_ctx(4, ctx)), "0.02")
    assert_eq(power_case(d("-0.008").rootn_ctx(-3, ctx)), "-5")
  }
  assert_eq(
    power_case(d("1").hypot_ctx(d("1"), c64)),
    "1.414213562373095 inexact",
  )
  assert_eq(power_case(d("2").rootn_ctx(3, c64)), "1.259921049894873 inexact")
}

///|
/// Large degrees must avoid unbounded exact-power probes and remain supported
/// across the complete Int range (#171).
// oracle: A
// source: CPython decimal at 100 digits: 2^(1/1000000) = 1.000000693147421, (-2)^(1/2147483647) = -1.000000000322772 (odd degree) and 2^(-1/2147483648) = 0.9999999996772282 at 16 digits, inexact
// shares: Decimal::from_string (the local d: builds the operands), to_string and power_case (print value and flags), pow_ctx, pown_ctx, rootn_ctx and hypot_ctx (the code under test)
test "decimal rootn handles large degrees" {
  let c64 = DecimalContext::decimal64()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  assert_eq(
    power_case(d("2").rootn_ctx(1_000_000, c64)),
    "1.000000693147421 inexact",
  )
  assert_eq(
    power_case(d("-2").rootn_ctx(2_147_483_647, c64)),
    "-1.000000000322772 inexact",
  )
  assert_eq(
    power_case(d("2").rootn_ctx(-2_147_483_647 - 1, c64)),
    "0.9999999996772282 inexact",
  )
}

///|
/// An exact non-integral power must come back exactly, and must come back at
/// all: the binary layer certifies these before refining, because a Ziv
/// enclosure straddles the exact value and never rounds uniquely (#53).
/// 4^2048.5 is exactly 2^4097, so it also needs a context whose exponent
/// range reaches it.
// oracle: A
// source: arithmetic: 4^1.5 = 8, 16^0.75 = 8, 16^-0.75 = 0.125, 0.25^1.5 = 0.125, 9^1.5 = 27 exactly (no inexact flag), 2^0.5 = 1.414214 at 7 digits inexact and 4^2048.5 = 2^4097 = 2.088777762826305013383505421433249E+1233 at 34 digits inexact (CPython decimal)
// shares: Decimal::from_string (the local d: builds the operands), to_string and power_case (print value and flags), pow_ctx, pown_ctx, rootn_ctx and hypot_ctx (the code under test)
test "decimal power returns exact non-integral powers" {
  let c32 = DecimalContext::decimal32()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  assert_eq(power_case(d("4").pow_ctx(d("1.5"), c32)), "8")
  assert_eq(power_case(d("16").pow_ctx(d("0.75"), c32)), "8")
  assert_eq(power_case(d("16").pow_ctx(d("-0.75"), c32)), "0.125")
  assert_eq(power_case(d("0.25").pow_ctx(d("1.5"), c32)), "0.125")
  assert_eq(power_case(d("9").pow_ctx(d("1.5"), c32)), "27")
  // An irrational power is still rounded and inexact.
  assert_eq(power_case(d("2").pow_ctx(d("0.5"), c32)), "1.414214 inexact")
  // 4^2048.5 = 2^4097 has 1234 digits, so it is rounded to the precision.
  let wide = DecimalContext::new(precision=34, e_max=999_999)
  assert_eq(
    power_case(d("4").pow_ctx(d("2048.5"), wide)),
    "2.088777762826305013383505421433249E+1233 inexact",
  )
}

///|
/// The math functions are defined only on contexts with precision and
/// exponent range within 999_999: an `e_max` above it leaves the context
/// restricted and a non-integral power signals Invalid context rather than
/// computing.
// oracle: A, S
// source: arithmetic for the integral power 2^10 = 1024; the rejection of a non-integral power in a context beyond the 999,999 limits (NaN with not_computed and no invalid operation) is the library's documented design limit (level S)
// shares: Decimal::from_string (the local d: builds the operands), to_string and power_case (print value and flags), pow_ctx, pown_ctx, rootn_ctx and hypot_ctx (the code under test)
test "decimal power rejects contexts outside the math function range" {
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  let default_e_min = DecimalContext::new(precision=34, e_max=1_000_000)
  let (value, flags) = d("4").pow_ctx(d("2048.5"), default_e_min)
  assert_true(value.is_nan())
  // S4: a context beyond the kernels is not computed, which is not an invalid operation
  assert_true(flags.not_computed() && !flags.invalid_operation())
  // An integral power is unaffected by the math function restriction.
  assert_eq(power_case(d("2").pow_ctx(d("10"), default_e_min)), "1024")
}
