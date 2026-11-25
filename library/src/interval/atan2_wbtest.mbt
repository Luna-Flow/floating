///|
// oracle: A
// source: written out by hand: pi = 3.14159265358979323846..., so the 53-bit numbers around pi/2 = 1.57079632679489661923... are 0x1921FB54442D18p-52 (below) and 0x1921FB54442D19p-52 (above), and RU(pi) = 0x1921FB54442D19p-51; atan2(1, 0) is the hull of pi/2 at 53 bits, atan2(0, 1) is the point 0, the hull over the branch cut (y in [-1, 1], x = -1, IEEE 1788-2015 Table 9.1 note f) is [-RU(pi), RU(pi)], and the try_ form gives the same
// shares: Interval::from_double, from_bounds and Binary::from_hex (inputs and expected ends); atan2 and try_atan2 are the code under test
test "certified atan2 handles axes and branch cut" {
  let zero = Interval::from_double(0.0, precision=53)
  let one = Interval::from_double(1.0, precision=53)
  let minus_one = Interval::from_double(-1.0, precision=53)
  let hex = fn(text : String) { @binary.Binary::from_hex(text, 64).unwrap() }
  let quarter_turn = one.atan2(zero)
  assert_eq(quarter_turn.lower_bound().compare(hex("0x1921FB54442D18p-52")), 0)
  assert_eq(quarter_turn.upper_bound().compare(hex("0x1921FB54442D19p-52")), 0)
  let origin = zero.atan2(one)
  assert_true(origin.lower_bound().is_zero() && origin.upper_bound().is_zero())
  let crossing = Interval::from_bounds(
    @binary.Binary::from_double(-1.0),
    @binary.Binary::from_double(1.0),
    precision=53,
  ).atan2(minus_one)
  assert_eq(crossing.lower_bound().compare(hex("-0x1921FB54442D19p-51")), 0)
  assert_eq(crossing.upper_bound().compare(hex("0x1921FB54442D19p-51")), 0)
  let tried = one.try_atan2(zero).unwrap()
  assert_true(tried.lower_bound().compare(quarter_turn.lower_bound()) == 0)
  assert_true(tried.upper_bound().compare(quarter_turn.upper_bound()) == 0)
}

///|
// oracle: A
// source: the upper end is RU_53(pi) = 0x1921FB54442D19p-51 (the 53-bit number just above pi = 3.14159265358979323846...; the number just below is 0x1921FB54442D18p-51) and the lower end is zero, because atan2 of [-0,0] and the whole line is [0, pi]; IEEE 1788-2015 12.12.8 gives the zero a Level 1 value of 0
// shares: Binary::negative_zero, Interval::from_bounds, entire, apply_ctx, IntervalContext::binary64 and expected_binary64 (Binary::from_hex)
test "atan2 identifies signed zero endpoints with the real interval zero" {
  let ordinate = Interval::from_bounds(
    @binary.Binary::negative_zero(precision=53),
    @binary.Binary::zero(precision=53),
    precision=53,
  )
  let actual = ordinate.atan2(Interval::entire(precision=53))
  let rounded = actual.apply_ctx(IntervalContext::binary64()).0
  assert_true(rounded.lower_bound().is_zero())
  assert_eq(
    rounded.upper_bound().compare(expected_binary64("0x1921FB54442D19p-51")),
    0,
  )
}

///|
// oracle: A
// source: IEEE 1788-2015 Table 9.1 note f: atan2 is discontinuous on the half-line y = 0, x < 0; the box y in [-0,1], x in [-2,-0.1] contains points of that half-line, so by the min-rule of 11.6 the decoration cannot be com and is dac (the result is bounded and defined everywhere on the box)
// shares: DecoratedInterval::new, decoration and atan2 (the code under test); Interval::from_bounds, Binary::negative_zero, one, from_int, from_double build the inputs
test "decorated atan2 downgrades an upper-side branch-cut touch" {
  let ordinate = DecoratedInterval::new(
    Interval::from_bounds(
      @binary.Binary::negative_zero(precision=53),
      @binary.Binary::one(precision=53),
      precision=53,
    ),
    decoration=Decoration::Com,
  )
  let abscissa = DecoratedInterval::new(
    Interval::from_bounds(
      @binary.Binary::from_int(-2, precision=53),
      @binary.Binary::from_double(-0.1, precision=53),
      precision=53,
    ),
    decoration=Decoration::Com,
  )
  assert_true(ordinate.atan2(abscissa).decoration() == Decoration::Dac)
}
