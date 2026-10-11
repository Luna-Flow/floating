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
test "decimal integer powers are correctly rounded" {
  let c32 = DecimalContext::decimal32()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  assert_eq(
    power_case(d("3.339434").power_ctx(d("3"), c32)),
    "37.24077 inexact",
  )
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
test "decimal pown keeps the integer exponent exact" {
  let ctx = DecimalContext::new(precision=7).unwrap()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  assert_eq(power_case(d("-1").pown_ctx(12345679, ctx)), "-1")
  assert_eq(
    power_case(d("-1").power_ctx(d("12345679"), ctx)),
    power_case(d("-1").pown_ctx(12345679, ctx)),
  )
  assert_eq(
    power_case(
      d("-0.02").pown_ctx(115, DecimalContext::new(precision=2).unwrap()),
    ),
    "-4.2E-196 inexact",
  )
}

///|
/// Exactly representable roots and norms used to come back from the
/// certified evaluation with `inexact` in the half modes and failed
/// certification in the directed modes.
test "decimal rootn and hypot return exact results exactly" {
  let c64 = DecimalContext::decimal64()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  for mode in [RoundingMode::ToNearestEven, TowardZero, TowardPositive] {
    let ctx = c64.with_rounding(mode)
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
/// An exact non-integral power must come back exactly, and must come back at
/// all: the binary layer certifies these before refining, because a Ziv
/// enclosure straddles the exact value and never rounds uniquely (#53).
/// 4^2048.5 is exactly 2^4097, so it also needs a context whose exponent
/// range reaches it.
test "decimal power returns exact non-integral powers" {
  let c32 = DecimalContext::decimal32()
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  assert_eq(power_case(d("4").power_ctx(d("1.5"), c32)), "8")
  assert_eq(power_case(d("16").power_ctx(d("0.75"), c32)), "8")
  assert_eq(power_case(d("16").power_ctx(d("-0.75"), c32)), "0.125")
  assert_eq(power_case(d("0.25").power_ctx(d("1.5"), c32)), "0.125")
  assert_eq(power_case(d("9").power_ctx(d("1.5"), c32)), "27")
  // An irrational power is still rounded and inexact.
  assert_eq(power_case(d("2").power_ctx(d("0.5"), c32)), "1.414214 inexact")
  // 4^2048.5 = 2^4097 has 1234 digits, so it is rounded to the precision.
  let wide = DecimalContext::new(precision=34, e_max=999_999, e_min=-999_999).unwrap()
  assert_eq(
    power_case(d("4").power_ctx(d("2048.5"), wide)),
    "2.088777762826305013383505421433249E+1233 inexact",
  )
}

///|
/// The GDA math functions are defined only on contexts with precision and
/// exponent range within 999_999. `DecimalContext::new` defaults `e_min` to
/// -999_999_999, so raising only `e_max` leaves the context restricted and a
/// non-integral power signals Invalid context rather than computing.
test "decimal power rejects contexts outside the math function range" {
  let d = fn(text : String) { Decimal::from_string(text).unwrap() }
  let default_e_min = DecimalContext::new(precision=34, e_max=999_999).unwrap()
  let (value, flags) = d("4").power_ctx(d("2048.5"), default_e_min)
  assert_true(value.is_nan())
  assert_true(flags.contains(DecimalSignal::InvalidContext))
  // An integral power is unaffected by the math function restriction.
  assert_eq(power_case(d("2").power_ctx(d("10"), default_e_min)), "1024")
}
