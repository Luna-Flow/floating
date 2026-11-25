///|
// Every `interval` constructor must return an interval that contains its
// input. `from_int` and `from_coefficient` used to round the value to the
// requested precision first and wrap the rounded result as a singleton, which
// excluded the input whenever it needed more bits than the precision.
// oracle: A
// source: the ends are the integer n rounded down and up to p bits (IEEE 1788-2015 12.12.7), written out and computed with Python fractions: for p = 8, 16, 24, 53 and n = 100001 (0xc3p9 and 0xc4p9 at 8 bits, 0xc350p1 and 0xc351p1 at 16, exact from 24 bits), 65537 (0x80p9, 0x81p9; 0x8000p1, 0x8001p1), 123456789 (0xebp19, 0xecp19; 0xeb79p11, 0xeb7ap11; 0xeb79a2p3, 0xeb79a3p3), 2147483647 (0xffp23, 0x100p23; 0xffffp15, 0x10000p15; 0xffffffp7, 0x1000000p7), and the negatives with the ends swapped
// shares: Binary::from_hex reads the expected ends; Interval::from_int is the code under test
test "Interval::from_int contains integers wider than the precision" {
  let hex = fn(text : String) { @binary.Binary::from_hex(text, 64).unwrap() }
  // (n, p, lower end, upper end)
  let rows : Array[(Int32, Int32, String, String)] = [
    (100001, 8, "0xc3p9", "0xc4p9"),
    (100001, 16, "0xc350p1", "0xc351p1"),
    (100001, 24, "0xc35080p-7", "0xc35080p-7"),
    (100001, 53, "0x186a1000000000p-36", "0x186a1000000000p-36"),
    (65537, 8, "0x80p9", "0x81p9"),
    (65537, 16, "0x8000p1", "0x8001p1"),
    (65537, 24, "0x800080p-7", "0x800080p-7"),
    (123456789, 8, "0xebp19", "0xecp19"),
    (123456789, 16, "0xeb79p11", "0xeb7ap11"),
    (123456789, 24, "0xeb79a2p3", "0xeb79a3p3"),
    (123456789, 53, "0x1d6f3454000000p-26", "0x1d6f3454000000p-26"),
    (2147483647, 8, "0xffp23", "0x100p23"),
    (2147483647, 16, "0xffffp15", "0x10000p15"),
    (2147483647, 24, "0xffffffp7", "0x1000000p7"),
    (2147483647, 53, "0x1fffffffc00000p-22", "0x1fffffffc00000p-22"),
    (-100001, 8, "-0xc4p9", "-0xc3p9"),
    (-100001, 16, "-0xc351p1", "-0xc350p1"),
    (-2147483647, 8, "-0x100p23", "-0xffp23"),
    (-2147483647, 24, "-0x1000000p7", "-0xffffffp7"),
    (-2147483647, 53, "-0x1fffffffc00000p-22", "-0x1fffffffc00000p-22"),
  ]
  for row in rows {
    let (n, precision, lower, upper) = row
    let interval = Interval::from_int(n, precision~)
    assert_eq(
      interval.lower_bound().compare(hex(lower)),
      0,
      msg="\{n} \{precision}",
    )
    assert_eq(
      interval.upper_bound().compare(hex(upper)),
      0,
      msg="\{n} \{precision}",
    )
  }
}

///|
// oracle: A
// source: the ends are 100001 (and -100001) rounded down and up to p bits, computed with Python fractions: 0xc3p9 and 0xc4p9 at 8 bits, 0xc350p1 and 0xc351p1 at 16, exact (0xc35080p-7) at 24; the negative has the ends swapped
// shares: Binary::from_hex reads the expected ends; BinCoeff::from_uint64 builds the coefficient; Interval::from_coefficient is the code under test
test "Interval::from_coefficient contains coefficients wider than the precision" {
  let coefficient = @binary.BinCoeff::from_uint64(100001UL)
  let hex = fn(text : String) { @binary.Binary::from_hex(text, 64).unwrap() }
  // (negative, p, lower end, upper end)
  let rows : Array[(Bool, Int32, String, String)] = [
    (false, 8, "0xc3p9", "0xc4p9"),
    (false, 16, "0xc350p1", "0xc351p1"),
    (false, 24, "0xc35080p-7", "0xc35080p-7"),
    (true, 8, "-0xc4p9", "-0xc3p9"),
    (true, 16, "-0xc351p1", "-0xc350p1"),
    (true, 24, "-0xc35080p-7", "-0xc35080p-7"),
  ]
  for row in rows {
    let (negative, precision, lower, upper) = row
    let interval = Interval::from_coefficient(
      coefficient,
      precision~,
      negative~,
    )
    assert_eq(interval.lower_bound().compare(hex(lower)), 0)
    assert_eq(interval.upper_bound().compare(hex(upper)), 0)
  }
}

///|
// oracle: A
// source: 100001 < 2^53 is exact in 53 bits, so the interval is a point and its radius is 0 (IEEE 1788-2015 12.12.8, rad of a point)
// shares: Interval::from_int, radius and is_zero (the code under test)
test "Interval::from_int stays exact when the precision is wide enough" {
  let interval = Interval::from_int(100001, precision=53)
  assert_eq(interval.radius().classify(), FpClass::Finite)
  assert_true(interval.radius().is_zero())
}
