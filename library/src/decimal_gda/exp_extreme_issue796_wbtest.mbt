///|
// Issue 796: Decimal::exp_ctx applies the rounding direction to a result beyond the coarse range
// guards x >= 3 (e_max + 1) and x <= -3 (1 - etiny): the largest finite number for the
// directions that do not round a positive result up (GDA 1.70, page 53, Overflow), the smallest
// subnormal where the direction rounds a positive result away from zero (Underflow, same page).

///|
fn i796_mode(name : String) -> DecimalRoundingMode {
  match name {
    "half_even" => DecimalRoundingMode::HalfEven
    "half_up" => DecimalRoundingMode::HalfUp
    "half_down" => DecimalRoundingMode::HalfDown
    "down" => DecimalRoundingMode::Down
    "ceiling" => DecimalRoundingMode::Ceiling
    "floor" => DecimalRoundingMode::Floor
    "up" => DecimalRoundingMode::Up
    _ => DecimalRoundingMode::ZeroFiveUp
  }
}

///|
fn i796_flags(f : DecimalFlags) -> String {
  let out = StringBuilder()
  if f.inexact {
    out.write_string("x")
  }
  if f.rounded {
    out.write_string("r")
  }
  if f.overflow {
    out.write_string("o")
  }
  if f.underflow {
    out.write_string("u")
  }
  if f.subnormal {
    out.write_string("s")
  }
  if f.clamped {
    out.write_string("c")
  }
  let text = out.to_string()
  if text == "" {
    "-"
  } else {
    text
  }
}

///|
fn i796_run(
  rows : Array[(String, Int32, Int32, Int32, Int32, String, String, String)],
  extended~ : Bool = true,
) -> Array[String] {
  let bad = []
  for row in rows {
    let (mode, precision, e_min, e_max, clamp, x, expected, flags) = row
    let ctx = DecimalContext::new(
      extended~,
      precision~,
      decimal_rounding=i796_mode(mode),
      e_min~,
      e_max~,
      clamp=clamp == 1,
    )
    let value = Decimal::from_string(x, precision=40).unwrap()
    let (result, got_flags) = value.exp_ctx(ctx)
    let got = result.to_sci_string() + " " + i796_flags(got_flags)
    let want = expected + " " + flags
    if got != want {
      bad.push(
        "\{mode} p=\{precision} emin=\{e_min} emax=\{e_max} clamp=\{clamp} exp(\{x}): got \{got}, want \{want}",
      )
    }
  }
  bad
}

///|
// oracle: A
// source: 320 rows from tools/generate_decimal_gda_exp_extreme_rows.py: the true value exp(x) at 400 digits in Python decimal (libmpdec) rounded once into the context by Context.plus, whose overflow and underflow finalisation is GDA 1.70 page 53; Context.exp of libmpdec is not used because it ignores the direction there (checked on libmpdec 2.5.0, 4.0.0 and 4.0.1)
// shares: Decimal::from_string, Decimal::to_sci_string, DecimalContext::new
test "issue 796: exp_ctx applies the rounding direction beyond the coarse guards" {
  assert_eq(exp_extreme_rows.length(), 320)
  assert_eq(i796_run(exp_extreme_rows), [])
}

///|
// Hand-written rows for a subset context (extended=false), decimal32 shape (precision 7,
// e_min -95, e_max 96, clamp), columns as exp_extreme_rows. libmpdec has no subset arithmetic.
// Underflow side: the result stays the zero of the subset in every mode, with Underflow,
// Subnormal, Inexact and Rounded (GDA 1.70, page 55, Appendix A: subnormal numbers are not
// permitted; page 53, Underflow). Overflow side: page 53, Overflow, the same rules as in an
// extended context.
let i796_subset_rows : Array[
  (String, Int32, Int32, Int32, Int32, String, String, String),
] = [
  ("half_even", 7, -95, 96, 1, "-306", "0", "xrus"),
  ("half_up", 7, -95, 96, 1, "-306", "0", "xrus"),
  ("half_down", 7, -95, 96, 1, "-306", "0", "xrus"),
  ("down", 7, -95, 96, 1, "-306", "0", "xrus"),
  ("ceiling", 7, -95, 96, 1, "-306", "0", "xrus"),
  ("floor", 7, -95, 96, 1, "-306", "0", "xrus"),
  ("up", 7, -95, 96, 1, "-306", "0", "xrus"),
  ("05up", 7, -95, 96, 1, "-306", "0", "xrus"),
  ("half_even", 7, -95, 96, 1, "291", "Infinity", "xro"),
  ("half_up", 7, -95, 96, 1, "291", "Infinity", "xro"),
  ("half_down", 7, -95, 96, 1, "291", "Infinity", "xro"),
  ("up", 7, -95, 96, 1, "291", "Infinity", "xro"),
  ("ceiling", 7, -95, 96, 1, "291", "Infinity", "xro"),
  ("down", 7, -95, 96, 1, "291", "9.999999E+96", "xro"),
  ("floor", 7, -95, 96, 1, "291", "9.999999E+96", "xro"),
  ("05up", 7, -95, 96, 1, "291", "9.999999E+96", "xro"),
]

///|
// oracle: A
// source: expected values written by hand from GDA 1.70 page 53 (Overflow and Underflow by rounding mode) and page 55 (Appendix A: no subnormal result in a subset context, so the zero stays); no program produced them
// shares: Decimal::from_string, Decimal::to_sci_string, DecimalContext::new
test "issue 796: exp_ctx in a subset context keeps the zero and applies the overflow direction" {
  assert_eq(i796_run(i796_subset_rows, extended=false), [])
}
