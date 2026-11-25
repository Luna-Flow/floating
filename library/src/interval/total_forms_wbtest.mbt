///|
fn total_forms_pow2(exponent : Int32, precision : Int32) -> @binary.Binary {
  @binary.Binary::make(@binary.BinCoeff::one(), exponent, precision)
}

///|
/// The ends of the row `op` of the table of the two extreme precisions (MPFR).
fn total_forms_big_row(op : String) -> (@binary.Binary, @binary.Binary) {
  // three lines per row: `op p x`, the lower end, the upper end
  let lines : Array[String] = []
  for line in point_elementary_big_table().split("\n") {
    let line = line.to_owned()
    if line != "" {
      lines.push(line)
    }
  }
  let mut i = 0
  while i + 2 < lines.length() {
    if lines[i].split(" ").next().unwrap().to_owned() == op {
      return (
        @binary.Binary::from_hex(lines[i + 1], 170_000).unwrap(),
        @binary.Binary::from_hex(lines[i + 2], 170_000).unwrap(),
      )
    }
    i += 3
  }
  abort("no row " + op)
}

///|
/// Issue 449: the plain `ln` aborted from about 32,000 bits of
/// precision ("certified log series did not converge"). The plain form is the
/// `try_` form with a fallback, so it returns an enclosure at any precision and
/// equals the `try_` form whenever that succeeds.
// oracle: A, S
// source: the two ends of ln 3 at 32,000 bits are the directed roundings (down, up) of the exact value computed by MPFR (tools/interval_point_elementary_oracle.py, table point_elementary_big_table_wbtest.mbt); the checks of the width, of exp(ln 3) containing 3 and of agreement with try_ln are self-consistency (S)
// shares: Binary::from_hex and String::split read the table; Interval::from_int, lower_bound, upper_bound, width, is_member, exp and try_ln are used for the inputs and for the self-consistency checks (S)
test "ln at 32,000 bits returns a tight enclosure (issue 449)" {
  let x = Interval::from_int(3, precision=32_000)
  let y = x.ln()
  let (lo, hi) = total_forms_big_row("ln")
  assert_true(y.lower_bound().compare(lo) == 0)
  assert_true(y.upper_bound().compare(hi) == 0)
  assert_true(y.is_common_interval())
  assert_true(y.width().compare(total_forms_pow2(-31_990, 32_000)) <= 0)
  // exp(ln 3) must contain 3.
  let back = y.exp()
  assert_true(back.is_member(@binary.Binary::from_int(3, precision=32_000)))
  match x.try_ln() {
    Ok(t) => assert_true(y.equal(t))
    Err(_) => ()
  }
}

///|
// oracle: A, S
// source: the two ends of exp 1 at 160,000 bits are the directed roundings (down, up) of the exact value computed by MPFR (tools/interval_point_elementary_oracle.py, table point_elementary_big_table_wbtest.mbt); the width bound is a quality check (S)
// shares: Binary::from_hex and String::split read the table; Interval::from_int, lower_bound, upper_bound, width and is_common_interval are used for the input and the quality check (S)
test "exp at 160,000 bits returns an enclosure (issue 449)" {
  let y = Interval::from_int(1, precision=160_000).exp()
  let (lo, hi) = total_forms_big_row("exp")
  assert_true(y.lower_bound().compare(lo) == 0)
  assert_true(y.upper_bound().compare(hi) == 0)
  assert_true(y.is_common_interval())
  assert_true(y.width().compare(total_forms_pow2(-159_990, 160_000)) <= 0)
}

///|
// The plain hyperbolic forms lost all relative accuracy for a tiny argument:
// the lower bound was 0 and the width about 2^-245 at x = 2^-300.
// oracle: A
// source: worked out by hand for x = 2^-300 at 53 bits: sinh(x) and atanh(x) lie strictly between x and its successor (2^52 + 1) * 2^-352, tanh(x) and asinh(x) strictly between the predecessor (2^53 - 1) * 2^-353 and x (x^3 / 6 and x^3 / 3 are below 2^-52 x), so every enclosure holds those two numbers; the lower bound is positive and the width at most 2^-340
// shares: total_forms_pow2 and Binary::make build the operands and the expected numbers; Binary::compare compares
test "hyperbolic forms keep relative accuracy for a tiny argument" {
  let x = Interval::exact(total_forms_pow2(-300, 53), precision=53)
  let tiny = total_forms_pow2(-340, 53)
  // x = 2^-300 = 2^52 * 2^-352 is the number 53 bits hold, its successor is (2^52 + 1) * 2^-352
  // and its predecessor (2^53 - 1) * 2^-353. sinh(x) = x + x^3 / 6 and atanh(x) = x + x^3 / 3 lie
  // strictly between x and its successor (x^3 is below 2^-52 x), tanh(x) = x - x^3 / 3 and
  // asinh(x) = x - x^3 / 6 strictly between the predecessor and x: a valid enclosure holds the
  // number 53 bits give on each side of the value, so it contains these hulls
  let successor = @binary.Binary::make(
    @binary.BinCoeff::from_uint64((1UL << 52) + 1UL),
    -352,
    53,
  )
  let predecessor = @binary.Binary::make(
    @binary.BinCoeff::from_uint64((1UL << 53) - 1UL),
    -353,
    53,
  )
  let xb = total_forms_pow2(-300, 53)
  for
    case in [
      (x.sinh(), xb, successor),
      (x.tanh(), predecessor, xb),
      (x.asinh(), predecessor, xb),
      (x.atanh(), xb, successor),
    ] {
    let (y, lower, upper) = case
    assert_true(y.lower_bound().compare(@binary.Binary::zero()) > 0)
    assert_true(y.lower_bound().compare(lower) <= 0)
    assert_true(y.upper_bound().compare(upper) >= 0)
    assert_true(y.width().compare(tiny) <= 0)
  }
}

///|
// `try_atanh` of an interval whose only point in the domain's closure
// is 1 or -1 evaluated the pole and aborted ("interval lower bound must not be
// positive infinity"); the open domain leaves nothing, so the result is Empty.
// oracle: A
// source: written out from the domain of atanh in IEEE 1788-2015 Table 9.1 (the open interval (-1, 1)): [1, 1], [1, +inf), (-inf, -1] and [-1, -1] have no point in the domain, so the result is Empty, by both atanh and try_atanh
// shares: Binary::one, inf and Interval::from_bounds build the inputs
test "atanh of an interval meeting the closure of the domain at one point" {
  let inf = @binary.Binary::inf(precision=53)
  let one = @binary.Binary::one(precision=53)
  for
    b in [
      (one, one),
      (one, inf),
      (inf.neg(), one.neg()),
      (one.neg(), one.neg()),
    ] {
    let x = Interval::from_bounds(b.0, b.1, precision=53)
    assert_true(x.atanh().is_empty())
    assert_true(x.try_atanh().unwrap().is_empty())
  }
}
