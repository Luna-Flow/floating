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
// shares: Binary::from_hex (reads the table)
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
// shares: Binary::from_hex (reads the table)
test "exp at 160,000 bits returns an enclosure (issue 449)" {
  let y = Interval::from_int(1, precision=160_000).exp()
  let (lo, hi) = total_forms_big_row("exp")
  assert_true(y.lower_bound().compare(lo) == 0)
  assert_true(y.upper_bound().compare(hi) == 0)
  assert_true(y.is_common_interval())
  assert_true(y.width().compare(total_forms_pow2(-159_990, 160_000)) <= 0)
}

///|
/// The plain hyperbolic forms lost all relative accuracy for a tiny argument:
/// the lower bound was 0 and the width about 2^-245 at x = 2^-300.
test "hyperbolic forms keep relative accuracy for a tiny argument" {
  let x = Interval::exact(total_forms_pow2(-300, 53), precision=53)
  let tiny = total_forms_pow2(-340, 53)
  for y in [x.sinh(), x.tanh(), x.asinh(), x.atanh()] {
    assert_true(y.lower_bound().compare(@binary.Binary::zero()) > 0)
    assert_true(y.width().compare(tiny) <= 0)
  }
}

///|
/// `try_atanh` of an interval whose only point in the domain's closure
/// is 1 or -1 evaluated the pole and aborted ("interval lower bound must not be
/// positive infinity"); the open domain leaves nothing, so the result is Empty.
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
