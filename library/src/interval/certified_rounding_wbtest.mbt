///|
// oracle: A
// source: the exact 53-bit hulls of expm1 and log1p at the ends of [-0.125, 0.25] (both functions increase), computed with Python decimal at 80 digits (Decimal.exp, Decimal.ln, rounded outward to 53 bits by Fraction arithmetic; no value is near a rounding boundary): expm1(-1/8) in [-0x1e14aed893eef4p-56, -0x1e14aed893eef3p-56], expm1(1/4) in [0x122d78f0fa0619p-54, 0x122d78f0fa061ap-54], log1p(-1/8) in [-0x11178e8227e47cp-55, -0x11178e8227e47bp-55], log1p(1/4) in [0x1c8ff7c79a9a21p-55, 0x1c8ff7c79a9a22p-55]; a valid enclosure contains [RD(f(-1/8)), RU(f(1/4))] and the result is checked to lie within 4 units of the last place of it
// shares: Interval::from_bounds, Binary::from_double and Binary::from_hex (inputs and expected ends); expm1 and log1p are the code under test
test "expm1 and log1p preserve certified containment" {
  let source = Interval::from_bounds(
    @binary.Binary::from_double(-0.125, precision=53),
    @binary.Binary::from_double(0.25, precision=53),
    precision=53,
  )
  let hex = fn(text : String) { @binary.Binary::from_hex(text, 64).unwrap() }
  let expm1 = source.expm1()
  // the exact hull is [RD(expm1(-1/8)), RU(expm1(1/4))]: contained, and at most 4 ulp wider
  assert_true(expm1.lower_bound().compare(hex("-0x1e14aed893eef4p-56")) <= 0)
  assert_true(expm1.upper_bound().compare(hex("0x122d78f0fa061ap-54")) >= 0)
  assert_true(expm1.lower_bound().compare(hex("-0x1e14aed893eef8p-56")) >= 0)
  assert_true(expm1.upper_bound().compare(hex("0x122d78f0fa061ep-54")) <= 0)
  let log1p = source.log1p()
  assert_true(log1p.lower_bound().compare(hex("-0x11178e8227e47cp-55")) <= 0)
  assert_true(log1p.upper_bound().compare(hex("0x1c8ff7c79a9a22p-55")) >= 0)
  assert_true(log1p.lower_bound().compare(hex("-0x11178e8227e480p-55")) >= 0)
  assert_true(log1p.upper_bound().compare(hex("0x1c8ff7c79a9a26p-55")) <= 0)
}

///|
// oracle: A
// source: IEEE 1788-2015 Table 9.1: log1p is defined for x > -1: [-0.5] is inside the domain and continuous, so com; [-2, 0] contains points outside the domain, so the result is trv (11.6 min-rule)
// shares: DecoratedInterval::new, decoration; Interval::from_double and from_bounds build the inputs; log1p is the code under test
test "decorated log1p uses its shifted IEEE domain" {
  let inside = DecoratedInterval::new(Interval::from_double(-0.5, precision=53)).log1p()
  assert_eq(inside.decoration(), Com)
  let crossing = DecoratedInterval::new(
    Interval::from_bounds(
      @binary.Binary::from_double(-2.0, precision=53),
      @binary.Binary::from_double(0.0, precision=53),
      precision=53,
    ),
  ).log1p()
  assert_eq(crossing.decoration(), Trv)
}
