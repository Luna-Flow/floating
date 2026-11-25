///|
fn point_table_hex(text : String) -> @binary.Binary {
  @binary.Binary::from_hex(text, 2200).unwrap()
}

///|
fn point_table_precision(text : String) -> Int32 {
  let mut n = 0
  for c in text {
    n = n * 10 + (c.to_int() - 48)
  }
  n
}

///|
// oracle: A
// source: the two directed roundings (down, up) to p bits of the exact exp(x) and ln(x), computed by MPFR (tools/interval_point_elementary_oracle.py, table point_elementary_table_wbtest.mbt); the interval of a point must have exactly these ends; exp and ln of a point at p = 24, 53, 64, 128, 200 with magnitudes 2^-30 to 2^30, small integers and the exponent-range end 2^-1073741000 (and ln at 2^1073741000); ln of a point at or below 0 is Empty by the domain x > 0 of IEEE 1788-2015 Table 9.1
// shares: Binary::from_hex and String::split read the table; Interval::from_bounds builds the point interval and Binary::zero, Binary::from_int and Binary::make build the operands of the Empty cases; the precision field is read by a digit loop in the test
test "exp and ln of a point interval are the MPFR directed bounds" {
  let mut count = 0
  for line in point_elementary_table().split("\n") {
    let line = line.to_owned()
    if line == "" {
      continue
    }
    let f = line.split(" ").map(fn(s) { s.to_owned() }).collect()
    let p = point_table_precision(f[1])
    let x = point_table_hex(f[2])
    let interval = Interval::from_bounds(x, x, precision=p)
    let got = if f[0] == "exp" {
      interval.try_exp().unwrap()
    } else {
      interval.try_ln().unwrap()
    }
    assert_true(got.lo_.compare(point_table_hex(f[3])) == 0, msg=line)
    assert_true(got.hi_.compare(point_table_hex(f[4])) == 0, msg=line)
    count += 1
  }
  assert_true(count >= 400)
  for p in [24, 53, 128] {
    for
      x in [
        @binary.Binary::zero(precision=p),
        @binary.Binary::from_int(-3, precision=p),
        @binary.Binary::make(@binary.BinCoeff::one(), -1073741000, p).neg(),
      ] {
      assert_true(
        Interval::from_bounds(x, x, precision=p).try_ln().unwrap().is_empty(),
      )
    }
  }
}

///|
fn point_pair_end(coefficient : UInt64, exponent : Int32) -> @binary.Binary {
  @binary.Binary::make(@binary.BinCoeff::from_uint64(coefficient), exponent, 53)
}

///|
// oracle: A
// source: the four endpoint values written out: the directed 53-bit roundings of exp(3), exp(3 + 2^-40),
//   ln(3) and ln(3 + 2^-40), computed with Python 3 decimal (libmpdec, correctly rounded) at 120 digits and
//   rounded down (lower end) and up (upper end) on exact fractions; the values are irrational, so the upward
//   bound is the floor plus one unit; this library did not produce them
// shares: nothing
test "exp and ln of an interval with two ends are the directed bounds of the ends" {
  let a = @binary.Binary::from_int(3, precision=53)
  let b = a.add(@binary.Binary::make(@binary.BinCoeff::one(), -40, 53))
  let interval = Interval::from_bounds(a, b, precision=53)
  let exp_interval = interval.try_exp().unwrap()
  assert_eq(
    exp_interval.lo_.compare(point_pair_end(5653576037675269UL, -48)),
    0,
  )
  assert_eq(
    exp_interval.hi_.compare(point_pair_end(5653576037680412UL, -48)),
    0,
  )
  let ln_interval = interval.try_ln().unwrap()
  assert_eq(ln_interval.lo_.compare(point_pair_end(4947709893870346UL, -52)), 0)
  assert_eq(ln_interval.hi_.compare(point_pair_end(4947709893871712UL, -52)), 0)
}
