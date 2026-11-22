///|
/// `power(x, 0.5)` and `power(x, -0.5)` (issue 397).
///
/// Contract, GDA 1.70, *power*: "In cases not covered above, the result will be
/// inexact unless the right-hand side has an integral value" and "Inexact
/// finite results should be correctly rounded, but may be up to 1 ulp ... in
/// error"; the result of a non-integral power is inexact with `precision`
/// digits (a coefficient of exactly `precision` digits, the exponent of an
/// inexact result being the smallest). *Clamped*: "if the exponent of a result
/// has been altered in order to fit the constraints of a specific concrete
/// representation ... The condition always occurs when a subnormal value rounds
/// to zero." The exponent of the full-precision form of a nonzero result is at
/// most `e_max - precision + 1`, so nothing is altered and Clamped is not
/// raised; only a result that rounds to zero keeps it. `squareroot.decTest`
/// pins Clamped for the *square root* operation, whose exact results have their
/// ideal exponent (sqtx8636 `squareroot 1E+18 -> 1.0E+9 Clamped`), which does
/// not apply to the padded inexact result of `power`; `power.decTest` has no row
/// with an exponent of one half. decNumber computes a non-integral power as
/// `exp(ln(x) * y)` in a working context with `clamp = 0` and then calls
/// `decCopyFit` and `decFinish` in the caller's context, which fold down only a
/// coefficient shorter than `precision`; the padded form is never folded.
/// The expected rows were derived from these rules and rounded with Python
/// `decimal` (libmpdec 4.0.0) as an arithmetic helper only.

///|
fn issue397_flags_text(flags : DecimalFlags) -> String {
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
fn issue397_gda_flags_text(flags : GdaFlags) -> String {
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
fn issue397_mode(name : String) -> DecimalRoundingMode {
  match name {
    "half_even" => HalfEven
    "half_down" => HalfDown
    "down" => Down
    "up" => Up
    "ceiling" => Ceiling
    "floor" => Floor
    _ => abort("unexpected rounding mode \{name}")
  }
}

///|
fn issue397_gda_mode(name : String) -> GdaRoundingMode {
  match name {
    "half_even" => GdaRoundingMode::HalfEven
    "half_down" => GdaRoundingMode::HalfDown
    "down" => GdaRoundingMode::Down
    "up" => GdaRoundingMode::Up
    "ceiling" => GdaRoundingMode::Ceiling
    "floor" => GdaRoundingMode::Floor
    _ => abort("unexpected rounding mode \{name}")
  }
}

///|
fn issue397_value_text(value : Decimal) -> String {
  if value.is_infinite() {
    if value.is_signed() {
      "-Infinity"
    } else {
      "Infinity"
    }
  } else {
    value.to_string()
  }
}

///|
fn issue397_run(
  precision : Int32,
  e_min : Int32,
  e_max : Int32,
  clamp : Bool,
  mode : String,
  base : String,
  exponent : String,
) -> Array[(String, String)] {
  let ctx = DecimalContext::new(
    precision~,
    decimal_rounding=issue397_mode(mode),
    e_min~,
    e_max~,
    clamp~,
  )
  let gda = gda_context_unchecked(
    precision~,
    rounding=issue397_gda_mode(mode),
    e_min~,
    e_max~,
    clamp~,
  )
  let x = Decimal::from_string(base).unwrap()
  let y = Decimal::from_string(exponent).unwrap()
  let (value, flags) = x.power_ctx(y, ctx)
  let outcome = power(x, y, gda)
  [
    (issue397_value_text(value), issue397_flags_text(flags)),
    (
      issue397_value_text(outcome.value()),
      issue397_gda_flags_text(outcome.raised()),
    ),
  ]
}

///|
test "power with exponent one half or minus one half is the padded inexact result without Clamped (issue 397)" {
  for row in issue397_rows {
    let (context_name, mode, base, exponent, value, flags) = row
    let mut found : (String, Int32, Int32, Int32, Bool)? = None
    for entry in issue397_contexts {
      if entry.0 == context_name {
        found = Some(entry)
      }
    }
    let (_, precision, e_min, e_max, clamp) = found.unwrap()
    for
      got in issue397_run(precision, e_min, e_max, clamp, mode, base, exponent) {
      let label = "\{context_name} power \{base} \{exponent} \{mode}"
      assert_eq((label, got.0, got.1), (label, value, flags))
    }
  }
}

///|
// oracle: A
// source: two hand-derived rows (0.01**0.5 at p4 e_max 0 padded 0.1000; 1E+6**0.5 at p56 padded 1000.000...);
//   CPython half_down row agrees, the p4 'down' row differs from CPython
// shares: Decimal::from_string and to_string (reading the inputs, printing the result, through the helper issue397_run)
test "the rows of issue 397 (clamped, e_max below precision - 1)" {
  // 0.01 ** 0.5: the square root 0.1 is short; padded it is 0.1000, exponent -4
  // = e_max - precision + 1 - 1, nothing is folded.
  for got in issue397_run(4, -4, 0, true, "down", "0.01", "0.5") {
    assert_eq(got, ("0.1000", "xr......"))
  }
  for got in issue397_run(56, -6, 6, true, "half_down", "1.00E+6", "0.5") {
    assert_eq(
      got,
      ("1000.0000000000000000000000000000000000000000000000000000", "xr......"),
    )
  }
}

///|
// oracle: A
// source: spelling variants of the exponent: literals 0.10000 and 0.50000 from hand derivation; CPython agrees
//   on all 10 spellings
// shares: Decimal::from_string and to_string (reading the inputs, printing the result, through the helper issue397_run)
test "the spellings of the exponent one half agree (issue 397)" {
  for spelling in ["0.5", "0.50", "5E-1", ".5", "+0.5", "50E-2"] {
    for got in issue397_run(5, -10, 0, true, "half_even", "0.01", spelling) {
      assert_eq(got, ("0.10000", "xr......"))
    }
  }
  for spelling in ["-0.5", "-0.50", "-5E-1", "-.5"] {
    for got in issue397_run(5, -10, 0, true, "half_even", "4", spelling) {
      assert_eq(got, ("0.50000", "xr......"))
    }
  }
}

///|
// oracle: A
// source: 1E-30**0.5 hand-derived (1E-15 below Etiny -14 gives 0E-14, GDA Clamped rule: subnormal rounds to
//   zero) ; CPython gives 0E-14 xr...usc
// shares: Decimal::from_string and to_string (reading the inputs, printing the result, through the helper issue397_run)
test "a result that rounds to zero keeps Clamped (issue 397)" {
  // 1E-9 ** 0.5 = 3.16E-5 is fine; 1E-30 ** 0.5 = 1E-15 is below Etiny = -14.
  for got in issue397_run(5, -10, 0, true, "half_even", "1E-30", "0.5") {
    assert_eq(got.0, "0E-14")
    assert_eq(got.1, "xr...usc")
  }
}

///|
let issue397_contexts : Array[(String, Int32, Int32, Int32, Bool)] = [
  ("clamped e_max < precision - 1", 5, -10, 0, true),
  ("clamped e_max 1", 3, -5, 1, true),
  ("not clamped", 5, -10, 0, false),
  ("decimal32", 7, -95, 96, true),
  ("decimal64", 16, -383, 384, true),
  ("decimal128", 34, -6143, 6144, true),
]

///|
let issue397_rows : Array[(String, String, String, String, String, String)] = [
  (
    "clamped e_max < precision - 1", "half_even", "0.01", "0.5", "0.10000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "0.01", "0.50", "0.10000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "0.01", "5E-1", "0.10000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "0.01", "-0.5", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "4", "0.5", "2.0000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "4", "0.50", "2.0000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "4", "5E-1", "2.0000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "4", "-0.5", "0.50000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "1E+2", "0.5", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "1E+2", "0.50", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "1E+2", "5E-1", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "1E+2", "-0.5", "0.10000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "0.25", "0.5", "0.50000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "0.25", "0.50", "0.50000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "0.25", "5E-1", "0.50000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "0.25", "-0.5", "2.0000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "2", "0.5", "1.4142", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "2", "0.50", "1.4142", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "2", "5E-1", "1.4142", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "2", "-0.5", "0.70711", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "1.0E+4", "0.5", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "1.0E+4", "0.50", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "1.0E+4", "5E-1", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "1.0E+4", "-0.5", "0.010000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "9", "0.5", "3.0000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "9", "0.50", "3.0000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "9", "5E-1", "3.0000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "9", "-0.5", "0.33333", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "1E-9", "0.5", "0.000031623", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "1E-9", "0.50", "0.000031623",
    "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "1E-9", "5E-1", "0.000031623",
    "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "1E-9", "-0.5", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "1E+20", "0.5", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "1E+20", "0.50", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "1E+20", "5E-1", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "1E+20", "-0.5", "1.0000E-10",
    "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "1E-5", "0.5", "0.0031623", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "1E-5", "0.50", "0.0031623", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "1E-5", "5E-1", "0.0031623", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "half_even", "1E-5", "-0.5", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "down", "0.01", "0.5", "0.10000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "down", "0.01", "0.50", "0.10000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "down", "0.01", "5E-1", "0.10000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "down", "0.01", "-0.5", "9.9999", "xr..o...",
  ),
  ("clamped e_max < precision - 1", "down", "4", "0.5", "2.0000", "xr......"),
  ("clamped e_max < precision - 1", "down", "4", "0.50", "2.0000", "xr......"),
  ("clamped e_max < precision - 1", "down", "4", "5E-1", "2.0000", "xr......"),
  ("clamped e_max < precision - 1", "down", "4", "-0.5", "0.50000", "xr......"),
  ("clamped e_max < precision - 1", "down", "1E+2", "0.5", "9.9999", "xr..o..."),
  (
    "clamped e_max < precision - 1", "down", "1E+2", "0.50", "9.9999", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "down", "1E+2", "5E-1", "9.9999", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "down", "1E+2", "-0.5", "0.10000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "down", "0.25", "0.5", "0.50000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "down", "0.25", "0.50", "0.50000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "down", "0.25", "5E-1", "0.50000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "down", "0.25", "-0.5", "2.0000", "xr......",
  ),
  ("clamped e_max < precision - 1", "down", "2", "0.5", "1.4142", "xr......"),
  ("clamped e_max < precision - 1", "down", "2", "0.50", "1.4142", "xr......"),
  ("clamped e_max < precision - 1", "down", "2", "5E-1", "1.4142", "xr......"),
  ("clamped e_max < precision - 1", "down", "2", "-0.5", "0.70710", "xr......"),
  (
    "clamped e_max < precision - 1", "down", "1.0E+4", "0.5", "9.9999", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "down", "1.0E+4", "0.50", "9.9999", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "down", "1.0E+4", "5E-1", "9.9999", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "down", "1.0E+4", "-0.5", "0.010000", "xr......",
  ),
  ("clamped e_max < precision - 1", "down", "9", "0.5", "3.0000", "xr......"),
  ("clamped e_max < precision - 1", "down", "9", "0.50", "3.0000", "xr......"),
  ("clamped e_max < precision - 1", "down", "9", "5E-1", "3.0000", "xr......"),
  ("clamped e_max < precision - 1", "down", "9", "-0.5", "0.33333", "xr......"),
  (
    "clamped e_max < precision - 1", "down", "1E-9", "0.5", "0.000031622", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "down", "1E-9", "0.50", "0.000031622", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "down", "1E-9", "5E-1", "0.000031622", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "down", "1E-9", "-0.5", "9.9999", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "down", "1E+20", "0.5", "9.9999", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "down", "1E+20", "0.50", "9.9999", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "down", "1E+20", "5E-1", "9.9999", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "down", "1E+20", "-0.5", "1.0000E-10", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "down", "1E-5", "0.5", "0.0031622", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "down", "1E-5", "0.50", "0.0031622", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "down", "1E-5", "5E-1", "0.0031622", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "down", "1E-5", "-0.5", "9.9999", "xr..o...",
  ),
  ("clamped e_max < precision - 1", "up", "0.01", "0.5", "0.10000", "xr......"),
  ("clamped e_max < precision - 1", "up", "0.01", "0.50", "0.10000", "xr......"),
  ("clamped e_max < precision - 1", "up", "0.01", "5E-1", "0.10000", "xr......"),
  (
    "clamped e_max < precision - 1", "up", "0.01", "-0.5", "Infinity", "xr..o...",
  ),
  ("clamped e_max < precision - 1", "up", "4", "0.5", "2.0000", "xr......"),
  ("clamped e_max < precision - 1", "up", "4", "0.50", "2.0000", "xr......"),
  ("clamped e_max < precision - 1", "up", "4", "5E-1", "2.0000", "xr......"),
  ("clamped e_max < precision - 1", "up", "4", "-0.5", "0.50000", "xr......"),
  ("clamped e_max < precision - 1", "up", "1E+2", "0.5", "Infinity", "xr..o..."),
  (
    "clamped e_max < precision - 1", "up", "1E+2", "0.50", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "up", "1E+2", "5E-1", "Infinity", "xr..o...",
  ),
  ("clamped e_max < precision - 1", "up", "1E+2", "-0.5", "0.10000", "xr......"),
  ("clamped e_max < precision - 1", "up", "0.25", "0.5", "0.50000", "xr......"),
  ("clamped e_max < precision - 1", "up", "0.25", "0.50", "0.50000", "xr......"),
  ("clamped e_max < precision - 1", "up", "0.25", "5E-1", "0.50000", "xr......"),
  ("clamped e_max < precision - 1", "up", "0.25", "-0.5", "2.0000", "xr......"),
  ("clamped e_max < precision - 1", "up", "2", "0.5", "1.4143", "xr......"),
  ("clamped e_max < precision - 1", "up", "2", "0.50", "1.4143", "xr......"),
  ("clamped e_max < precision - 1", "up", "2", "5E-1", "1.4143", "xr......"),
  ("clamped e_max < precision - 1", "up", "2", "-0.5", "0.70711", "xr......"),
  (
    "clamped e_max < precision - 1", "up", "1.0E+4", "0.5", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "up", "1.0E+4", "0.50", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "up", "1.0E+4", "5E-1", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "up", "1.0E+4", "-0.5", "0.010000", "xr......",
  ),
  ("clamped e_max < precision - 1", "up", "9", "0.5", "3.0000", "xr......"),
  ("clamped e_max < precision - 1", "up", "9", "0.50", "3.0000", "xr......"),
  ("clamped e_max < precision - 1", "up", "9", "5E-1", "3.0000", "xr......"),
  ("clamped e_max < precision - 1", "up", "9", "-0.5", "0.33334", "xr......"),
  (
    "clamped e_max < precision - 1", "up", "1E-9", "0.5", "0.000031623", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "up", "1E-9", "0.50", "0.000031623", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "up", "1E-9", "5E-1", "0.000031623", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "up", "1E-9", "-0.5", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "up", "1E+20", "0.5", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "up", "1E+20", "0.50", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "up", "1E+20", "5E-1", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "up", "1E+20", "-0.5", "1.0000E-10", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "up", "1E-5", "0.5", "0.0031623", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "up", "1E-5", "0.50", "0.0031623", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "up", "1E-5", "5E-1", "0.0031623", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "up", "1E-5", "-0.5", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "0.01", "0.5", "0.10000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "0.01", "0.50", "0.10000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "0.01", "5E-1", "0.10000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "0.01", "-0.5", "Infinity", "xr..o...",
  ),
  ("clamped e_max < precision - 1", "ceiling", "4", "0.5", "2.0000", "xr......"),
  (
    "clamped e_max < precision - 1", "ceiling", "4", "0.50", "2.0000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "4", "5E-1", "2.0000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "4", "-0.5", "0.50000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "1E+2", "0.5", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "1E+2", "0.50", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "1E+2", "5E-1", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "1E+2", "-0.5", "0.10000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "0.25", "0.5", "0.50000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "0.25", "0.50", "0.50000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "0.25", "5E-1", "0.50000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "0.25", "-0.5", "2.0000", "xr......",
  ),
  ("clamped e_max < precision - 1", "ceiling", "2", "0.5", "1.4143", "xr......"),
  (
    "clamped e_max < precision - 1", "ceiling", "2", "0.50", "1.4143", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "2", "5E-1", "1.4143", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "2", "-0.5", "0.70711", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "1.0E+4", "0.5", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "1.0E+4", "0.50", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "1.0E+4", "5E-1", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "1.0E+4", "-0.5", "0.010000", "xr......",
  ),
  ("clamped e_max < precision - 1", "ceiling", "9", "0.5", "3.0000", "xr......"),
  (
    "clamped e_max < precision - 1", "ceiling", "9", "0.50", "3.0000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "9", "5E-1", "3.0000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "9", "-0.5", "0.33334", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "1E-9", "0.5", "0.000031623", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "1E-9", "0.50", "0.000031623", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "1E-9", "5E-1", "0.000031623", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "1E-9", "-0.5", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "1E+20", "0.5", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "1E+20", "0.50", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "1E+20", "5E-1", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "1E+20", "-0.5", "1.0000E-10", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "1E-5", "0.5", "0.0031623", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "1E-5", "0.50", "0.0031623", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "1E-5", "5E-1", "0.0031623", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "ceiling", "1E-5", "-0.5", "Infinity", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "floor", "0.01", "0.5", "0.10000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "floor", "0.01", "0.50", "0.10000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "floor", "0.01", "5E-1", "0.10000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "floor", "0.01", "-0.5", "9.9999", "xr..o...",
  ),
  ("clamped e_max < precision - 1", "floor", "4", "0.5", "2.0000", "xr......"),
  ("clamped e_max < precision - 1", "floor", "4", "0.50", "2.0000", "xr......"),
  ("clamped e_max < precision - 1", "floor", "4", "5E-1", "2.0000", "xr......"),
  ("clamped e_max < precision - 1", "floor", "4", "-0.5", "0.50000", "xr......"),
  (
    "clamped e_max < precision - 1", "floor", "1E+2", "0.5", "9.9999", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "floor", "1E+2", "0.50", "9.9999", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "floor", "1E+2", "5E-1", "9.9999", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "floor", "1E+2", "-0.5", "0.10000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "floor", "0.25", "0.5", "0.50000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "floor", "0.25", "0.50", "0.50000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "floor", "0.25", "5E-1", "0.50000", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "floor", "0.25", "-0.5", "2.0000", "xr......",
  ),
  ("clamped e_max < precision - 1", "floor", "2", "0.5", "1.4142", "xr......"),
  ("clamped e_max < precision - 1", "floor", "2", "0.50", "1.4142", "xr......"),
  ("clamped e_max < precision - 1", "floor", "2", "5E-1", "1.4142", "xr......"),
  ("clamped e_max < precision - 1", "floor", "2", "-0.5", "0.70710", "xr......"),
  (
    "clamped e_max < precision - 1", "floor", "1.0E+4", "0.5", "9.9999", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "floor", "1.0E+4", "0.50", "9.9999", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "floor", "1.0E+4", "5E-1", "9.9999", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "floor", "1.0E+4", "-0.5", "0.010000", "xr......",
  ),
  ("clamped e_max < precision - 1", "floor", "9", "0.5", "3.0000", "xr......"),
  ("clamped e_max < precision - 1", "floor", "9", "0.50", "3.0000", "xr......"),
  ("clamped e_max < precision - 1", "floor", "9", "5E-1", "3.0000", "xr......"),
  ("clamped e_max < precision - 1", "floor", "9", "-0.5", "0.33333", "xr......"),
  (
    "clamped e_max < precision - 1", "floor", "1E-9", "0.5", "0.000031622", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "floor", "1E-9", "0.50", "0.000031622", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "floor", "1E-9", "5E-1", "0.000031622", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "floor", "1E-9", "-0.5", "9.9999", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "floor", "1E+20", "0.5", "9.9999", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "floor", "1E+20", "0.50", "9.9999", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "floor", "1E+20", "5E-1", "9.9999", "xr..o...",
  ),
  (
    "clamped e_max < precision - 1", "floor", "1E+20", "-0.5", "1.0000E-10", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "floor", "1E-5", "0.5", "0.0031622", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "floor", "1E-5", "0.50", "0.0031622", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "floor", "1E-5", "5E-1", "0.0031622", "xr......",
  ),
  (
    "clamped e_max < precision - 1", "floor", "1E-5", "-0.5", "9.9999", "xr..o...",
  ),
  ("clamped e_max 1", "half_even", "0.01", "0.5", "0.100", "xr......"),
  ("clamped e_max 1", "half_even", "0.01", "0.50", "0.100", "xr......"),
  ("clamped e_max 1", "half_even", "0.01", "5E-1", "0.100", "xr......"),
  ("clamped e_max 1", "half_even", "0.01", "-0.5", "10.0", "xr......"),
  ("clamped e_max 1", "half_even", "4", "0.5", "2.00", "xr......"),
  ("clamped e_max 1", "half_even", "4", "0.50", "2.00", "xr......"),
  ("clamped e_max 1", "half_even", "4", "5E-1", "2.00", "xr......"),
  ("clamped e_max 1", "half_even", "4", "-0.5", "0.500", "xr......"),
  ("clamped e_max 1", "half_even", "1E+2", "0.5", "10.0", "xr......"),
  ("clamped e_max 1", "half_even", "1E+2", "0.50", "10.0", "xr......"),
  ("clamped e_max 1", "half_even", "1E+2", "5E-1", "10.0", "xr......"),
  ("clamped e_max 1", "half_even", "1E+2", "-0.5", "0.100", "xr......"),
  ("clamped e_max 1", "half_even", "0.25", "0.5", "0.500", "xr......"),
  ("clamped e_max 1", "half_even", "0.25", "0.50", "0.500", "xr......"),
  ("clamped e_max 1", "half_even", "0.25", "5E-1", "0.500", "xr......"),
  ("clamped e_max 1", "half_even", "0.25", "-0.5", "2.00", "xr......"),
  ("clamped e_max 1", "half_even", "2", "0.5", "1.41", "xr......"),
  ("clamped e_max 1", "half_even", "2", "0.50", "1.41", "xr......"),
  ("clamped e_max 1", "half_even", "2", "5E-1", "1.41", "xr......"),
  ("clamped e_max 1", "half_even", "2", "-0.5", "0.707", "xr......"),
  ("clamped e_max 1", "half_even", "1.0E+4", "0.5", "Infinity", "xr..o..."),
  ("clamped e_max 1", "half_even", "1.0E+4", "0.50", "Infinity", "xr..o..."),
  ("clamped e_max 1", "half_even", "1.0E+4", "5E-1", "Infinity", "xr..o..."),
  ("clamped e_max 1", "half_even", "1.0E+4", "-0.5", "0.0100", "xr......"),
  ("clamped e_max 1", "half_even", "9", "0.5", "3.00", "xr......"),
  ("clamped e_max 1", "half_even", "9", "0.50", "3.00", "xr......"),
  ("clamped e_max 1", "half_even", "9", "5E-1", "3.00", "xr......"),
  ("clamped e_max 1", "half_even", "9", "-0.5", "0.333", "xr......"),
  ("clamped e_max 1", "half_even", "1E-9", "0.5", "0.0000316", "xr......"),
  ("clamped e_max 1", "half_even", "1E-9", "0.50", "0.0000316", "xr......"),
  ("clamped e_max 1", "half_even", "1E-9", "5E-1", "0.0000316", "xr......"),
  ("clamped e_max 1", "half_even", "1E-9", "-0.5", "Infinity", "xr..o..."),
  ("clamped e_max 1", "half_even", "1E+20", "0.5", "Infinity", "xr..o..."),
  ("clamped e_max 1", "half_even", "1E+20", "0.50", "Infinity", "xr..o..."),
  ("clamped e_max 1", "half_even", "1E+20", "5E-1", "Infinity", "xr..o..."),
  ("clamped e_max 1", "half_even", "1E+20", "-0.5", "0E-7", "xr...usc"),
  ("clamped e_max 1", "half_even", "1E-5", "0.5", "0.00316", "xr......"),
  ("clamped e_max 1", "half_even", "1E-5", "0.50", "0.00316", "xr......"),
  ("clamped e_max 1", "half_even", "1E-5", "5E-1", "0.00316", "xr......"),
  ("clamped e_max 1", "half_even", "1E-5", "-0.5", "Infinity", "xr..o..."),
  ("clamped e_max 1", "down", "0.01", "0.5", "0.100", "xr......"),
  ("clamped e_max 1", "down", "0.01", "0.50", "0.100", "xr......"),
  ("clamped e_max 1", "down", "0.01", "5E-1", "0.100", "xr......"),
  ("clamped e_max 1", "down", "0.01", "-0.5", "10.0", "xr......"),
  ("clamped e_max 1", "down", "4", "0.5", "2.00", "xr......"),
  ("clamped e_max 1", "down", "4", "0.50", "2.00", "xr......"),
  ("clamped e_max 1", "down", "4", "5E-1", "2.00", "xr......"),
  ("clamped e_max 1", "down", "4", "-0.5", "0.500", "xr......"),
  ("clamped e_max 1", "down", "1E+2", "0.5", "10.0", "xr......"),
  ("clamped e_max 1", "down", "1E+2", "0.50", "10.0", "xr......"),
  ("clamped e_max 1", "down", "1E+2", "5E-1", "10.0", "xr......"),
  ("clamped e_max 1", "down", "1E+2", "-0.5", "0.100", "xr......"),
  ("clamped e_max 1", "down", "0.25", "0.5", "0.500", "xr......"),
  ("clamped e_max 1", "down", "0.25", "0.50", "0.500", "xr......"),
  ("clamped e_max 1", "down", "0.25", "5E-1", "0.500", "xr......"),
  ("clamped e_max 1", "down", "0.25", "-0.5", "2.00", "xr......"),
  ("clamped e_max 1", "down", "2", "0.5", "1.41", "xr......"),
  ("clamped e_max 1", "down", "2", "0.50", "1.41", "xr......"),
  ("clamped e_max 1", "down", "2", "5E-1", "1.41", "xr......"),
  ("clamped e_max 1", "down", "2", "-0.5", "0.707", "xr......"),
  ("clamped e_max 1", "down", "1.0E+4", "0.5", "99.9", "xr..o..."),
  ("clamped e_max 1", "down", "1.0E+4", "0.50", "99.9", "xr..o..."),
  ("clamped e_max 1", "down", "1.0E+4", "5E-1", "99.9", "xr..o..."),
  ("clamped e_max 1", "down", "1.0E+4", "-0.5", "0.0100", "xr......"),
  ("clamped e_max 1", "down", "9", "0.5", "3.00", "xr......"),
  ("clamped e_max 1", "down", "9", "0.50", "3.00", "xr......"),
  ("clamped e_max 1", "down", "9", "5E-1", "3.00", "xr......"),
  ("clamped e_max 1", "down", "9", "-0.5", "0.333", "xr......"),
  ("clamped e_max 1", "down", "1E-9", "0.5", "0.0000316", "xr......"),
  ("clamped e_max 1", "down", "1E-9", "0.50", "0.0000316", "xr......"),
  ("clamped e_max 1", "down", "1E-9", "5E-1", "0.0000316", "xr......"),
  ("clamped e_max 1", "down", "1E-9", "-0.5", "99.9", "xr..o..."),
  ("clamped e_max 1", "down", "1E+20", "0.5", "99.9", "xr..o..."),
  ("clamped e_max 1", "down", "1E+20", "0.50", "99.9", "xr..o..."),
  ("clamped e_max 1", "down", "1E+20", "5E-1", "99.9", "xr..o..."),
  ("clamped e_max 1", "down", "1E+20", "-0.5", "0E-7", "xr...usc"),
  ("clamped e_max 1", "down", "1E-5", "0.5", "0.00316", "xr......"),
  ("clamped e_max 1", "down", "1E-5", "0.50", "0.00316", "xr......"),
  ("clamped e_max 1", "down", "1E-5", "5E-1", "0.00316", "xr......"),
  ("clamped e_max 1", "down", "1E-5", "-0.5", "99.9", "xr..o..."),
  ("clamped e_max 1", "up", "0.01", "0.5", "0.100", "xr......"),
  ("clamped e_max 1", "up", "0.01", "0.50", "0.100", "xr......"),
  ("clamped e_max 1", "up", "0.01", "5E-1", "0.100", "xr......"),
  ("clamped e_max 1", "up", "0.01", "-0.5", "10.0", "xr......"),
  ("clamped e_max 1", "up", "4", "0.5", "2.00", "xr......"),
  ("clamped e_max 1", "up", "4", "0.50", "2.00", "xr......"),
  ("clamped e_max 1", "up", "4", "5E-1", "2.00", "xr......"),
  ("clamped e_max 1", "up", "4", "-0.5", "0.500", "xr......"),
  ("clamped e_max 1", "up", "1E+2", "0.5", "10.0", "xr......"),
  ("clamped e_max 1", "up", "1E+2", "0.50", "10.0", "xr......"),
  ("clamped e_max 1", "up", "1E+2", "5E-1", "10.0", "xr......"),
  ("clamped e_max 1", "up", "1E+2", "-0.5", "0.100", "xr......"),
  ("clamped e_max 1", "up", "0.25", "0.5", "0.500", "xr......"),
  ("clamped e_max 1", "up", "0.25", "0.50", "0.500", "xr......"),
  ("clamped e_max 1", "up", "0.25", "5E-1", "0.500", "xr......"),
  ("clamped e_max 1", "up", "0.25", "-0.5", "2.00", "xr......"),
  ("clamped e_max 1", "up", "2", "0.5", "1.42", "xr......"),
  ("clamped e_max 1", "up", "2", "0.50", "1.42", "xr......"),
  ("clamped e_max 1", "up", "2", "5E-1", "1.42", "xr......"),
  ("clamped e_max 1", "up", "2", "-0.5", "0.708", "xr......"),
  ("clamped e_max 1", "up", "1.0E+4", "0.5", "Infinity", "xr..o..."),
  ("clamped e_max 1", "up", "1.0E+4", "0.50", "Infinity", "xr..o..."),
  ("clamped e_max 1", "up", "1.0E+4", "5E-1", "Infinity", "xr..o..."),
  ("clamped e_max 1", "up", "1.0E+4", "-0.5", "0.0100", "xr......"),
  ("clamped e_max 1", "up", "9", "0.5", "3.00", "xr......"),
  ("clamped e_max 1", "up", "9", "0.50", "3.00", "xr......"),
  ("clamped e_max 1", "up", "9", "5E-1", "3.00", "xr......"),
  ("clamped e_max 1", "up", "9", "-0.5", "0.334", "xr......"),
  ("clamped e_max 1", "up", "1E-9", "0.5", "0.0000317", "xr......"),
  ("clamped e_max 1", "up", "1E-9", "0.50", "0.0000317", "xr......"),
  ("clamped e_max 1", "up", "1E-9", "5E-1", "0.0000317", "xr......"),
  ("clamped e_max 1", "up", "1E-9", "-0.5", "Infinity", "xr..o..."),
  ("clamped e_max 1", "up", "1E+20", "0.5", "Infinity", "xr..o..."),
  ("clamped e_max 1", "up", "1E+20", "0.50", "Infinity", "xr..o..."),
  ("clamped e_max 1", "up", "1E+20", "5E-1", "Infinity", "xr..o..."),
  ("clamped e_max 1", "up", "1E+20", "-0.5", "1E-7", "xr...us."),
  ("clamped e_max 1", "up", "1E-5", "0.5", "0.00317", "xr......"),
  ("clamped e_max 1", "up", "1E-5", "0.50", "0.00317", "xr......"),
  ("clamped e_max 1", "up", "1E-5", "5E-1", "0.00317", "xr......"),
  ("clamped e_max 1", "up", "1E-5", "-0.5", "Infinity", "xr..o..."),
  ("clamped e_max 1", "ceiling", "0.01", "0.5", "0.100", "xr......"),
  ("clamped e_max 1", "ceiling", "0.01", "0.50", "0.100", "xr......"),
  ("clamped e_max 1", "ceiling", "0.01", "5E-1", "0.100", "xr......"),
  ("clamped e_max 1", "ceiling", "0.01", "-0.5", "10.0", "xr......"),
  ("clamped e_max 1", "ceiling", "4", "0.5", "2.00", "xr......"),
  ("clamped e_max 1", "ceiling", "4", "0.50", "2.00", "xr......"),
  ("clamped e_max 1", "ceiling", "4", "5E-1", "2.00", "xr......"),
  ("clamped e_max 1", "ceiling", "4", "-0.5", "0.500", "xr......"),
  ("clamped e_max 1", "ceiling", "1E+2", "0.5", "10.0", "xr......"),
  ("clamped e_max 1", "ceiling", "1E+2", "0.50", "10.0", "xr......"),
  ("clamped e_max 1", "ceiling", "1E+2", "5E-1", "10.0", "xr......"),
  ("clamped e_max 1", "ceiling", "1E+2", "-0.5", "0.100", "xr......"),
  ("clamped e_max 1", "ceiling", "0.25", "0.5", "0.500", "xr......"),
  ("clamped e_max 1", "ceiling", "0.25", "0.50", "0.500", "xr......"),
  ("clamped e_max 1", "ceiling", "0.25", "5E-1", "0.500", "xr......"),
  ("clamped e_max 1", "ceiling", "0.25", "-0.5", "2.00", "xr......"),
  ("clamped e_max 1", "ceiling", "2", "0.5", "1.42", "xr......"),
  ("clamped e_max 1", "ceiling", "2", "0.50", "1.42", "xr......"),
  ("clamped e_max 1", "ceiling", "2", "5E-1", "1.42", "xr......"),
  ("clamped e_max 1", "ceiling", "2", "-0.5", "0.708", "xr......"),
  ("clamped e_max 1", "ceiling", "1.0E+4", "0.5", "Infinity", "xr..o..."),
  ("clamped e_max 1", "ceiling", "1.0E+4", "0.50", "Infinity", "xr..o..."),
  ("clamped e_max 1", "ceiling", "1.0E+4", "5E-1", "Infinity", "xr..o..."),
  ("clamped e_max 1", "ceiling", "1.0E+4", "-0.5", "0.0100", "xr......"),
  ("clamped e_max 1", "ceiling", "9", "0.5", "3.00", "xr......"),
  ("clamped e_max 1", "ceiling", "9", "0.50", "3.00", "xr......"),
  ("clamped e_max 1", "ceiling", "9", "5E-1", "3.00", "xr......"),
  ("clamped e_max 1", "ceiling", "9", "-0.5", "0.334", "xr......"),
  ("clamped e_max 1", "ceiling", "1E-9", "0.5", "0.0000317", "xr......"),
  ("clamped e_max 1", "ceiling", "1E-9", "0.50", "0.0000317", "xr......"),
  ("clamped e_max 1", "ceiling", "1E-9", "5E-1", "0.0000317", "xr......"),
  ("clamped e_max 1", "ceiling", "1E-9", "-0.5", "Infinity", "xr..o..."),
  ("clamped e_max 1", "ceiling", "1E+20", "0.5", "Infinity", "xr..o..."),
  ("clamped e_max 1", "ceiling", "1E+20", "0.50", "Infinity", "xr..o..."),
  ("clamped e_max 1", "ceiling", "1E+20", "5E-1", "Infinity", "xr..o..."),
  ("clamped e_max 1", "ceiling", "1E+20", "-0.5", "1E-7", "xr...us."),
  ("clamped e_max 1", "ceiling", "1E-5", "0.5", "0.00317", "xr......"),
  ("clamped e_max 1", "ceiling", "1E-5", "0.50", "0.00317", "xr......"),
  ("clamped e_max 1", "ceiling", "1E-5", "5E-1", "0.00317", "xr......"),
  ("clamped e_max 1", "ceiling", "1E-5", "-0.5", "Infinity", "xr..o..."),
  ("clamped e_max 1", "floor", "0.01", "0.5", "0.100", "xr......"),
  ("clamped e_max 1", "floor", "0.01", "0.50", "0.100", "xr......"),
  ("clamped e_max 1", "floor", "0.01", "5E-1", "0.100", "xr......"),
  ("clamped e_max 1", "floor", "0.01", "-0.5", "10.0", "xr......"),
  ("clamped e_max 1", "floor", "4", "0.5", "2.00", "xr......"),
  ("clamped e_max 1", "floor", "4", "0.50", "2.00", "xr......"),
  ("clamped e_max 1", "floor", "4", "5E-1", "2.00", "xr......"),
  ("clamped e_max 1", "floor", "4", "-0.5", "0.500", "xr......"),
  ("clamped e_max 1", "floor", "1E+2", "0.5", "10.0", "xr......"),
  ("clamped e_max 1", "floor", "1E+2", "0.50", "10.0", "xr......"),
  ("clamped e_max 1", "floor", "1E+2", "5E-1", "10.0", "xr......"),
  ("clamped e_max 1", "floor", "1E+2", "-0.5", "0.100", "xr......"),
  ("clamped e_max 1", "floor", "0.25", "0.5", "0.500", "xr......"),
  ("clamped e_max 1", "floor", "0.25", "0.50", "0.500", "xr......"),
  ("clamped e_max 1", "floor", "0.25", "5E-1", "0.500", "xr......"),
  ("clamped e_max 1", "floor", "0.25", "-0.5", "2.00", "xr......"),
  ("clamped e_max 1", "floor", "2", "0.5", "1.41", "xr......"),
  ("clamped e_max 1", "floor", "2", "0.50", "1.41", "xr......"),
  ("clamped e_max 1", "floor", "2", "5E-1", "1.41", "xr......"),
  ("clamped e_max 1", "floor", "2", "-0.5", "0.707", "xr......"),
  ("clamped e_max 1", "floor", "1.0E+4", "0.5", "99.9", "xr..o..."),
  ("clamped e_max 1", "floor", "1.0E+4", "0.50", "99.9", "xr..o..."),
  ("clamped e_max 1", "floor", "1.0E+4", "5E-1", "99.9", "xr..o..."),
  ("clamped e_max 1", "floor", "1.0E+4", "-0.5", "0.0100", "xr......"),
  ("clamped e_max 1", "floor", "9", "0.5", "3.00", "xr......"),
  ("clamped e_max 1", "floor", "9", "0.50", "3.00", "xr......"),
  ("clamped e_max 1", "floor", "9", "5E-1", "3.00", "xr......"),
  ("clamped e_max 1", "floor", "9", "-0.5", "0.333", "xr......"),
  ("clamped e_max 1", "floor", "1E-9", "0.5", "0.0000316", "xr......"),
  ("clamped e_max 1", "floor", "1E-9", "0.50", "0.0000316", "xr......"),
  ("clamped e_max 1", "floor", "1E-9", "5E-1", "0.0000316", "xr......"),
  ("clamped e_max 1", "floor", "1E-9", "-0.5", "99.9", "xr..o..."),
  ("clamped e_max 1", "floor", "1E+20", "0.5", "99.9", "xr..o..."),
  ("clamped e_max 1", "floor", "1E+20", "0.50", "99.9", "xr..o..."),
  ("clamped e_max 1", "floor", "1E+20", "5E-1", "99.9", "xr..o..."),
  ("clamped e_max 1", "floor", "1E+20", "-0.5", "0E-7", "xr...usc"),
  ("clamped e_max 1", "floor", "1E-5", "0.5", "0.00316", "xr......"),
  ("clamped e_max 1", "floor", "1E-5", "0.50", "0.00316", "xr......"),
  ("clamped e_max 1", "floor", "1E-5", "5E-1", "0.00316", "xr......"),
  ("clamped e_max 1", "floor", "1E-5", "-0.5", "99.9", "xr..o..."),
  ("not clamped", "half_even", "0.01", "0.5", "0.10000", "xr......"),
  ("not clamped", "half_even", "0.01", "0.50", "0.10000", "xr......"),
  ("not clamped", "half_even", "0.01", "5E-1", "0.10000", "xr......"),
  ("not clamped", "half_even", "0.01", "-0.5", "Infinity", "xr..o..."),
  ("not clamped", "half_even", "4", "0.5", "2.0000", "xr......"),
  ("not clamped", "half_even", "4", "0.50", "2.0000", "xr......"),
  ("not clamped", "half_even", "4", "5E-1", "2.0000", "xr......"),
  ("not clamped", "half_even", "4", "-0.5", "0.50000", "xr......"),
  ("not clamped", "half_even", "1E+2", "0.5", "Infinity", "xr..o..."),
  ("not clamped", "half_even", "1E+2", "0.50", "Infinity", "xr..o..."),
  ("not clamped", "half_even", "1E+2", "5E-1", "Infinity", "xr..o..."),
  ("not clamped", "half_even", "1E+2", "-0.5", "0.10000", "xr......"),
  ("not clamped", "half_even", "0.25", "0.5", "0.50000", "xr......"),
  ("not clamped", "half_even", "0.25", "0.50", "0.50000", "xr......"),
  ("not clamped", "half_even", "0.25", "5E-1", "0.50000", "xr......"),
  ("not clamped", "half_even", "0.25", "-0.5", "2.0000", "xr......"),
  ("not clamped", "half_even", "2", "0.5", "1.4142", "xr......"),
  ("not clamped", "half_even", "2", "0.50", "1.4142", "xr......"),
  ("not clamped", "half_even", "2", "5E-1", "1.4142", "xr......"),
  ("not clamped", "half_even", "2", "-0.5", "0.70711", "xr......"),
  ("not clamped", "half_even", "1.0E+4", "0.5", "Infinity", "xr..o..."),
  ("not clamped", "half_even", "1.0E+4", "0.50", "Infinity", "xr..o..."),
  ("not clamped", "half_even", "1.0E+4", "5E-1", "Infinity", "xr..o..."),
  ("not clamped", "half_even", "1.0E+4", "-0.5", "0.010000", "xr......"),
  ("not clamped", "half_even", "9", "0.5", "3.0000", "xr......"),
  ("not clamped", "half_even", "9", "0.50", "3.0000", "xr......"),
  ("not clamped", "half_even", "9", "5E-1", "3.0000", "xr......"),
  ("not clamped", "half_even", "9", "-0.5", "0.33333", "xr......"),
  ("not clamped", "half_even", "1E-9", "0.5", "0.000031623", "xr......"),
  ("not clamped", "half_even", "1E-9", "0.50", "0.000031623", "xr......"),
  ("not clamped", "half_even", "1E-9", "5E-1", "0.000031623", "xr......"),
  ("not clamped", "half_even", "1E-9", "-0.5", "Infinity", "xr..o..."),
  ("not clamped", "half_even", "1E+20", "0.5", "Infinity", "xr..o..."),
  ("not clamped", "half_even", "1E+20", "0.50", "Infinity", "xr..o..."),
  ("not clamped", "half_even", "1E+20", "5E-1", "Infinity", "xr..o..."),
  ("not clamped", "half_even", "1E+20", "-0.5", "1.0000E-10", "xr......"),
  ("not clamped", "half_even", "1E-5", "0.5", "0.0031623", "xr......"),
  ("not clamped", "half_even", "1E-5", "0.50", "0.0031623", "xr......"),
  ("not clamped", "half_even", "1E-5", "5E-1", "0.0031623", "xr......"),
  ("not clamped", "half_even", "1E-5", "-0.5", "Infinity", "xr..o..."),
  ("not clamped", "down", "0.01", "0.5", "0.10000", "xr......"),
  ("not clamped", "down", "0.01", "0.50", "0.10000", "xr......"),
  ("not clamped", "down", "0.01", "5E-1", "0.10000", "xr......"),
  ("not clamped", "down", "0.01", "-0.5", "9.9999", "xr..o..."),
  ("not clamped", "down", "4", "0.5", "2.0000", "xr......"),
  ("not clamped", "down", "4", "0.50", "2.0000", "xr......"),
  ("not clamped", "down", "4", "5E-1", "2.0000", "xr......"),
  ("not clamped", "down", "4", "-0.5", "0.50000", "xr......"),
  ("not clamped", "down", "1E+2", "0.5", "9.9999", "xr..o..."),
  ("not clamped", "down", "1E+2", "0.50", "9.9999", "xr..o..."),
  ("not clamped", "down", "1E+2", "5E-1", "9.9999", "xr..o..."),
  ("not clamped", "down", "1E+2", "-0.5", "0.10000", "xr......"),
  ("not clamped", "down", "0.25", "0.5", "0.50000", "xr......"),
  ("not clamped", "down", "0.25", "0.50", "0.50000", "xr......"),
  ("not clamped", "down", "0.25", "5E-1", "0.50000", "xr......"),
  ("not clamped", "down", "0.25", "-0.5", "2.0000", "xr......"),
  ("not clamped", "down", "2", "0.5", "1.4142", "xr......"),
  ("not clamped", "down", "2", "0.50", "1.4142", "xr......"),
  ("not clamped", "down", "2", "5E-1", "1.4142", "xr......"),
  ("not clamped", "down", "2", "-0.5", "0.70710", "xr......"),
  ("not clamped", "down", "1.0E+4", "0.5", "9.9999", "xr..o..."),
  ("not clamped", "down", "1.0E+4", "0.50", "9.9999", "xr..o..."),
  ("not clamped", "down", "1.0E+4", "5E-1", "9.9999", "xr..o..."),
  ("not clamped", "down", "1.0E+4", "-0.5", "0.010000", "xr......"),
  ("not clamped", "down", "9", "0.5", "3.0000", "xr......"),
  ("not clamped", "down", "9", "0.50", "3.0000", "xr......"),
  ("not clamped", "down", "9", "5E-1", "3.0000", "xr......"),
  ("not clamped", "down", "9", "-0.5", "0.33333", "xr......"),
  ("not clamped", "down", "1E-9", "0.5", "0.000031622", "xr......"),
  ("not clamped", "down", "1E-9", "0.50", "0.000031622", "xr......"),
  ("not clamped", "down", "1E-9", "5E-1", "0.000031622", "xr......"),
  ("not clamped", "down", "1E-9", "-0.5", "9.9999", "xr..o..."),
  ("not clamped", "down", "1E+20", "0.5", "9.9999", "xr..o..."),
  ("not clamped", "down", "1E+20", "0.50", "9.9999", "xr..o..."),
  ("not clamped", "down", "1E+20", "5E-1", "9.9999", "xr..o..."),
  ("not clamped", "down", "1E+20", "-0.5", "1.0000E-10", "xr......"),
  ("not clamped", "down", "1E-5", "0.5", "0.0031622", "xr......"),
  ("not clamped", "down", "1E-5", "0.50", "0.0031622", "xr......"),
  ("not clamped", "down", "1E-5", "5E-1", "0.0031622", "xr......"),
  ("not clamped", "down", "1E-5", "-0.5", "9.9999", "xr..o..."),
  ("not clamped", "up", "0.01", "0.5", "0.10000", "xr......"),
  ("not clamped", "up", "0.01", "0.50", "0.10000", "xr......"),
  ("not clamped", "up", "0.01", "5E-1", "0.10000", "xr......"),
  ("not clamped", "up", "0.01", "-0.5", "Infinity", "xr..o..."),
  ("not clamped", "up", "4", "0.5", "2.0000", "xr......"),
  ("not clamped", "up", "4", "0.50", "2.0000", "xr......"),
  ("not clamped", "up", "4", "5E-1", "2.0000", "xr......"),
  ("not clamped", "up", "4", "-0.5", "0.50000", "xr......"),
  ("not clamped", "up", "1E+2", "0.5", "Infinity", "xr..o..."),
  ("not clamped", "up", "1E+2", "0.50", "Infinity", "xr..o..."),
  ("not clamped", "up", "1E+2", "5E-1", "Infinity", "xr..o..."),
  ("not clamped", "up", "1E+2", "-0.5", "0.10000", "xr......"),
  ("not clamped", "up", "0.25", "0.5", "0.50000", "xr......"),
  ("not clamped", "up", "0.25", "0.50", "0.50000", "xr......"),
  ("not clamped", "up", "0.25", "5E-1", "0.50000", "xr......"),
  ("not clamped", "up", "0.25", "-0.5", "2.0000", "xr......"),
  ("not clamped", "up", "2", "0.5", "1.4143", "xr......"),
  ("not clamped", "up", "2", "0.50", "1.4143", "xr......"),
  ("not clamped", "up", "2", "5E-1", "1.4143", "xr......"),
  ("not clamped", "up", "2", "-0.5", "0.70711", "xr......"),
  ("not clamped", "up", "1.0E+4", "0.5", "Infinity", "xr..o..."),
  ("not clamped", "up", "1.0E+4", "0.50", "Infinity", "xr..o..."),
  ("not clamped", "up", "1.0E+4", "5E-1", "Infinity", "xr..o..."),
  ("not clamped", "up", "1.0E+4", "-0.5", "0.010000", "xr......"),
  ("not clamped", "up", "9", "0.5", "3.0000", "xr......"),
  ("not clamped", "up", "9", "0.50", "3.0000", "xr......"),
  ("not clamped", "up", "9", "5E-1", "3.0000", "xr......"),
  ("not clamped", "up", "9", "-0.5", "0.33334", "xr......"),
  ("not clamped", "up", "1E-9", "0.5", "0.000031623", "xr......"),
  ("not clamped", "up", "1E-9", "0.50", "0.000031623", "xr......"),
  ("not clamped", "up", "1E-9", "5E-1", "0.000031623", "xr......"),
  ("not clamped", "up", "1E-9", "-0.5", "Infinity", "xr..o..."),
  ("not clamped", "up", "1E+20", "0.5", "Infinity", "xr..o..."),
  ("not clamped", "up", "1E+20", "0.50", "Infinity", "xr..o..."),
  ("not clamped", "up", "1E+20", "5E-1", "Infinity", "xr..o..."),
  ("not clamped", "up", "1E+20", "-0.5", "1.0000E-10", "xr......"),
  ("not clamped", "up", "1E-5", "0.5", "0.0031623", "xr......"),
  ("not clamped", "up", "1E-5", "0.50", "0.0031623", "xr......"),
  ("not clamped", "up", "1E-5", "5E-1", "0.0031623", "xr......"),
  ("not clamped", "up", "1E-5", "-0.5", "Infinity", "xr..o..."),
  ("not clamped", "ceiling", "0.01", "0.5", "0.10000", "xr......"),
  ("not clamped", "ceiling", "0.01", "0.50", "0.10000", "xr......"),
  ("not clamped", "ceiling", "0.01", "5E-1", "0.10000", "xr......"),
  ("not clamped", "ceiling", "0.01", "-0.5", "Infinity", "xr..o..."),
  ("not clamped", "ceiling", "4", "0.5", "2.0000", "xr......"),
  ("not clamped", "ceiling", "4", "0.50", "2.0000", "xr......"),
  ("not clamped", "ceiling", "4", "5E-1", "2.0000", "xr......"),
  ("not clamped", "ceiling", "4", "-0.5", "0.50000", "xr......"),
  ("not clamped", "ceiling", "1E+2", "0.5", "Infinity", "xr..o..."),
  ("not clamped", "ceiling", "1E+2", "0.50", "Infinity", "xr..o..."),
  ("not clamped", "ceiling", "1E+2", "5E-1", "Infinity", "xr..o..."),
  ("not clamped", "ceiling", "1E+2", "-0.5", "0.10000", "xr......"),
  ("not clamped", "ceiling", "0.25", "0.5", "0.50000", "xr......"),
  ("not clamped", "ceiling", "0.25", "0.50", "0.50000", "xr......"),
  ("not clamped", "ceiling", "0.25", "5E-1", "0.50000", "xr......"),
  ("not clamped", "ceiling", "0.25", "-0.5", "2.0000", "xr......"),
  ("not clamped", "ceiling", "2", "0.5", "1.4143", "xr......"),
  ("not clamped", "ceiling", "2", "0.50", "1.4143", "xr......"),
  ("not clamped", "ceiling", "2", "5E-1", "1.4143", "xr......"),
  ("not clamped", "ceiling", "2", "-0.5", "0.70711", "xr......"),
  ("not clamped", "ceiling", "1.0E+4", "0.5", "Infinity", "xr..o..."),
  ("not clamped", "ceiling", "1.0E+4", "0.50", "Infinity", "xr..o..."),
  ("not clamped", "ceiling", "1.0E+4", "5E-1", "Infinity", "xr..o..."),
  ("not clamped", "ceiling", "1.0E+4", "-0.5", "0.010000", "xr......"),
  ("not clamped", "ceiling", "9", "0.5", "3.0000", "xr......"),
  ("not clamped", "ceiling", "9", "0.50", "3.0000", "xr......"),
  ("not clamped", "ceiling", "9", "5E-1", "3.0000", "xr......"),
  ("not clamped", "ceiling", "9", "-0.5", "0.33334", "xr......"),
  ("not clamped", "ceiling", "1E-9", "0.5", "0.000031623", "xr......"),
  ("not clamped", "ceiling", "1E-9", "0.50", "0.000031623", "xr......"),
  ("not clamped", "ceiling", "1E-9", "5E-1", "0.000031623", "xr......"),
  ("not clamped", "ceiling", "1E-9", "-0.5", "Infinity", "xr..o..."),
  ("not clamped", "ceiling", "1E+20", "0.5", "Infinity", "xr..o..."),
  ("not clamped", "ceiling", "1E+20", "0.50", "Infinity", "xr..o..."),
  ("not clamped", "ceiling", "1E+20", "5E-1", "Infinity", "xr..o..."),
  ("not clamped", "ceiling", "1E+20", "-0.5", "1.0000E-10", "xr......"),
  ("not clamped", "ceiling", "1E-5", "0.5", "0.0031623", "xr......"),
  ("not clamped", "ceiling", "1E-5", "0.50", "0.0031623", "xr......"),
  ("not clamped", "ceiling", "1E-5", "5E-1", "0.0031623", "xr......"),
  ("not clamped", "ceiling", "1E-5", "-0.5", "Infinity", "xr..o..."),
  ("not clamped", "floor", "0.01", "0.5", "0.10000", "xr......"),
  ("not clamped", "floor", "0.01", "0.50", "0.10000", "xr......"),
  ("not clamped", "floor", "0.01", "5E-1", "0.10000", "xr......"),
  ("not clamped", "floor", "0.01", "-0.5", "9.9999", "xr..o..."),
  ("not clamped", "floor", "4", "0.5", "2.0000", "xr......"),
  ("not clamped", "floor", "4", "0.50", "2.0000", "xr......"),
  ("not clamped", "floor", "4", "5E-1", "2.0000", "xr......"),
  ("not clamped", "floor", "4", "-0.5", "0.50000", "xr......"),
  ("not clamped", "floor", "1E+2", "0.5", "9.9999", "xr..o..."),
  ("not clamped", "floor", "1E+2", "0.50", "9.9999", "xr..o..."),
  ("not clamped", "floor", "1E+2", "5E-1", "9.9999", "xr..o..."),
  ("not clamped", "floor", "1E+2", "-0.5", "0.10000", "xr......"),
  ("not clamped", "floor", "0.25", "0.5", "0.50000", "xr......"),
  ("not clamped", "floor", "0.25", "0.50", "0.50000", "xr......"),
  ("not clamped", "floor", "0.25", "5E-1", "0.50000", "xr......"),
  ("not clamped", "floor", "0.25", "-0.5", "2.0000", "xr......"),
  ("not clamped", "floor", "2", "0.5", "1.4142", "xr......"),
  ("not clamped", "floor", "2", "0.50", "1.4142", "xr......"),
  ("not clamped", "floor", "2", "5E-1", "1.4142", "xr......"),
  ("not clamped", "floor", "2", "-0.5", "0.70710", "xr......"),
  ("not clamped", "floor", "1.0E+4", "0.5", "9.9999", "xr..o..."),
  ("not clamped", "floor", "1.0E+4", "0.50", "9.9999", "xr..o..."),
  ("not clamped", "floor", "1.0E+4", "5E-1", "9.9999", "xr..o..."),
  ("not clamped", "floor", "1.0E+4", "-0.5", "0.010000", "xr......"),
  ("not clamped", "floor", "9", "0.5", "3.0000", "xr......"),
  ("not clamped", "floor", "9", "0.50", "3.0000", "xr......"),
  ("not clamped", "floor", "9", "5E-1", "3.0000", "xr......"),
  ("not clamped", "floor", "9", "-0.5", "0.33333", "xr......"),
  ("not clamped", "floor", "1E-9", "0.5", "0.000031622", "xr......"),
  ("not clamped", "floor", "1E-9", "0.50", "0.000031622", "xr......"),
  ("not clamped", "floor", "1E-9", "5E-1", "0.000031622", "xr......"),
  ("not clamped", "floor", "1E-9", "-0.5", "9.9999", "xr..o..."),
  ("not clamped", "floor", "1E+20", "0.5", "9.9999", "xr..o..."),
  ("not clamped", "floor", "1E+20", "0.50", "9.9999", "xr..o..."),
  ("not clamped", "floor", "1E+20", "5E-1", "9.9999", "xr..o..."),
  ("not clamped", "floor", "1E+20", "-0.5", "1.0000E-10", "xr......"),
  ("not clamped", "floor", "1E-5", "0.5", "0.0031622", "xr......"),
  ("not clamped", "floor", "1E-5", "0.50", "0.0031622", "xr......"),
  ("not clamped", "floor", "1E-5", "5E-1", "0.0031622", "xr......"),
  ("not clamped", "floor", "1E-5", "-0.5", "9.9999", "xr..o..."),
  ("decimal32", "half_even", "0.01", "0.5", "0.1000000", "xr......"),
  ("decimal32", "half_even", "0.01", "0.50", "0.1000000", "xr......"),
  ("decimal32", "half_even", "0.01", "5E-1", "0.1000000", "xr......"),
  ("decimal32", "half_even", "0.01", "-0.5", "10.00000", "xr......"),
  ("decimal32", "half_even", "4", "0.5", "2.000000", "xr......"),
  ("decimal32", "half_even", "4", "0.50", "2.000000", "xr......"),
  ("decimal32", "half_even", "4", "5E-1", "2.000000", "xr......"),
  ("decimal32", "half_even", "4", "-0.5", "0.5000000", "xr......"),
  ("decimal32", "half_even", "1E+2", "0.5", "10.00000", "xr......"),
  ("decimal32", "half_even", "1E+2", "0.50", "10.00000", "xr......"),
  ("decimal32", "half_even", "1E+2", "5E-1", "10.00000", "xr......"),
  ("decimal32", "half_even", "1E+2", "-0.5", "0.1000000", "xr......"),
  ("decimal32", "half_even", "0.25", "0.5", "0.5000000", "xr......"),
  ("decimal32", "half_even", "0.25", "0.50", "0.5000000", "xr......"),
  ("decimal32", "half_even", "0.25", "5E-1", "0.5000000", "xr......"),
  ("decimal32", "half_even", "0.25", "-0.5", "2.000000", "xr......"),
  ("decimal32", "half_even", "2", "0.5", "1.414214", "xr......"),
  ("decimal32", "half_even", "2", "0.50", "1.414214", "xr......"),
  ("decimal32", "half_even", "2", "5E-1", "1.414214", "xr......"),
  ("decimal32", "half_even", "2", "-0.5", "0.7071068", "xr......"),
  ("decimal32", "half_even", "1.0E+4", "0.5", "100.0000", "xr......"),
  ("decimal32", "half_even", "1.0E+4", "0.50", "100.0000", "xr......"),
  ("decimal32", "half_even", "1.0E+4", "5E-1", "100.0000", "xr......"),
  ("decimal32", "half_even", "1.0E+4", "-0.5", "0.01000000", "xr......"),
  ("decimal32", "half_even", "9", "0.5", "3.000000", "xr......"),
  ("decimal32", "half_even", "9", "0.50", "3.000000", "xr......"),
  ("decimal32", "half_even", "9", "5E-1", "3.000000", "xr......"),
  ("decimal32", "half_even", "9", "-0.5", "0.3333333", "xr......"),
  ("decimal32", "half_even", "1E-9", "0.5", "0.00003162278", "xr......"),
  ("decimal32", "half_even", "1E-9", "0.50", "0.00003162278", "xr......"),
  ("decimal32", "half_even", "1E-9", "5E-1", "0.00003162278", "xr......"),
  ("decimal32", "half_even", "1E-9", "-0.5", "31622.78", "xr......"),
  ("decimal32", "half_even", "1E+20", "0.5", "1.000000E+10", "xr......"),
  ("decimal32", "half_even", "1E+20", "0.50", "1.000000E+10", "xr......"),
  ("decimal32", "half_even", "1E+20", "5E-1", "1.000000E+10", "xr......"),
  ("decimal32", "half_even", "1E+20", "-0.5", "1.000000E-10", "xr......"),
  ("decimal32", "half_even", "1E-5", "0.5", "0.003162278", "xr......"),
  ("decimal32", "half_even", "1E-5", "0.50", "0.003162278", "xr......"),
  ("decimal32", "half_even", "1E-5", "5E-1", "0.003162278", "xr......"),
  ("decimal32", "half_even", "1E-5", "-0.5", "316.2278", "xr......"),
  ("decimal32", "down", "0.01", "0.5", "0.1000000", "xr......"),
  ("decimal32", "down", "0.01", "0.50", "0.1000000", "xr......"),
  ("decimal32", "down", "0.01", "5E-1", "0.1000000", "xr......"),
  ("decimal32", "down", "0.01", "-0.5", "10.00000", "xr......"),
  ("decimal32", "down", "4", "0.5", "2.000000", "xr......"),
  ("decimal32", "down", "4", "0.50", "2.000000", "xr......"),
  ("decimal32", "down", "4", "5E-1", "2.000000", "xr......"),
  ("decimal32", "down", "4", "-0.5", "0.5000000", "xr......"),
  ("decimal32", "down", "1E+2", "0.5", "10.00000", "xr......"),
  ("decimal32", "down", "1E+2", "0.50", "10.00000", "xr......"),
  ("decimal32", "down", "1E+2", "5E-1", "10.00000", "xr......"),
  ("decimal32", "down", "1E+2", "-0.5", "0.1000000", "xr......"),
  ("decimal32", "down", "0.25", "0.5", "0.5000000", "xr......"),
  ("decimal32", "down", "0.25", "0.50", "0.5000000", "xr......"),
  ("decimal32", "down", "0.25", "5E-1", "0.5000000", "xr......"),
  ("decimal32", "down", "0.25", "-0.5", "2.000000", "xr......"),
  ("decimal32", "down", "2", "0.5", "1.414213", "xr......"),
  ("decimal32", "down", "2", "0.50", "1.414213", "xr......"),
  ("decimal32", "down", "2", "5E-1", "1.414213", "xr......"),
  ("decimal32", "down", "2", "-0.5", "0.7071067", "xr......"),
  ("decimal32", "down", "1.0E+4", "0.5", "100.0000", "xr......"),
  ("decimal32", "down", "1.0E+4", "0.50", "100.0000", "xr......"),
  ("decimal32", "down", "1.0E+4", "5E-1", "100.0000", "xr......"),
  ("decimal32", "down", "1.0E+4", "-0.5", "0.01000000", "xr......"),
  ("decimal32", "down", "9", "0.5", "3.000000", "xr......"),
  ("decimal32", "down", "9", "0.50", "3.000000", "xr......"),
  ("decimal32", "down", "9", "5E-1", "3.000000", "xr......"),
  ("decimal32", "down", "9", "-0.5", "0.3333333", "xr......"),
  ("decimal32", "down", "1E-9", "0.5", "0.00003162277", "xr......"),
  ("decimal32", "down", "1E-9", "0.50", "0.00003162277", "xr......"),
  ("decimal32", "down", "1E-9", "5E-1", "0.00003162277", "xr......"),
  ("decimal32", "down", "1E-9", "-0.5", "31622.77", "xr......"),
  ("decimal32", "down", "1E+20", "0.5", "1.000000E+10", "xr......"),
  ("decimal32", "down", "1E+20", "0.50", "1.000000E+10", "xr......"),
  ("decimal32", "down", "1E+20", "5E-1", "1.000000E+10", "xr......"),
  ("decimal32", "down", "1E+20", "-0.5", "1.000000E-10", "xr......"),
  ("decimal32", "down", "1E-5", "0.5", "0.003162277", "xr......"),
  ("decimal32", "down", "1E-5", "0.50", "0.003162277", "xr......"),
  ("decimal32", "down", "1E-5", "5E-1", "0.003162277", "xr......"),
  ("decimal32", "down", "1E-5", "-0.5", "316.2277", "xr......"),
  ("decimal32", "up", "0.01", "0.5", "0.1000000", "xr......"),
  ("decimal32", "up", "0.01", "0.50", "0.1000000", "xr......"),
  ("decimal32", "up", "0.01", "5E-1", "0.1000000", "xr......"),
  ("decimal32", "up", "0.01", "-0.5", "10.00000", "xr......"),
  ("decimal32", "up", "4", "0.5", "2.000000", "xr......"),
  ("decimal32", "up", "4", "0.50", "2.000000", "xr......"),
  ("decimal32", "up", "4", "5E-1", "2.000000", "xr......"),
  ("decimal32", "up", "4", "-0.5", "0.5000000", "xr......"),
  ("decimal32", "up", "1E+2", "0.5", "10.00000", "xr......"),
  ("decimal32", "up", "1E+2", "0.50", "10.00000", "xr......"),
  ("decimal32", "up", "1E+2", "5E-1", "10.00000", "xr......"),
  ("decimal32", "up", "1E+2", "-0.5", "0.1000000", "xr......"),
  ("decimal32", "up", "0.25", "0.5", "0.5000000", "xr......"),
  ("decimal32", "up", "0.25", "0.50", "0.5000000", "xr......"),
  ("decimal32", "up", "0.25", "5E-1", "0.5000000", "xr......"),
  ("decimal32", "up", "0.25", "-0.5", "2.000000", "xr......"),
  ("decimal32", "up", "2", "0.5", "1.414214", "xr......"),
  ("decimal32", "up", "2", "0.50", "1.414214", "xr......"),
  ("decimal32", "up", "2", "5E-1", "1.414214", "xr......"),
  ("decimal32", "up", "2", "-0.5", "0.7071068", "xr......"),
  ("decimal32", "up", "1.0E+4", "0.5", "100.0000", "xr......"),
  ("decimal32", "up", "1.0E+4", "0.50", "100.0000", "xr......"),
  ("decimal32", "up", "1.0E+4", "5E-1", "100.0000", "xr......"),
  ("decimal32", "up", "1.0E+4", "-0.5", "0.01000000", "xr......"),
  ("decimal32", "up", "9", "0.5", "3.000000", "xr......"),
  ("decimal32", "up", "9", "0.50", "3.000000", "xr......"),
  ("decimal32", "up", "9", "5E-1", "3.000000", "xr......"),
  ("decimal32", "up", "9", "-0.5", "0.3333334", "xr......"),
  ("decimal32", "up", "1E-9", "0.5", "0.00003162278", "xr......"),
  ("decimal32", "up", "1E-9", "0.50", "0.00003162278", "xr......"),
  ("decimal32", "up", "1E-9", "5E-1", "0.00003162278", "xr......"),
  ("decimal32", "up", "1E-9", "-0.5", "31622.78", "xr......"),
  ("decimal32", "up", "1E+20", "0.5", "1.000000E+10", "xr......"),
  ("decimal32", "up", "1E+20", "0.50", "1.000000E+10", "xr......"),
  ("decimal32", "up", "1E+20", "5E-1", "1.000000E+10", "xr......"),
  ("decimal32", "up", "1E+20", "-0.5", "1.000000E-10", "xr......"),
  ("decimal32", "up", "1E-5", "0.5", "0.003162278", "xr......"),
  ("decimal32", "up", "1E-5", "0.50", "0.003162278", "xr......"),
  ("decimal32", "up", "1E-5", "5E-1", "0.003162278", "xr......"),
  ("decimal32", "up", "1E-5", "-0.5", "316.2278", "xr......"),
  ("decimal32", "ceiling", "0.01", "0.5", "0.1000000", "xr......"),
  ("decimal32", "ceiling", "0.01", "0.50", "0.1000000", "xr......"),
  ("decimal32", "ceiling", "0.01", "5E-1", "0.1000000", "xr......"),
  ("decimal32", "ceiling", "0.01", "-0.5", "10.00000", "xr......"),
  ("decimal32", "ceiling", "4", "0.5", "2.000000", "xr......"),
  ("decimal32", "ceiling", "4", "0.50", "2.000000", "xr......"),
  ("decimal32", "ceiling", "4", "5E-1", "2.000000", "xr......"),
  ("decimal32", "ceiling", "4", "-0.5", "0.5000000", "xr......"),
  ("decimal32", "ceiling", "1E+2", "0.5", "10.00000", "xr......"),
  ("decimal32", "ceiling", "1E+2", "0.50", "10.00000", "xr......"),
  ("decimal32", "ceiling", "1E+2", "5E-1", "10.00000", "xr......"),
  ("decimal32", "ceiling", "1E+2", "-0.5", "0.1000000", "xr......"),
  ("decimal32", "ceiling", "0.25", "0.5", "0.5000000", "xr......"),
  ("decimal32", "ceiling", "0.25", "0.50", "0.5000000", "xr......"),
  ("decimal32", "ceiling", "0.25", "5E-1", "0.5000000", "xr......"),
  ("decimal32", "ceiling", "0.25", "-0.5", "2.000000", "xr......"),
  ("decimal32", "ceiling", "2", "0.5", "1.414214", "xr......"),
  ("decimal32", "ceiling", "2", "0.50", "1.414214", "xr......"),
  ("decimal32", "ceiling", "2", "5E-1", "1.414214", "xr......"),
  ("decimal32", "ceiling", "2", "-0.5", "0.7071068", "xr......"),
  ("decimal32", "ceiling", "1.0E+4", "0.5", "100.0000", "xr......"),
  ("decimal32", "ceiling", "1.0E+4", "0.50", "100.0000", "xr......"),
  ("decimal32", "ceiling", "1.0E+4", "5E-1", "100.0000", "xr......"),
  ("decimal32", "ceiling", "1.0E+4", "-0.5", "0.01000000", "xr......"),
  ("decimal32", "ceiling", "9", "0.5", "3.000000", "xr......"),
  ("decimal32", "ceiling", "9", "0.50", "3.000000", "xr......"),
  ("decimal32", "ceiling", "9", "5E-1", "3.000000", "xr......"),
  ("decimal32", "ceiling", "9", "-0.5", "0.3333334", "xr......"),
  ("decimal32", "ceiling", "1E-9", "0.5", "0.00003162278", "xr......"),
  ("decimal32", "ceiling", "1E-9", "0.50", "0.00003162278", "xr......"),
  ("decimal32", "ceiling", "1E-9", "5E-1", "0.00003162278", "xr......"),
  ("decimal32", "ceiling", "1E-9", "-0.5", "31622.78", "xr......"),
  ("decimal32", "ceiling", "1E+20", "0.5", "1.000000E+10", "xr......"),
  ("decimal32", "ceiling", "1E+20", "0.50", "1.000000E+10", "xr......"),
  ("decimal32", "ceiling", "1E+20", "5E-1", "1.000000E+10", "xr......"),
  ("decimal32", "ceiling", "1E+20", "-0.5", "1.000000E-10", "xr......"),
  ("decimal32", "ceiling", "1E-5", "0.5", "0.003162278", "xr......"),
  ("decimal32", "ceiling", "1E-5", "0.50", "0.003162278", "xr......"),
  ("decimal32", "ceiling", "1E-5", "5E-1", "0.003162278", "xr......"),
  ("decimal32", "ceiling", "1E-5", "-0.5", "316.2278", "xr......"),
  ("decimal32", "floor", "0.01", "0.5", "0.1000000", "xr......"),
  ("decimal32", "floor", "0.01", "0.50", "0.1000000", "xr......"),
  ("decimal32", "floor", "0.01", "5E-1", "0.1000000", "xr......"),
  ("decimal32", "floor", "0.01", "-0.5", "10.00000", "xr......"),
  ("decimal32", "floor", "4", "0.5", "2.000000", "xr......"),
  ("decimal32", "floor", "4", "0.50", "2.000000", "xr......"),
  ("decimal32", "floor", "4", "5E-1", "2.000000", "xr......"),
  ("decimal32", "floor", "4", "-0.5", "0.5000000", "xr......"),
  ("decimal32", "floor", "1E+2", "0.5", "10.00000", "xr......"),
  ("decimal32", "floor", "1E+2", "0.50", "10.00000", "xr......"),
  ("decimal32", "floor", "1E+2", "5E-1", "10.00000", "xr......"),
  ("decimal32", "floor", "1E+2", "-0.5", "0.1000000", "xr......"),
  ("decimal32", "floor", "0.25", "0.5", "0.5000000", "xr......"),
  ("decimal32", "floor", "0.25", "0.50", "0.5000000", "xr......"),
  ("decimal32", "floor", "0.25", "5E-1", "0.5000000", "xr......"),
  ("decimal32", "floor", "0.25", "-0.5", "2.000000", "xr......"),
  ("decimal32", "floor", "2", "0.5", "1.414213", "xr......"),
  ("decimal32", "floor", "2", "0.50", "1.414213", "xr......"),
  ("decimal32", "floor", "2", "5E-1", "1.414213", "xr......"),
  ("decimal32", "floor", "2", "-0.5", "0.7071067", "xr......"),
  ("decimal32", "floor", "1.0E+4", "0.5", "100.0000", "xr......"),
  ("decimal32", "floor", "1.0E+4", "0.50", "100.0000", "xr......"),
  ("decimal32", "floor", "1.0E+4", "5E-1", "100.0000", "xr......"),
  ("decimal32", "floor", "1.0E+4", "-0.5", "0.01000000", "xr......"),
  ("decimal32", "floor", "9", "0.5", "3.000000", "xr......"),
  ("decimal32", "floor", "9", "0.50", "3.000000", "xr......"),
  ("decimal32", "floor", "9", "5E-1", "3.000000", "xr......"),
  ("decimal32", "floor", "9", "-0.5", "0.3333333", "xr......"),
  ("decimal32", "floor", "1E-9", "0.5", "0.00003162277", "xr......"),
  ("decimal32", "floor", "1E-9", "0.50", "0.00003162277", "xr......"),
  ("decimal32", "floor", "1E-9", "5E-1", "0.00003162277", "xr......"),
  ("decimal32", "floor", "1E-9", "-0.5", "31622.77", "xr......"),
  ("decimal32", "floor", "1E+20", "0.5", "1.000000E+10", "xr......"),
  ("decimal32", "floor", "1E+20", "0.50", "1.000000E+10", "xr......"),
  ("decimal32", "floor", "1E+20", "5E-1", "1.000000E+10", "xr......"),
  ("decimal32", "floor", "1E+20", "-0.5", "1.000000E-10", "xr......"),
  ("decimal32", "floor", "1E-5", "0.5", "0.003162277", "xr......"),
  ("decimal32", "floor", "1E-5", "0.50", "0.003162277", "xr......"),
  ("decimal32", "floor", "1E-5", "5E-1", "0.003162277", "xr......"),
  ("decimal32", "floor", "1E-5", "-0.5", "316.2277", "xr......"),
  ("decimal64", "half_even", "0.01", "0.5", "0.1000000000000000", "xr......"),
  ("decimal64", "half_even", "0.01", "0.50", "0.1000000000000000", "xr......"),
  ("decimal64", "half_even", "0.01", "5E-1", "0.1000000000000000", "xr......"),
  ("decimal64", "half_even", "0.01", "-0.5", "10.00000000000000", "xr......"),
  ("decimal64", "half_even", "4", "0.5", "2.000000000000000", "xr......"),
  ("decimal64", "half_even", "4", "0.50", "2.000000000000000", "xr......"),
  ("decimal64", "half_even", "4", "5E-1", "2.000000000000000", "xr......"),
  ("decimal64", "half_even", "4", "-0.5", "0.5000000000000000", "xr......"),
  ("decimal64", "half_even", "1E+2", "0.5", "10.00000000000000", "xr......"),
  ("decimal64", "half_even", "1E+2", "0.50", "10.00000000000000", "xr......"),
  ("decimal64", "half_even", "1E+2", "5E-1", "10.00000000000000", "xr......"),
  ("decimal64", "half_even", "1E+2", "-0.5", "0.1000000000000000", "xr......"),
  ("decimal64", "half_even", "0.25", "0.5", "0.5000000000000000", "xr......"),
  ("decimal64", "half_even", "0.25", "0.50", "0.5000000000000000", "xr......"),
  ("decimal64", "half_even", "0.25", "5E-1", "0.5000000000000000", "xr......"),
  ("decimal64", "half_even", "0.25", "-0.5", "2.000000000000000", "xr......"),
  ("decimal64", "half_even", "2", "0.5", "1.414213562373095", "xr......"),
  ("decimal64", "half_even", "2", "0.50", "1.414213562373095", "xr......"),
  ("decimal64", "half_even", "2", "5E-1", "1.414213562373095", "xr......"),
  ("decimal64", "half_even", "2", "-0.5", "0.7071067811865475", "xr......"),
  ("decimal64", "half_even", "1.0E+4", "0.5", "100.0000000000000", "xr......"),
  ("decimal64", "half_even", "1.0E+4", "0.50", "100.0000000000000", "xr......"),
  ("decimal64", "half_even", "1.0E+4", "5E-1", "100.0000000000000", "xr......"),
  (
    "decimal64", "half_even", "1.0E+4", "-0.5", "0.01000000000000000", "xr......",
  ),
  ("decimal64", "half_even", "9", "0.5", "3.000000000000000", "xr......"),
  ("decimal64", "half_even", "9", "0.50", "3.000000000000000", "xr......"),
  ("decimal64", "half_even", "9", "5E-1", "3.000000000000000", "xr......"),
  ("decimal64", "half_even", "9", "-0.5", "0.3333333333333333", "xr......"),
  (
    "decimal64", "half_even", "1E-9", "0.5", "0.00003162277660168379", "xr......",
  ),
  (
    "decimal64", "half_even", "1E-9", "0.50", "0.00003162277660168379", "xr......",
  ),
  (
    "decimal64", "half_even", "1E-9", "5E-1", "0.00003162277660168379", "xr......",
  ),
  ("decimal64", "half_even", "1E-9", "-0.5", "31622.77660168379", "xr......"),
  ("decimal64", "half_even", "1E+20", "0.5", "10000000000.00000", "xr......"),
  ("decimal64", "half_even", "1E+20", "0.50", "10000000000.00000", "xr......"),
  ("decimal64", "half_even", "1E+20", "5E-1", "10000000000.00000", "xr......"),
  (
    "decimal64", "half_even", "1E+20", "-0.5", "1.000000000000000E-10", "xr......",
  ),
  ("decimal64", "half_even", "1E-5", "0.5", "0.003162277660168379", "xr......"),
  ("decimal64", "half_even", "1E-5", "0.50", "0.003162277660168379", "xr......"),
  ("decimal64", "half_even", "1E-5", "5E-1", "0.003162277660168379", "xr......"),
  ("decimal64", "half_even", "1E-5", "-0.5", "316.2277660168379", "xr......"),
  ("decimal64", "down", "0.01", "0.5", "0.1000000000000000", "xr......"),
  ("decimal64", "down", "0.01", "0.50", "0.1000000000000000", "xr......"),
  ("decimal64", "down", "0.01", "5E-1", "0.1000000000000000", "xr......"),
  ("decimal64", "down", "0.01", "-0.5", "10.00000000000000", "xr......"),
  ("decimal64", "down", "4", "0.5", "2.000000000000000", "xr......"),
  ("decimal64", "down", "4", "0.50", "2.000000000000000", "xr......"),
  ("decimal64", "down", "4", "5E-1", "2.000000000000000", "xr......"),
  ("decimal64", "down", "4", "-0.5", "0.5000000000000000", "xr......"),
  ("decimal64", "down", "1E+2", "0.5", "10.00000000000000", "xr......"),
  ("decimal64", "down", "1E+2", "0.50", "10.00000000000000", "xr......"),
  ("decimal64", "down", "1E+2", "5E-1", "10.00000000000000", "xr......"),
  ("decimal64", "down", "1E+2", "-0.5", "0.1000000000000000", "xr......"),
  ("decimal64", "down", "0.25", "0.5", "0.5000000000000000", "xr......"),
  ("decimal64", "down", "0.25", "0.50", "0.5000000000000000", "xr......"),
  ("decimal64", "down", "0.25", "5E-1", "0.5000000000000000", "xr......"),
  ("decimal64", "down", "0.25", "-0.5", "2.000000000000000", "xr......"),
  ("decimal64", "down", "2", "0.5", "1.414213562373095", "xr......"),
  ("decimal64", "down", "2", "0.50", "1.414213562373095", "xr......"),
  ("decimal64", "down", "2", "5E-1", "1.414213562373095", "xr......"),
  ("decimal64", "down", "2", "-0.5", "0.7071067811865475", "xr......"),
  ("decimal64", "down", "1.0E+4", "0.5", "100.0000000000000", "xr......"),
  ("decimal64", "down", "1.0E+4", "0.50", "100.0000000000000", "xr......"),
  ("decimal64", "down", "1.0E+4", "5E-1", "100.0000000000000", "xr......"),
  ("decimal64", "down", "1.0E+4", "-0.5", "0.01000000000000000", "xr......"),
  ("decimal64", "down", "9", "0.5", "3.000000000000000", "xr......"),
  ("decimal64", "down", "9", "0.50", "3.000000000000000", "xr......"),
  ("decimal64", "down", "9", "5E-1", "3.000000000000000", "xr......"),
  ("decimal64", "down", "9", "-0.5", "0.3333333333333333", "xr......"),
  ("decimal64", "down", "1E-9", "0.5", "0.00003162277660168379", "xr......"),
  ("decimal64", "down", "1E-9", "0.50", "0.00003162277660168379", "xr......"),
  ("decimal64", "down", "1E-9", "5E-1", "0.00003162277660168379", "xr......"),
  ("decimal64", "down", "1E-9", "-0.5", "31622.77660168379", "xr......"),
  ("decimal64", "down", "1E+20", "0.5", "10000000000.00000", "xr......"),
  ("decimal64", "down", "1E+20", "0.50", "10000000000.00000", "xr......"),
  ("decimal64", "down", "1E+20", "5E-1", "10000000000.00000", "xr......"),
  ("decimal64", "down", "1E+20", "-0.5", "1.000000000000000E-10", "xr......"),
  ("decimal64", "down", "1E-5", "0.5", "0.003162277660168379", "xr......"),
  ("decimal64", "down", "1E-5", "0.50", "0.003162277660168379", "xr......"),
  ("decimal64", "down", "1E-5", "5E-1", "0.003162277660168379", "xr......"),
  ("decimal64", "down", "1E-5", "-0.5", "316.2277660168379", "xr......"),
  ("decimal64", "up", "0.01", "0.5", "0.1000000000000000", "xr......"),
  ("decimal64", "up", "0.01", "0.50", "0.1000000000000000", "xr......"),
  ("decimal64", "up", "0.01", "5E-1", "0.1000000000000000", "xr......"),
  ("decimal64", "up", "0.01", "-0.5", "10.00000000000000", "xr......"),
  ("decimal64", "up", "4", "0.5", "2.000000000000000", "xr......"),
  ("decimal64", "up", "4", "0.50", "2.000000000000000", "xr......"),
  ("decimal64", "up", "4", "5E-1", "2.000000000000000", "xr......"),
  ("decimal64", "up", "4", "-0.5", "0.5000000000000000", "xr......"),
  ("decimal64", "up", "1E+2", "0.5", "10.00000000000000", "xr......"),
  ("decimal64", "up", "1E+2", "0.50", "10.00000000000000", "xr......"),
  ("decimal64", "up", "1E+2", "5E-1", "10.00000000000000", "xr......"),
  ("decimal64", "up", "1E+2", "-0.5", "0.1000000000000000", "xr......"),
  ("decimal64", "up", "0.25", "0.5", "0.5000000000000000", "xr......"),
  ("decimal64", "up", "0.25", "0.50", "0.5000000000000000", "xr......"),
  ("decimal64", "up", "0.25", "5E-1", "0.5000000000000000", "xr......"),
  ("decimal64", "up", "0.25", "-0.5", "2.000000000000000", "xr......"),
  ("decimal64", "up", "2", "0.5", "1.414213562373096", "xr......"),
  ("decimal64", "up", "2", "0.50", "1.414213562373096", "xr......"),
  ("decimal64", "up", "2", "5E-1", "1.414213562373096", "xr......"),
  ("decimal64", "up", "2", "-0.5", "0.7071067811865476", "xr......"),
  ("decimal64", "up", "1.0E+4", "0.5", "100.0000000000000", "xr......"),
  ("decimal64", "up", "1.0E+4", "0.50", "100.0000000000000", "xr......"),
  ("decimal64", "up", "1.0E+4", "5E-1", "100.0000000000000", "xr......"),
  ("decimal64", "up", "1.0E+4", "-0.5", "0.01000000000000000", "xr......"),
  ("decimal64", "up", "9", "0.5", "3.000000000000000", "xr......"),
  ("decimal64", "up", "9", "0.50", "3.000000000000000", "xr......"),
  ("decimal64", "up", "9", "5E-1", "3.000000000000000", "xr......"),
  ("decimal64", "up", "9", "-0.5", "0.3333333333333334", "xr......"),
  ("decimal64", "up", "1E-9", "0.5", "0.00003162277660168380", "xr......"),
  ("decimal64", "up", "1E-9", "0.50", "0.00003162277660168380", "xr......"),
  ("decimal64", "up", "1E-9", "5E-1", "0.00003162277660168380", "xr......"),
  ("decimal64", "up", "1E-9", "-0.5", "31622.77660168380", "xr......"),
  ("decimal64", "up", "1E+20", "0.5", "10000000000.00000", "xr......"),
  ("decimal64", "up", "1E+20", "0.50", "10000000000.00000", "xr......"),
  ("decimal64", "up", "1E+20", "5E-1", "10000000000.00000", "xr......"),
  ("decimal64", "up", "1E+20", "-0.5", "1.000000000000000E-10", "xr......"),
  ("decimal64", "up", "1E-5", "0.5", "0.003162277660168380", "xr......"),
  ("decimal64", "up", "1E-5", "0.50", "0.003162277660168380", "xr......"),
  ("decimal64", "up", "1E-5", "5E-1", "0.003162277660168380", "xr......"),
  ("decimal64", "up", "1E-5", "-0.5", "316.2277660168380", "xr......"),
  ("decimal64", "ceiling", "0.01", "0.5", "0.1000000000000000", "xr......"),
  ("decimal64", "ceiling", "0.01", "0.50", "0.1000000000000000", "xr......"),
  ("decimal64", "ceiling", "0.01", "5E-1", "0.1000000000000000", "xr......"),
  ("decimal64", "ceiling", "0.01", "-0.5", "10.00000000000000", "xr......"),
  ("decimal64", "ceiling", "4", "0.5", "2.000000000000000", "xr......"),
  ("decimal64", "ceiling", "4", "0.50", "2.000000000000000", "xr......"),
  ("decimal64", "ceiling", "4", "5E-1", "2.000000000000000", "xr......"),
  ("decimal64", "ceiling", "4", "-0.5", "0.5000000000000000", "xr......"),
  ("decimal64", "ceiling", "1E+2", "0.5", "10.00000000000000", "xr......"),
  ("decimal64", "ceiling", "1E+2", "0.50", "10.00000000000000", "xr......"),
  ("decimal64", "ceiling", "1E+2", "5E-1", "10.00000000000000", "xr......"),
  ("decimal64", "ceiling", "1E+2", "-0.5", "0.1000000000000000", "xr......"),
  ("decimal64", "ceiling", "0.25", "0.5", "0.5000000000000000", "xr......"),
  ("decimal64", "ceiling", "0.25", "0.50", "0.5000000000000000", "xr......"),
  ("decimal64", "ceiling", "0.25", "5E-1", "0.5000000000000000", "xr......"),
  ("decimal64", "ceiling", "0.25", "-0.5", "2.000000000000000", "xr......"),
  ("decimal64", "ceiling", "2", "0.5", "1.414213562373096", "xr......"),
  ("decimal64", "ceiling", "2", "0.50", "1.414213562373096", "xr......"),
  ("decimal64", "ceiling", "2", "5E-1", "1.414213562373096", "xr......"),
  ("decimal64", "ceiling", "2", "-0.5", "0.7071067811865476", "xr......"),
  ("decimal64", "ceiling", "1.0E+4", "0.5", "100.0000000000000", "xr......"),
  ("decimal64", "ceiling", "1.0E+4", "0.50", "100.0000000000000", "xr......"),
  ("decimal64", "ceiling", "1.0E+4", "5E-1", "100.0000000000000", "xr......"),
  ("decimal64", "ceiling", "1.0E+4", "-0.5", "0.01000000000000000", "xr......"),
  ("decimal64", "ceiling", "9", "0.5", "3.000000000000000", "xr......"),
  ("decimal64", "ceiling", "9", "0.50", "3.000000000000000", "xr......"),
  ("decimal64", "ceiling", "9", "5E-1", "3.000000000000000", "xr......"),
  ("decimal64", "ceiling", "9", "-0.5", "0.3333333333333334", "xr......"),
  ("decimal64", "ceiling", "1E-9", "0.5", "0.00003162277660168380", "xr......"),
  ("decimal64", "ceiling", "1E-9", "0.50", "0.00003162277660168380", "xr......"),
  ("decimal64", "ceiling", "1E-9", "5E-1", "0.00003162277660168380", "xr......"),
  ("decimal64", "ceiling", "1E-9", "-0.5", "31622.77660168380", "xr......"),
  ("decimal64", "ceiling", "1E+20", "0.5", "10000000000.00000", "xr......"),
  ("decimal64", "ceiling", "1E+20", "0.50", "10000000000.00000", "xr......"),
  ("decimal64", "ceiling", "1E+20", "5E-1", "10000000000.00000", "xr......"),
  ("decimal64", "ceiling", "1E+20", "-0.5", "1.000000000000000E-10", "xr......"),
  ("decimal64", "ceiling", "1E-5", "0.5", "0.003162277660168380", "xr......"),
  ("decimal64", "ceiling", "1E-5", "0.50", "0.003162277660168380", "xr......"),
  ("decimal64", "ceiling", "1E-5", "5E-1", "0.003162277660168380", "xr......"),
  ("decimal64", "ceiling", "1E-5", "-0.5", "316.2277660168380", "xr......"),
  ("decimal64", "floor", "0.01", "0.5", "0.1000000000000000", "xr......"),
  ("decimal64", "floor", "0.01", "0.50", "0.1000000000000000", "xr......"),
  ("decimal64", "floor", "0.01", "5E-1", "0.1000000000000000", "xr......"),
  ("decimal64", "floor", "0.01", "-0.5", "10.00000000000000", "xr......"),
  ("decimal64", "floor", "4", "0.5", "2.000000000000000", "xr......"),
  ("decimal64", "floor", "4", "0.50", "2.000000000000000", "xr......"),
  ("decimal64", "floor", "4", "5E-1", "2.000000000000000", "xr......"),
  ("decimal64", "floor", "4", "-0.5", "0.5000000000000000", "xr......"),
  ("decimal64", "floor", "1E+2", "0.5", "10.00000000000000", "xr......"),
  ("decimal64", "floor", "1E+2", "0.50", "10.00000000000000", "xr......"),
  ("decimal64", "floor", "1E+2", "5E-1", "10.00000000000000", "xr......"),
  ("decimal64", "floor", "1E+2", "-0.5", "0.1000000000000000", "xr......"),
  ("decimal64", "floor", "0.25", "0.5", "0.5000000000000000", "xr......"),
  ("decimal64", "floor", "0.25", "0.50", "0.5000000000000000", "xr......"),
  ("decimal64", "floor", "0.25", "5E-1", "0.5000000000000000", "xr......"),
  ("decimal64", "floor", "0.25", "-0.5", "2.000000000000000", "xr......"),
  ("decimal64", "floor", "2", "0.5", "1.414213562373095", "xr......"),
  ("decimal64", "floor", "2", "0.50", "1.414213562373095", "xr......"),
  ("decimal64", "floor", "2", "5E-1", "1.414213562373095", "xr......"),
  ("decimal64", "floor", "2", "-0.5", "0.7071067811865475", "xr......"),
  ("decimal64", "floor", "1.0E+4", "0.5", "100.0000000000000", "xr......"),
  ("decimal64", "floor", "1.0E+4", "0.50", "100.0000000000000", "xr......"),
  ("decimal64", "floor", "1.0E+4", "5E-1", "100.0000000000000", "xr......"),
  ("decimal64", "floor", "1.0E+4", "-0.5", "0.01000000000000000", "xr......"),
  ("decimal64", "floor", "9", "0.5", "3.000000000000000", "xr......"),
  ("decimal64", "floor", "9", "0.50", "3.000000000000000", "xr......"),
  ("decimal64", "floor", "9", "5E-1", "3.000000000000000", "xr......"),
  ("decimal64", "floor", "9", "-0.5", "0.3333333333333333", "xr......"),
  ("decimal64", "floor", "1E-9", "0.5", "0.00003162277660168379", "xr......"),
  ("decimal64", "floor", "1E-9", "0.50", "0.00003162277660168379", "xr......"),
  ("decimal64", "floor", "1E-9", "5E-1", "0.00003162277660168379", "xr......"),
  ("decimal64", "floor", "1E-9", "-0.5", "31622.77660168379", "xr......"),
  ("decimal64", "floor", "1E+20", "0.5", "10000000000.00000", "xr......"),
  ("decimal64", "floor", "1E+20", "0.50", "10000000000.00000", "xr......"),
  ("decimal64", "floor", "1E+20", "5E-1", "10000000000.00000", "xr......"),
  ("decimal64", "floor", "1E+20", "-0.5", "1.000000000000000E-10", "xr......"),
  ("decimal64", "floor", "1E-5", "0.5", "0.003162277660168379", "xr......"),
  ("decimal64", "floor", "1E-5", "0.50", "0.003162277660168379", "xr......"),
  ("decimal64", "floor", "1E-5", "5E-1", "0.003162277660168379", "xr......"),
  ("decimal64", "floor", "1E-5", "-0.5", "316.2277660168379", "xr......"),
  (
    "decimal128", "half_even", "0.01", "0.5", "0.1000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "0.01", "0.50", "0.1000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "0.01", "5E-1", "0.1000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "0.01", "-0.5", "10.00000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "4", "0.5", "2.000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "4", "0.50", "2.000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "4", "5E-1", "2.000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "4", "-0.5", "0.5000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "1E+2", "0.5", "10.00000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "1E+2", "0.50", "10.00000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "1E+2", "5E-1", "10.00000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "1E+2", "-0.5", "0.1000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "0.25", "0.5", "0.5000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "0.25", "0.50", "0.5000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "0.25", "5E-1", "0.5000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "0.25", "-0.5", "2.000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "2", "0.5", "1.414213562373095048801688724209698",
    "xr......",
  ),
  (
    "decimal128", "half_even", "2", "0.50", "1.414213562373095048801688724209698",
    "xr......",
  ),
  (
    "decimal128", "half_even", "2", "5E-1", "1.414213562373095048801688724209698",
    "xr......",
  ),
  (
    "decimal128", "half_even", "2", "-0.5", "0.7071067811865475244008443621048490",
    "xr......",
  ),
  (
    "decimal128", "half_even", "1.0E+4", "0.5", "100.0000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "1.0E+4", "0.50", "100.0000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "1.0E+4", "5E-1", "100.0000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "1.0E+4", "-0.5", "0.01000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "9", "0.5", "3.000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "9", "0.50", "3.000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "9", "5E-1", "3.000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "9", "-0.5", "0.3333333333333333333333333333333333",
    "xr......",
  ),
  (
    "decimal128", "half_even", "1E-9", "0.5", "0.00003162277660168379331998893544432719",
    "xr......",
  ),
  (
    "decimal128", "half_even", "1E-9", "0.50", "0.00003162277660168379331998893544432719",
    "xr......",
  ),
  (
    "decimal128", "half_even", "1E-9", "5E-1", "0.00003162277660168379331998893544432719",
    "xr......",
  ),
  (
    "decimal128", "half_even", "1E-9", "-0.5", "31622.77660168379331998893544432719",
    "xr......",
  ),
  (
    "decimal128", "half_even", "1E+20", "0.5", "10000000000.00000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "1E+20", "0.50", "10000000000.00000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "1E+20", "5E-1", "10000000000.00000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "half_even", "1E+20", "-0.5", "1.000000000000000000000000000000000E-10",
    "xr......",
  ),
  (
    "decimal128", "half_even", "1E-5", "0.5", "0.003162277660168379331998893544432719",
    "xr......",
  ),
  (
    "decimal128", "half_even", "1E-5", "0.50", "0.003162277660168379331998893544432719",
    "xr......",
  ),
  (
    "decimal128", "half_even", "1E-5", "5E-1", "0.003162277660168379331998893544432719",
    "xr......",
  ),
  (
    "decimal128", "half_even", "1E-5", "-0.5", "316.2277660168379331998893544432719",
    "xr......",
  ),
  (
    "decimal128", "down", "0.01", "0.5", "0.1000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "down", "0.01", "0.50", "0.1000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "down", "0.01", "5E-1", "0.1000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "down", "0.01", "-0.5", "10.00000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "down", "4", "0.5", "2.000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "down", "4", "0.50", "2.000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "down", "4", "5E-1", "2.000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "down", "4", "-0.5", "0.5000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "down", "1E+2", "0.5", "10.00000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "down", "1E+2", "0.50", "10.00000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "down", "1E+2", "5E-1", "10.00000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "down", "1E+2", "-0.5", "0.1000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "down", "0.25", "0.5", "0.5000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "down", "0.25", "0.50", "0.5000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "down", "0.25", "5E-1", "0.5000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "down", "0.25", "-0.5", "2.000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "down", "2", "0.5", "1.414213562373095048801688724209698", "xr......",
  ),
  (
    "decimal128", "down", "2", "0.50", "1.414213562373095048801688724209698", "xr......",
  ),
  (
    "decimal128", "down", "2", "5E-1", "1.414213562373095048801688724209698", "xr......",
  ),
  (
    "decimal128", "down", "2", "-0.5", "0.7071067811865475244008443621048490", "xr......",
  ),
  (
    "decimal128", "down", "1.0E+4", "0.5", "100.0000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "down", "1.0E+4", "0.50", "100.0000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "down", "1.0E+4", "5E-1", "100.0000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "down", "1.0E+4", "-0.5", "0.01000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "down", "9", "0.5", "3.000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "down", "9", "0.50", "3.000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "down", "9", "5E-1", "3.000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "down", "9", "-0.5", "0.3333333333333333333333333333333333", "xr......",
  ),
  (
    "decimal128", "down", "1E-9", "0.5", "0.00003162277660168379331998893544432718",
    "xr......",
  ),
  (
    "decimal128", "down", "1E-9", "0.50", "0.00003162277660168379331998893544432718",
    "xr......",
  ),
  (
    "decimal128", "down", "1E-9", "5E-1", "0.00003162277660168379331998893544432718",
    "xr......",
  ),
  (
    "decimal128", "down", "1E-9", "-0.5", "31622.77660168379331998893544432718",
    "xr......",
  ),
  (
    "decimal128", "down", "1E+20", "0.5", "10000000000.00000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "down", "1E+20", "0.50", "10000000000.00000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "down", "1E+20", "5E-1", "10000000000.00000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "down", "1E+20", "-0.5", "1.000000000000000000000000000000000E-10",
    "xr......",
  ),
  (
    "decimal128", "down", "1E-5", "0.5", "0.003162277660168379331998893544432718",
    "xr......",
  ),
  (
    "decimal128", "down", "1E-5", "0.50", "0.003162277660168379331998893544432718",
    "xr......",
  ),
  (
    "decimal128", "down", "1E-5", "5E-1", "0.003162277660168379331998893544432718",
    "xr......",
  ),
  (
    "decimal128", "down", "1E-5", "-0.5", "316.2277660168379331998893544432718",
    "xr......",
  ),
  (
    "decimal128", "up", "0.01", "0.5", "0.1000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "up", "0.01", "0.50", "0.1000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "up", "0.01", "5E-1", "0.1000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "up", "0.01", "-0.5", "10.00000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "up", "4", "0.5", "2.000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "up", "4", "0.50", "2.000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "up", "4", "5E-1", "2.000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "up", "4", "-0.5", "0.5000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "up", "1E+2", "0.5", "10.00000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "up", "1E+2", "0.50", "10.00000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "up", "1E+2", "5E-1", "10.00000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "up", "1E+2", "-0.5", "0.1000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "up", "0.25", "0.5", "0.5000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "up", "0.25", "0.50", "0.5000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "up", "0.25", "5E-1", "0.5000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "up", "0.25", "-0.5", "2.000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "up", "2", "0.5", "1.414213562373095048801688724209699", "xr......",
  ),
  (
    "decimal128", "up", "2", "0.50", "1.414213562373095048801688724209699", "xr......",
  ),
  (
    "decimal128", "up", "2", "5E-1", "1.414213562373095048801688724209699", "xr......",
  ),
  (
    "decimal128", "up", "2", "-0.5", "0.7071067811865475244008443621048491", "xr......",
  ),
  (
    "decimal128", "up", "1.0E+4", "0.5", "100.0000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "up", "1.0E+4", "0.50", "100.0000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "up", "1.0E+4", "5E-1", "100.0000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "up", "1.0E+4", "-0.5", "0.01000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "up", "9", "0.5", "3.000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "up", "9", "0.50", "3.000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "up", "9", "5E-1", "3.000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "up", "9", "-0.5", "0.3333333333333333333333333333333334", "xr......",
  ),
  (
    "decimal128", "up", "1E-9", "0.5", "0.00003162277660168379331998893544432719",
    "xr......",
  ),
  (
    "decimal128", "up", "1E-9", "0.50", "0.00003162277660168379331998893544432719",
    "xr......",
  ),
  (
    "decimal128", "up", "1E-9", "5E-1", "0.00003162277660168379331998893544432719",
    "xr......",
  ),
  (
    "decimal128", "up", "1E-9", "-0.5", "31622.77660168379331998893544432719", "xr......",
  ),
  (
    "decimal128", "up", "1E+20", "0.5", "10000000000.00000000000000000000000", "xr......",
  ),
  (
    "decimal128", "up", "1E+20", "0.50", "10000000000.00000000000000000000000", "xr......",
  ),
  (
    "decimal128", "up", "1E+20", "5E-1", "10000000000.00000000000000000000000", "xr......",
  ),
  (
    "decimal128", "up", "1E+20", "-0.5", "1.000000000000000000000000000000000E-10",
    "xr......",
  ),
  (
    "decimal128", "up", "1E-5", "0.5", "0.003162277660168379331998893544432719",
    "xr......",
  ),
  (
    "decimal128", "up", "1E-5", "0.50", "0.003162277660168379331998893544432719",
    "xr......",
  ),
  (
    "decimal128", "up", "1E-5", "5E-1", "0.003162277660168379331998893544432719",
    "xr......",
  ),
  (
    "decimal128", "up", "1E-5", "-0.5", "316.2277660168379331998893544432719", "xr......",
  ),
  (
    "decimal128", "ceiling", "0.01", "0.5", "0.1000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "0.01", "0.50", "0.1000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "0.01", "5E-1", "0.1000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "0.01", "-0.5", "10.00000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "4", "0.5", "2.000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "ceiling", "4", "0.50", "2.000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "4", "5E-1", "2.000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "4", "-0.5", "0.5000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "1E+2", "0.5", "10.00000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "1E+2", "0.50", "10.00000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "1E+2", "5E-1", "10.00000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "1E+2", "-0.5", "0.1000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "0.25", "0.5", "0.5000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "0.25", "0.50", "0.5000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "0.25", "5E-1", "0.5000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "0.25", "-0.5", "2.000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "2", "0.5", "1.414213562373095048801688724209699", "xr......",
  ),
  (
    "decimal128", "ceiling", "2", "0.50", "1.414213562373095048801688724209699",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "2", "5E-1", "1.414213562373095048801688724209699",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "2", "-0.5", "0.7071067811865475244008443621048491",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "1.0E+4", "0.5", "100.0000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "1.0E+4", "0.50", "100.0000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "1.0E+4", "5E-1", "100.0000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "1.0E+4", "-0.5", "0.01000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "9", "0.5", "3.000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "ceiling", "9", "0.50", "3.000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "9", "5E-1", "3.000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "9", "-0.5", "0.3333333333333333333333333333333334",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "1E-9", "0.5", "0.00003162277660168379331998893544432719",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "1E-9", "0.50", "0.00003162277660168379331998893544432719",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "1E-9", "5E-1", "0.00003162277660168379331998893544432719",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "1E-9", "-0.5", "31622.77660168379331998893544432719",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "1E+20", "0.5", "10000000000.00000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "1E+20", "0.50", "10000000000.00000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "1E+20", "5E-1", "10000000000.00000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "1E+20", "-0.5", "1.000000000000000000000000000000000E-10",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "1E-5", "0.5", "0.003162277660168379331998893544432719",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "1E-5", "0.50", "0.003162277660168379331998893544432719",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "1E-5", "5E-1", "0.003162277660168379331998893544432719",
    "xr......",
  ),
  (
    "decimal128", "ceiling", "1E-5", "-0.5", "316.2277660168379331998893544432719",
    "xr......",
  ),
  (
    "decimal128", "floor", "0.01", "0.5", "0.1000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "floor", "0.01", "0.50", "0.1000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "floor", "0.01", "5E-1", "0.1000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "floor", "0.01", "-0.5", "10.00000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "floor", "4", "0.5", "2.000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "floor", "4", "0.50", "2.000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "floor", "4", "5E-1", "2.000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "floor", "4", "-0.5", "0.5000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "floor", "1E+2", "0.5", "10.00000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "floor", "1E+2", "0.50", "10.00000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "floor", "1E+2", "5E-1", "10.00000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "floor", "1E+2", "-0.5", "0.1000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "floor", "0.25", "0.5", "0.5000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "floor", "0.25", "0.50", "0.5000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "floor", "0.25", "5E-1", "0.5000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "floor", "0.25", "-0.5", "2.000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "floor", "2", "0.5", "1.414213562373095048801688724209698", "xr......",
  ),
  (
    "decimal128", "floor", "2", "0.50", "1.414213562373095048801688724209698", "xr......",
  ),
  (
    "decimal128", "floor", "2", "5E-1", "1.414213562373095048801688724209698", "xr......",
  ),
  (
    "decimal128", "floor", "2", "-0.5", "0.7071067811865475244008443621048490", "xr......",
  ),
  (
    "decimal128", "floor", "1.0E+4", "0.5", "100.0000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "floor", "1.0E+4", "0.50", "100.0000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "floor", "1.0E+4", "5E-1", "100.0000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "floor", "1.0E+4", "-0.5", "0.01000000000000000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "floor", "9", "0.5", "3.000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "floor", "9", "0.50", "3.000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "floor", "9", "5E-1", "3.000000000000000000000000000000000", "xr......",
  ),
  (
    "decimal128", "floor", "9", "-0.5", "0.3333333333333333333333333333333333", "xr......",
  ),
  (
    "decimal128", "floor", "1E-9", "0.5", "0.00003162277660168379331998893544432718",
    "xr......",
  ),
  (
    "decimal128", "floor", "1E-9", "0.50", "0.00003162277660168379331998893544432718",
    "xr......",
  ),
  (
    "decimal128", "floor", "1E-9", "5E-1", "0.00003162277660168379331998893544432718",
    "xr......",
  ),
  (
    "decimal128", "floor", "1E-9", "-0.5", "31622.77660168379331998893544432718",
    "xr......",
  ),
  (
    "decimal128", "floor", "1E+20", "0.5", "10000000000.00000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "floor", "1E+20", "0.50", "10000000000.00000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "floor", "1E+20", "5E-1", "10000000000.00000000000000000000000",
    "xr......",
  ),
  (
    "decimal128", "floor", "1E+20", "-0.5", "1.000000000000000000000000000000000E-10",
    "xr......",
  ),
  (
    "decimal128", "floor", "1E-5", "0.5", "0.003162277660168379331998893544432718",
    "xr......",
  ),
  (
    "decimal128", "floor", "1E-5", "0.50", "0.003162277660168379331998893544432718",
    "xr......",
  ),
  (
    "decimal128", "floor", "1E-5", "5E-1", "0.003162277660168379331998893544432718",
    "xr......",
  ),
  (
    "decimal128", "floor", "1E-5", "-0.5", "316.2277660168379331998893544432718",
    "xr......",
  ),
]
