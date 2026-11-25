// `midpoint`, `radius` and `to_midpoint_radius_string` against the independent oracle
// `tools/interval_mid_oracle.py` (level A: Python integers from IEEE 1788-2015 12.12.8, no
// `interval` code). The table is `midpoint_radius_table_wbtest.mbt`: random intervals, centers
// that need p + 1 bits, gaps of more than 65,536 places, the bottom of the exponent range, point
// intervals. For every row the test also asserts, exactly, that the printed pair encloses the
// interval: `mid - rad <= lower` and `mid + rad >= upper` (a sum of exact values formed by integer
// arithmetic: `exact_add_full`, which the code under test does not call).

// oracle: A
// source: expected mid and rad computed with Python integers (tools/interval_mid_oracle.py), the exact enclosure checked again in the test by integer arithmetic
// shares: nothing for the expected values; Binary::from_hex reads the bounds

///|
test "midpoint, radius and their text agree with the independent oracle on every row of the table" {
  let mut count = 0
  for table in mid_rad_tables() {
    for line in table.split("\n") {
      let line = line.to_owned()
      if line == "" {
        continue
      }
      let fields = line.split("\t").map(fn(f) { f.to_owned() }).collect()
      let mut precision = 0
      for c in fields[2] {
        precision = precision * 10 + (c.to_int() - '0'.to_int())
      }
      let lower = @binary.Binary::from_hex(fields[0], precision).unwrap()
      let upper = @binary.Binary::from_hex(fields[1], precision).unwrap()
      let x = Interval::from_bounds(lower, upper, precision~)
      let m = x.midpoint()
      let r = x.radius()
      assert_eq(m.to_string(), fields[3], msg=line)
      assert_eq(r.to_string(), fields[4], msg=line)
      assert_eq(
        x.to_midpoint_radius_string(),
        fields[3] + " +/- " + fields[4],
        msg=line,
      )
      // the pair encloses the interval, exactly
      assert_true(
        exact_add_full(m, r.neg()).compare(x.lower_bound()) <= 0,
        msg="mid - rad > lower: " + line,
      )
      assert_true(
        exact_add_full(m, r).compare(x.upper_bound()) >= 0,
        msg="mid + rad < upper: " + line,
      )
      count += 1
    }
  }
  assert_eq(count, 1495)
}

// oracle: A
// source: written out from the definitions (12.12.8): the cases that are not a bounded interval
// shares: nothing

///|
test "to_midpoint_radius_string of an empty, entire and unbounded interval and of a decorated one" {
  inspect(Interval::empty().to_midpoint_radius_string(), content="[empty]")
  inspect(Interval::entire().to_midpoint_radius_string(), content="[-inf, inf]")
  let one = @binary.Binary::one(precision=53)
  let half_line = Interval::from_bounds(one, @binary.Binary::inf(precision=53))
  inspect(half_line.to_midpoint_radius_string(), content="[1p0, inf]")
  // [-1, 2] at 53 bits: mid 1/2 is exact, rad 3/2 covers -1 and 2
  let x = Interval::from_bounds(
    one.neg(),
    @binary.Binary::from_int(2, precision=53),
  )
  inspect(x.to_midpoint_radius_string(), content="1p-1 +/- 3p-1")
  inspect(
    DecoratedInterval::new(x, decoration=Com).to_midpoint_radius_string(),
    content="1p-1 +/- 3p-1_com",
  )
}
