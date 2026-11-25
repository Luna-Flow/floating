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
) -> Array[String] {
  let bad = []
  for row in rows {
    let (mode, precision, e_min, e_max, clamp, x, expected, flags) = row
    let ctx = DecimalContext::new(
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
