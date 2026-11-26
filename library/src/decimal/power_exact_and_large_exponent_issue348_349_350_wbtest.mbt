///|
fn issue348_mode(name : String) -> DecimalRound {
  match name {
    "half_even" => HalfEven
    "half_up" => HalfUp
    "half_down" => HalfDown
    "down" => Down
    "ceiling" => Ceiling
    "floor" => Floor
    "up" => Up
    "05up" => ZeroFiveUp
    _ => abort("unexpected mode \{name}")
  }
}

///|
fn issue348_flags_text(flags : DecimalFlags) -> String {
  (if flags.inexact { "x" } else { "." }) +
  (if flags.invalid_operation { "i" } else { "." }) +
  (if flags.division_by_zero { "z" } else { "." }) +
  (if flags.overflow { "o" } else { "." }) +
  (if flags.underflow { "u" } else { "." })
}

///|
fn issue348_decimal64(mode : DecimalRound) -> DecimalContext {
  DecimalContext::new(precision=16, e_max=384).with_round(mode)
}

///|
fn issue348_text(value : Decimal) -> String {
  if value.is_infinite() {
    if value.is_sign_minus() {
      "-Infinity"
    } else {
      "Infinity"
    }
  } else {
    value.to_string()
  }
}

///|
/// Issue 348, IEEE 754-2019 §9.2 ("shall return results correctly rounded"):
/// integer exponents beyond the `Int` range (and `-2^31`, whose magnitude is
/// not an `Int`) keep the base's deviation from 1. Expected values: Python
/// `decimal` at 120 digits, rounded once to decimal64 in each mode (the exact
/// power is at least 10^-80 away from every decimal64 rounding boundary).
test "issue 348: large integer exponents are correctly rounded" {
  let rows : Array[(String, String, String, String)] = [
    (
      "1.000000000000000000000000000001", "-2147483648", "half_even", "1.000000000000000",
    ),
    (
      "1.000000000000000000000000000001", "-2147483648", "half_up", "1.000000000000000",
    ),
    (
      "1.000000000000000000000000000001", "-2147483648", "half_down", "1.000000000000000",
    ),
    (
      "1.000000000000000000000000000001", "-2147483648", "down", "0.9999999999999999",
    ),
    (
      "1.000000000000000000000000000001", "-2147483648", "ceiling", "1.000000000000000",
    ),
    (
      "1.000000000000000000000000000001", "-2147483648", "floor", "0.9999999999999999",
    ),
    (
      "1.000000000000000000000000000001", "-2147483648", "up", "1.000000000000000",
    ),
    (
      "1.000000000000000000000000000001", "-2147483648", "05up", "0.9999999999999999",
    ),
    (
      "1.000000000000000000000000000001", "3000000000", "half_even", "1.000000000000000",
    ),
    (
      "1.000000000000000000000000000001", "3000000000", "half_up", "1.000000000000000",
    ),
    (
      "1.000000000000000000000000000001", "3000000000", "half_down", "1.000000000000000",
    ),
    (
      "1.000000000000000000000000000001", "3000000000", "down", "1.000000000000000",
    ),
    (
      "1.000000000000000000000000000001", "3000000000", "ceiling", "1.000000000000001",
    ),
    (
      "1.000000000000000000000000000001", "3000000000", "floor", "1.000000000000000",
    ),
    (
      "1.000000000000000000000000000001", "3000000000", "up", "1.000000000000001",
    ),
    (
      "1.000000000000000000000000000001", "3000000000", "05up", "1.000000000000001",
    ),
    (
      "1.000000000000000000000000000001", "-1E+12", "half_even", "1.000000000000000",
    ),
    (
      "1.000000000000000000000000000001", "-1E+12", "half_up", "1.000000000000000",
    ),
    (
      "1.000000000000000000000000000001", "-1E+12", "half_down", "1.000000000000000",
    ),
    ("1.000000000000000000000000000001", "-1E+12", "down", "0.9999999999999999"),
    (
      "1.000000000000000000000000000001", "-1E+12", "ceiling", "1.000000000000000",
    ),
    (
      "1.000000000000000000000000000001", "-1E+12", "floor", "0.9999999999999999",
    ),
    ("1.000000000000000000000000000001", "-1E+12", "up", "1.000000000000000"),
    ("1.000000000000000000000000000001", "-1E+12", "05up", "0.9999999999999999"),
    (
      "0.999999999999999999999999999999", "3000000000", "half_even", "1.000000000000000",
    ),
    (
      "0.999999999999999999999999999999", "3000000000", "half_up", "1.000000000000000",
    ),
    (
      "0.999999999999999999999999999999", "3000000000", "half_down", "1.000000000000000",
    ),
    (
      "0.999999999999999999999999999999", "3000000000", "down", "0.9999999999999999",
    ),
    (
      "0.999999999999999999999999999999", "3000000000", "ceiling", "1.000000000000000",
    ),
    (
      "0.999999999999999999999999999999", "3000000000", "floor", "0.9999999999999999",
    ),
    (
      "0.999999999999999999999999999999", "3000000000", "up", "1.000000000000000",
    ),
    (
      "0.999999999999999999999999999999", "3000000000", "05up", "0.9999999999999999",
    ),
    (
      "-1.000000000000000000000000000001", "3000000001", "half_even", "-1.000000000000000",
    ),
    (
      "-1.000000000000000000000000000001", "3000000001", "half_up", "-1.000000000000000",
    ),
    (
      "-1.000000000000000000000000000001", "3000000001", "half_down", "-1.000000000000000",
    ),
    (
      "-1.000000000000000000000000000001", "3000000001", "down", "-1.000000000000000",
    ),
    (
      "-1.000000000000000000000000000001", "3000000001", "ceiling", "-1.000000000000000",
    ),
    (
      "-1.000000000000000000000000000001", "3000000001", "floor", "-1.000000000000001",
    ),
    (
      "-1.000000000000000000000000000001", "3000000001", "up", "-1.000000000000001",
    ),
    (
      "-1.000000000000000000000000000001", "3000000001", "05up", "-1.000000000000001",
    ),
    (
      "1.000000000000000000000000000001", "2147483647", "half_even", "1.000000000000000",
    ),
    (
      "1.000000000000000000000000000001", "2147483647", "half_up", "1.000000000000000",
    ),
    (
      "1.000000000000000000000000000001", "2147483647", "half_down", "1.000000000000000",
    ),
    (
      "1.000000000000000000000000000001", "2147483647", "down", "1.000000000000000",
    ),
    (
      "1.000000000000000000000000000001", "2147483647", "ceiling", "1.000000000000001",
    ),
    (
      "1.000000000000000000000000000001", "2147483647", "floor", "1.000000000000000",
    ),
    (
      "1.000000000000000000000000000001", "2147483647", "up", "1.000000000000001",
    ),
    (
      "1.000000000000000000000000000001", "2147483647", "05up", "1.000000000000001",
    ),
  ]
  for row in rows {
    let (x, y, mode, expected) = row
    let (value, flags) = Decimal::from_string(x)
      .unwrap()
      .pow_ctx(
        Decimal::from_string(y).unwrap(),
        issue348_decimal64(issue348_mode(mode)),
      )
    assert_eq(
      (x, y, mode, issue348_text(value), issue348_flags_text(flags)),
      (x, y, mode, expected, "x...."),
    )
  }
}

///|
/// Issue 348: `pown_ctx` with the `Int32` minimum goes through the same path.
/// Expected values: the same Python `decimal` rows (120 digits, rounded once
/// to decimal64 in each mode) as the `pow_ctx` test above, not `pow_ctx`
/// itself.
// oracle: A
// source: expected strings for (1 + 10^-30)^(-2^31) at decimal64 in the five directed or nearest modes, from CPython decimal at 120 digits rounded once (the exact power, 1 - 2.147483648E-21 + ..., is 10^-80 or more away from every decimal64 rounding boundary); flags inexact only
// shares: Decimal::from_string, DecimalContext::new and with_round, and the helpers issue348_text and issue348_flags_text (they build the operands and read the result and flags as text; the expected strings are written in the test)
test "issue 348: pown at the Int32 minimum" {
  let x = Decimal::from_string("1.000000000000000000000000000001").unwrap()
  let rows : Array[(String, String)] = [
    ("half_even", "1.000000000000000"),
    ("down", "0.9999999999999999"),
    ("floor", "0.9999999999999999"),
    ("ceiling", "1.000000000000000"),
    ("up", "1.000000000000000"),
  ]
  for row in rows {
    let (mode, expected) = row
    let (value, flags) = x.pown_ctx(
      -2147483648,
      issue348_decimal64(issue348_mode(mode)),
    )
    assert_eq(
      (mode, issue348_text(value), issue348_flags_text(flags)),
      (mode, expected, "x...."),
    )
  }
}

///|
/// Issue 350: an inexact result has a full-length coefficient, whose exponent
/// is at most `e_max - p + 1`, so it is never clamped. Before the fix the
/// directed upper bound `1 / 1` (exact, exponent 0) was folded down and its
/// `clamped` flag returned with the result.
test "issue 350: no clamped for an inexact pown result near 1" {
  let rows : Array[(String, String)] = [
    ("half_even", "1.000"),
    ("half_up", "1.000"),
    ("half_down", "1.000"),
    ("down", "0.9999"),
    ("ceiling", "1.000"),
    ("floor", "0.9999"),
    ("up", "1.000"),
    ("05up", "0.9999"),
  ]
  let x = Decimal::from_string("1.000000000000000006354").unwrap()
  for row in rows {
    let (mode, expected) = row
    let ctx = DecimalContext::new(precision=4, e_max=11).with_round(
      issue348_mode(mode),
    )
    let (value, flags) = x.pown_ctx(-40, ctx)
    assert_eq(
      (mode, issue348_text(value), issue348_flags_text(flags)),
      (mode, expected, "x...."),
    )
    let (value, flags) = x.pow_ctx(Decimal::from_string("-40").unwrap(), ctx)
    assert_eq(
      (mode, issue348_text(value), issue348_flags_text(flags)),
      (mode, expected, "x...."),
    )
  }
}

///|
/// Issue 349, IEEE 754-2019 §9.2 and §9.2.2: `pow(10^k, y)` with `k*y` an
/// integer is the exact `10^(k*y)` in every mode, with no inexact and the
/// cohort of `floor(y * Q(x))`; beyond the range it overflows or underflows.
test "issue 349: exact powers of ten with a non-integral exponent" {
  let rows : Array[(String, String, String, String)] = [
    ("1E-5", "1.2", "0.000001", "....."),
    ("1E-5", "-1.2", "1E+6", "....."),
    ("1E+10", "0.5", "1E+5", "....."),
    ("1E-4", "-0.25", "1E+1", "....."),
    // Q(x) = -8: floor(1.2 * -8) = -10.
    ("1000E-8", "1.2", "0.0000010000", "....."),
    // Q(x) = 0: preferred exponent 0.
    ("100", "2.5", "100000", "....."),
    ("1E-300", "1.32", "1E-396", "....."),
    ("1E+300", "1.5", "Infinity", "x..o."),
  ]
  for
    mode in [
      "half_even", "half_up", "half_down", "down", "ceiling", "floor", "up", "05up",
    ] {
    let ctx = issue348_decimal64(issue348_mode(mode))
    for row in rows {
      let (x, y, expected, flags_text) = row
      let (value, flags) = Decimal::from_string(x)
        .unwrap()
        .pow_ctx(Decimal::from_string(y).unwrap(), ctx)
      let expected = if expected == "Infinity" &&
        (mode == "down" || mode == "floor" || mode == "05up") {
        "9.999999999999999E+384"
      } else {
        expected
      }
      assert_eq(
        (mode, x, y, issue348_text(value), issue348_flags_text(flags)),
        (mode, x, y, expected, flags_text),
      )
    }
  }
}

///|
/// Issue 349 controls: `k*y` not an integer is irrational and stays inexact,
/// and a negative power of ten keeps the domain error.
test "issue 349: non-exact powers of ten are unchanged" {
  let (value, flags) = Decimal::from_string("1E-5")
    .unwrap()
    .pow_ctx(Decimal::from_string("1.3").unwrap(), issue348_decimal64(HalfEven))
  assert_eq(issue348_text(value), "3.162277660168379E-7")
  assert_eq(issue348_flags_text(flags), "x....")
  let (value, flags) = Decimal::from_string("-1E-5")
    .unwrap()
    .pow_ctx(Decimal::from_string("1.2").unwrap(), issue348_decimal64(HalfEven))
  assert_true(value.is_nan())
  assert_true(flags.invalid_operation)
}

///|
// oracle: A
// source: CPython decimal at 100 digits (Context(prec=100).power), rounded once with Context(prec=16, Emax=384, Emin=-383, clamp=1) in the direction of the row: (1 + 10^-15)^y and (1 - 10^-16)^y for y = 0.5, 0.001 and 0.999 are strictly between 1 and the neighbour of 1 (so the exact value is irrational or at least not representable, and the result is inexact); toward negative gives the lower neighbour, toward positive the upper one (IEEE 754-2019 4.3), run 2026-11-26; the earlier rows of this file never put a base next to 1 under a directed mode
// shares: Decimal::from_string, issue348_decimal64, issue348_text and issue348_flags_text (they build the operands and context and print the result and flags), pow_ctx (the code under test)
test "issue 348: a base next to 1 under floor and ceiling, exponent between 0 and 1" {
  let rows : Array[(String, String, String, String)] = [
    ("1.000000000000001", "0.5", "floor", "1.000000000000000"),
    ("1.000000000000001", "0.5", "ceiling", "1.000000000000001"),
    ("1.000000000000001", "0.001", "floor", "1.000000000000000"),
    ("1.000000000000001", "0.001", "ceiling", "1.000000000000001"),
    ("1.000000000000001", "0.999", "floor", "1.000000000000000"),
    ("1.000000000000001", "0.999", "ceiling", "1.000000000000001"),
    ("0.9999999999999999", "0.5", "floor", "0.9999999999999999"),
    ("0.9999999999999999", "0.5", "ceiling", "1.000000000000000"),
    ("0.9999999999999999", "0.001", "floor", "0.9999999999999999"),
    ("0.9999999999999999", "0.001", "ceiling", "1.000000000000000"),
    ("0.9999999999999999", "0.999", "floor", "0.9999999999999999"),
    ("0.9999999999999999", "0.999", "ceiling", "1.000000000000000"),
  ]
  for row in rows {
    let (base, exponent, mode, expected) = row
    let (value, flags) = Decimal::from_string(base)
      .unwrap()
      .pow_ctx(
        Decimal::from_string(exponent).unwrap(),
        issue348_decimal64(issue348_mode(mode)),
      )
    assert_eq(
      (base, exponent, mode, issue348_text(value), issue348_flags_text(flags)),
      (base, exponent, mode, expected, "x...."),
    )
  }
}
