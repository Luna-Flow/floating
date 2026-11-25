// The sign of a zero returned by the numeric functions of IEEE 1788-2015 12.12.8 (issue #643).
//
// 12.12.8: in a format with a signed zero, "a Level 1 value of 0 shall be returned as -0 by inf,
// and +0 by all other functions in this subclause". The expected signs below are written out
// from that rule (oracle level A: nothing is computed by the code under test). The ITF1788
// corpus compares by value, so it neither supports nor contradicts this rule.
//
// A bound that is the F-number 0 is the Level 1 value 0 of the stored interval, also when the
// bound came from rounding a nonzero literal to zero (`[0x1p-2000000000]` is the interval
// [0, smallest]): the interval is a set and its inf is that set's greatest lower bound, which is
// 0; the rule applies to it and not to the value that was rounded.

///|
fn zs(x : @binary.Binary) -> String {
  if x.is_zero() {
    if x.is_sign_minus() {
      "-0"
    } else {
      "+0"
    }
  } else {
    x.to_shortest_string()
  }
}

///|
fn zero_case(lo : @binary.Binary, hi : @binary.Binary) -> Interval {
  Interval::from_bounds(lo, hi, precision=53)
}

///|
fn zero_report(x : Interval) -> String {
  [
    "inf " + zs(x.lower_bound()),
    "sup " + zs(x.upper_bound()),
    "mid " + zs(x.midpoint()),
    "rad " + zs(x.radius()),
    "wid " + zs(x.width()),
    "mag " + zs(x.magnitude()),
    "mig " + zs(x.mignitude()),
  ].join("; ")
}

///|
// oracle: A
// source: written out from IEEE 1788-2015 12.12.8, quoted in the header of the file: a Level 1 value of 0 is returned as -0 by inf and as +0 by every other function of the subclause; the expected reports are the strings of the test, such as inf -0; sup 1; mid 0.5; rad 0.5; wid 1; mag 1; mig +0 for [0, 1]
// shares: zs and zero_report (to_shortest_string, is_zero and is_sign_minus) print the report; Binary::zero, negative_zero, from_int and Interval::from_bounds build the inputs
test "12.12.8: the sign of a zero from inf, sup, mid, rad, wid, mag and mig" {
  let zero = @binary.Binary::zero(precision=53)
  let negative_zero = @binary.Binary::negative_zero(precision=53)
  let one = @binary.Binary::from_int(1, precision=53)
  let minus_one = one.neg()
  inspect(
    zero_report(zero_case(zero, one)),
    content="inf -0; sup 1; mid 0.5; rad 0.5; wid 1; mag 1; mig +0",
  )
  inspect(
    zero_report(zero_case(minus_one, zero)),
    content="inf -1; sup +0; mid -0.5; rad 0.5; wid 1; mag 1; mig +0",
  )
  // [0, 0] and [-0, +0], given with either sign of zero on input: the stored sign is not the
  // observable one
  for lo in [zero, negative_zero] {
    for hi in [zero, negative_zero] {
      inspect(
        zero_report(zero_case(lo, hi)),
        content="inf -0; sup +0; mid +0; rad +0; wid +0; mag +0; mig +0",
      )
    }
  }
  // a zero bound of an interval with the other bound given with a negative zero as well
  inspect(
    zero_report(zero_case(negative_zero, one)),
    content="inf -0; sup 1; mid 0.5; rad 0.5; wid 1; mag 1; mig +0",
  )
  inspect(
    zero_report(zero_case(minus_one, negative_zero)),
    content="inf -1; sup +0; mid -0.5; rad 0.5; wid 1; mag 1; mig +0",
  )
}

///|
// oracle: A
// source: written out from IEEE 1788-2015 12.12.8 (inf of a zero bound is -0, every other function +0): the report of each literal of 0 is inf -0; sup +0; mid +0; rad +0; wid +0; mag +0; mig +0, the bound of [0x1p-2000000000] is the F-number 0 and is returned as -0, the interval of [0, 3] has inf -0 and sup 3, and that of [-3, 0] has sup +0
// shares: Interval::from_string reads the literals (the parser is level A in its own gate); zs and zero_report print the values; DecoratedInterval::new builds the decorated forms
test "12.12.8: literals of a zero bound, the point 0, a bound rounded to zero, and decorated forms" {
  for
    text in [
      "[0, 0]", "[-0, +0]", "[0]", "[-0]", "0?0", "[0x0p0]", "[-0x0p0, 0x0p0]",
    ] {
    let x = Interval::from_string(text).unwrap()
    assert_eq(
      zero_report(x),
      "inf -0; sup +0; mid +0; rad +0; wid +0; mag +0; mig +0",
      msg=text,
    )
  }
  // [0x1p-2000000000] is [0, smallest subnormal]: its inf is 0, returned as -0
  let tiny = Interval::from_string("[0x1p-2000000000]").unwrap()
  assert_eq(zs(tiny.lower_bound()), "-0")
  assert_eq(zs(tiny.mignitude()), "+0")
  // the interval of a decorated interval is the same set
  let decorated = DecoratedInterval::new(
    Interval::from_string("[0, 3]").unwrap(),
    decoration=Com,
  )
  assert_eq(zs(decorated.interval().lower_bound()), "-0")
  assert_eq(zs(decorated.interval().upper_bound()), "3")
  let negative_decorated = DecoratedInterval::new(
    Interval::from_string("[-3, 0]").unwrap(),
    decoration=Com,
  )
  assert_eq(zs(negative_decorated.interval().upper_bound()), "+0")
  // Empty and Entire have no zero bound
  assert_eq(zs(Interval::entire().midpoint()), "+0")
}

///|
// oracle: A
// source: written out from IEEE 1788-2015 12.12.8: the midpoint 0 of [-3, 3] is returned as +0 in every context
// shares: Interval::from_string reads [-3, 3]; zs prints the sign of the zero; IntervalContext::new builds the contexts
test "12.12.8: midpoint_ctx returns +0 for the midpoint 0 in every context" {
  let x = Interval::from_string("[-3, 3]").unwrap()
  for precision in [2, 11, 24, 53, 113] {
    let (m, _) = x.midpoint_ctx(IntervalContext::new(precision~))
    assert_eq(zs(m), "+0")
  }
}
