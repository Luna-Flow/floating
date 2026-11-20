///|
fn issue348_mode(name : String) -> DecimalRoundingMode {
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
  (if flags.rounded { "r" } else { "." }) +
  (if flags.invalid_operation { "i" } else { "." }) +
  (if flags.division_by_zero { "z" } else { "." }) +
  (if flags.overflow { "o" } else { "." }) +
  (if flags.underflow { "u" } else { "." }) +
  (if flags.subnormal { "s" } else { "." }) +
  (if flags.clamped { "c" } else { "." })
}

///|
fn issue348_decimal64(mode : DecimalRoundingMode) -> DecimalContext {
  DecimalContext::new(
    precision=16,
    decimal_rounding=mode,
    e_min=-383,
    e_max=384,
    clamp=true,
  )
}

///|
fn issue348_text(value : Decimal) -> String {
  if value.is_infinite() {
    if value.is_negative() {
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
      .power_ctx(
        Decimal::from_string(y).unwrap(),
        issue348_decimal64(issue348_mode(mode)),
      )
    assert_eq(
      (x, y, mode, issue348_text(value), issue348_flags_text(flags)),
      (x, y, mode, expected, "xr......"),
    )
  }
}

///|
/// Issue 348: `pown_ctx` with the `Int32` minimum goes through the same path.
test "issue 348: pown at the Int32 minimum" {
  let x = Decimal::from_string("1.000000000000000000000000000001").unwrap()
  for mode in ["half_even", "down", "floor", "ceiling", "up"] {
    let ctx = issue348_decimal64(issue348_mode(mode))
    let (value, flags) = x.pown_ctx(-2147483648, ctx)
    let (power, power_flags) = x.power_ctx(
      Decimal::from_string("-2147483648").unwrap(),
      ctx,
    )
    assert_eq(issue348_text(value), issue348_text(power))
    assert_eq(issue348_flags_text(flags), issue348_flags_text(power_flags))
  }
  let (value, _) = x.pown_ctx(-2147483648, issue348_decimal64(Floor))
  assert_eq(issue348_text(value), "0.9999999999999999")
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
    let ctx = DecimalContext::new(
      precision=4,
      decimal_rounding=issue348_mode(mode),
      e_min=-10,
      e_max=0,
      clamp=true,
    )
    let (value, flags) = x.pown_ctx(-40, ctx)
    assert_eq(
      (mode, issue348_text(value), issue348_flags_text(flags)),
      (mode, expected, "xr......"),
    )
    let (value, flags) = x.power_ctx(Decimal::from_string("-40").unwrap(), ctx)
    assert_eq(
      (mode, issue348_text(value), issue348_flags_text(flags)),
      (mode, expected, "xr......"),
    )
  }
}

///|
/// Issue 349, IEEE 754-2019 §9.2 and §9.2.2: `pow(10^k, y)` with `k*y` an
/// integer is the exact `10^(k*y)` in every mode, with no inexact and the
/// cohort of `floor(y * Q(x))`; beyond the range it overflows or underflows.
test "issue 349: exact powers of ten with a non-integral exponent" {
  let rows : Array[(String, String, String, String)] = [
    ("1E-5", "1.2", "0.000001", "........"),
    ("1E-5", "-1.2", "1E+6", "........"),
    ("1E+10", "0.5", "1E+5", "........"),
    ("1E-4", "-0.25", "1E+1", "........"),
    // Q(x) = -8: floor(1.2 * -8) = -10.
    ("1000E-8", "1.2", "0.0000010000", "........"),
    // Q(x) = 0: preferred exponent 0.
    ("100", "2.5", "100000", "........"),
    ("1E-300", "1.32", "1E-396", "......s."),
    ("1E+300", "1.5", "Infinity", "xr..o..."),
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
        .power_ctx(Decimal::from_string(y).unwrap(), ctx)
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
    .power_ctx(
      Decimal::from_string("1.3").unwrap(),
      issue348_decimal64(HalfEven),
    )
  assert_eq(issue348_text(value), "3.162277660168379E-7")
  assert_eq(issue348_flags_text(flags), "xr......")
  let (value, flags) = Decimal::from_string("-1E-5")
    .unwrap()
    .power_ctx(
      Decimal::from_string("1.2").unwrap(),
      issue348_decimal64(HalfEven),
    )
  assert_true(value.is_nan())
  assert_true(flags.invalid_operation)
}
